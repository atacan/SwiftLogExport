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

import ServiceLifecycle

/// Log processors allow for processing logs throughout their lifetime via ``onStart(_:parentContext:)`` and ``onEnd(_:)`` calls.
/// Usually, log processors will forward logs to a configurable ``LogRecordExporter``.
///
/// ### Implementation Notes
///
/// On shutdown, processors forwarding logs to an ``LogRecordExporter`` MUST shutdown that exporter.
public protocol LogRecordProcessor<T>: Service & Sendable {
    associatedtype T: LogRecord

    func onEmit(_ record: inout T)

    /// Force log processors that batch logs to flush immediately.
    ///
    /// For ``BatchLogRecordProcessor``, this is an ordered ingress barrier: it waits for all records accepted before
    /// the barrier to be ingested and for every resulting batch export attempt to finish according to the processor's
    /// best-effort policy. It throws ``LogRecordProcessorError/stopped`` when shutdown has already closed ingress.
    func forceFlush() async throws
}
