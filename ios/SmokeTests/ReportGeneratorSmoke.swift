import Foundation
import PDFKit

@main
enum ReportGeneratorSmoke {
    static func main() throws {
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

        let data = try ReportGenerator.makePDF(
            assignments: assignments,
            filterDescription: "All active assignments",
            groupByRole: true
        )
        guard
            let document = PDFDocument(data: data),
            document.pageCount == 2,
            let text = document.string,
            text.contains("Deacon"),
            text.contains("Deacon (continued)"),
            text.contains("Elder"),
            text.contains("Welcome Team"),
            text.contains("Coordinates the deacon schedule"),
            text.occurrences(of: "Deacon") == 2,
            text.occurrences(of: "Welcome Team") == 1
        else {
            throw SmokeError.invalidPDF
        }

        try data.write(to: URL(fileURLWithPath: "/private/tmp/Riverview-report-smoke.pdf"))
        print(
            "Grouped PDF smoke test passed: \(data.count) bytes, " +
            "\(document.pageCount) pages, \(assignments.count) assignments"
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
