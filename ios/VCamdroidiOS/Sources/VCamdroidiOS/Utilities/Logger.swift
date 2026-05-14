import Foundation
import OSLog

/// Thin facade over `os.Logger` so the rest of the codebase can log without
/// importing `OSLog` everywhere and so tests can swap in an in-memory log sink.
public protocol LogSink: Sendable {
    func log(_ level: LogLevel, _ category: String, _ message: @autoclosure () -> String)
}

public enum LogLevel: Int, Sendable, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct OSLogSink: LogSink {
    private let subsystem: String

    public init(subsystem: String = Bundle.main.bundleIdentifier ?? "VCamdroidiOS") {
        self.subsystem = subsystem
    }

    public func log(_ level: LogLevel, _ category: String, _ message: @autoclosure () -> String) {
        let osLogger = Logger(subsystem: subsystem, category: category)
        let rendered = message()
        switch level {
        case .debug:   osLogger.debug("\(rendered, privacy: .public)")
        case .info:    osLogger.info("\(rendered, privacy: .public)")
        case .warning: osLogger.warning("\(rendered, privacy: .public)")
        case .error:   osLogger.error("\(rendered, privacy: .public)")
        }
    }
}

/// Convenience namespace so call sites read as `Log.info("net", "...")`.
public enum Log {
    public nonisolated(unsafe) static var sink: LogSink = OSLogSink()

    public static func debug(_ category: String, _ message: @autoclosure () -> String) {
        sink.log(.debug, category, message())
    }
    public static func info(_ category: String, _ message: @autoclosure () -> String) {
        sink.log(.info, category, message())
    }
    public static func warning(_ category: String, _ message: @autoclosure () -> String) {
        sink.log(.warning, category, message())
    }
    public static func error(_ category: String, _ message: @autoclosure () -> String) {
        sink.log(.error, category, message())
    }
}
