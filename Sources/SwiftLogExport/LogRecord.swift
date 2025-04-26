import Logging

public protocol LogRecord: Equatable, Sendable {
    var label: String { get }
    var message: Logger.Message { get }
    var level: Logger.Level { get }
    var metadata: Logger.Metadata { get }
}

public struct DefaultLogRecord: LogRecord, Equatable, Sendable {
    public var label: String
    public var message: Logger.Message
    public var level: Logger.Level
    public var metadata: Logger.Metadata
    public var timeNanosecondsSinceEpoch: UInt64

    public init(
        label: String,
        message: Logger.Message,
        level: Logger.Level,
        metadata: Logger.Metadata,
        timeNanosecondsSinceEpoch: UInt64
    ) {
        self.label = label
        self.message = message
        self.level = level
        self.metadata = metadata
        self.timeNanosecondsSinceEpoch = timeNanosecondsSinceEpoch
    }
}
