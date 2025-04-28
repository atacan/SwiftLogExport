import Foundation // For Date
import Logging

/// A `LogHandler` that initializes a `LogRecord` and passes it to a `BatchLogRecordProcessor` using a `LogRecordExporter`.
public struct LoggingHandler<T: LogRecord, E: LogRecordExporter<T>>: LogHandler {
    // MARK: - Properties

    /// The label identifying this logger instance. Often corresponds to the `Logger`'s label.
    private let label: String

    /// The shared batch processor that handles buffering and exporting log records.
    /// This MUST be shared across handler instances derived from the same initial bootstrap
    /// or configuration to ensure logs go to the same batcher.
    private let processor: BatchLogRecordProcessor<T, E, ContinuousClock>

    /// The specific log level for this handler instance. Messages below this level will be ignored.
    /// Stored directly in the struct to ensure value semantics.
    public var logLevel: Logger.Level

    /// Metadata associated with this specific handler instance.
    /// Stored directly in the struct to ensure value semantics.
    public var metadata: Logger.Metadata

    /// An optional provider for adding metadata dynamically (e.g., from task-local storage).
    /// Stored directly in the struct to ensure value semantics.
    public var metadataProvider: Logger.MetadataProvider?

    // MARK: - Initialization

    /// Creates a `LoggingHandler`.
    ///
    /// - Parameters:
    ///   - label: The label for the logger.
    ///   - processor: The **shared** `BatchLogRecordProcessor` instance responsible for handling `T`s.
    ///   - level: The initial minimum log level for this handler instance. Defaults to `.info`.
    ///   - metadata: Initial metadata for this handler instance. Defaults to empty.
    ///   - metadataProvider: An optional `Logger.MetadataProvider`. Defaults to `nil`.
    public init(
        label: String,
        processor: BatchLogRecordProcessor<T, E, ContinuousClock>,
        level: Logger.Level = .info,
        metadata: Logger.Metadata = [:],
        metadataProvider: Logger.MetadataProvider? = nil
    ) {
        self.label = label
        self.processor = processor
        self.logLevel = level
        self.metadata = metadata
        self.metadataProvider = metadataProvider
    }

    // MARK: - LogHandler Conformance

    /// The core logging function. Called by `Logger` when a message should be logged.
    ///
    /// This function creates a `T` and passes it to the underlying processor.
    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata logMetadata: Logger.Metadata?, // Renamed to avoid conflict with property
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        // 1. Combine metadata following swift-log precedence:
        //    - Handler's base metadata
        //    - Provider's metadata
        //    - Log call's metadata
        let effectiveMetadata = self.metadata
            .merging(self.metadataProvider?.get() ?? [:], uniquingKeysWith: { _, new in new })
            .merging(logMetadata ?? [:], uniquingKeysWith: { _, new in new })

        // 2. Create the specific LogRecord type
        var record = T(
            label: self.label,
            message: message,
            level: level,
            metadata: effectiveMetadata,
            source: source,
            file: file,
            function: function,
            line: line,
            timestamp: Date() // Add timestamp at the moment of logging
        )

        // 3. Emit the record to the processor
        // Since processor is an actor, we call its method asynchronously.
        // We use Task.detached or similar if needed, but onEmit itself is non-blocking
        // as it just yields to an AsyncStream. Swift-log expects `log` to be synchronous.
        // The `onEmit` is nonisolated, so it can be called synchronously.
        self.processor.onEmit(&record)
    }

    /// Accessor for individual metadata items. Modifies the handler's specific metadata.
    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get {
            self.metadata[key]
        }
        set {
            // Ensures value semantics - modification only affects this struct instance
            self.metadata[key] = newValue
        }
    }
}