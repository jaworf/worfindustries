import XCTest
@testable import RiverviewMinistry

final class CSVParserTests: XCTestCase {
    func testQuotedCommasAndNewlinesArePreserved() throws {
        let source = """
        id,First Name,Last Name,Notes
        1,Jane,Doe,"Lead, outreach"
        2,John,Smith,"Line one
        Line two"
        """

        let document = try CSVParser.parse(data: Data(source.utf8))

        XCTAssertEqual(document.rows.count, 2)
        XCTAssertEqual(document.rows[0]["Notes"], "Lead, outreach")
        XCTAssertEqual(document.rows[1]["Notes"], "Line one\nLine two")
    }

    func testHeaderLookupIgnoresPunctuationAndCase() throws {
        let source = "Sub-Role,Mobile Phone Number\nHead,509-555-0100\n"
        let document = try CSVParser.parse(data: Data(source.utf8))

        XCTAssertEqual(document.rows[0].csvValue("sub role"), "Head")
        XCTAssertEqual(
            document.rows[0].csvValue("MOBILE PHONE NUMBER"),
            "509-555-0100"
        )
    }
}
