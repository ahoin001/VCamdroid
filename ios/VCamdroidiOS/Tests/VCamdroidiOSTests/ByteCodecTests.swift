import XCTest
@testable import VCamdroidiOS

final class ByteCodecTests: XCTestCase {

    func testBigEndianRoundTrip() throws {
        var writer = ByteWriter()
        writer.appendUInt16BE(0xBEEF)
        writer.appendUInt32BE(0xDEADBEEF)
        writer.appendFloat32BE(3.14159)

        var reader = ByteReader(writer.bytes)
        XCTAssertEqual(try reader.readUInt16BE(), 0xBEEF)
        XCTAssertEqual(try reader.readUInt32BE(), 0xDEADBEEF)
        XCTAssertEqual(try reader.readFloat32BE(), 3.14159, accuracy: 1e-5)
    }

    func testLittleEndianRoundTrip() throws {
        var writer = ByteWriter()
        writer.appendUInt16LE(0xCAFE)
        writer.appendUInt32LE(0xFEEDFACE)
        writer.appendFloat32LE(-2.0)

        var reader = ByteReader(writer.bytes)
        XCTAssertEqual(try reader.readUInt16LE(), 0xCAFE)
        XCTAssertEqual(try reader.readUInt32LE(), 0xFEEDFACE)
        XCTAssertEqual(try reader.readFloat32LE(), -2.0, accuracy: 1e-5)
    }

    func testLengthPrefixedStringRoundTrip() throws {
        var writer = ByteWriter()
        writer.appendLengthPrefixedStringBE("iPhone 16 Pro")
        var reader = ByteReader(writer.bytes)
        XCTAssertEqual(try reader.readLengthPrefixedStringBE(), "iPhone 16 Pro")
    }

    func testReaderRejectsShortBuffer() {
        var reader = ByteReader([0x01])
        XCTAssertThrowsError(try reader.readUInt16BE()) { error in
            XCTAssertEqual(
                error as? ByteReader.Error,
                .unexpectedEndOfStream(needed: 2, available: 1)
            )
        }
    }
}
