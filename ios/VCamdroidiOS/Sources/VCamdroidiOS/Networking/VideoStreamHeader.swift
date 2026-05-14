import Foundation

/// Wire-format header that opens every iOS video stream. See
/// `docs/PROTOCOL.md` §2 (iOS video transport).
public struct VideoStreamHeader: Equatable, Sendable {
    public enum Codec: UInt8 {
        case h264 = 0x01
        case h265 = 0x02
    }

    public static let magic: UInt32 = 0x5643_4D44 // "VCMD"
    public static let version: UInt8 = 0x01

    public let codec: Codec
    public let width: UInt16
    public let height: UInt16
    public let fps: UInt8

    public init(codec: Codec, width: UInt16, height: UInt16, fps: UInt8) {
        self.codec = codec
        self.width = width
        self.height = height
        self.fps = fps
    }

    /// Serializes the header (magic + version + codec + width + height + fps).
    public func encode() -> Data {
        var writer = ByteWriter(reserving: 11)
        writer.appendUInt32BE(Self.magic)
        writer.appendUInt8(Self.version)
        writer.appendUInt8(codec.rawValue)
        writer.appendUInt16BE(width)
        writer.appendUInt16BE(height)
        writer.appendUInt8(fps)
        return writer.data()
    }
}

/// Wraps a single NAL unit in its `[uint32 BE length][bytes]` envelope.
public enum NALFraming {
    public static func frame(_ nal: Data) -> Data {
        var writer = ByteWriter(reserving: 4 + nal.count)
        writer.appendUInt32BE(UInt32(nal.count))
        writer.append(nal)
        return writer.data()
    }
}
