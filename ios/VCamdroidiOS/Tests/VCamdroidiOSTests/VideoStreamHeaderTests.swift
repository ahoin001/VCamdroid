import XCTest
@testable import VCamdroidiOS

final class VideoStreamHeaderTests: XCTestCase {

    func testHeaderLayoutMatchesSpec() throws {
        let header = VideoStreamHeader(codec: .h264, width: 1920, height: 1080, fps: 30)
        let bytes = Array(header.encode())

        XCTAssertEqual(bytes.count, 11)
        // Magic "VCMD" big-endian = 0x56434D44
        XCTAssertEqual(bytes[0], 0x56)
        XCTAssertEqual(bytes[1], 0x43)
        XCTAssertEqual(bytes[2], 0x4D)
        XCTAssertEqual(bytes[3], 0x44)
        // Version
        XCTAssertEqual(bytes[4], 0x01)
        // Codec
        XCTAssertEqual(bytes[5], 0x01)
        // Width
        XCTAssertEqual(bytes[6], 0x07)
        XCTAssertEqual(bytes[7], 0x80)
        // Height
        XCTAssertEqual(bytes[8], 0x04)
        XCTAssertEqual(bytes[9], 0x38)
        // FPS
        XCTAssertEqual(bytes[10], 30)
    }

    func testNALFraming() {
        let nal: [UInt8] = [0x67, 0x42, 0xC0, 0x1E]
        let framed = Array(NALFraming.frame(Data(nal)))
        XCTAssertEqual(framed.count, 4 + nal.count)
        XCTAssertEqual(framed[0], 0x00)
        XCTAssertEqual(framed[1], 0x00)
        XCTAssertEqual(framed[2], 0x00)
        XCTAssertEqual(framed[3], 0x04)
        XCTAssertEqual(Array(framed[4...]), nal)
    }
}
