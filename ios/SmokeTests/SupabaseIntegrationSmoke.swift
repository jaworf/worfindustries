import Foundation

@main
enum SupabaseIntegrationSmoke {
    static func main() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            let projectURL = environment["SUPABASE_URL"],
            let publishableKey = environment["SUPABASE_PUBLISHABLE_KEY"],
            let email = environment["RIVERVIEW_TEST_EMAIL"],
            let password = environment["RIVERVIEW_TEST_PASSWORD"]
        else {
            throw SmokeError.missingEnvironment
        }

        let token = UUID().uuidString.prefix(8).lowercased()
        let marker = "Codex QA \(token)"
        let client = SupabaseRESTClient(
            configuration: SupabaseConfiguration(
                projectURL: projectURL,
                publishableKey: publishableKey
            )
        )

        _ = try await client.signIn(email: email, password: password)
        let initial = try await client.loadSnapshot()
        guard !initial.people.isEmpty, !initial.roles.isEmpty, !initial.terms.isEmpty else {
            throw SmokeError.emptyProductionSnapshot
        }

        var roleDraft = RoleDraft()
        roleDraft.name = "\(marker) Role"
        roleDraft.description = "Disposable integration-test role"
        roleDraft.requiresVote = true
        roleDraft.isPublic = false
        try await client.createRole(roleDraft, displayOrder: 99_900)

        var snapshot = try await client.loadSnapshot()
        guard var role = snapshot.roles.first(where: { $0.name == roleDraft.name }) else {
            throw SmokeError.roleNotCreated
        }
        role.name += " Renamed"
        try await client.updateRole(role)

        var termDraft = TermDraft()
        termDraft.name = "\(marker) Term"
        termDraft.termType = "calendar"
        termDraft.startDate = try requiredDate("2030-01-01")
        termDraft.endDate = try requiredDate("2031-12-31")
        try await client.createTerm(termDraft)

        let externalID = "codex-qa-member-\(token)"
        let lastName = "QA\(token)"
        let firstCSV = """
        id,First Name,Last Name,Home Email,Mobile Phone Number
        \(externalID),Codex,\(lastName),,
        """
        let enrichedCSV = """
        id,First Name,Last Name,Home Email,Mobile Phone Number
        \(externalID),Codex,\(lastName),codex.qa.\(token)@example.invalid,509-555-0199
        """
        let firstImport = try await client.importCSV(
            try CSVParser.parse(data: Data(firstCSV.utf8)),
            kind: .members,
            sourceName: "\(marker) members.csv"
        )
        let enrichedImport = try await client.importCSV(
            try CSVParser.parse(data: Data(enrichedCSV.utf8)),
            kind: .members,
            sourceName: "\(marker) members enriched.csv"
        )

        snapshot = try await client.loadSnapshot()
        guard
            let person = snapshot.people.first(where: {
                $0.firstName == "Codex" && $0.lastName == lastName
            }),
            person.email == "codex.qa.\(token)@example.invalid",
            person.mobilePhone == "509-555-0199"
        else {
            throw SmokeError.personNotDeduplicatedAndEnriched
        }
        guard
            let renamedRole = snapshot.roles.first(where: { $0.id == role.id }),
            renamedRole.name == role.name,
            let term = snapshot.terms.first(where: { $0.name == termDraft.name }),
            let head = snapshot.subRoles.first(where: { $0.name == "Head" })
        else {
            throw SmokeError.referenceDataMissing
        }

        var assignment = AssignmentDraft()
        assignment.personId = person.id
        assignment.roleId = renamedRole.id
        assignment.subRoleId = head.id
        assignment.termId = term.id
        assignment.voteDate = try requiredDate("2026-08-03")
        assignment.notes = "\(marker) disposable assignment"
        assignment.isPublic = false
        try await client.createAssignment(assignment)

        let final = try await client.loadSnapshot()
        guard let createdAssignment = final.assignments.first(where: {
            $0.personId == person.id && $0.roleId == renamedRole.id
        }) else {
            throw SmokeError.assignmentNotCreated
        }
        guard
            createdAssignment.subRoleName == "Head",
            createdAssignment.termId == term.id,
            createdAssignment.voteDate == "2026-08-03",
            createdAssignment.requiresVote,
            !createdAssignment.voteMissing
        else {
            throw SmokeError.assignmentFieldsIncorrect
        }

        let output: [String: Any] = [
            "marker": marker,
            "person_id": person.id.uuidString,
            "role_id": renamedRole.id.uuidString,
            "term_id": term.id.uuidString,
            "assignment_id": createdAssignment.id.uuidString,
            "first_import": summaryDictionary(firstImport),
            "enriched_import": summaryDictionary(enrichedImport),
            "initial_people": initial.people.count,
            "initial_assignments": initial.assignments.count,
            "final_people": final.people.count,
            "final_assignments": final.assignments.count
        ]
        let data = try JSONSerialization.data(
            withJSONObject: output,
            options: [.prettyPrinted, .sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }

    private static func requiredDate(_ value: String) throws -> Date {
        guard let date = AppDate.parse(value) else { throw SmokeError.invalidDate }
        return date
    }

    private static func summaryDictionary(_ summary: ImportSummary) -> [String: Int] {
        [
            "inserted": summary.inserted,
            "updated": summary.updated,
            "unchanged": summary.unchanged,
            "conflicts": summary.conflicts,
            "errors": summary.errors
        ]
    }
}

private enum SmokeError: Error {
    case missingEnvironment
    case emptyProductionSnapshot
    case invalidDate
    case roleNotCreated
    case personNotDeduplicatedAndEnriched
    case referenceDataMissing
    case assignmentNotCreated
    case assignmentFieldsIncorrect
}
