@_spi(Logging)
public protocol LogRecordExporter: Sendable {
    /// Export the given batch of logs.
    ///
    /// - Parameter batch: A batch of logs to export.
    func export(_ batch: some Collection<LogRecord> & Sendable) async throws

    /// Force the log exporter to export any previously received logs as soon as possible.
    func forceFlush() async throws

    /// Shut down the log exporter.
    ///
    /// This method gives exporters a chance to wrap up existing work such as finishing in-flight exports while not allowing new ones anymore.
    /// Once this method returns, the exporter is to be considered shut down and further invocations of ``export(_:)``
    /// are expected to fail.
    func shutdown() async
}
