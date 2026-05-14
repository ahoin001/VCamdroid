import Foundation

/// Phone-to-Windows error report. Big-endian, matches Android's `ErrorReport.kt`
/// and the Windows-side `Connection::ErrorReport` struct.
public struct ErrorReport: Equatable, Sendable {
    public enum Severity: UInt8, Sendable {
        case warning = 0
        case error = 1
    }

    public let severity: Severity
    public let title: String
    public let description: String

    public init(severity: Severity, title: String, description: String) {
        self.severity = severity
        self.title = title
        self.description = description
    }

    public func encode() -> Data {
        var writer = ByteWriter(reserving: 64)
        writer.appendUInt8(severity.rawValue)
        writer.appendLengthPrefixedStringBE(title)
        writer.appendLengthPrefixedStringBE(description)
        return writer.data()
    }
}
