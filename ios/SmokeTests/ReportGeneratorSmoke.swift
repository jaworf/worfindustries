import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import PDFKit

@main
enum ReportGeneratorSmoke {
    @MainActor static func main() throws {
        var assignments = [
            makeAssignment(
                firstName: "Jane",
                lastName: "Doe",
                roleName: "Deacon",
                subRoleName: "Head",
                leadershipRank: 10
            )
        ]
        assignments.append(
            contentsOf: (1...13).map { index in
                makeAssignment(
                    firstName: "Member",
                    lastName: String(format: "%02d", index),
                    roleName: "Deacon",
                    subRoleName: "Volunteer",
                    leadershipRank: 100
                )
            }
        )
        assignments.append(
            contentsOf: [
                makeAssignment(
                    firstName: "Alex",
                    lastName: "Elder",
                    roleName: "Elder",
                    subRoleName: "Head",
                    leadershipRank: 10
                ),
                makeAssignment(
                    firstName: "Bailey",
                    lastName: "Elder",
                    roleName: "Elder",
                    subRoleName: "Volunteer",
                    leadershipRank: 100
                ),
                makeAssignment(
                    firstName: "Casey",
                    lastName: "Welcome",
                    roleName: "Welcome Team",
                    subRoleName: "Leader",
                    leadershipRank: 10
                ),
                makeAssignment(
                    firstName: "Drew",
                    lastName: "Welcome",
                    roleName: "Welcome Team",
                    subRoleName: "Volunteer",
                    leadershipRank: 100
                ),
                makeAssignment(
                    firstName: "Emery",
                    lastName: "Welcome",
                    roleName: "Welcome Team",
                    subRoleName: "Volunteer",
                    leadershipRank: 100
                )
            ]
        )


        let logoBytes = NSMutableData()
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let logoContext = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        logoContext.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.7, alpha: 1))
        logoContext.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        let destination = CGImageDestinationCreateWithData(logoBytes, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, logoContext.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        let data = try ReportGenerator.makePDF(
            assignments: assignments,
            filterDescription: "All active assignments",
            churchName: "Independent Test Church", churchLogoData: logoBytes as Data
        )
        guard let document = PDFDocument(data: data), let text = document.string else {
            throw SmokeError.invalidPDF
        }


        for index in 0..<document.pageCount {
            guard let dictionary = document.page(at: index)?.pageRef?.dictionary else { throw SmokeError.invalidPDF }
            var resources: CGPDFDictionaryRef?
            var objects: CGPDFDictionaryRef?
            precondition(CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources))
            precondition(CGPDFDictionaryGetDictionary(resources!, "XObject", &objects))
            precondition(CGPDFDictionaryGetCount(objects!) > 0, "Church logo is missing on a report page")
        }
        let presentation = try ReportPreviewDocument(data: data)
        let firstView = PDFPreview.makeView(data: presentation.data)
        precondition(firstView.document?.pageCount == document.pageCount, "First preview must already contain the complete document")
        precondition(firstView.document?.page(at: 0)?.string?.contains("Independent Test Church") == true, "First preview must contain church report text")
        do {
            _ = try ReportPreviewDocument(data: Data())
            throw SmokeError.invalidPDF
        } catch is CocoaError { }
        let filteredData = try ReportGenerator.makePDF(
            assignments: assignments.filter { $0.roleName == "Welcome Team" },
            filterDescription: "Welcome Team only", groupByRole: true,
            churchName: "Independent Test Church", churchLogoData: logoBytes as Data
        )
        let filteredDocument = PDFDocument(data: filteredData)!
        let filteredText = filteredDocument.string ?? ""
        precondition(filteredText.occurrences(of: "Welcome Team") == 2, "Single ministry needs one section heading plus its filter description, never a label on each row")
        precondition(filteredText.contains("Casey") && filteredText.contains("Drew") && filteredText.contains("Emery"))
        precondition(!filteredText.contains("Deacon") && !filteredText.contains("Elder"))
        precondition(!filteredText.contains("Ministry\nVolunteer"), "Filtered report must not use flat Ministry column")
        if let path = ProcessInfo.processInfo.environment["FILTERED_REPORT_OUTPUT_PATH"] {
            try filteredData.write(to: URL(fileURLWithPath: path))
        }
        let outputPath = ProcessInfo.processInfo.environment["REPORT_OUTPUT_PATH"]
            ?? "/private/tmp/Riverview-report-smoke.pdf"
        try data.write(to: URL(fileURLWithPath: outputPath))

        let checks: [(String, Bool)] = [
            ("at least two pages", document.pageCount >= 2),
            ("correct church name", text.contains("Independent Test Church")),
            ("no Riverview header", !text.contains("Pasco Riverview Adventist Church")),
            ("Deacon heading", text.contains("Deacon")),
            ("continued heading", text.contains("Deacon (continued)")),
            ("Elder heading", text.contains("Elder")),
            ("Welcome Team heading", text.contains("Welcome Team")),
            ("public note", text.contains("Coordinates the deacon schedule")),
            ("first page total", text.contains("1 of \(document.pageCount)")),
            (
                "last page total",
                text.contains("\(document.pageCount) of \(document.pageCount)")
            ),
            ("Term column removed", !text.contains("July 26 - June 28")),
            ("continued group count", text.occurrences(of: "Deacon") == 2),
            ("single Welcome Team heading", text.occurrences(of: "Welcome Team") == 1)
        ]
        let failures = checks.filter { !$0.1 }.map(\.0)
        guard failures.isEmpty else {
            let diagnostics =
                "PDF smoke failures: \(failures.joined(separator: ", "))\n" +
                "Extracted PDF text:\n\(text)\n"
            FileHandle.standardError.write(Data(diagnostics.utf8))
            throw SmokeError.invalidPDF
        }

        print(
            "Grouped PDF smoke test passed: \(data.count) bytes, " +
            "\(document.pageCount) pages, \(assignments.count) assignments, " +
            "written to \(outputPath)"
        )
    }

    private static func makeAssignment(
        firstName: String,
        lastName: String,
        roleName: String,
        subRoleName: String,
        leadershipRank: Int
    ) -> AssignmentDetail {
        AssignmentDetail(
            id: UUID(),
            personId: UUID(),
            firstName: firstName,
            preferredName: nil,
            lastName: lastName,
            personName: "\(firstName) \(lastName)",
            email: nil,
            mobilePhone: nil,
            homePhone: nil,
            roleId: UUID(),
            roleName: roleName,
            subRoleId: UUID(),
            subRoleName: subRoleName,
            leadershipRank: leadershipRank,
            termId: UUID(),
            termName: "July 26 - June 28",
            startDate: "2026-07-01",
            endDate: "2028-06-30",
            termType: "fiscal",
            voteDate: "2026-06-20",
            ministryRequiresVote: true,
            positionRequiresVote: false,
            requiresVote: true,
            voteMissing: false,
            status: "active",
            isPublic: true,
            notes: roleName == "Deacon" && leadershipRank == 10
                ? "Coordinates the deacon schedule and monthly team check-in."
                : nil,
            noteIsPublic: roleName == "Deacon" && leadershipRank == 10
        )
    }
}

private enum SmokeError: Error {
    case invalidPDF
}

private extension String {
    func occurrences(of value: String) -> Int {
        components(separatedBy: value).count - 1
    }
}
