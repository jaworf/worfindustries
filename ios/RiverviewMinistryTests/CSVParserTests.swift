import XCTest
@testable import RiverviewMinistry

final class CSVParserTests: XCTestCase {
    func testAccountDeletionRequestsRequireExplicitConfirmation() async throws {
        DeletionRequestURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeletionRequestURLProtocol.self]
        let client = SupabaseRESTClient(
            configuration: SupabaseConfiguration(
                projectURL: "https://example.supabase.co",
                publishableKey: "sb_publishable_test"
            ),
            session: SupabaseSession(
                accessToken: "test-access-token",
                refreshToken: "test-refresh-token",
                expiresAt: Date().timeIntervalSince1970 + 3600,
                user: SupabaseUser(id: UUID(), email: "reviewer@example.com")
            ),
            urlSession: URLSession(configuration: configuration)
        )
        let targetId = UUID()
        try await client.updateAppUser(targetId, action: "delete_user")
        try await client.deleteOwnAccount()

        let requests = DeletionRequestURLProtocol.requests
        XCTAssertEqual(requests.count, 2)
        let adminRequest = try XCTUnwrap(requests.first)
        let selfRequest = try XCTUnwrap(requests.last)
        XCTAssertEqual(adminRequest["action"], "delete_user")
        XCTAssertEqual(adminRequest["user_id"], targetId.uuidString)
        XCTAssertEqual(adminRequest["confirmation"], "DELETE")
        XCTAssertEqual(selfRequest["action"], "delete_self")
        XCTAssertNil(selfRequest["user_id"])
        XCTAssertEqual(selfRequest["confirmation"], "DELETE")
    }

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

    func testInvalidCredentialsHaveFriendlyMessage() {
        XCTAssertEqual(
            SupabaseClientError.invalidCredentials.localizedDescription,
            "The email or password is incorrect."
        )
    }

    func testExpiredSessionHasFriendlyMessage() {
        XCTAssertEqual(
            SupabaseClientError.sessionExpired.localizedDescription,
            "Your saved sign-in has expired. Please sign in again."
        )
    }

    func testConcurrentSnapshotRequestsShareOneTokenRefresh() async throws {
        RefreshCoalescingURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RefreshCoalescingURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)
        let userId = UUID()
        let client = SupabaseRESTClient(
            configuration: SupabaseConfiguration(
                projectURL: "https://example.supabase.co",
                publishableKey: "sb_publishable_test"
            ),
            session: SupabaseSession(
                accessToken: "expired-access-token",
                refreshToken: "single-use-refresh-token",
                expiresAt: 0,
                user: SupabaseUser(id: userId, email: "tester@example.com")
            ),
            urlSession: urlSession
        )

        _ = try await client.loadSnapshot()

        XCTAssertEqual(RefreshCoalescingURLProtocol.refreshRequestCount, 1)
    }

    func testMissingRefreshTokenBecomesExpiredSessionError() async throws {
        RefreshCoalescingURLProtocol.reset(rejectRefresh: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RefreshCoalescingURLProtocol.self]
        let client = SupabaseRESTClient(
            configuration: SupabaseConfiguration(
                projectURL: "https://example.supabase.co",
                publishableKey: "sb_publishable_test"
            ),
            session: SupabaseSession(
                accessToken: "expired-access-token",
                refreshToken: "missing-refresh-token",
                expiresAt: 0,
                user: SupabaseUser(id: UUID(), email: "tester@example.com")
            ),
            urlSession: URLSession(configuration: configuration)
        )

        do {
            _ = try await client.loadSnapshot()
            XCTFail("An invalid stored refresh token should require a new sign-in.")
        } catch let error as SupabaseClientError {
            guard case .sessionExpired = error else {
                return XCTFail("Expected sessionExpired, received \(error)")
            }
        }
    }

    func testOnlyNonAdministratorRolesAreAvailableForInvitations() {
        XCTAssertEqual(AppUserRole.invitationChoices, [.editor, .viewer])
        XCTAssertFalse(AppUserRole.invitationChoices.contains(.admin))
    }

    @MainActor
    func testStartupRestorationAlwaysCompletes() async {
        let model = AppModel()

        XCTAssertFalse(model.hasRestoredSession)
        await model.restoreStoredSession()

        XCTAssertTrue(model.hasRestoredSession)
        XCTAssertTrue(model.isConfigured)
    }

    func testAssignmentWithoutVoteRequirementDoesNotRequireTermOrVoteDate() {
        let requirements = AssignmentRequirements(
            ministryRequiresVote: false,
            positionRequiresVote: false
        )

        XCTAssertFalse(requirements.requiresChurchVote)
        XCTAssertFalse(requirements.requiresTerm)
        XCTAssertNil(requirements.validationMessage(termId: nil, voteDate: nil))
    }

    func testMinistryVoteRequirementRequiresTermWithOptionalVoteDate() {
        let requirements = AssignmentRequirements(
            ministryRequiresVote: true,
            positionRequiresVote: false
        )
        let termId = UUID()

        XCTAssertTrue(requirements.requiresTerm)
        XCTAssertNotNil(requirements.validationMessage(termId: nil, voteDate: Date()))
        XCTAssertNil(requirements.validationMessage(termId: termId, voteDate: nil))
        XCTAssertNil(requirements.validationMessage(termId: termId, voteDate: Date()))
    }

    func testTeamMemberNeedsNoTermOrVoteEvenWhenMinistryRequiresVote() {
        for ministryVote in [false, true] {
            for positionVote in [false, true] {
                let requirements = AssignmentRequirements(
                    ministryRequiresVote: ministryVote,
                    positionRequiresVote: positionVote,
                    hasPosition: false
                )
                XCTAssertFalse(requirements.requiresChurchVote)
                XCTAssertFalse(requirements.requiresTerm)
                XCTAssertNil(requirements.validationMessage(termId: nil, voteDate: nil))
            }
        }
    }

    func testPositionVoteRequirementRequiresTermWithOptionalVoteDate() {
        let requirements = AssignmentRequirements(
            ministryRequiresVote: false,
            positionRequiresVote: true
        )

        XCTAssertTrue(requirements.requiresChurchVote)
        XCTAssertTrue(requirements.requiresTerm)
    }

    func testAssignmentDetailsUpdateIncludesPositionAndExplicitNulls() throws {
        let positionId = UUID()
        let payload = AssignmentDetailsWrite(
            subRoleId: positionId,
            termId: nil,
            notes: nil,
            noteIsPublic: false,
            voteDate: nil
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(payload)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(json["sub_role_id"] as? String, positionId.uuidString)
        XCTAssertTrue(json["term_id"] is NSNull)
        XCTAssertTrue(json["notes"] is NSNull)
        XCTAssertEqual(json["note_is_public"] as? Bool, false)
        XCTAssertTrue(json["vote_date"] is NSNull)
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

    func testOrdinationFocusIncludesOnlyCurrentUnordainedTeamMembers() throws {
        let role = makeRole(name: "Deacon")
        let position = MinistrySubRole(
            id: UUID(),
            roleId: role.id,
            name: "Team Member",
            leadershipRank: 100,
            requiresVote: false,
            isActive: true
        )
        let needsOrdination = makePerson(name: "Needs Ordination", ordainedDeacon: false)
        let alreadyOrdained = makePerson(name: "Already Ordained", ordainedDeacon: true)
        let archivedPerson = makePerson(name: "Archived Person", ordainedDeacon: false)

        let needs = makeOrdinationFocusNeeds(
            people: [needsOrdination, alreadyOrdained, archivedPerson],
            assignments: [
                makeAssignment(
                    role: role,
                    position: position,
                    personId: needsOrdination.id,
                    personName: needsOrdination.displayName,
                    status: "active",
                    endDate: "2028-06-30"
                ),
                makeAssignment(
                    role: role,
                    position: position,
                    personId: alreadyOrdained.id,
                    personName: alreadyOrdained.displayName,
                    status: "active",
                    endDate: "2028-06-30"
                ),
                makeAssignment(
                    role: role,
                    position: position,
                    personId: archivedPerson.id,
                    personName: archivedPerson.displayName,
                    status: "completed",
                    endDate: "2028-06-30"
                )
            ],
            now: try XCTUnwrap(AppDate.parse("2026-08-05"))
        )

        XCTAssertEqual(needs.map(\.person.id), [needsOrdination.id])
        XCTAssertEqual(needs.first?.kind, .deacon)
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
        personId: UUID = UUID(),
        personName: String,
        status: String,
        endDate: String
    ) -> AssignmentDetail {
        let nameParts = personName.split(separator: " ").map(String.init)
        return AssignmentDetail(
            id: UUID(),
            personId: personId,
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

    private func makePerson(name: String, ordainedDeacon: Bool) -> Person {
        let parts = name.split(separator: " ").map(String.init)
        return Person(
            id: UUID(),
            firstName: parts.first ?? name,
            middleName: nil,
            lastName: parts.last ?? name,
            preferredName: nil,
            suffix: nil,
            email: nil,
            mobilePhone: nil,
            homePhone: nil,
            addressLine1: nil,
            addressLine2: nil,
            city: nil,
            stateRegion: nil,
            postalCode: nil,
            countryCode: nil,
            membershipStatus: nil,
            notes: nil,
            isActive: true,
            isPublic: false,
            isOrdainedDeacon: ordainedDeacon,
            isOrdainedDeaconess: false,
            isOrdainedElder: false,
            sourceCreatedAt: nil,
            sourceUpdatedAt: nil,
            createdAt: nil
        )
    }
}

private final class DeletionRequestURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var storedRequests: [[String: String]] = []

    static var requests: [[String: String]] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        storedRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/functions/v1/admin-users")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token")
            var body = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
            }
            let payload = try JSONDecoder().decode([String: String].self, from: body)
            Self.lock.lock()
            Self.storedRequests.append(payload)
            Self.lock.unlock()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{\"message\":\"Account deleted\"}".utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class RefreshCoalescingURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var storedRefreshRequestCount = 0
    nonisolated(unsafe) private static var rejectRefresh = false

    static var refreshRequestCount: Int {
        lock.withLock { storedRefreshRequestCount }
    }

    static func reset(rejectRefresh: Bool = false) {
        lock.withLock {
            storedRefreshRequestCount = 0
            Self.rejectRefresh = rejectRefresh
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let data: Data
        let statusCode: Int
        if url.path == "/auth/v1/token" {
            Self.lock.withLock { Self.storedRefreshRequestCount += 1 }
            Thread.sleep(forTimeInterval: 0.15)
            if Self.lock.withLock({ Self.rejectRefresh }) {
                statusCode = 400
                data = Data(
                    """
                    {
                      "error_code": "refresh_token_not_found",
                      "message": "Invalid Refresh Token: Refresh Token Not Found"
                    }
                    """.utf8
                )
            } else {
                statusCode = 200
                data = Data(
                    """
                    {
                      "access_token": "fresh-access-token",
                      "refresh_token": "rotated-refresh-token",
                      "expires_at": 4102444800,
                      "user": {
                        "id": "00000000-0000-0000-0000-000000000001",
                        "email": "tester@example.com"
                      }
                    }
                    """.utf8
                )
            }
        } else {
            statusCode = 200
            data = Data("[]".utf8)
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
