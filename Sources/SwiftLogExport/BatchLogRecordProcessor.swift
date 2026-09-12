//===----------------------------------------------------------------------===//
//
// The code is mostly taken from the Swift OTel project
//
// Copyright (c) 2024 the Swift OTel project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AsyncAlgorithms
import DequeModule
import Logging
import ServiceLifecycle

/// Errors reported by a log record processor's lifecycle operations.
public enum LogRecordProcessorError: Error, Sendable, Equatable {
    /// The processor has begun shutting down and can no longer accept a flush barrier.
    case stopped
}

/// A log processor that batches logs and forwards them to a configured exporter.
///
/// A record is accepted when the processor's ingress successfully enqueues it. Graceful shutdown atomically closes
/// ingress, drains every record accepted before that close point, performs a final full drain, and then shuts down the
/// exporter. Records racing after the close point are rejected.
public actor BatchLogRecordProcessor<RecordType, Exporter, Clock: _Concurrency.Clock>:
    LogRecordProcessor, Service, CustomStringConvertible
where RecordType: LogRecord, Exporter: LogRecordExporter<RecordType>, Clock.Duration == Duration {
    public typealias T = RecordType

    private enum Ingress: Sendable {
        case record(RecordType)
        case flush(CheckedContinuation<Void, any Error>)
        case tick
    }

    public nonisolated let description = "BatchLogRecordProcessor"
    internal /* for testing */ private(set) var buffer: Deque<RecordType>

    private let exporter: Exporter
    private let configuration: BatchLogRecordProcessorConfiguration
    private let clock: Clock
    private let logger = Logger(label: "BatchLogRecordProcessor")
    private let ingressStream: AsyncStream<Ingress>
    private nonisolated let ingressContinuation: AsyncStream<Ingress>.Continuation

    @_spi(Testing)
    public init(
        exporter: Exporter, configuration: BatchLogRecordProcessorConfiguration, clock: Clock
    ) {
        self.exporter = exporter
        self.configuration = configuration
        self.clock = clock
        buffer = Deque(minimumCapacity: Int(configuration.maximumQueueSize))
        (ingressStream, ingressContinuation) = AsyncStream.makeStream()
    }

    /// Synchronously submits a record to the ordered ingress channel.
    ///
    /// The record is accepted if this call's ingress yield is ordered before shutdown closes the channel. A record
    /// submitted after that terminal close is dropped.
    public nonisolated func onEmit(_ record: inout RecordType) {
        _ = ingressContinuation.yield(.record(record))
    }

    private func onLog(_ log: RecordType) async {
        buffer.append(log)
        if buffer.count >= configuration.maximumQueueSize {
            await exportNextBatch()
        }
    }

    /// Runs until cancellation or graceful shutdown closes ingress, then drains all accepted work before returning.
    public func run() async throws {
        // Cancellation closes ingress. This independent consumer remains alive to drain all elements accepted earlier.
        let consumer = Task {
            for await event in self.ingressStream {
                await self.consume(event)
            }
        }
        let timer = Task {
            let ticks = AsyncTimerSequence(interval: self.configuration.scheduleDelay, clock: self.clock)
            for await _ in ticks {
                switch self.ingressContinuation.yield(.tick) {
                case .enqueued: break
                case .terminated, .dropped: return
                @unknown default: return
                }
            }
        }

        await withTaskCancellationOrGracefulShutdownHandler {
            await consumer.value
        } onCancelOrGracefulShutdown: {
            self.ingressContinuation.finish()
        }

        timer.cancel()
        await timer.value
        logger.debug("Shutting down.")
        try? await drainBuffer()
        try? await exporter.forceFlush()
        await exporter.shutdown()
        logger.debug("Shut down.")
    }

    private func consume(_ event: Ingress) async {
        switch event {
        case .record(let record):
            await onLog(record)
        case .flush(let continuation):
            do {
                try await drainBuffer()
                try await exporter.forceFlush()
                continuation.resume()
            } catch {
                continuation.resume(throwing: error)
            }
        case .tick:
            if !buffer.isEmpty { await exportNextBatch() }
        }
    }

    /// Waits for every record accepted before this FIFO barrier to be ingested and fully attempted for export.
    ///
    /// Individual batch failures remain best-effort and do not cancel sibling batches. Throws
    /// ``LogRecordProcessorError/stopped`` if shutdown has already closed ingress.
    public func forceFlush() async throws {
        try await withCheckedThrowingContinuation { continuation in
            switch ingressContinuation.yield(.flush(continuation)) {
            case .enqueued: break
            case .terminated, .dropped:
                continuation.resume(throwing: LogRecordProcessorError.stopped)
            @unknown default:
                continuation.resume(throwing: LogRecordProcessorError.stopped)
            }
        }
    }

    private func drainBuffer() async throws {
        guard !buffer.isEmpty else { return }

        let chunkSize = Int(configuration.maximumExportBatchSize)
        let records = Array(buffer)
        buffer.removeAll(keepingCapacity: true)
        let batches = stride(from: 0, to: records.count, by: chunkSize).map {
            Array(records[$0..<min($0 + chunkSize, records.count)])
        }

        try await withThrowingTaskGroup(of: Void.self) { race in
            race.addTask {
                await withTaskGroup(of: Void.self) { exports in
                    for batch in batches {
                        exports.addTask { await self.export(batch) }
                    }
                    await exports.waitForAll()
                }
            }
            race.addTask {
                try await Task.sleep(for: self.configuration.exportTimeout, clock: self.clock)
                try Task.checkCancellation()
                throw CancellationError()
            }
            defer { race.cancelAll() }
            try await race.next()
        }
    }

    private func exportNextBatch() async {
        let batch = Array(buffer.prefix(Int(configuration.maximumExportBatchSize)))
        buffer.removeFirst(batch.count)
        await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { await self.export(batch) }
            group.addTask {
                try await Task.sleep(for: self.configuration.exportTimeout, clock: self.clock)
                throw CancellationError()
            }
            try? await group.next()
            group.cancelAll()
        }
    }

    private func export(_ batch: some Collection<RecordType> & Sendable) async {
        try? await exporter.export(batch)
    }
}

extension BatchLogRecordProcessor where Clock == ContinuousClock {
    /// Create a batch log processor exporting log batches via the given log exporter.
    ///
    /// - Parameters:
    ///   - exporter: The log exporter to receive batched logs to export.
    ///   - configuration: Further configuration parameters to tweak the batching behavior.
    public init(exporter: Exporter, configuration: BatchLogRecordProcessorConfiguration) {
        self.init(exporter: exporter, configuration: configuration, clock: .continuous)
    }
}

extension BatchLogRecordProcessor {
    /// The number of log records currently waiting in the buffer to be exported.
    ///
    /// - Warning: This member is part of the testing SPI and is not part of the stable API surface.
    @_spi(Testing)
    public var bufferedRecordCount: Int { buffer.count }

    /// Returns copies of all log records currently waiting in the buffer to be exported, oldest first.
    ///
    /// - Warning: This member is part of the testing SPI and is not part of the stable API surface.
    @_spi(Testing)
    public func snapshotOfBufferedRecords() -> [RecordType] { Array(buffer) }
}
