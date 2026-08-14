import Foundation

struct Person: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var firstName: String
    var middleName: String?
    var lastName: String
    var preferredName: String?
    var suffix: String?
    var email: String?
    var mobilePhone: String?
    var homePhone: String?
    var addressLine1: String?
    var addressLine2: String?
    var city: String?
    var stateRegion: String?
    var postalCode: String?
    var countryCode: String?
    var membershipStatus: String? = nil
    var notes: String?
    var isActive: Bool
    var isPublic: Bool
    var isOrdainedDeacon: Bool = false
    var isOrdainedDeaconess: Bool = false
    var isOrdainedElder: Bool = false
    var sourceCreatedAt: String? = nil
    var sourceUpdatedAt: String? = nil
    var createdAt: String? = nil

    var displayName: String {
        let givenName = preferredName.nilIfBlank ?? firstName
        return ([givenName, lastName] + [suffix.nilIfBlank].compactMap { $0 })
            .joined(separator: " ")
    }

    var addedDate: Date? {
        AppDate.parseTimestamp(sourceCreatedAt ?? createdAt ?? "")
    }

    var ordinationLabels: [String] {
        var labels: [String] = []
        if isOrdainedDeacon { labels.append("Ordained Deacon") }
        if isOrdainedDeaconess { labels.append("Ordained Deaconess") }
        if isOrdainedElder { labels.append("Ordained Elder") }
        return labels
    }
}

enum OrdinationKind: String, CaseIterable, Identifiable, Sendable {
    case deacon
    case deaconess
    case elder

    var id: String { rawValue }

    var label: String {
        switch self {
        case .deacon: "Ordained Deacon"
        case .deaconess: "Ordained Deaconess"
        case .elder: "Ordained Elder"
        }
    }

    static func matching(ministryName: String?) -> OrdinationKind? {
        guard let normalized = ministryName?.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else { return nil }
        return OrdinationKind(rawValue: normalized)
    }
}

struct MinistryRole: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var description: String?
    var requiresVote: Bool
    var isActive: Bool
    var isPublic: Bool
    var displayOrder: Int
    var archivedAt: String? = nil
}

struct MinistrySubRole: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var roleId: UUID?
    var name: String
    var leadershipRank: Int
    var requiresVote: Bool
    var isActive: Bool
}

struct MinistryTerm: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var startDate: String?
    var endDate: String?
    var termType: String
    var isActive: Bool

    var dateRangeLabel: String {
        guard
            let startDate,
            let endDate,
            let start = AppDate.parse(startDate),
            let end = AppDate.parse(endDate)
        else {
            return termType == "ongoing" ? "Ongoing" : "Dates not set"
        }
        return "\(AppDate.display(start)) – \(AppDate.display(end))"
    }
}

struct AssignmentDetail: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let personId: UUID
    let firstName: String
    let preferredName: String?
    let lastName: String
    let personName: String
    let email: String?
    let mobilePhone: String?
    let homePhone: String?
    let roleId: UUID
    let roleName: String
    let subRoleId: UUID?
    let subRoleName: String?
    let leadershipRank: Int
    let termId: UUID?
    let termName: String?
    let startDate: String?
    let endDate: String?
    let termType: String?
    let voteDate: String?
    let ministryRequiresVote: Bool
    let positionRequiresVote: Bool
    let requiresVote: Bool
    let voteMissing: Bool
    let status: String
    let isPublic: Bool
    let notes: String?
    let noteIsPublic: Bool
    var archivedAt: String? = nil
    var ministryIsActive: Bool = true
    var ministryArchivedAt: String? = nil

    var endDateValue: Date? {
        endDate.flatMap(AppDate.parse)
    }

    var publishedNote: String? {
        noteIsPublic ? notes.nilIfBlank : nil
    }

    var isCurrentPlacement: Bool {
        status == "active" && ministryIsActive
    }
}

struct MinistrySnapshot: Sendable {
    let people: [Person]
    let roles: [MinistryRole]
    let subRoles: [MinistrySubRole]
    let terms: [MinistryTerm]
    let assignments: [AssignmentDetail]
}

struct PersonDraft: Sendable {
    var firstName = ""
    var middleName = ""
    var lastName = ""
    var preferredName = ""
    var suffix = ""
    var email = ""
    var mobilePhone = ""
    var homePhone = ""
    var isPublic = true
    var isOrdainedDeacon = false
    var isOrdainedDeaconess = false
    var isOrdainedElder = false

    init() {}

    init(person: Person) {
        firstName = person.firstName
        middleName = person.middleName ?? ""
        lastName = person.lastName
        preferredName = person.preferredName ?? ""
        suffix = person.suffix ?? ""
        email = person.email ?? ""
        mobilePhone = person.mobilePhone ?? ""
        homePhone = person.homePhone ?? ""
        isPublic = person.isPublic
        isOrdainedDeacon = person.isOrdainedDeacon
        isOrdainedDeaconess = person.isOrdainedDeaconess
        isOrdainedElder = person.isOrdainedElder
    }
}

struct PersonOrdinationDraft: Sendable {
    var isOrdainedDeacon = false
    var isOrdainedDeaconess = false
    var isOrdainedElder = false

    init() {}

    init(person: Person) {
        isOrdainedDeacon = person.isOrdainedDeacon
        isOrdainedDeaconess = person.isOrdainedDeaconess
        isOrdainedElder = person.isOrdainedElder
    }
}

struct AssignmentDraft: Sendable {
    var personId: UUID?
    var roleId: UUID?
    var subRoleId: UUID?
    var termId: UUID?
    var voteDate: Date?
    var notes = ""
    var noteIsPublic = false
    var isPublic = true
}

struct AssignmentRequirements: Equatable, Sendable {
    let requiresChurchVote: Bool

    init(ministryRequiresVote: Bool, positionRequiresVote: Bool) {
        requiresChurchVote = ministryRequiresVote || positionRequiresVote
    }

    var requiresTerm: Bool {
        requiresChurchVote
    }

    func validationMessage(termId: UUID?, voteDate: Date?) -> String? {
        if requiresTerm, termId == nil {
            return "Choose a term because this ministry placement requires a church vote."
        }
        if requiresChurchVote, voteDate == nil {
            return "This ministry placement requires a church vote date."
        }
        return nil
    }
}

struct RoleDraft: Sendable {
    var name = ""
    var description = ""
    var requiresVote = false
    var isPublic = true
}

struct SubRoleDraft: Sendable {
    var roleId: UUID
    var name = ""
    var leadershipRank = 100
    var requiresVote = false
    var isActive = true
}

struct TermDraft: Sendable {
    var name = ""
    var startDate = Date()
    var endDate = Calendar.current.date(byAdding: .year, value: 2, to: Date()) ?? Date()
    var termType = "custom"
}

struct ImportSummary: Sendable, Equatable {
    var inserted = 0
    var updated = 0
    var unchanged = 0
    var conflicts = 0
    var errors = 0

    var total: Int {
        inserted + updated + unchanged + conflicts + errors
    }

    mutating func record(outcome: String) {
        switch outcome {
        case "inserted": inserted += 1
        case "updated": updated += 1
        case "unchanged": unchanged += 1
        case "conflict": conflicts += 1
        default: errors += 1
        }
    }
}

struct ImportRPCResult: Decodable, Sendable {
    let outcome: String
    let personId: UUID?
    let assignmentId: UUID?
    let message: String?
}

enum CSVImportKind: String, CaseIterable, Identifiable, Sendable {
    case members = "Members"
    case assignments = "Assignments"

    var id: String { rawValue }
}

enum VoteStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All vote statuses"
    case awaiting = "Awaiting church vote"

    var id: String { rawValue }
}

enum EndingWindow: String, CaseIterable, Identifiable, Sendable {
    case all = "All terms"
    case sixMonths = "Ending in 6 months"
    case oneYear = "Ending in 1 year"

    var id: String { rawValue }

    var monthCount: Int? {
        switch self {
        case .all: nil
        case .sixMonths: 6
        case .oneYear: 12
        }
    }
}

struct PlanningCenterSyncResult: Decodable, Sendable {
    let importRunId: UUID?
    let status: String
    let counts: [String: Int]
}

struct SupabaseConfiguration: Codable, Equatable, Sendable {
    var projectURL: String
    var publishableKey: String

    var isValid: Bool {
        guard
            let url = URL(string: projectURL),
            ["https", "http"].contains(url.scheme?.lowercased())
        else {
            return false
        }
        return !publishableKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct SupabaseSession: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: TimeInterval?
    let user: SupabaseUser
}

struct SupabaseUser: Codable, Sendable {
    let id: UUID
    let email: String?
}

enum AppUserRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case admin
    case editor
    case viewer

    var id: String { rawValue }

    static let invitationChoices: [AppUserRole] = [.editor, .viewer]

    var label: String {
        switch self {
        case .admin: "Administrator"
        case .editor: "Editor"
        case .viewer: "Viewer"
        }
    }

    var invitationDescription: String {
        switch self {
        case .admin:
            "Can manage users and all ministry data."
        case .editor:
            "Can add and edit people, ministries, terms, and assignments."
        case .viewer:
            "Can view the signed-in app but cannot change ministry data."
        }
    }
}

struct AppProfile: Codable, Sendable {
    let userId: UUID
    let displayName: String?
    let appRole: AppUserRole
}

struct AppUserInvitationResult: Codable, Sendable {
    let userId: UUID
    let email: String
    let role: AppUserRole
    let message: String
}

enum AppDate {
    private static let storageFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // These are calendar dates, not moments in time. Using UTC caused a late-evening
        // vote recorded on the West Coast to be stored as the following day.
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func parse(_ value: String) -> Date? {
        storageFormatter.date(from: value)
    }

    static func storage(_ date: Date) -> String {
        storageFormatter.string(from: date)
    }

    static func display(_ date: Date) -> String {
        displayFormatter.string(from: date)
    }

    static func displayTimestamp(_ value: String) -> String? {
        guard let date = parseTimestamp(value) else { return nil }
        return displayFormatter.string(from: date)
    }

    static func parseTimestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: value)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: value)
        }
        return date
    }
}

extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        guard let self else { return nil }
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
