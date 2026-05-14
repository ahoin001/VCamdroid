import XCTest
@testable import VCamdroidiOS

final class ErrorReportTests: XCTestCase {

    func testRoundTripLayout() throws {
        let report = ErrorReport(severity: .warning, title: "Resolution", description: "1920x1080 not supported")
        var reader = ByteReader(report.encode())
        XCTAssertEqual(try reader.readUInt8(), ErrorReport.Severity.warning.rawValue)
        XCTAssertEqual(try reader.readLengthPrefixedStringBE(), "Resolution")
        XCTAssertEqual(try reader.readLengthPrefixedStringBE(), "1920x1080 not supported")
        XCTAssertTrue(reader.isExhausted)
    }
}
