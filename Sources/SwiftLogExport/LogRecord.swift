import Logging

public protocol LogRecord: Equatable, Sendable {
    var message: Logger.Message { get }
    var level: Logger.Level { get }
    var metadata: Logger.Metadata { get }
}

public struct DefaultLogRecord: LogRecord, Equatable, Sendable {
    public var message: Logger.Message
    public var level: Logger.Level
    public var metadata: Logger.Metadata
    public var timeNanosecondsSinceEpoch: UInt64

    package init(
        message: Logger.Message,
        level: Logger.Level,
        metadata: Logger.Metadata,
        timeNanosecondsSinceEpoch: UInt64
    ) {
        self.message = message
        self.level = level
        self.metadata = metadata
        self.timeNanosecondsSinceEpoch = timeNanosecondsSinceEpoch
    }
}
