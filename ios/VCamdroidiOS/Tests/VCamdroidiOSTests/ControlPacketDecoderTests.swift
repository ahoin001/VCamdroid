import XCTest
@testable import VCamdroidiOS

final class ControlPacketDecoderTests: XCTestCase {

    func testResolutionLittleEndian() throws {
        // Matches the byte layout emitted by RTSP::Manager::SetResolution(1920, 1080)
        let bytes: [UInt8] = [
            0x01,           // RESOLUTION
            0x80, 0x07,     // 1920 LE
            0x38, 0x04      // 1080 LE
        ]
        let result = try ControlPacketDecoder.decodeOne(Data(bytes))
        XCTAssertEqual(result?.0, .setResolution(width: 1920, height: 1080))
        XCTAssertEqual(result?.consumed, 5)
    }

    func testZoomFloatLittleEndian() throws {
        // 1.5f → 0x3FC00000 LE → 00 00 C0 3F
        let bytes: [UInt8] = [
            0x0F,
            0x00, 0x00, 0xC0, 0x3F
        ]
        let result = try ControlPacketDecoder.decodeOne(Data(bytes))
        if case let .setZoom(factor) = result?.0 {
            XCTAssertEqual(factor, 1.5, accuracy: 1e-5)
        } else {
            XCTFail("Expected setZoom command")
        }
    }

    func testFlipParsing() throws {
        let horizontal: [UInt8] = [0x10, 0x01]
        let vertical:   [UInt8] = [0x10, 0x00]
        XCTAssertEqual(try ControlPacketDecoder.decodeOne(Data(horizontal))?.0, .flip(.horizontal))
        XCTAssertEqual(try ControlPacketDecoder.decodeOne(Data(vertical))?.0,   .flip(.vertical))
    }

    func testFocusLockSentinelReleasesToAuto() throws {
        // 0x26 + 0xFFFFFFFF (LE) sentinel → release lock
        let bytes: [UInt8] = [0x26, 0xFF, 0xFF, 0xFF, 0xFF]
        let result = try ControlPacketDecoder.decodeOne(Data(bytes))
        XCTAssertEqual(result?.0, .setFocusLock(lensPosition: nil))
    }

    func testActivationDecodesIntegerFields() throws {
        // Craft an ACTIVATION packet: opcode + 11 uint32 BE + uint16 filter count + uint16 effect string len
        var writer = ByteWriter()
        writer.appendUInt8(PacketType.activation.rawValue)
        writer.appendUInt32BE(30)        // fps
        writer.appendUInt32BE(1920)      // width
        writer.appendUInt32BE(1080)      // height
        writer.appendBool(asUInt32: true) // back camera
        writer.appendBool(asUInt32: false) // adaptive bitrate
        writer.appendUInt32BE(4000)      // bitrate
        writer.appendUInt32BE(2000)      // min
        writer.appendUInt32BE(12000)     // max
        writer.appendBool(asUInt32: true)  // stabilization
        writer.appendBool(asUInt32: false) // flash
        writer.appendBool(asUInt32: true)  // h265
        writer.appendUInt16BE(0)         // no filter values
        writer.appendUInt16BE(0)         // empty effect filter name

        let result = try ControlPacketDecoder.decodeOne(writer.data())
        guard case let .activation(config) = result?.0 else {
            XCTFail("Expected activation command")
            return
        }
        XCTAssertEqual(config.fps, 30)
        XCTAssertEqual(config.width, 1920)
        XCTAssertEqual(config.height, 1080)
        XCTAssertTrue(config.useBackCamera)
        XCTAssertFalse(config.adaptiveBitrate)
        XCTAssertEqual(config.bitrateKbps, 4000)
        XCTAssertEqual(config.minBitrateKbps, 2000)
        XCTAssertEqual(config.maxBitrateKbps, 12000)
        XCTAssertTrue(config.stabilizationEnabled)
        XCTAssertFalse(config.flashEnabled)
        XCTAssertTrue(config.h265Enabled)
        XCTAssertNil(config.activeEffectFilter)
    }
}
