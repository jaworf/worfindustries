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
    @Published private(set) var currentProfile: AppProfile?
    @Published private(set) var currentChurch: Church?
    @Published private(set) var planningCenterStatus: PlanningCenterConnectionStatus?
    @Published private(set) var hasRestoredSession = false
    @Published var configuration: SupabaseConfiguration
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var noticeMessage: String?

    private var client: SupabaseRESTClient?
    private let configurationKey = "supabase-configuration"
    private let sessionAccount = "supabase-session"
    private static let passwordResetURL = URL(
        string: "https://riverview-ministry-directory.jaworf.chatgpt.site/reset-password"
    )!

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    var isConfigured: Bool { configuration.isValid }
    var isSignedIn: Bool { session != nil }
    var isAdministrator: Bool { currentProfile?.appRole == .admin }
    var canEdit: Bool {
        currentProfile?.appRole == .admin || currentProfile?.appRole == .editor
    }

    init() {
        if
            let data = UserDefaults.standard.data(forKey: configurationKey),
            let saved = try? JSONDecoder().decode(SupabaseConfiguration.self, from: data)
        {
            configuration = saved
        } else {
            configuration = Self.productionConfiguration()
        }

        if configuration.isValid {
            client = SupabaseRESTClient(configuration: configuration)
        }
    }

    func restoreStoredSession() async {
        guard !hasRestoredSession else { return }
        guard configuration.isValid else {
            hasRestoredSession = true
            return
        }

        let restored: SupabaseSession?
        if Self.isRunningTests {
            restored = nil
        } else {
            let account = sessionAccount
            restored = await Task.detached(priority: .userInitiated) {
                try? KeychainStore.load(
                    SupabaseSession.self,
                    account: account
                )
            }.value
        }

        session = restored
        client = SupabaseRESTClient(configuration: configuration, session: restored)
        hasRestoredSession = true
    }

    private static func productionConfiguration() -> SupabaseConfiguration {
        return SupabaseConfiguration(
            projectURL: "https://syyennvldkenqrcbvgaq.supabase.co",
            publishableKey: "sb_publishable_Nq87oxGP61lMI0QsaiXnsg_AGSjSAYT"
        )
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
            currentProfile = nil
            KeychainStore.delete(account: sessionAccount)
            client = SupabaseRESTClient(configuration: configuration)
            hasRestoredSession = true
            noticeMessage = "Supabase connection settings saved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signIn(email: String, password: String) async {
        await perform {
            let client = try requireClient()
            guard let normalizedEmail = email.nilIfBlank else {
                throw SupabaseClientError.invalidRequest("Enter your email address.")
            }
            let newSession = try await client.signIn(
                email: normalizedEmail,
                password: password
            )
            try KeychainStore.save(newSession, account: sessionAccount)
            session = newSession
            try await reload(using: client)
            noticeMessage = "Signed in and ministry data loaded."
        }
    }

    func requestPasswordReset(email: String) async -> Bool {
        var succeeded = false
        await perform {
            guard let normalizedEmail = email.nilIfBlank else {
                throw SupabaseClientError.invalidRequest("Enter your email address.")
            }
            try await requireClient().requestPasswordReset(
                email: normalizedEmail,
                redirectTo: Self.passwordResetURL
            )
            noticeMessage =
                "Password recovery email sent. Open the newest email and follow its link."
            succeeded = true
        }
        return succeeded
    }

    func signOut() {
        session = nil
        currentProfile = nil
        currentChurch = nil
        planningCenterStatus = nil
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

    func inviteAppUser(email: String, role: AppUserRole) async -> Bool {
        var succeeded = false
        await perform {
            guard isAdministrator else {
                throw SupabaseClientError.invalidRequest(
                    "Only an administrator can create app users."
                )
            }
            guard role != .admin else {
                throw SupabaseClientError.invalidRequest(
                    "New administrator access must be granted directly in Supabase."
                )
            }
            guard
                let normalizedEmail = email.nilIfBlank?.lowercased(),
                normalizedEmail.contains("@")
            else {
                throw SupabaseClientError.invalidRequest("Enter a valid email address.")
            }

            let invitation = try await requireClient().inviteAppUser(
                email: normalizedEmail,
                role: role
            )
            noticeMessage =
                "\(invitation.message) \(invitation.email) has \(invitation.role.label) access."
            succeeded = true
        }
        return succeeded
    }

    func saveAssignment(
        _ draft: AssignmentDraft,
        newPerson: PersonDraft?,
        ordination: PersonOrdinationDraft? = nil
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
                throw SupabaseClientError.invalidRequest("Choose a ministry.")
            }
            let positionRequiresVote = subRoles.first {
                $0.id == assignment.subRoleId
            }?.requiresVote == true
            let requirements = AssignmentRequirements(
                ministryRequiresVote: role.requiresVote,
                positionRequiresVote: positionRequiresVote
            )
            if let message = requirements.validationMessage(
                termId: assignment.termId,
                voteDate: assignment.voteDate
            ) {
                throw SupabaseClientError.invalidRequest(message)
            }

            try await client.createAssignment(assignment)
            if let personId = assignment.personId, let ordination {
                try await client.updatePersonOrdination(
                    personId: personId,
                    ordination: ordination
                )
            }
            try await reload(using: client)
            noticeMessage = "Volunteer assignment saved."
            succeeded = true
        }
        return succeeded
    }

    func updatePersonOrdination(
        personId: UUID,
        ordination: PersonOrdinationDraft
    ) async -> Bool {
        var succeeded = false
        await perform {
            guard canEdit else {
                throw SupabaseClientError.invalidRequest(
                    "Your account can view ordination records but cannot edit them."
                )
            }
            let client = try requireClient()
            try await client.updatePersonOrdination(
                personId: personId,
                ordination: ordination
            )
            try await reload(using: client)
            noticeMessage = "Ordination record updated."
            succeeded = true
        }
        return succeeded
    }

    func addRole(_ draft: RoleDraft) async -> Bool {
        var succeeded = false
        await perform {
            guard let name = draft.name.nilIfBlank else {
                throw SupabaseClientError.invalidRequest("Enter a ministry name.")
            }
            var clean = draft
            clean.name = name
            let nextOrder = (roles.map(\.displayOrder).max() ?? 0) + 10
            let client = try requireClient()
            try await client.createRole(clean, displayOrder: nextOrder)
            try await reload(using: client)
            noticeMessage = "Ministry added."
            succeeded = true
        }
        return succeeded
    }

    func updateAssignmentNote(
        assignmentId: UUID,
        notes: String,
        noteIsPublic: Bool
    ) async -> Bool {
        var succeeded = false
        await perform {
            let client = try requireClient()
            try await client.updateAssignmentNote(
                assignmentId: assignmentId,
                notes: notes,
                noteIsPublic: noteIsPublic
            )
            try await reload(using: client)
            noticeMessage = "Assignment note updated."
            succeeded = true
        }
        return succeeded
    }

    func recordAssignmentVote(
        assignmentId: UUID,
        voteDate: Date
    ) async -> Bool {
        var succeeded = false
        await perform {
            let client = try requireClient()
            try await client.updateAssignmentVoteDate(
                assignmentId: assignmentId,
                voteDate: voteDate
            )
            try await reload(using: client)
            noticeMessage = "Church vote recorded."
            succeeded = true
        }
        return succeeded
    }

    func updateAssignmentDetails(
        assignmentId: UUID,
        subRoleId: UUID?,
        termId: UUID?,
        notes: String,
        noteIsPublic: Bool,
        voteDate: Date?
    ) async -> Bool {
        var succeeded = false
        await perform {
            let client = try requireClient()
            try await client.updateAssignmentDetails(
                assignmentId: assignmentId,
                subRoleId: subRoleId,
                termId: termId,
                notes: notes,
                noteIsPublic: noteIsPublic,
                voteDate: voteDate
            )
            try await reload(using: client)
            noticeMessage = "Assignment details updated."
            succeeded = true
        }
        return succeeded
    }

    func setAssignmentArchived(
        assignmentId: UUID,
        archived: Bool
    ) async -> Bool {
        var succeeded = false
        await perform {
            let client = try requireClient()
            try await client.setAssignmentArchived(
                assignmentId: assignmentId,
                archived: archived
            )
            try await reload(using: client)
            noticeMessage = archived
                ? "Assignment archived and removed from current directories and reports."
                : "Assignment restored to current directories and reports."
            succeeded = true
        }
        return succeeded
    }

    func setMinistryArchived(
        _ role: MinistryRole,
        archived: Bool
    ) async -> Bool {
        var succeeded = false
        await perform {
            var updated = role
            updated.isActive = !archived
            let client = try requireClient()
            try await client.updateRole(updated)
            try await reload(using: client)
            noticeMessage = archived
                ? "Ministry archived and removed from current directories and reports."
                : "Ministry restored."
            succeeded = true
        }
        return succeeded
    }

    func updateRole(_ role: MinistryRole) async -> Bool {
        var succeeded = false
        await perform {
            guard role.name.nilIfBlank != nil else {
                throw SupabaseClientError.invalidRequest("The ministry name cannot be blank.")
            }
            let client = try requireClient()
            try await client.updateRole(role)
            try await reload(using: client)
            noticeMessage = "Ministry updated everywhere it is assigned."
            succeeded = true
        }
        return succeeded
    }

    func addSubRole(_ draft: SubRoleDraft) async -> MinistrySubRole? {
        var createdPosition: MinistrySubRole?
        await perform {
            guard draft.name.nilIfBlank != nil else {
                throw SupabaseClientError.invalidRequest("Enter a position name.")
            }
            var clean = draft
            clean.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let client = try requireClient()
            let created = try await client.createSubRole(clean)
            try await reload(using: client)
            guard let reloaded = subRoles.first(where: { $0.id == created.id }) else {
                throw SupabaseClientError.emptyResponse
            }
            noticeMessage = "Ministry position added."
            createdPosition = reloaded
        }
        return createdPosition
    }

    func updateSubRole(_ subRole: MinistrySubRole) async -> Bool {
        var succeeded = false
        await perform {
            guard subRole.name.nilIfBlank != nil else {
                throw SupabaseClientError.invalidRequest("The position name cannot be blank.")
            }
            let client = try requireClient()
            try await client.updateSubRole(subRole)
            try await reload(using: client)
            noticeMessage = "Ministry position updated."
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

    func loadPlanningCenterStatus() async {
        do {
            planningCenterStatus = try await requireClient().planningCenterConnectionStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func configurePlanningCenter(applicationId: String, secret: String) async -> Bool {
        var succeeded = false
        await perform {
            guard isAdministrator else {
                throw SupabaseClientError.invalidRequest(
                    "Only a church administrator can change the Planning Center connection."
                )
            }
            guard let applicationId = applicationId.nilIfBlank,
                  let secret = secret.nilIfBlank else {
                throw SupabaseClientError.invalidRequest(
                    "Enter both the Personal Access Token application ID and secret."
                )
            }
            let client = try requireClient()
            try await client.configurePlanningCenter(applicationId: applicationId, secret: secret)
            planningCenterStatus = try await client.planningCenterConnectionStatus()
            noticeMessage = "Planning Center connection saved securely for this church."
            succeeded = true
        }
        return succeeded
    }

    private func reload(using client: SupabaseRESTClient) async throws {
        async let snapshotRequest = client.loadSnapshot()
        async let profileRequest = client.loadCurrentProfile()
        let (snapshot, profile) = try await (snapshotRequest, profileRequest)
        let church = try await client.loadChurch(id: profile.churchId)
        people = snapshot.people
        roles = snapshot.roles
        subRoles = snapshot.subRoles
        terms = snapshot.terms
        assignments = snapshot.assignments
        currentProfile = profile
        currentChurch = church
        planningCenterStatus = try? await client.planningCenterConnectionStatus()
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
