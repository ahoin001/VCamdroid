import Foundation

/// Mutable byte buffer with explicit big- and little-endian helpers.
///
/// VCamdroid's wire format is mixed-endian (see `docs/PROTOCOL.md`). Rather
/// than rely on `ByteOrder` defaults this writer forces every call site to be
/// explicit, which makes the protocol code self-documenting.
public struct ByteWriter {
    public private(set) var bytes: [UInt8]

    public init(reserving capacity: Int = 0) {
        bytes = []
        bytes.reserveCapacity(capacity)
    }

    public var count: Int { bytes.count }

    public mutating func appendUInt8(_ value: UInt8) {
        bytes.append(value)
    }

    public mutating func appendBool(asUInt32 value: Bool) {
        // Matches `WriteBool` in windows/src/net/serializer.cpp which writes a
        // 4-byte big-endian "boolean".
        appendUInt32BE(value ? 1 : 0)
    }

    // MARK: - Big-endian

    public mutating func appendUInt16BE(_ value: UInt16) {
        bytes.append(UInt8((value >> 8) & 0xFF))
        bytes.append(UInt8(value & 0xFF))
    }

    public mutating func appendUInt32BE(_ value: UInt32) {
        bytes.append(UInt8((value >> 24) & 0xFF))
        bytes.append(UInt8((value >> 16) & 0xFF))
        bytes.append(UInt8((value >> 8) & 0xFF))
        bytes.append(UInt8(value & 0xFF))
    }

    public mutating func appendFloat32BE(_ value: Float) {
        appendUInt32BE(value.bitPattern)
    }

    // MARK: - Little-endian

    public mutating func appendUInt16LE(_ value: UInt16) {
        bytes.append(UInt8(value & 0xFF))
        bytes.append(UInt8((value >> 8) & 0xFF))
    }

    public mutating func appendUInt32LE(_ value: UInt32) {
        bytes.append(UInt8(value & 0xFF))
        bytes.append(UInt8((value >> 8) & 0xFF))
        bytes.append(UInt8((value >> 16) & 0xFF))
        bytes.append(UInt8((value >> 24) & 0xFF))
    }

    public mutating func appendFloat32LE(_ value: Float) {
        appendUInt32LE(value.bitPattern)
    }

    // MARK: - Strings

    /// Writes a string as `[uint16 BE length][UTF-8 bytes]`, matching the
    /// Android `DeviceDescriptor.putString` helper.
    public mutating func appendLengthPrefixedStringBE(_ string: String) {
        let data = Array(string.utf8)
        precondition(data.count <= UInt16.max, "String too long for uint16 length prefix")
        appendUInt16BE(UInt16(data.count))
        bytes.append(contentsOf: data)
    }

    /// Writes a string as `[uint8 length][UTF-8 bytes]`, matching the
    /// short-form filter command format on the Windows side.
    public mutating func appendShortPrefixedString(_ string: String) {
        let data = Array(string.utf8)
        precondition(data.count <= UInt8.max, "String too long for uint8 length prefix")
        bytes.append(UInt8(data.count))
        bytes.append(contentsOf: data)
    }

    public mutating func append(_ raw: [UInt8]) {
        bytes.append(contentsOf: raw)
    }

    public mutating func append(_ raw: Data) {
        bytes.append(contentsOf: raw)
    }

    public func data() -> Data { Data(bytes) }
}
