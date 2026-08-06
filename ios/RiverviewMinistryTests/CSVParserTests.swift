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

    func testTextSizeChoicesIncreaseInVisibleSteps() {
        XCTAssertLessThan(AppTextSize.small.bodyPointSize, AppTextSize.medium.bodyPointSize)
        XCTAssertLessThan(AppTextSize.medium.bodyPointSize, AppTextSize.large.bodyPointSize)
        XCTAssertLessThan(AppTextSize.large.bodyPointSize, AppTextSize.extraLarge.bodyPointSize)
    }

    func testPlacementFocusFindsEmptyMinistryAndUnfilledExpiredPosition() throws {
        let emptyRole = makeRole(name: "Empty Ministry")
        let gapRole = makeRole(name: "Needs Replacement")
        let coveredRole = makeRole(name: "Covered Ministry")
        let gapPosition = MinistrySubRole(
            id: UUID(),
            roleId: gapRole.id,
            name: "Head",
            leadershipRank: 10,
            requiresVote: false,
            isActive: true
        )
        let coveredPosition = MinistrySubRole(
            id: UUID(),
            roleId: coveredRole.id,
            name: "Head",
            leadershipRank: 10,
            requiresVote: false,
            isActive: true
        )
        let outgoing = makeAssignment(
            role: gapRole,
            position: gapPosition,
            personName: "Outgoing Volunteer",
            status: "completed",
            endDate: "2026-06-30"
        )
        let coveredOutgoing = makeAssignment(
            role: coveredRole,
            position: coveredPosition,
            personName: "Former Volunteer",
            status: "completed",
            endDate: "2026-06-30"
        )
        let coveredReplacement = makeAssignment(
            role: coveredRole,
            position: coveredPosition,
            personName: "Current Volunteer",
            status: "active",
            endDate: "2028-06-30"
        )

        let snapshot = PlacementFocusSnapshot(
            roles: [emptyRole, gapRole, coveredRole],
            subRoles: [gapPosition, coveredPosition],
            assignments: [outgoing, coveredOutgoing, coveredReplacement],
            now: try XCTUnwrap(AppDate.parse("2026-08-05"))
        )

        XCTAssertEqual(snapshot.ministryNeeds.map(\.role.name), ["Empty Ministry", "Needs Replacement"])
        XCTAssertTrue(snapshot.ministryNeeds[0].isEmpty)
        XCTAssertEqual(snapshot.ministryNeeds[1].positionGaps.first?.replacementsNeeded, 1)
        XCTAssertEqual(snapshot.ministryNeeds[1].positionGaps.first?.outgoingNames, ["Outgoing Volunteer"])
        XCTAssertEqual(snapshot.activePersonIds, [coveredReplacement.personId])
    }

    private func makeRole(name: String) -> MinistryRole {
        MinistryRole(
            id: UUID(),
            name: name,
            description: nil,
            requiresVote: false,
            isActive: true,
            isPublic: true,
            displayOrder: 0
        )
    }

    private func makeAssignment(
        role: MinistryRole,
        position: MinistrySubRole,
        personName: String,
        status: String,
        endDate: String
    ) -> AssignmentDetail {
        let nameParts = personName.split(separator: " ").map(String.init)
        return AssignmentDetail(
            id: UUID(),
            personId: UUID(),
            firstName: nameParts.first ?? personName,
            preferredName: nil,
            lastName: nameParts.last ?? personName,
            personName: personName,
            email: nil,
            mobilePhone: nil,
            homePhone: nil,
            roleId: role.id,
            roleName: role.name,
            subRoleId: position.id,
            subRoleName: position.name,
            leadershipRank: position.leadershipRank,
            termId: nil,
            termName: nil,
            startDate: nil,
            endDate: endDate,
            termType: "fixed",
            voteDate: nil,
            ministryRequiresVote: false,
            positionRequiresVote: false,
            requiresVote: false,
            voteMissing: false,
            status: status,
            isPublic: true,
            notes: nil,
            noteIsPublic: false
        )
    }
}
