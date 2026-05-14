import Foundation

/// Cursor-style reader for the mixed-endian VCamdroid wire format. Throws on
/// short reads rather than crashing so a malformed packet from Windows can
/// be surfaced gracefully.
public struct ByteReader {
    public enum Error: Swift.Error, Equatable {
        case unexpectedEndOfStream(needed: Int, available: Int)
        case invalidUTF8
    }

    private let bytes: [UInt8]
    public private(set) var offset: Int

    public init(_ data: Data) {
        self.bytes = Array(data)
        self.offset = 0
    }

    public init(_ bytes: [UInt8]) {
        self.bytes = bytes
        self.offset = 0
    }

    public var remaining: Int { bytes.count - offset }
    public var isExhausted: Bool { offset >= bytes.count }

    private mutating func require(_ n: Int) throws {
        if remaining < n {
            throw Error.unexpectedEndOfStream(needed: n, available: remaining)
        }
    }

    public mutating func readUInt8() throws -> UInt8 {
        try require(1)
        defer { offset += 1 }
        return bytes[offset]
    }

    // MARK: - Big-endian

    public mutating func readUInt16BE() throws -> UInt16 {
        try require(2)
        defer { offset += 2 }
        return (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    public mutating func readUInt32BE() throws -> UInt32 {
        try require(4)
        defer { offset += 4 }
        return (UInt32(bytes[offset]) << 24)
             | (UInt32(bytes[offset + 1]) << 16)
             | (UInt32(bytes[offset + 2]) << 8)
             |  UInt32(bytes[offset + 3])
    }

    public mutating func readFloat32BE() throws -> Float {
        Float(bitPattern: try readUInt32BE())
    }

    public mutating func readBool32BE() throws -> Bool {
        try readUInt32BE() != 0
    }

    // MARK: - Little-endian

    public mutating func readUInt16LE() throws -> UInt16 {
        try require(2)
        defer { offset += 2 }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    public mutating func readInt16LE() throws -> Int16 {
        Int16(bitPattern: try readUInt16LE())
    }

    public mutating func readUInt32LE() throws -> UInt32 {
        try require(4)
        defer { offset += 4 }
        return  UInt32(bytes[offset])
             | (UInt32(bytes[offset + 1]) << 8)
             | (UInt32(bytes[offset + 2]) << 16)
             | (UInt32(bytes[offset + 3]) << 24)
    }

    public mutating func readFloat32LE() throws -> Float {
        Float(bitPattern: try readUInt32LE())
    }

    // MARK: - Bytes & strings

    public mutating func readBytes(_ n: Int) throws -> [UInt8] {
        try require(n)
        defer { offset += n }
        return Array(bytes[offset..<(offset + n)])
    }

    /// Reads `[uint16 BE length][UTF-8 bytes]`.
    public mutating func readLengthPrefixedStringBE() throws -> String {
        let length = Int(try readUInt16BE())
        let raw = try readBytes(length)
        guard let s = String(bytes: raw, encoding: .utf8) else {
            throw Error.invalidUTF8
        }
        return s
    }

    /// Reads `[uint8 length][UTF-8 bytes]`.
    public mutating func readShortPrefixedString() throws -> String {
        let length = Int(try readUInt8())
        let raw = try readBytes(length)
        guard let s = String(bytes: raw, encoding: .utf8) else {
            throw Error.invalidUTF8
        }
        return s
    }
}
