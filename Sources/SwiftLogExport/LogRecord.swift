import Foundation
import Logging

public protocol LogRecord: Equatable, Sendable {
    init(
        label: String,
        message: Logger.Message,
        level: Logger.Level,
        metadata: Logger.Metadata,
        source: String,
        file: String,
        function: String,
        line: UInt,
        timestamp: Date
    )
}
