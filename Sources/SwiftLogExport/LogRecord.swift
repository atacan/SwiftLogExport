import Logging

@_spi(Logging)
public struct LogRecord: Equatable, Sendable {
    public var body: Logger.Message
    public var level: Logger.Level
    public var metadata: Logger.Metadata
    public var timeNanosecondsSinceEpoch: UInt64

    package init(
        body: Logger.Message,
        level: Logger.Level,
        metadata: Logger.Metadata,
        timeNanosecondsSinceEpoch: UInt64
    ) {
        self.body = body
        self.level = level
        self.metadata = metadata
        self.timeNanosecondsSinceEpoch = timeNanosecondsSinceEpoch
    }
}
