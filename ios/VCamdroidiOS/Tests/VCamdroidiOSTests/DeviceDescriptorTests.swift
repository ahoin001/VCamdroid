import XCTest
@testable import VCamdroidiOS

/// Verifies that the iOS encoder produces the exact byte layout the Windows
/// `Serializer::DeserializeDeviceDescriptor` expects.
final class DeviceDescriptorTests: XCTestCase {

    func testKnownPayload() {
        let descriptor = DeviceDescriptor(
            name: "iPhone 16 Pro",
            url: "vcmd://192.168.1.20:8554/v1?codec=h264",
            frontResolutions: [
                .init(width: 1280, height: 720)
            ],
            backResolutions: [
                .init(width: 1920, height: 1080),
                .init(width: 3840, height: 2160)
            ],
            filters: [
                .init(name: "brightness", category: .correction)
            ]
        )

        let bytes = Array(descriptor.encode())
        var reader = ByteReader(bytes)

        // Name
        XCTAssertEqual(try reader.readLengthPrefixedStringBE(), "iPhone 16 Pro")
        // URL
        XCTAssertEqual(try reader.readLengthPrefixedStringBE(), "vcmd://192.168.1.20:8554/v1?codec=h264")

        // Front resolutions
        XCTAssertEqual(try reader.readUInt16BE(), 1)
        XCTAssertEqual(try reader.readUInt16BE(), 1280)
        XCTAssertEqual(try reader.readUInt16BE(), 720)

        // Back resolutions
        XCTAssertEqual(try reader.readUInt16BE(), 2)
        XCTAssertEqual(try reader.readUInt16BE(), 1920)
        XCTAssertEqual(try reader.readUInt16BE(), 1080)
        XCTAssertEqual(try reader.readUInt16BE(), 3840)
        XCTAssertEqual(try reader.readUInt16BE(), 2160)

        // Filters
        XCTAssertEqual(try reader.readUInt16BE(), 1)
        XCTAssertEqual(try reader.readLengthPrefixedStringBE(), "brightness")
        XCTAssertEqual(try reader.readUInt8(), DeviceDescriptor.FilterInfo.Category.correction.rawValue)
        XCTAssertTrue(reader.isExhausted)
    }
}
