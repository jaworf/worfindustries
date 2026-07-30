import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var people: [Person] = []
    @Published private(set) var roles: [MinistryRole] = []
    @Published private(set) var subRoles: [MinistrySubRole] = []
    @Published private(set) var terms: [MinistryTerm] = []
    @Published private(set) var assignments: [AssignmentDetail] = []
    @Published private(set) var session: SupabaseSession?
    @Published var configuration: SupabaseConfiguration
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var noticeMessage: String?

    private var client: SupabaseRESTClient?
    private let configurationKey = "supabase-configuration"
    private let sessionAccount = "supabase-session"

    var isConfigured: Bool { configuration.isValid }
    var isSignedIn: Bool { session != nil }

    init() {
        if
            let data = UserDefaults.standard.data(forKey: configurationKey),
            let saved = try? JSONDecoder().decode(SupabaseConfiguration.self, from: data)
        {
            configuration = saved
        } else {
            configuration = SupabaseConfiguration(projectURL: "", publishableKey: "")
        }

        if configuration.isValid {
            let restored = try? KeychainStore.load(
                SupabaseSession.self,
                account: sessionAccount
            )
            session = restored ?? nil
            client = SupabaseRESTClient(configuration: configuration, session: session)
        }
    }

    func saveConfiguration() {
        errorMessage = nil
        guard configuration.isValid else {
            errorMessage = "Enter the project URL and publishable key shown in Supabase."
            return
        }
        do {
            UserDefaults.standard.set(
                try JSONEncoder().encode(configuration),
                forKey: configurationKey
            )
            session = nil
            KeychainStore.delete(account: sessionAccount)
            client = SupabaseRESTClient(configuration: configuration)
            noticeMessage = "Supabase connection settings saved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signIn(email: String, password: String) async {
        await perform {
            let client = try requireClient()
            let newSession = try await client.signIn(email: email, password: password)
            try KeychainStore.save(newSession, account: sessionAccount)
            session = newSession
            try await reload(using: client)
            noticeMessage = "Signed in and ministry data loaded."
        }
    }

    func signOut() {
        session = nil
        people = []
        roles = []
        subRoles = []
        terms = []
        assignments = []
        KeychainStore.delete(account: sessionAccount)
        client = configuration.isValid
            ? SupabaseRESTClient(configuration: configuration)
            : nil
    }

    func reload() async {
        await perform {
            try await reload(using: requireClient())
        }
    }

    func saveAssignment(
        _ draft: AssignmentDraft,
        newPerson: PersonDraft?
    ) async -> Bool {
        var succeeded = false
        await perform {
            let client = try requireClient()
            var assignment = draft
            if let newPerson {
                guard
                    newPerson.firstName.nilIfBlank != nil,
                    newPerson.lastName.nilIfBlank != nil
                else {
                    throw SupabaseClientError.invalidRequest(
                        "A new person needs a first and last name."
                    )
                }
                assignment.personId = try await client.createPerson(newPerson).id
            }

            guard let role = roles.first(where: { $0.id == assignment.roleId }) else {
                throw SupabaseClientError.invalidRequest("Choose a ministry role.")
            }
            guard assignment.termId != nil else {
                throw SupabaseClientError.invalidRequest("Choose a term.")
            }
            if role.requiresVote, assignment.voteDate == nil {
                throw SupabaseClientError.invalidRequest(
                    "\(role.name) requires a church vote date."
                )
            }

            try await client.createAssignment(assignment)
            try await reload(using: client)
            noticeMessage = "Volunteer assignment saved."
            succeeded = true
        }
        return succeeded
    }

    func addRole(_ draft: RoleDraft) async -> Bool {
        var succeeded = false
        await perform {
            guard let name = draft.name.nilIfBlank else {
                throw SupabaseClientError.invalidRequest("Enter a role name.")
            }
            var clean = draft
            clean.name = name
            let nextOrder = (roles.map(\.displayOrder).max() ?? 0) + 10
            let client = try requireClient()
            try await client.createRole(clean, displayOrder: nextOrder)
            try await reload(using: client)
            noticeMessage = "Role added."
            succeeded = true
        }
        return succeeded
    }

    func updateRole(_ role: MinistryRole) async -> Bool {
        var succeeded = false
        await perform {
            guard role.name.nilIfBlank != nil else {
                throw SupabaseClientError.invalidRequest("The role name cannot be blank.")
            }
            let client = try requireClient()
            try await client.updateRole(role)
            try await reload(using: client)
            noticeMessage = "Role updated everywhere it is assigned."
            succeeded = true
        }
        return succeeded
    }

    func addTerm(_ draft: TermDraft) async -> Bool {
        var succeeded = false
        await perform {
            guard draft.name.nilIfBlank != nil else {
                throw SupabaseClientError.invalidRequest("Enter a term name.")
            }
            if draft.termType != "ongoing", draft.endDate < draft.startDate {
                throw SupabaseClientError.invalidRequest(
                    "The term end date must be on or after its start date."
                )
            }
            let client = try requireClient()
            try await client.createTerm(draft)
            try await reload(using: client)
            noticeMessage = "Term added."
            succeeded = true
        }
        return succeeded
    }

    func importCSV(data: Data, fileName: String, kind: CSVImportKind) async {
        await perform {
            let document = try CSVParser.parse(data: data)
            let client = try requireClient()
            let summary = try await client.importCSV(
                document,
                kind: kind,
                sourceName: fileName
            )
            try await reload(using: client)
            noticeMessage = [
                "\(kind.rawValue) import finished:",
                "\(summary.inserted) added,",
                "\(summary.updated) matched/enriched,",
                "\(summary.conflicts) need review,",
                "\(summary.errors) errors."
            ].joined(separator: " ")
        }
    }

    func syncPlanningCenter() async {
        await perform {
            let client = try requireClient()
            let result = try await client.runPlanningCenterSync()
            try await reload(using: client)
            let added = result.counts["inserted", default: 0]
            let updated = result.counts["updated", default: 0]
            let conflicts = result.counts["conflict", default: 0]
            noticeMessage =
                "Planning Center sync \(result.status): \(added) added, " +
                "\(updated) updated, \(conflicts) conflicts."
        }
    }

    private func reload(using client: SupabaseRESTClient) async throws {
        let snapshot = try await client.loadSnapshot()
        people = snapshot.people
        roles = snapshot.roles
        subRoles = snapshot.subRoles
        terms = snapshot.terms
        assignments = snapshot.assignments
        if let currentSession = await client.currentSession(),
           currentSession.accessToken != session?.accessToken
        {
            try KeychainStore.save(currentSession, account: sessionAccount)
            session = currentSession
        }
    }

    private func requireClient() throws -> SupabaseRESTClient {
        guard let client else {
            throw SupabaseClientError.invalidConfiguration
        }
        return client
    }

    private func perform(_ operation: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
