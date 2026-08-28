import Foundation

actor SupabaseRESTClient {
    private var configuration: SupabaseConfiguration
    private var session: SupabaseSession?
    private var refreshTask: Task<SupabaseSession, Error>?
    private let urlSession: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        configuration: SupabaseConfiguration,
        session: SupabaseSession? = nil,
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
        self.urlSession = urlSession

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    func currentSession() -> SupabaseSession? {
        session
    }

    func signIn(email: String, password: String) async throws -> SupabaseSession {
        let body = try encoder.encode(SignInRequest(email: email, password: password))
        let response: SupabaseSession = try await send(
            method: "POST",
            path: "auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "password")],
            body: body,
            requiresAuthentication: false
        )
        session = response
        return response
    }

    func requestPasswordReset(email: String, redirectTo: URL) async throws {
        let body = try encoder.encode(PasswordResetRequest(email: email))
        let _: EmptyBody = try await send(
            method: "POST",
            path: "auth/v1/recover",
            query: [
                URLQueryItem(
                    name: "redirect_to",
                    value: redirectTo.absoluteString
                )
            ],
            body: body,
            requiresAuthentication: false
        )
    }

    private func validAccessToken() async throws -> String {
        guard let current = session else {
            throw SupabaseClientError.notSignedIn
        }
        let refreshThreshold = Date().timeIntervalSince1970 + 60
        guard
            let expiresAt = current.expiresAt,
            expiresAt <= refreshThreshold
        else {
            return current.accessToken
        }

        if let refreshTask {
            return try await refreshTask.value.accessToken
        }

        let task = Task { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.refreshSession(using: current.refreshToken)
        }
        refreshTask = task

        do {
            let refreshed = try await task.value
            session = refreshed
            refreshTask = nil
            return refreshed.accessToken
        } catch {
            refreshTask = nil
            throw error
        }
    }

    private func refreshSession(using refreshToken: String) async throws -> SupabaseSession {
        let body = try encoder.encode(RefreshRequest(refreshToken: refreshToken))
        return try await send(
            method: "POST",
            path: "auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            body: body,
            requiresAuthentication: false
        )
    }

    func loadSnapshot() async throws -> MinistrySnapshot {
        async let people: [Person] = restAll(
            "people",
            query: [
                .init(name: "select", value: "*"),
                .init(name: "order", value: "last_name.asc,first_name.asc")
            ]
        )
        async let roles: [MinistryRole] = restAll(
            "roles",
            query: [
                .init(name: "select", value: "*"),
                .init(name: "order", value: "display_order.asc,name.asc")
            ]
        )
        async let subRoles: [MinistrySubRole] = restAll(
            "sub_roles",
            query: [
                .init(name: "select", value: "*"),
                .init(name: "order", value: "leadership_rank.asc,name.asc")
            ]
        )
        async let terms: [MinistryTerm] = restAll(
            "terms",
            query: [
                .init(name: "select", value: "*"),
                .init(name: "order", value: "start_date.desc.nullslast,name.asc")
            ]
        )
        async let assignments: [AssignmentDetail] = restAll(
            "assignment_details",
            query: [
                .init(name: "select", value: "*"),
                .init(name: "order", value: "role_name.asc,leadership_rank.asc,last_name.asc,first_name.asc")
            ]
        )

        return try await MinistrySnapshot(
            people: people,
            roles: roles,
            subRoles: subRoles,
            terms: terms,
            assignments: assignments
        )
    }

    func loadCurrentProfile() async throws -> AppProfile {
        guard let userId = session?.user.id else {
            throw SupabaseClientError.notSignedIn
        }
        let profiles: [AppProfile] = try await send(
            method: "GET",
            path: "rest/v1/profiles",
            query: [
                .init(name: "select", value: "user_id,display_name,app_role,church_id,is_platform_admin"),
                .init(name: "user_id", value: "eq.\(userId.uuidString)")
            ]
        )
        guard let profile = profiles.first else {
            throw SupabaseClientError.invalidRequest(
                "Your app account does not have an access profile. Contact an administrator."
            )
        }
        return profile
    }

    func loadChurch(id: UUID) async throws -> Church {
        let churches: [Church] = try await send(
            method: "GET",
            path: "rest/v1/churches",
            query: [
                .init(name: "select", value: "id,name,slug,support_email"),
                .init(name: "id", value: "eq.\(id.uuidString)")
            ]
        )
        guard let church = churches.first else {
            throw SupabaseClientError.invalidRequest("This account is not assigned to an active church.")
        }
        return church
    }

    func planningCenterConnectionStatus() async throws -> PlanningCenterConnectionStatus {
        try await rpc("planning_center_connection_status", body: EmptyBody())
    }

    func configurePlanningCenter(applicationId: String, secret: String) async throws {
        let _: PlanningCenterConnectionStatus = try await rpc(
            "configure_planning_center",
            body: PlanningCenterConnectionWrite(
                pApplicationId: applicationId,
                pSecret: secret
            )
        )
    }

    func inviteAppUser(
        email: String,
        role: AppUserRole
    ) async throws -> AppUserInvitationResult {
        let body = try encoder.encode(AppUserInvitationRequest(email: email, role: role))
        return try await send(
            method: "POST",
            path: "functions/v1/admin-users",
            body: body
        )
    }

    func createPerson(_ draft: PersonDraft) async throws -> Person {
        let payload = PersonWrite(
            firstName: draft.firstName,
            middleName: draft.middleName.nilIfBlank,
            lastName: draft.lastName,
            preferredName: draft.preferredName.nilIfBlank,
            suffix: draft.suffix.nilIfBlank,
            email: draft.email.nilIfBlank,
            mobilePhone: draft.mobilePhone.nilIfBlank,
            homePhone: draft.homePhone.nilIfBlank,
            isActive: true,
            isPublic: draft.isPublic,
            isOrdainedDeacon: draft.isOrdainedDeacon,
            isOrdainedDeaconess: draft.isOrdainedDeaconess,
            isOrdainedElder: draft.isOrdainedElder
        )
        let rows: [Person] = try await restWrite("POST", table: "people", body: payload)
        guard let person = rows.first else { throw SupabaseClientError.emptyResponse }
        return person
    }

    func updatePersonOrdination(
        personId: UUID,
        ordination: PersonOrdinationDraft
    ) async throws {
        let payload = PersonOrdinationWrite(
            isOrdainedDeacon: ordination.isOrdainedDeacon,
            isOrdainedDeaconess: ordination.isOrdainedDeaconess,
            isOrdainedElder: ordination.isOrdainedElder
        )
        let _: [Person] = try await restWrite(
            "PATCH",
            table: "people",
            query: [.init(name: "id", value: "eq.\(personId.uuidString)")],
            body: payload
        )
    }

    func createAssignment(_ draft: AssignmentDraft) async throws {
        guard let personId = draft.personId, let roleId = draft.roleId else {
            throw SupabaseClientError.invalidRequest("A person and ministry are required.")
        }
        let payload = AssignmentWrite(
            personId: personId,
            roleId: roleId,
            subRoleId: draft.subRoleId,
            termId: draft.termId,
            voteDate: draft.voteDate.map(AppDate.storage),
            notes: draft.notes.nilIfBlank,
            noteIsPublic: draft.noteIsPublic && draft.notes.nilIfBlank != nil,
            status: "active",
            isPublic: draft.isPublic
        )
        let _: [AssignmentWriteResult] = try await restWrite(
            "POST",
            table: "assignments",
            body: payload
        )
    }

    func updateAssignmentNote(
        assignmentId: UUID,
        notes: String?,
        noteIsPublic: Bool
    ) async throws {
        let cleanNotes = notes.nilIfBlank
        let payload = AssignmentNoteWrite(
            notes: cleanNotes,
            noteIsPublic: noteIsPublic && cleanNotes != nil
        )
        let _: [AssignmentWriteResult] = try await restWrite(
            "PATCH",
            table: "assignments",
            query: [.init(name: "id", value: "eq.\(assignmentId.uuidString)")],
            body: payload
        )
    }

    func updateAssignmentVoteDate(
        assignmentId: UUID,
        voteDate: Date?
    ) async throws {
        let payload = AssignmentVoteWrite(voteDate: voteDate.map(AppDate.storage))
        let _: [AssignmentWriteResult] = try await restWrite(
            "PATCH",
            table: "assignments",
            query: [.init(name: "id", value: "eq.\(assignmentId.uuidString)")],
            body: payload
        )
    }

    func updateAssignmentDetails(
        assignmentId: UUID,
        subRoleId: UUID?,
        termId: UUID?,
        notes: String?,
        noteIsPublic: Bool,
        voteDate: Date?
    ) async throws {
        let cleanNotes = notes.nilIfBlank
        let payload = AssignmentDetailsWrite(
            subRoleId: subRoleId,
            termId: termId,
            notes: cleanNotes,
            noteIsPublic: noteIsPublic && cleanNotes != nil,
            voteDate: voteDate.map(AppDate.storage)
        )
        let _: [AssignmentWriteResult] = try await restWrite(
            "PATCH",
            table: "assignments",
            query: [.init(name: "id", value: "eq.\(assignmentId.uuidString)")],
            body: payload
        )
    }

    func setAssignmentArchived(
        assignmentId: UUID,
        archived: Bool
    ) async throws {
        let payload = AssignmentStatusWrite(status: archived ? "completed" : "active")
        let _: [AssignmentWriteResult] = try await restWrite(
            "PATCH",
            table: "assignments",
            query: [.init(name: "id", value: "eq.\(assignmentId.uuidString)")],
            body: payload
        )
    }

    func createRole(_ draft: RoleDraft, displayOrder: Int) async throws {
        let payload = RoleWrite(
            name: draft.name,
            description: draft.description.nilIfBlank,
            requiresVote: draft.requiresVote,
            isActive: true,
            isPublic: draft.isPublic,
            displayOrder: displayOrder
        )
        let _: [MinistryRole] = try await restWrite("POST", table: "roles", body: payload)
    }

    func updateRole(_ role: MinistryRole) async throws {
        let payload = RoleWrite(
            name: role.name,
            description: role.description,
            requiresVote: role.requiresVote,
            isActive: role.isActive,
            isPublic: role.isPublic,
            displayOrder: role.displayOrder
        )
        let _: [MinistryRole] = try await restWrite(
            "PATCH",
            table: "roles",
            query: [.init(name: "id", value: "eq.\(role.id.uuidString)")],
            body: payload
        )
    }

    func createSubRole(_ draft: SubRoleDraft) async throws -> MinistrySubRole {
        let payload = SubRoleWrite(
            roleId: draft.roleId,
            name: draft.name,
            leadershipRank: draft.leadershipRank,
            requiresVote: draft.requiresVote,
            isActive: draft.isActive
        )
        let rows: [MinistrySubRole] = try await restWrite(
            "POST",
            table: "sub_roles",
            body: payload
        )
        guard let position = rows.first else {
            throw SupabaseClientError.emptyResponse
        }
        return position
    }

    func updateSubRole(_ subRole: MinistrySubRole) async throws {
        guard let roleId = subRole.roleId else {
            throw SupabaseClientError.invalidRequest(
                "This imported position must be assigned to a ministry before it can be edited."
            )
        }
        let payload = SubRoleWrite(
            roleId: roleId,
            name: subRole.name,
            leadershipRank: subRole.leadershipRank,
            requiresVote: subRole.requiresVote,
            isActive: subRole.isActive
        )
        let _: [MinistrySubRole] = try await restWrite(
            "PATCH",
            table: "sub_roles",
            query: [.init(name: "id", value: "eq.\(subRole.id.uuidString)")],
            body: payload
        )
    }

    func createTerm(_ draft: TermDraft) async throws {
        let ongoing = draft.termType == "ongoing"
        let payload = TermWrite(
            name: draft.name,
            startDate: ongoing ? nil : AppDate.storage(draft.startDate),
            endDate: ongoing ? nil : AppDate.storage(draft.endDate),
            termType: draft.termType,
            isActive: true
        )
        let _: [MinistryTerm] = try await restWrite("POST", table: "terms", body: payload)
    }

    func runPlanningCenterSync() async throws -> PlanningCenterSyncResult {
        let data = try encoder.encode(EmptyBody())
        return try await send(
            method: "POST",
            path: "functions/v1/planning-center-sync",
            body: data
        )
    }

    func importCSV(
        _ document: CSVDocument,
        kind: CSVImportKind,
        sourceName: String
    ) async throws -> ImportSummary {
        let run = try await createImportRun(kind: kind, sourceName: sourceName)
        var summary = ImportSummary()

        for (offset, row) in document.rows.enumerated() {
            let rowNumber = offset + 2
            do {
                let result: ImportRPCResult
                switch kind {
                case .members:
                    guard
                        let firstName = row.csvValue("First Name", "first_name"),
                        let lastName = row.csvValue("Last Name", "last_name")
                    else {
                        continue
                    }
                    let externalId = row.csvValue("id")
                        ?? "\(sourceName)-member-row-\(rowNumber)"
                    let record = PersonImportRecord(
                        firstName: firstName,
                        middleName: row.csvValue("Middle Name", "middle_name"),
                        lastName: lastName,
                        preferredName: row.csvValue("Preferred Name", "preferred_name"),
                        suffix: row.csvValue("Suffix"),
                        email: row.csvValue("Home Email", "Email"),
                        mobilePhone: row.csvValue("Mobile Phone Number", "Mobile Phone"),
                        homePhone: row.csvValue("Home Phone Number", "Home Phone"),
                        addressLine1: row.csvValue("Address Line 1"),
                        addressLine2: row.csvValue("Address Line 2"),
                        city: row.csvValue("City"),
                        stateRegion: row.csvValue("State", "State Region"),
                        postalCode: row.csvValue("Postal Code", "ZIP"),
                        countryCode: row.csvValue("Country Code"),
                        isActive: true
                    )
                    result = try await mergePerson(
                        externalId: externalId,
                        record: record,
                        runId: run.id,
                        rowNumber: rowNumber
                    )

                case .assignments:
                    guard
                        let personName = row.csvValue("Name", "Person Name"),
                        let roleName = row.csvValue("Role", "Role Name")
                    else {
                        continue
                    }
                    let externalId = row.csvValue("id")
                        ?? "\(sourceName)-assignment-row-\(rowNumber)"
                    let canonicalRoleName = roleName == "Sabbath Schol — Fireside D"
                        ? "Sabbath School — Fireside D"
                        : roleName
                    let record = AssignmentImportRecord(
                        personName: personName,
                        roleName: canonicalRoleName,
                        subRoleName: row.csvValue("Sub-Role", "Sub Role", "Sub Role Name"),
                        termName: row.csvValue("Term", "Term Name"),
                        voteDate: ImportedDate.storageValue(row.csvValue("Voted", "Vote Date")),
                        notes: row.csvValue("Notes")
                    )
                    result = try await mergeAssignment(
                        externalId: externalId,
                        record: record,
                        runId: run.id,
                        rowNumber: rowNumber
                    )
                }
                summary.record(outcome: result.outcome)
            } catch {
                summary.errors += 1
            }
        }

        try await finishImportRun(run.id, summary: summary)
        return summary
    }

    private func createImportRun(
        kind: CSVImportKind,
        sourceName: String
    ) async throws -> ImportRunRecord {
        let payload = ImportRunWrite(
            sourceType: kind == .members ? "members_csv" : "assignments_csv",
            sourceName: sourceName,
            status: "processing"
        )
        let rows: [ImportRunRecord] = try await restWrite(
            "POST",
            table: "import_runs",
            body: payload
        )
        guard let run = rows.first else { throw SupabaseClientError.emptyResponse }
        return run
    }

    private func finishImportRun(_ id: UUID, summary: ImportSummary) async throws {
        let status = summary.errors > 0
            ? "failed"
            : (summary.conflicts > 0 ? "completed_with_conflicts" : "completed")
        let payload = ImportRunFinish(
            status: status,
            insertedCount: summary.inserted,
            updatedCount: summary.updated,
            unchangedCount: summary.unchanged,
            conflictCount: summary.conflicts,
            errorCount: summary.errors,
            completedAt: ISO8601DateFormatter().string(from: Date())
        )
        let _: [ImportRunRecord] = try await restWrite(
            "PATCH",
            table: "import_runs",
            query: [.init(name: "id", value: "eq.\(id.uuidString)")],
            body: payload
        )
    }

    private func mergePerson(
        externalId: String,
        record: PersonImportRecord,
        runId: UUID,
        rowNumber: Int
    ) async throws -> ImportRPCResult {
        let body = MergePersonRequest(
            pSourceSystem: "members_csv",
            pExternalId: externalId,
            pRecord: record,
            pImportRunId: runId,
            pRowNumber: rowNumber
        )
        return try await rpc("merge_person_from_source", body: body)
    }

    private func mergeAssignment(
        externalId: String,
        record: AssignmentImportRecord,
        runId: UUID,
        rowNumber: Int
    ) async throws -> ImportRPCResult {
        let body = MergeAssignmentRequest(
            pSourceSystem: "assignments_csv",
            pExternalId: externalId,
            pRecord: record,
            pImportRunId: runId,
            pRowNumber: rowNumber
        )
        return try await rpc("upsert_assignment_from_source", body: body)
    }

    private func rpc<Response: Decodable, Body: Encodable>(
        _ name: String,
        body: Body
    ) async throws -> Response {
        let data = try encoder.encode(body)
        return try await send(
            method: "POST",
            path: "rest/v1/rpc/\(name)",
            body: data
        )
    }

    private func restAll<Element: Decodable>(
        _ relation: String,
        query: [URLQueryItem]
    ) async throws -> [Element] {
        let pageSize = 1000
        var offset = 0
        var result: [Element] = []

        while true {
            let page: [Element] = try await send(
                method: "GET",
                path: "rest/v1/\(relation)",
                query: query + [
                    .init(name: "limit", value: String(pageSize)),
                    .init(name: "offset", value: String(offset))
                ]
            )
            result.append(contentsOf: page)
            if page.count < pageSize { return result }
            offset += pageSize
        }
    }

    private func restWrite<Response: Decodable, Body: Encodable>(
        _ method: String,
        table: String,
        query: [URLQueryItem] = [],
        body: Body
    ) async throws -> Response {
        let data = try encoder.encode(body)
        return try await send(
            method: method,
            path: "rest/v1/\(table)",
            query: query,
            body: data,
            preferRepresentation: true
        )
    }

    private func send<Response: Decodable>(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        requiresAuthentication: Bool = true,
        preferRepresentation: Bool = false
    ) async throws -> Response {
        guard configuration.isValid else {
            throw SupabaseClientError.invalidConfiguration
        }

        let trimmedBase = configuration.projectURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: "\(trimmedBase)/\(path)") else {
            throw SupabaseClientError.invalidConfiguration
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw SupabaseClientError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if preferRepresentation {
            request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        }

        if requiresAuthentication {
            let accessToken = try await validAccessToken()
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        var result = try await urlSession.data(for: request)
        if
            let http = result.1 as? HTTPURLResponse,
            http.statusCode == 401,
            String(data: result.0, encoding: .utf8)?
                .localizedCaseInsensitiveContains("JWT issued at future") == true
        {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            result = try await urlSession.data(for: request)
        }

        let (data, response) = result
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let detail = try? decoder.decode(SupabaseErrorResponse.self, from: data) {
                let message = detail.message
                    ?? detail.errorDescription
                    ?? detail.error
                    ?? "Unknown server error"
                if
                    http.statusCode == 400,
                    detail.code == "invalid_credentials"
                        || detail.errorCode == "invalid_credentials"
                        || message.localizedCaseInsensitiveContains(
                            "invalid login credentials"
                        )
                {
                    throw SupabaseClientError.invalidCredentials
                }
                if
                    http.statusCode == 400,
                    detail.code == "refresh_token_not_found"
                        || detail.errorCode == "refresh_token_not_found"
                        || message.localizedCaseInsensitiveContains("invalid refresh token")
                {
                    throw SupabaseClientError.sessionExpired
                }
                throw SupabaseClientError.server(
                    status: http.statusCode,
                    message: message
                )
            }
            throw SupabaseClientError.server(
                status: http.statusCode,
                message: String(data: data, encoding: .utf8) ?? "Unknown server error"
            )
        }
        guard !data.isEmpty else { throw SupabaseClientError.emptyResponse }
        return try decoder.decode(Response.self, from: data)
    }
}

enum SupabaseClientError: LocalizedError {
    case invalidConfiguration
    case notSignedIn
    case invalidCredentials
    case sessionExpired
    case invalidRequest(String)
    case invalidResponse
    case emptyResponse
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            "Enter a valid Supabase project URL and publishable key."
        case .notSignedIn:
            "Sign in to continue."
        case .invalidCredentials:
            "The email or password is incorrect."
        case .sessionExpired:
            "Your saved sign-in has expired. Please sign in again."
        case .invalidRequest(let message):
            message
        case .invalidResponse:
            "Supabase returned an invalid response."
        case .emptyResponse:
            "Supabase returned no data."
        case .server(let status, let message):
            "Supabase error \(status): \(message)"
        }
    }
}

private struct SignInRequest: Encodable {
    let email: String
    let password: String
}

private struct PasswordResetRequest: Encodable {
    let email: String
}

private struct AppUserInvitationRequest: Encodable {
    let email: String
    let role: AppUserRole
}

private struct RefreshRequest: Encodable {
    let refreshToken: String
}

private struct SupabaseErrorResponse: Decodable {
    let code: String?
    let errorCode: String?
    let message: String?
    let error: String?
    let errorDescription: String?
}

private struct EmptyBody: Codable {}

private struct PlanningCenterConnectionWrite: Encodable {
    let pApplicationId: String
    let pSecret: String
}

private struct PersonWrite: Encodable {
    let firstName: String
    let middleName: String?
    let lastName: String
    let preferredName: String?
    let suffix: String?
    let email: String?
    let mobilePhone: String?
    let homePhone: String?
    let isActive: Bool
    let isPublic: Bool
    let isOrdainedDeacon: Bool
    let isOrdainedDeaconess: Bool
    let isOrdainedElder: Bool
}

private struct PersonOrdinationWrite: Encodable {
    let isOrdainedDeacon: Bool
    let isOrdainedDeaconess: Bool
    let isOrdainedElder: Bool
}

private struct AssignmentWrite: Encodable {
    let personId: UUID
    let roleId: UUID
    let subRoleId: UUID?
    let termId: UUID?
    let voteDate: String?
    let notes: String?
    let noteIsPublic: Bool
    let status: String
    let isPublic: Bool
}

private struct AssignmentNoteWrite: Encodable {
    let notes: String?
    let noteIsPublic: Bool
}

private struct AssignmentVoteWrite: Encodable {
    let voteDate: String?
}

struct AssignmentDetailsWrite: Encodable {
    let subRoleId: UUID?
    let termId: UUID?
    let notes: String?
    let noteIsPublic: Bool
    let voteDate: String?

    private enum CodingKeys: String, CodingKey {
        case subRoleId
        case termId
        case notes
        case noteIsPublic
        case voteDate
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let subRoleId {
            try container.encode(subRoleId, forKey: .subRoleId)
        } else {
            try container.encodeNil(forKey: .subRoleId)
        }
        if let termId {
            try container.encode(termId, forKey: .termId)
        } else {
            try container.encodeNil(forKey: .termId)
        }
        if let notes {
            try container.encode(notes, forKey: .notes)
        } else {
            try container.encodeNil(forKey: .notes)
        }
        try container.encode(noteIsPublic, forKey: .noteIsPublic)
        if let voteDate {
            try container.encode(voteDate, forKey: .voteDate)
        } else {
            try container.encodeNil(forKey: .voteDate)
        }
    }
}

private struct AssignmentStatusWrite: Encodable {
    let status: String
}

private struct AssignmentWriteResult: Decodable {
    let id: UUID
}

private struct RoleWrite: Encodable {
    let name: String
    let description: String?
    let requiresVote: Bool
    let isActive: Bool
    let isPublic: Bool
    let displayOrder: Int
}

private struct SubRoleWrite: Encodable {
    let roleId: UUID
    let name: String
    let leadershipRank: Int
    let requiresVote: Bool
    let isActive: Bool
}

private struct TermWrite: Encodable {
    let name: String
    let startDate: String?
    let endDate: String?
    let termType: String
    let isActive: Bool
}

private struct ImportRunWrite: Encodable {
    let sourceType: String
    let sourceName: String
    let status: String
}

private struct ImportRunFinish: Encodable {
    let status: String
    let insertedCount: Int
    let updatedCount: Int
    let unchangedCount: Int
    let conflictCount: Int
    let errorCount: Int
    let completedAt: String
}

private struct ImportRunRecord: Decodable {
    let id: UUID
}

private struct PersonImportRecord: Encodable {
    let firstName: String
    let middleName: String?
    let lastName: String
    let preferredName: String?
    let suffix: String?
    let email: String?
    let mobilePhone: String?
    let homePhone: String?
    let addressLine1: String?
    let addressLine2: String?
    let city: String?
    let stateRegion: String?
    let postalCode: String?
    let countryCode: String?
    let isActive: Bool
}

private struct AssignmentImportRecord: Encodable {
    let personName: String
    let roleName: String
    let subRoleName: String?
    let termName: String?
    let voteDate: String?
    let notes: String?
}

private struct MergePersonRequest: Encodable {
    let pSourceSystem: String
    let pExternalId: String
    let pRecord: PersonImportRecord
    let pImportRunId: UUID
    let pRowNumber: Int
}

private struct MergeAssignmentRequest: Encodable {
    let pSourceSystem: String
    let pExternalId: String
    let pRecord: AssignmentImportRecord
    let pImportRunId: UUID
    let pRowNumber: Int
}
