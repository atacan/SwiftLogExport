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

    func export(_ batch: some Collection<TestLogRecord> & Sendable) async throws {
        exportedBatches.append(Array(batch))
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
