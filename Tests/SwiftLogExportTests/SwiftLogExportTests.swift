import Foundation
import Logging
import Testing

@testable import SwiftLogExport
@_spi(Testing) import SwiftLogExport

@Test func example() async throws {
    // Write your test here and use APIs like `#expect(...)` to check expected conditions.
}

/// A minimal ``LogRecord`` used by the processor tests.
private struct TestLogRecord: LogRecord {
    let label: String
    let message: Logger.Message
    let level: Logger.Level
    let metadata: Logger.Metadata
    let source: String
    let file: String
    let function: String
    let line: UInt
    let timestamp: Date

    init(
        label: String,
        message: Logger.Message,
        level: Logger.Level,
        metadata: Logger.Metadata,
        source: String,
        file: String,
        function: String,
        line: UInt,
        timestamp: Date
    ) {
        self.label = label
        self.message = message
        self.level = level
        self.metadata = metadata
        self.source = source
        self.file = file
        self.function = function
        self.line = line
        self.timestamp = timestamp
    }

    static func make(_ message: String) -> TestLogRecord {
        TestLogRecord(
            label: "test",
            message: "message \(message)",
            level: .info,
            metadata: [:],
            source: "test",
            file: #file,
            function: #function,
            line: #line,
            timestamp: Date(timeIntervalSinceReferenceDate: 0)
        )
    }
}

/// An exporter stub that records every batch it receives.
private actor RecordingExporter: LogRecordExporter {
    typealias T = TestLogRecord

    private(set) var exportedBatches: [[TestLogRecord]] = []

    var exportedRecords: [TestLogRecord] { exportedBatches.flatMap { $0 } }

    func export(_ batch: some Collection<TestLogRecord> & Sendable) async throws {
        exportedBatches.append(Array(batch))
    }

    func forceFlush() async throws {}

    func shutdown() async {}
}

/// Records every attempted batch and throws for the batch containing a selected message.
private actor SelectivelyFailingExporter: LogRecordExporter {
    typealias T = TestLogRecord

    private struct ExpectedFailure: Error {}

    let failedMessage: String
    private(set) var attemptedBatches: [[TestLogRecord]] = []

    init(failedMessage: String) {
        self.failedMessage = failedMessage
    }

    func export(_ batch: some Collection<TestLogRecord> & Sendable) async throws {
        let records = Array(batch)
        attemptedBatches.append(records)
        if records.contains(where: { $0.message.description.contains(failedMessage) }) {
            throw ExpectedFailure()
        }
    }

    func forceFlush() async throws {}
    func shutdown() async {}
}

private actor CancellationAwareExporter: LogRecordExporter {
    typealias T = TestLogRecord

    private(set) var observedCancellation = false

    func export(_ batch: some Collection<TestLogRecord> & Sendable) async throws {
        do {
            try await Task.sleep(for: .seconds(60))
        } catch is CancellationError {
            observedCancellation = true
            throw CancellationError()
        }
    }

    func forceFlush() async throws {}
    func shutdown() async {}
}

@Test func bufferAccessorsReportEmptyBufferInitially() async throws {
    let processor = BatchLogRecordProcessor<TestLogRecord, RecordingExporter, ContinuousClock>(
        exporter: RecordingExporter(),
        configuration: BatchLogRecordProcessorConfiguration()
    )

    #expect(await processor.bufferedRecordCount == 0)
    #expect(await processor.snapshotOfBufferedRecords().isEmpty)
}

@Test func bufferAccessorsReflectEmittedRecordsDeterministically() async throws {
    let processor = BatchLogRecordProcessor<TestLogRecord, RecordingExporter, ContinuousClock>(
        exporter: RecordingExporter(),
        configuration: BatchLogRecordProcessorConfiguration(
            maximumQueueSize: 8,
            scheduleDelay: .seconds(3600),
            maximumExportBatchSize: 4,
            exportTimeout: .seconds(5)
        )
    )

    let runner = Task { try await processor.run() }
    defer { runner.cancel() }

    let records = (1...3).map { TestLogRecord.make("\($0)") }
    for var record in records {
        processor.onEmit(&record)
    }

    // Wait for the run loop to pick up all records without sleep-and-poll timing margins:
    // each await of an actor-isolated SPI member plus `Task.yield()` gives the processor a chance to progress.
    var observedCount = 0
    for _ in 0..<10_000 {
        observedCount = await processor.bufferedRecordCount
        if observedCount == records.count { break }
        await Task.yield()
    }

    #expect(observedCount == records.count)
    #expect(await processor.snapshotOfBufferedRecords() == records)

    runner.cancel()
    _ = try? await runner.value
}

@Test func immediateEmitThenForceFlushIsAnIngressBarrier() async throws {
    let exporter = RecordingExporter()
    let processor = BatchLogRecordProcessor<TestLogRecord, RecordingExporter, ContinuousClock>(
        exporter: exporter,
        configuration: .init(scheduleDelay: .seconds(3600))
    )
    let runner = Task { try await processor.run() }

    var record = TestLogRecord.make("one")
    processor.onEmit(&record)
    try await processor.forceFlush()

    #expect(await exporter.exportedRecords == [record])
    runner.cancel()
    _ = try? await runner.value
}

@Test func immediateEmitThenShutdownDrainsAcceptedIngress() async throws {
    let exporter = RecordingExporter()
    let processor = BatchLogRecordProcessor<TestLogRecord, RecordingExporter, ContinuousClock>(
        exporter: exporter,
        configuration: .init(scheduleDelay: .seconds(3600))
    )
    let runner = Task { try await processor.run() }

    var record = TestLogRecord.make("one")
    processor.onEmit(&record)
    runner.cancel()
    _ = try? await runner.value

    #expect(await exporter.exportedRecords == [record])
}

@Test func forceFlushWaitsForEveryBatchAndProcessingContinues() async throws {
    let exporter = RecordingExporter()
    let processor = BatchLogRecordProcessor<TestLogRecord, RecordingExporter, ContinuousClock>(
        exporter: exporter,
        configuration: .init(
            maximumQueueSize: 1_000,
            scheduleDelay: .seconds(3600),
            maximumExportBatchSize: 8,
            exportTimeout: .seconds(5)
        )
    )
    let runner = Task { try await processor.run() }

    let firstRecords = (0..<100).map { TestLogRecord.make("\($0)") }
    for var record in firstRecords { processor.onEmit(&record) }
    try await processor.forceFlush()
    #expect(Set(await exporter.exportedRecords.map(\.message.description)) == Set(firstRecords.map(\.message.description)))

    var laterRecord = TestLogRecord.make("later")
    processor.onEmit(&laterRecord)
    try await processor.forceFlush()
    #expect(await exporter.exportedRecords.contains(laterRecord))

    runner.cancel()
    _ = try? await runner.value
}

@Test func failedBatchDoesNotCancelSiblingExports() async throws {
    let exporter = SelectivelyFailingExporter(failedMessage: "message 8")
    let processor = BatchLogRecordProcessor<TestLogRecord, SelectivelyFailingExporter, ContinuousClock>(
        exporter: exporter,
        configuration: .init(
            maximumQueueSize: 1_000,
            scheduleDelay: .seconds(3600),
            maximumExportBatchSize: 8,
            exportTimeout: .seconds(5)
        )
    )
    let runner = Task { try await processor.run() }

    for index in 0..<100 {
        var record = TestLogRecord.make("\(index)")
        processor.onEmit(&record)
    }
    try await processor.forceFlush()

    #expect(await exporter.attemptedBatches.count == 13)
    #expect(await exporter.attemptedBatches.flatMap { $0 }.count == 100)
    runner.cancel()
    _ = try? await runner.value
}

@Test func flushAfterShutdownFailsPromptly() async throws {
    let processor = BatchLogRecordProcessor<TestLogRecord, RecordingExporter, ContinuousClock>(
        exporter: RecordingExporter(),
        configuration: .init(scheduleDelay: .seconds(3600))
    )
    let runner = Task { try await processor.run() }
    runner.cancel()
    _ = try? await runner.value

    await #expect(throws: LogRecordProcessorError.stopped) {
        try await processor.forceFlush()
    }
}

@Test func concurrentFlushBarriersAllComplete() async throws {
    let exporter = RecordingExporter()
    let processor = BatchLogRecordProcessor<TestLogRecord, RecordingExporter, ContinuousClock>(
        exporter: exporter,
        configuration: .init(scheduleDelay: .seconds(3600), maximumExportBatchSize: 2)
    )
    let runner = Task { try await processor.run() }

    for index in 0..<20 {
        var record = TestLogRecord.make("\(index)")
        processor.onEmit(&record)
    }
    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<10 { group.addTask { try await processor.forceFlush() } }
        try await group.waitForAll()
    }
    #expect(await exporter.exportedRecords.count == 20)

    runner.cancel()
    _ = try? await runner.value
}

@Test func multiBatchShutdownDrainsEveryAcceptedRecord() async throws {
    let exporter = RecordingExporter()
    let processor = BatchLogRecordProcessor<TestLogRecord, RecordingExporter, ContinuousClock>(
        exporter: exporter,
        configuration: .init(
            maximumQueueSize: 1_000,
            scheduleDelay: .seconds(3600),
            maximumExportBatchSize: 8,
            exportTimeout: .seconds(5)
        )
    )
    let runner = Task { try await processor.run() }

    for index in 0..<100 {
        var record = TestLogRecord.make("\(index)")
        processor.onEmit(&record)
    }
    runner.cancel()
    _ = try? await runner.value

    #expect(await exporter.exportedRecords.count == 100)
    #expect(await exporter.exportedBatches.count == 13)
}

@Test func exportTimeoutCancelsOutstandingBatchWork() async throws {
    let exporter = CancellationAwareExporter()
    let processor = BatchLogRecordProcessor<TestLogRecord, CancellationAwareExporter, ContinuousClock>(
        exporter: exporter,
        configuration: .init(
            maximumQueueSize: 100,
            scheduleDelay: .seconds(3600),
            maximumExportBatchSize: 8,
            exportTimeout: .milliseconds(10)
        )
    )
    let runner = Task { try await processor.run() }

    var record = TestLogRecord.make("one")
    processor.onEmit(&record)
    await #expect(throws: CancellationError.self) {
        try await processor.forceFlush()
    }
    #expect(await exporter.observedCancellation)

    runner.cancel()
    _ = try? await runner.value
}
