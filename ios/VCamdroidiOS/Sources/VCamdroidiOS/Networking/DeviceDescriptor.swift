import Foundation

/// Describes the iOS device to the Windows client at handshake time.
///
/// The wire format intentionally mirrors `DeviceDescriptor.kt` (Android) and
/// is parsed by `Serializer::DeserializeDeviceDescriptor` on the Windows
/// side. See `docs/PROTOCOL.md` for the full byte layout.
public struct DeviceDescriptor: Equatable, Sendable {
    public struct Resolution: Equatable, Sendable {
        public let width: Int
        public let height: Int
        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }

    public struct FilterInfo: Equatable, Sendable {
        /// Matches the C++ `Video::Filter::Category` enum.
        public enum Category: UInt8, Sendable {
            case none        = 0
            case correction  = 1
            case effect      = 2
            case distortion  = 3
            case artistic    = 4
        }

        public let name: String
        public let category: Category

        public init(name: String, category: Category) {
            self.name = name
            self.category = category
        }
    }

    /// Display name shown in the Windows source dropdown.
    public let name: String

    /// Video transport URL.
    ///
    /// - For iOS we use a custom scheme (`vcmd://<host>:<port>/v1?...`) so the
    ///   Windows parser can detect iOS devices without a separate field while
    ///   remaining wire-compatible with the v1 parser.
    public let url: String

    public let frontResolutions: [Resolution]
    public let backResolutions: [Resolution]
    public let filters: [FilterInfo]

    public init(
        name: String,
        url: String,
        frontResolutions: [Resolution],
        backResolutions: [Resolution],
        filters: [FilterInfo]
    ) {
        self.name = name
        self.url = url
        self.frontResolutions = frontResolutions
        self.backResolutions = backResolutions
        self.filters = filters
    }

    /// Serializes the descriptor into its big-endian wire form.
    public func encode() -> Data {
        var writer = ByteWriter(reserving: 256)
        writer.appendLengthPrefixedStringBE(name)
        writer.appendLengthPrefixedStringBE(url)

        writer.appendUInt16BE(UInt16(frontResolutions.count))
        for res in frontResolutions {
            writer.appendUInt16BE(UInt16(res.width))
            writer.appendUInt16BE(UInt16(res.height))
        }

        writer.appendUInt16BE(UInt16(backResolutions.count))
        for res in backResolutions {
            writer.appendUInt16BE(UInt16(res.width))
            writer.appendUInt16BE(UInt16(res.height))
        }

        writer.appendUInt16BE(UInt16(filters.count))
        for filter in filters {
            writer.appendLengthPrefixedStringBE(filter.name)
            writer.appendUInt8(filter.category.rawValue)
        }

        return writer.data()
    }
}
