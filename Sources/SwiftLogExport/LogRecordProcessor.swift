import ServiceLifecycle

/// Log processors allow for processing logs throughout their lifetime via ``onStart(_:parentContext:)`` and ``onEnd(_:)`` calls.
/// Usually, log processors will forward logs to a configurable ``LogRecordExporter``.
///
/// ### Implementation Notes
///
/// On shutdown, processors forwarding logs to an ``LogRecordExporter`` MUST shutdown that exporter.
@_spi(Logging)
public protocol LogRecordProcessor: Service & Sendable {
    func onEmit(_ record: inout LogRecord)

    /// Force log processors that batch logs to flush immediately.
    func forceFlush() async throws
}
