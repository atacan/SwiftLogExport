/// The configuration options for an ``BatchLogRecordProcessor``.

public struct BatchLogRecordProcessorConfiguration: Sendable {
    /// The maximum queue size.
    ///
    /// - Warning: After this size is reached log will be dropped.
    public var maximumQueueSize: UInt

    /// The maximum delay between two consecutive log exports.
    public var scheduleDelay: Duration

    /// The maximum batch size of each export.
    ///
    /// - Note: If the queue reaches this size, a batch will be exported even if ``scheduleDelay`` has not elapsed.
    public var maximumExportBatchSize: UInt

    /// The duration a single export can run until it is cancelled.
    public var exportTimeout: Duration

    /// Create a batch log processor configuration.
    ///
    /// - Parameters:
    ///   - maximumQueueSize: A maximum queue size used even if `OTEL_BLRP_MAX_QUEUE_SIZE` is set. Defaults to `2048` if both are `nil`.
    ///   - scheduleDelay: A schedule delay used even if `OTEL_BLRP_SCHEDULE_DELAY` is set. Defaults to `1` second if both are `nil`.
    ///   - maximumExportBatchSize: A maximum export batch size used even if `OTEL_BLRP_MAX_EXPORT_BATCH_SIZE` is set. Defaults to `512` if both are `nil`.
    ///   - exportTimeout: An export timeout used even if `OTEL_BLRP_EXPORT_TIMEOUT` is set. Defaults to `30` seconds if both are `nil`.
    public init(
        maximumQueueSize: UInt = 2048,
        scheduleDelay: Duration = .seconds(1),
        maximumExportBatchSize: UInt = 512,
        exportTimeout: Duration = .seconds(30)
    ) {
        self.maximumQueueSize = maximumQueueSize

        self.scheduleDelay = scheduleDelay

        self.maximumExportBatchSize = maximumExportBatchSize

        self.exportTimeout = exportTimeout
    }
}
