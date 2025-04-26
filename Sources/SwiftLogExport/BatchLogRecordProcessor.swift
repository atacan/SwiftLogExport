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

/// A log processor that batches logs and forwards them to a configured exporter.

public actor BatchLogRecordProcessor<RecordType, Exporter, Clock: _Concurrency.Clock>:
    LogRecordProcessor,
    Service,
    CustomStringConvertible
where RecordType: LogRecord, Exporter: LogRecordExporter<RecordType>, Clock.Duration == Duration {
    public typealias T = RecordType

    public nonisolated let description = "BatchLogRecordProcessor"

    internal /* for testing */ private(set) var buffer: Deque<RecordType>

    private let exporter: Exporter
    private let configuration: BatchLogRecordProcessorConfiguration
    private let clock: Clock
    private let logger = Logger(label: "BatchLogRecordProcessor")
    private let logStream: AsyncStream<RecordType>
    private let logContinuation: AsyncStream<RecordType>.Continuation
    private let explicitTickStream: AsyncStream<Void>
    private let explicitTick: AsyncStream<Void>.Continuation

    @_spi(Testing)
    public init(
        exporter: Exporter, configuration: BatchLogRecordProcessorConfiguration, clock: Clock
    ) {
        self.exporter = exporter
        self.configuration = configuration
        self.clock = clock

        buffer = Deque(minimumCapacity: Int(configuration.maximumQueueSize))
        (explicitTickStream, explicitTick) = AsyncStream.makeStream()
        (logStream, logContinuation) = AsyncStream.makeStream()
    }

    public nonisolated func onEmit(_ record: inout RecordType) {
        logContinuation.yield(record)
    }

    private func _onLog(_ log: RecordType) {
        buffer.append(log)

        if buffer.count == configuration.maximumQueueSize {
            explicitTick.yield()
        }
    }

    public func run() async throws {
        let timerSequence = AsyncTimerSequence(interval: configuration.scheduleDelay, clock: clock)
            .map { _ in }
        let mergedSequence = merge(timerSequence, explicitTickStream).cancelOnGracefulShutdown()

        await withTaskCancellationOrGracefulShutdownHandler {
            await withThrowingTaskGroup(of: Void.self) { taskGroup in
                taskGroup.addTask {
                    for await log in self.logStream {
                        await self._onLog(log)
                    }
                }

                taskGroup.addTask {
                    for try await _ in mergedSequence where await !(self.buffer.isEmpty) {
                        await self.tick()
                    }
                }

                try? await taskGroup.next()
                taskGroup.cancelAll()
            }
        } onCancelOrGracefulShutdown: {
            self.logContinuation.finish()
        }

        logger.debug("Shutting down.")
        try? await forceFlush()
        await exporter.shutdown()
        logger.debug("Shut down.")
    }

    public func forceFlush() async throws {
        let chunkSize = Int(configuration.maximumExportBatchSize)
        let batches = stride(from: 0, to: buffer.count, by: chunkSize).map {
            buffer[$0..<min($0 + Int(configuration.maximumExportBatchSize), buffer.count)]
        }

        if !buffer.isEmpty {
            buffer.removeAll()

            try await withThrowingTaskGroup(of: Void.self) { group in
                for batch in batches {
                    group.addTask { await self.export(batch) }
                }

                group.addTask {
                    try await Task.sleep(for: self.configuration.exportTimeout, clock: self.clock)
                    throw CancellationError()
                }

                defer { group.cancelAll() }
                // Don't cancel unless it's an error
                // A single export shouldn't cancel the other exports
                try await group.next()
            }
        }

        try await exporter.forceFlush()
    }

    private func tick() async {
        let batch = buffer.prefix(Int(configuration.maximumExportBatchSize))
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
