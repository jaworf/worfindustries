import Foundation
import PDFKit

@main
enum ReportGeneratorSmoke {
    static func main() throws {
        let assignment = AssignmentDetail(
            id: UUID(),
            personId: UUID(),
            firstName: "Jane",
            preferredName: nil,
            lastName: "Doe",
            personName: "Jane Doe",
            email: nil,
            mobilePhone: nil,
            homePhone: nil,
            roleId: UUID(),
            roleName: "Deacon",
            subRoleId: UUID(),
            subRoleName: "Head",
            leadershipRank: 10,
            termId: UUID(),
            termName: "July 26 - June 28",
            startDate: "2026-07-01",
            endDate: "2028-06-30",
            termType: "fiscal",
            voteDate: "2026-06-20",
            requiresVote: true,
            voteMissing: false,
            status: "active",
            isPublic: true,
            notes: nil
        )
        let data = try ReportGenerator.makePDF(
            assignments: [assignment],
            filterDescription: "Smoke test"
        )
        guard let document = PDFDocument(data: data), document.pageCount == 1 else {
            throw SmokeError.invalidPDF
        }
        try data.write(to: URL(fileURLWithPath: "/private/tmp/Riverview-report-smoke.pdf"))
        print("PDF smoke test passed: \(data.count) bytes, \(document.pageCount) page")
    }
}

private enum SmokeError: Error {
    case invalidPDF
}
