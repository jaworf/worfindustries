import Foundation

@main
enum CSVImportSmoke {
    static func main() throws {
        let source = """
        \u{FEFF}id,First Name,Last Name,Notes
        1,Jane,Doe,"Lead, outreach"
        2,John,Smith,"Line one
        Line two"
        """
        let document = try CSVParser.parse(data: Data(source.utf8))
        guard
            document.rows.count == 2,
            document.rows[0].csvValue("first name") == "Jane",
            document.rows[0]["Notes"] == "Lead, outreach",
            document.rows[1]["Notes"] == "Line one\nLine two"
        else {
            throw SmokeError.unexpectedCSV
        }
        print("CSV smoke test passed: \(document.rows.count) rows")
    }
}

private enum SmokeError: Error {
    case unexpectedCSV
}
