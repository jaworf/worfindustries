import SwiftUI

private struct PositionFocusKey: Hashable {
    let roleId: UUID
    let subRoleId: UUID?
}

struct PositionCoverageGap: Identifiable {
    let roleId: UUID
    let subRoleId: UUID?
    let positionName: String
    let replacementsNeeded: Int
    let outgoingNames: [String]
    let lastTermEnd: Date

    var id: String {
        "\(roleId.uuidString)-\(subRoleId?.uuidString ?? "none")"
    }
}

struct MinistryFocusNeed: Identifiable {
    let role: MinistryRole
    let activeVolunteerCount: Int
    let positionGaps: [PositionCoverageGap]

    var id: UUID { role.id }
    var isEmpty: Bool { activeVolunteerCount == 0 }
}

struct OrdinationFocusNeed: Identifiable {
    let person: Person
    let kind: OrdinationKind
    let ministryName: String

    var id: String { "\(person.id.uuidString)-\(kind.rawValue)" }
}

func makeOrdinationFocusNeeds(
    people: [Person],
    assignments: [AssignmentDetail],
    now: Date = Date()
) -> [OrdinationFocusNeed] {
    let calendar = Calendar.autoupdatingCurrent
    let today = calendar.startOfDay(for: now)
    let peopleById = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
    var needsById: [String: OrdinationFocusNeed] = [:]

    for assignment in assignments {
        guard
            assignment.status == "active",
            assignment.ministryIsActive,
            assignment.endDateValue.map({ calendar.startOfDay(for: $0) >= today }) ?? true,
            let kind = OrdinationKind.matching(ministryName: assignment.roleName),
            let person = peopleById[assignment.personId],
            person.isActive
        else {
            continue
        }

        let isOrdained = switch kind {
        case .deacon: person.isOrdainedDeacon
        case .deaconess: person.isOrdainedDeaconess
        case .elder: person.isOrdainedElder
        }
        guard !isOrdained else { continue }

        let need = OrdinationFocusNeed(
            person: person,
            kind: kind,
            ministryName: assignment.roleName
        )
        needsById[need.id] = need
    }

    return needsById.values.sorted { left, right in
        let ministryOrder = left.ministryName.localizedCaseInsensitiveCompare(right.ministryName)
        if ministryOrder != .orderedSame { return ministryOrder == .orderedAscending }
        let lastOrder = left.person.lastName.localizedCaseInsensitiveCompare(right.person.lastName)
        if lastOrder != .orderedSame { return lastOrder == .orderedAscending }
        return left.person.firstName.localizedCaseInsensitiveCompare(right.person.firstName)
            == .orderedAscending
    }
}

struct PlacementFocusSnapshot {
    let ministryNeeds: [MinistryFocusNeed]
    let activePersonIds: Set<UUID>

    init(
        roles: [MinistryRole],
        subRoles: [MinistrySubRole],
        assignments: [AssignmentDetail],
        now: Date = Date()
    ) {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: now)
        let activeRoles = roles.filter(\.isActive)
        let activeRoleIds = Set(activeRoles.map(\.id))
        let positionNames = Dictionary(
            uniqueKeysWithValues: subRoles.map { ($0.id, $0.name) }
        )
        let leadershipRanks = Dictionary(
            uniqueKeysWithValues: subRoles.map { ($0.id, $0.leadershipRank) }
        )

        let currentAssignments = assignments.filter { assignment in
            guard
                assignment.status == "active",
                assignment.ministryIsActive,
                activeRoleIds.contains(assignment.roleId)
            else {
                return false
            }
            guard let endDate = assignment.endDateValue else { return true }
            return calendar.startOfDay(for: endDate) >= today
        }
        activePersonIds = Set(currentAssignments.map(\.personId))

        let expiredAssignments = assignments.filter { assignment in
            guard
                activeRoleIds.contains(assignment.roleId),
                let endDate = assignment.endDateValue
            else {
                return false
            }
            return calendar.startOfDay(for: endDate) < today
        }
        let expiredByPosition = Dictionary(
            grouping: expiredAssignments,
            by: { PositionFocusKey(roleId: $0.roleId, subRoleId: $0.subRoleId) }
        )
        let currentByPosition = Dictionary(
            grouping: currentAssignments,
            by: { PositionFocusKey(roleId: $0.roleId, subRoleId: $0.subRoleId) }
        )

        var gapsByRole: [UUID: [PositionCoverageGap]] = [:]
        for (key, history) in expiredByPosition {
            guard let latestEnd = history.compactMap(\.endDateValue).max() else { continue }
            let latestOutgoing = history.filter { assignment in
                guard let endDate = assignment.endDateValue else { return false }
                return calendar.isDate(endDate, inSameDayAs: latestEnd)
            }
            let selectedReplacementCount = Set(
                (currentByPosition[key] ?? []).map(\.personId)
            ).count
            let replacementsNeeded = max(
                latestOutgoing.count - selectedReplacementCount,
                0
            )
            guard replacementsNeeded > 0 else { continue }

            let outgoingNames = latestOutgoing
                .map(\.personName)
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            let positionName = key.subRoleId
                .flatMap { positionNames[$0] }
                ?? latestOutgoing.first?.subRoleName
                ?? "Unspecified position"
            gapsByRole[key.roleId, default: []].append(
                PositionCoverageGap(
                    roleId: key.roleId,
                    subRoleId: key.subRoleId,
                    positionName: positionName,
                    replacementsNeeded: replacementsNeeded,
                    outgoingNames: outgoingNames,
                    lastTermEnd: latestEnd
                )
            )
        }

        ministryNeeds = activeRoles.compactMap { role in
            let activeVolunteerCount = Set(
                currentAssignments
                    .filter { $0.roleId == role.id }
                    .map(\.personId)
            ).count
            let positionGaps = (gapsByRole[role.id] ?? []).sorted { left, right in
                let leftRank = left.subRoleId.flatMap { leadershipRanks[$0] } ?? 100
                let rightRank = right.subRoleId.flatMap { leadershipRanks[$0] } ?? 100
                if leftRank != rightRank { return leftRank < rightRank }
                return left.positionName.localizedCaseInsensitiveCompare(right.positionName)
                    == .orderedAscending
            }
            guard activeVolunteerCount == 0 || !positionGaps.isEmpty else { return nil }
            return MinistryFocusNeed(
                role: role,
                activeVolunteerCount: activeVolunteerCount,
                positionGaps: positionGaps
            )
        }
        .sorted {
            if $0.isEmpty != $1.isEmpty { return $0.isEmpty }
            return $0.role.name.localizedCaseInsensitiveCompare($1.role.name)
                == .orderedAscending
        }
    }
}

private enum VolunteerActivationScope: String, CaseIterable, Identifiable {
    case new = "New"
    case local = "Local"
    case all = "All"

    var id: String { rawValue }
}

struct FocusView: View {
    @EnvironmentObject private var model: AppModel
    @State private var activationScope: VolunteerActivationScope = .local
    @State private var membershipFilter = "All membership statuses"
    @State private var search = ""

    let assign: (AssignmentRoute) -> Void

    private struct ViewData {
        let snapshot: PlacementFocusSnapshot
        let ordinationNeeds: [OrdinationFocusNeed]
        let unassignedPeople: [Person]
        let newUnassignedCount: Int
        let membershipOptions: [String]
        let filteredPeople: [Person]
        let displayedPeople: [Person]
    }

    private func makeViewData() -> ViewData {
        let snapshot = PlacementFocusSnapshot(
            roles: model.roles,
            subRoles: model.subRoles,
            assignments: model.assignments
        )
        let activePersonIds = snapshot.activePersonIds
        let unassignedPeople = model.people.filter {
            $0.isActive && !activePersonIds.contains($0.id)
        }
        let newCutoff = Calendar.autoupdatingCurrent.date(
            byAdding: .day,
            value: -90,
            to: Date()
        ) ?? Date.distantPast
        let addedDates = Dictionary(
            uniqueKeysWithValues: unassignedPeople.compactMap { person in
                person.addedDate.map { (person.id, $0) }
            }
        )
        let newUnassignedCount = unassignedPeople.filter {
            (addedDates[$0.id] ?? .distantPast) >= newCutoff
        }.count
        let membershipValues = Set(
            unassignedPeople.compactMap { $0.membershipStatus.nilIfBlank }
        )
        .filter { $0 != "No membership status" }
        let membershipOptions = ["All membership statuses", "No membership status"]
            + membershipValues.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredPeople = unassignedPeople
            .filter { person in
                switch activationScope {
                case .new:
                    guard (addedDates[person.id] ?? .distantPast) >= newCutoff else {
                        return false
                    }
                case .local:
                    guard ["Riverview Member", "Regular Attender"].contains(
                        person.membershipStatus ?? ""
                    ) else {
                        return false
                    }
                case .all:
                    break
                }

                if membershipFilter == "No membership status" {
                    guard person.membershipStatus.nilIfBlank == nil else { return false }
                } else if membershipFilter != "All membership statuses" {
                    guard person.membershipStatus == membershipFilter else { return false }
                }

                guard !query.isEmpty else { return true }
                return [
                    person.displayName,
                    person.email ?? "",
                    person.mobilePhone ?? "",
                    person.homePhone ?? "",
                    person.membershipStatus ?? ""
                ].contains { $0.localizedCaseInsensitiveContains(query) }
            }
            .sorted { left, right in
                let leftMembershipPriority = left.membershipStatus == "Riverview Member" ? 0 : 1
                let rightMembershipPriority = right.membershipStatus == "Riverview Member" ? 0 : 1
                if leftMembershipPriority != rightMembershipPriority {
                    return leftMembershipPriority < rightMembershipPriority
                }
                let leftDate = addedDates[left.id] ?? .distantPast
                let rightDate = addedDates[right.id] ?? .distantPast
                if leftDate != rightDate { return leftDate > rightDate }
                let lastOrder = left.lastName.localizedCaseInsensitiveCompare(right.lastName)
                if lastOrder != .orderedSame { return lastOrder == .orderedAscending }
                return left.firstName.localizedCaseInsensitiveCompare(right.firstName)
                    == .orderedAscending
            }
        return ViewData(
            snapshot: snapshot,
            ordinationNeeds: makeOrdinationFocusNeeds(
                people: model.people,
                assignments: model.assignments
            ),
            unassignedPeople: unassignedPeople,
            newUnassignedCount: newUnassignedCount,
            membershipOptions: membershipOptions,
            filteredPeople: filteredPeople,
            displayedPeople: Array(filteredPeople.prefix(75))
        )
    }

    var body: some View {
        let data = makeViewData()

        Form {
            Section("Needing Votes") {
                ForEach(model.assignments.filter { $0.isCurrentPlacement && $0.voteMissing }) { assignment in
                    PendingVoteRow(assignment: assignment).disabled(!model.canEdit || model.isBusy)
                }
            }
            Section {
                if data.ordinationNeeds.isEmpty {
                    Label(
                        "Every current Deacon, Deaconess, and Elder is marked ordained.",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                    .padding(.vertical, 12)
                } else {
                    ForEach(data.ordinationNeeds) { need in
                        OrdinationFocusRow(need: need)
                    }
                }
            } header: {
                Text("Ordination Actions")
            } footer: {
                Text(
                    "This queue shows current Deacons, Deaconesses, and Elders whose matching " +
                    "permanent ordination record is not checked. Ordination is never included in reports."
                )
            }

            Section("Terms ending in the next 6 months") {
                ForEach(model.assignments.filter { assignment in
                    guard assignment.isCurrentPlacement, let end = assignment.endDateValue,
                          let cutoff = Calendar.autoupdatingCurrent.date(byAdding: .month, value: 6, to: Date()) else { return false }
                    return end >= Calendar.autoupdatingCurrent.startOfDay(for: Date()) && end <= cutoff
                }) { assignment in
                    Button {
                        assign(AssignmentRoute(personId: assignment.personId, roleId: assignment.roleId, subRoleId: assignment.subRoleId))
                    } label: {
                        VStack(alignment: .leading) {
                            Text(assignment.personName).fontWeight(.semibold)
                            Text(assignment.roleName).foregroundStyle(.secondary)
                        }
                    }.disabled(!model.canEdit)
                }
            }
            Section {
                if data.snapshot.ministryNeeds.isEmpty {
                    Label("Every active ministry currently has coverage.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .padding(.vertical, 12)
                } else {
                    ForEach(data.snapshot.ministryNeeds) { need in
                        MinistryFocusRow(need: need, assign: assign)
                    }
                }
            } header: {
                Text("Ministries Needing Volunteers")
            } footer: {
                Text(
                    "A ministry appears here when it has no active volunteer or when the " +
                    "most recently completed position has fewer replacements than outgoing volunteers."
                )
            }

            Section {
                Picker("People to show", selection: $activationScope) {
                    ForEach(VolunteerActivationScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Membership", selection: $membershipFilter) {
                    ForEach(data.membershipOptions, id: \.self) { membership in
                        Text(membership).tag(membership)
                    }
                }

                TextField("Search name, contact information, or membership", text: $search)
                    .textFieldStyle(.roundedBorder)

                LabeledContent("People matching filters") {
                    Text("\(data.filteredPeople.count)")
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.riverBlueDark)
                }
            } header: {
                Text("Volunteer Activation")
            } footer: {
                Text(
                    "New means added to Planning Center or this app within 90 days. Local " +
                    "shows unassigned Riverview Members and Regular Attenders. All keeps " +
                    "every active unassigned person available."
                )
            }

            Section {
                if data.filteredPeople.isEmpty {
                    ContentUnavailableView(
                        "No unassigned people match",
                        systemImage: "person.crop.circle.badge.checkmark",
                        description: Text("Try another scope, membership status, or search.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                } else {
                    ForEach(data.displayedPeople) { person in
                        VolunteerActivationRow(person: person) {
                            assign(
                                AssignmentRoute(
                                    personId: person.id,
                                    roleId: nil,
                                    subRoleId: nil
                                )
                            )
                        }
                    }
                }
            } header: {
                Text("People ready to connect")
            } footer: {
                if data.filteredPeople.count > data.displayedPeople.count {
                    Text(
                        "Showing the first \(data.displayedPeople.count) of \(data.filteredPeople.count). " +
                        "Use search or membership filters to narrow the list."
                    )
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 960)
        .frame(maxWidth: .infinity)
        .background(AppTheme.pageBackground)
        .navigationTitle("Placement Focus")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(model.isBusy)
                .accessibilityLabel("Reload")
            }
        }
        .onChange(of: activationScope) { _, _ in
            membershipFilter = "All membership statuses"
        }
    }

    @ViewBuilder
    private func summaryCards(data: ViewData) -> some View {
        FocusSummaryCard(
            title: "Ministries to review",
            value: data.snapshot.ministryNeeds.count,
            systemImage: "exclamationmark.circle.fill",
            color: .orange
        )
        FocusSummaryCard(
            title: "New and unassigned",
            value: data.newUnassignedCount,
            systemImage: "person.crop.circle.badge.plus",
            color: AppTheme.riverBlue
        )
        FocusSummaryCard(
            title: "All unassigned",
            value: data.unassignedPeople.count,
            systemImage: "person.2.slash",
            color: AppTheme.riverBlueDark
        )
        FocusSummaryCard(
            title: "Awaiting ordination",
            value: data.ordinationNeeds.count,
            systemImage: "person.crop.circle.badge.exclamationmark",
            color: .orange
        )
    }
}

private struct OrdinationFocusRow: View {
    @EnvironmentObject private var model: AppModel
    let need: OrdinationFocusNeed

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .appFont(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(need.person.displayName)
                    .appFont(.headline, weight: .semibold)
                Text("\(need.ministryName) · \(need.kind.label) is not checked")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.canEdit {
                Button("Mark \(need.kind.label)") {
                    var ordination = PersonOrdinationDraft(person: need.person)
                    switch need.kind {
                    case .deacon: ordination.isOrdainedDeacon = true
                    case .deaconess: ordination.isOrdainedDeaconess = true
                    case .elder: ordination.isOrdainedElder = true
                    }
                    Task {
                        _ = await model.updatePersonOrdination(
                            personId: need.person.id,
                            ordination: ordination
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isBusy)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct FocusSummaryCard: View {
    let title: String
    let value: Int
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .appFont(.title2, weight: .semibold)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)")
                    .appFont(.title2, weight: .bold)
                    .monospacedDigit()
                Text(title)
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(AppTheme.riverBlueSoft.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(0.2))
        }
    }
}

private struct MinistryFocusRow: View {
    let need: MinistryFocusNeed
    let assign: (AssignmentRoute) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(need.role.name)
                    .appFont(.title3, weight: .bold)
                    .foregroundStyle(AppTheme.riverBlueDark)
                Spacer()
                if need.isEmpty {
                    Text("EMPTY")
                        .appFont(.caption2, weight: .bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.orange, in: Capsule())
                }
            }

            if need.isEmpty {
                Label(
                    "No active volunteer is assigned to this ministry.",
                    systemImage: "person.crop.circle.badge.exclamationmark"
                )
                .foregroundStyle(.orange)
            } else {
                Text("\(need.activeVolunteerCount) active volunteer\(need.activeVolunteerCount == 1 ? "" : "s")")
                    .appFont(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(need.positionGaps) { gap in
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(gap.positionName): \(gap.replacementsNeeded) replacement\(gap.replacementsNeeded == 1 ? "" : "s") needed")
                        .appFont(.headline, weight: .semibold)
                    Text(
                        "Last term ended \(AppDate.display(gap.lastTermEnd)). " +
                        "Outgoing: \(gap.outgoingNames.joined(separator: ", "))."
                    )
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    Button {
                        assign(
                            AssignmentRoute(
                                personId: nil,
                                roleId: gap.roleId,
                                subRoleId: gap.subRoleId
                            )
                        )
                    } label: {
                        Label("Fill \(gap.positionName)", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(12)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }

            if need.isEmpty && need.positionGaps.isEmpty {
                Button {
                    assign(
                        AssignmentRoute(
                            personId: nil,
                            roleId: need.role.id,
                            subRoleId: nil
                        )
                    )
                } label: {
                    Label("Assign a Volunteer", systemImage: "person.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct VolunteerActivationRow: View {
    let person: Person
    let assign: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .appFont(.title2)
                .foregroundStyle(AppTheme.riverBlue)
            VStack(alignment: .leading, spacing: 4) {
                Text(person.displayName)
                    .appFont(.headline, weight: .semibold)
                HStack(spacing: 8) {
                    Text(person.membershipStatus.nilIfBlank ?? "No membership status")
                    if let addedDate = person.addedDate {
                        Text("•")
                        Text("Added \(AppDate.display(addedDate))")
                    }
                }
                .appFont(.caption)
                .foregroundStyle(.secondary)
                if let contact = person.email.nilIfBlank
                    ?? person.mobilePhone.nilIfBlank
                    ?? person.homePhone.nilIfBlank {
                    Text(contact)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Assign", action: assign)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(.vertical, 5)
    }
}

private let placementResponses = ["considering", "yes", "no", "maybe_later", "no_answer", "message_left", "other"]
private func placementLabel(_ value: String) -> String {
    if value == "yes" { return "Yes / Willing" }
    return value.replacingOccurrences(of: "_", with: " ").capitalized
}

struct VolunteerHistoryRows: View {
    let entries: [VolunteerContactEntry]
    var body: some View {
        if entries.isEmpty { Text("No volunteer contact history recorded.").foregroundStyle(.secondary) }
        ForEach(entries) { entry in
            VStack(alignment: .leading, spacing: 6) {
                Text("\(entry.happenedOn) · \(placementLabel(entry.kind == "call" ? (entry.response ?? "call") : entry.kind))").font(.headline)
                Text(entry.roleLabel)
                if let caller = entry.callerName { Text("Caller: \(caller)") }
                Text("Recorded by: \(entry.recorderName)").font(.caption)
                if !entry.notes.isEmpty { Text(entry.notes) }
                if let followUp = entry.followUp { Text("Follow up: \(followUp)") }
            }.padding(.vertical, 5)
        }
    }
}

struct PersonVolunteerHistorySection: View {
    @EnvironmentObject private var model: AppModel
    let personId: UUID
    @State private var entries: [VolunteerContactEntry] = []
    @State private var error: String?
    @State private var loading = true
    var body: some View {
        Section("Volunteer Contact History") {
            Text("Private church records. Responses apply to the opportunity discussed.").font(.caption)
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            if !loading && error == nil { VolunteerHistoryRows(entries: entries) }
        }.task(id: personId) {
            loading = true
            do { entries = try await model.loadPlacementWorkflow().history.filter { $0.personId == personId }; error = nil }
            catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}

struct PlacementWorkflowView: View {
    @EnvironmentObject private var model: AppModel
    @State private var data = PlacementSnapshot()
    @State private var scope = "Openings"
    @State private var selectedOpening: UUID?
    @State private var error: String?
    @State private var showingOpening = false
    @State private var personId = ""
    @State private var search = ""

    private func title(_ opening: PlacementOpening) -> String {
        [model.roles.first { $0.id == opening.roleId }?.name,
         model.subRoles.first { $0.id == opening.subRoleId }?.name,
         model.terms.first { $0.id == opening.termId }?.name].compactMap { $0 }.joined(separator: " · ")
    }
    private var displayed: [PlacementCandidate] {
        data.candidates.filter { candidate in
            switch scope {
            case "My Calls":
                return candidate.assignedTo == model.currentProfile?.userId
                    && data.openings.contains { $0.id == candidate.openingId && $0.status == "open" }
                    && !["elected", "appointed", "withdrawn", "not_elected"].contains(candidate.stage)
                    && (!["yes", "no"].contains(candidate.response) || candidate.followUp != nil)
            case "Nominations": return ["nominated", "first_reading", "second_reading", "deferred"].contains(candidate.stage)
            default: return candidate.openingId == selectedOpening
            }
        }
    }
    private func refresh() async {
        do { data = try await model.loadPlacementWorkflow(); error = nil }
        catch { self.error = error.localizedDescription }
    }
    var body: some View {
        List {
            Picker("Show", selection: $scope) {
                Text("Openings").tag("Openings")
                Text("My Calls").tag("My Calls")
                Text("Nominations").tag("Nominations")
            }
            if let error { Text(error).foregroundStyle(.red) }
            if scope == "Openings" {
                if model.canEdit { Button("Create Opening") { showingOpening = true } }
                Picker("Opening", selection: $selectedOpening) {
                    Text("Choose opening").tag(nil as UUID?)
                    ForEach(data.openings) { opening in
                        Text("\(title(opening)) — \(opening.status)").tag(Optional(opening.id))
                    }
                }
                if let opening = data.openings.first(where: { $0.id == selectedOpening }) {
                    Section(title(opening)) {
                        Text("\(opening.quantity) needed · \(data.candidates.filter { $0.openingId == opening.id && ["elected", "appointed"].contains($0.stage) }.count) filled")
                        if !opening.notes.isEmpty { Text(opening.notes) }
                        if model.canEdit && opening.status == "open" {
                            TextField("Find candidate", text: $search)
                            Picker("Candidate", selection: $personId) {
                                Text("Choose person").tag("")
                                ForEach(model.people.filter { person in person.isActive && (search.isEmpty || person.displayName.localizedCaseInsensitiveContains(search)) && !data.candidates.contains { $0.openingId == opening.id && $0.personId == person.id } }) { person in
                                    Text(person.displayName).tag(person.id.uuidString)
                                }
                            }
                            Button("Add Candidate") {
                                Task { if await model.savePlacementAction("candidate", data: ["opening_id": opening.id.uuidString, "person_id": personId]) { personId = ""; await refresh() } }
                            }.disabled(personId.isEmpty || model.isBusy)
                            Button("Close Opening", role: .destructive) {
                                Task { if await model.savePlacementAction("cancel_opening", data: ["opening_id": opening.id.uuidString]) { await refresh() } }
                            }.disabled(model.isBusy)
                        }
                    }
                }
            }
            if scope == "Nominations" {
                Section("Bulletin Text") {
                    Text("First reading").font(.headline)
                    Text(bulletin(stage: "nominated")).textSelection(.enabled)
                    Text("Second reading").font(.headline)
                    Text(bulletin(stage: "first_reading")).textSelection(.enabled)
                }
            }
            ForEach(displayed) { candidate in
                if let person = model.people.first(where: { $0.id == candidate.personId }), let opening = data.openings.first(where: { $0.id == candidate.openingId }) {
                    NavigationLink {
                        PlacementCandidateView(candidateId: candidate.id, data: data)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(person.displayName).font(.headline)
                            Text(title(opening))
                            Text("\(placementLabel(candidate.response)) · \(placementLabel(candidate.stage))").font(.caption)
                            if let followUp = candidate.followUp { Text("Follow up: \(followUp)").font(.caption) }
                        }
                    }
                }
            }
            if scope != "Openings" && displayed.isEmpty { Text("Nothing in this list.") }
        }
        .navigationTitle("Placement Process")
        .task { await refresh() }
        .refreshable { await refresh() }
        .toolbar { Button("Refresh") { Task { await refresh() } } }
        .sheet(isPresented: $showingOpening, onDismiss: { Task { await refresh() } }) { NewPlacementOpeningView() }
    }
    private func bulletin(stage: String) -> String {
        let lines = data.candidates.filter { $0.stage == stage }.compactMap { candidate -> String? in
            guard let person = model.people.first(where: { $0.id == candidate.personId }), let opening = data.openings.first(where: { $0.id == candidate.openingId }) else { return nil }
            return "\(person.displayName) — \(title(opening))"
        }
        return lines.isEmpty ? "None" : lines.joined(separator: "\n")
    }
}

private struct NewPlacementOpeningView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var roleId = ""
    @State private var positionId = ""
    @State private var termId = ""
    @State private var quantity = 1
    @State private var notes = ""
    var body: some View {
        NavigationStack {
            Form {
                Picker("Ministry", selection: $roleId) {
                    Text("Choose ministry").tag("")
                    ForEach(model.roles.filter(\.isActive)) { Text($0.name).tag($0.id.uuidString) }
                }.onChange(of: roleId) { _, _ in positionId = "" }
                Picker("Position", selection: $positionId) {
                    Text("Team member — no vote").tag("")
                    ForEach(model.subRoles.filter { $0.roleId?.uuidString == roleId && $0.isActive }) { Text($0.name).tag($0.id.uuidString) }
                }
                Picker("Term", selection: $termId) {
                    Text("No term").tag("")
                    ForEach(model.terms.filter(\.isActive)) { Text($0.name).tag($0.id.uuidString) }
                }
                Stepper("People needed: \(quantity)", value: $quantity, in: 1...100)
                TextField("Committee notes", text: $notes, axis: .vertical)
                if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
                Button("Create Opening") {
                    Task {
                        var body = ["role_id": roleId, "quantity": String(quantity), "notes": notes]
                        if !positionId.isEmpty { body["sub_role_id"] = positionId }
                        if !termId.isEmpty { body["term_id"] = termId }
                        if await model.savePlacementAction("opening", data: body) { dismiss() }
                    }
                }.disabled(roleId.isEmpty || model.isBusy)
            }.navigationTitle("Create Opening")
                .toolbar { Button("Cancel") { dismiss() } }
        }
    }
}

private struct PlacementCandidateView: View {
    @EnvironmentObject private var model: AppModel
    let candidateId: UUID
    @State var data: PlacementSnapshot
    @State private var callerId = ""
    @State private var assignee = ""
    @State private var response = "considering"
    @State private var notes = ""
    @State private var callDate = Date()
    @State private var actionDate = Date()
    @State private var followUp = Date()
    @State private var includeFollowUp = false
    @State private var error: String?
    private func execute(_ action: String) async {
        var body = ["candidate_id": candidateId.uuidString, "date": AppDate.storage(action == "call" ? callDate : actionDate), "notes": notes]
        if action == "call" { body["caller_id"] = model.isAdministrator ? callerId : model.currentProfile?.userId.uuidString; body["response"] = response }
        if action == "assign_call" { body["caller_id"] = assignee }
        if includeFollowUp && ["call", "assign_call"].contains(action) { body["follow_up"] = AppDate.storage(followUp) }
        if await model.savePlacementAction(action, data: body) {
            do { data = try await model.loadPlacementWorkflow(); notes = ""; error = nil }
            catch { self.error = error.localizedDescription }
        }
    }
    var body: some View {
        Form {
            if let candidate = data.candidates.first(where: { $0.id == candidateId }), let person = model.people.first(where: { $0.id == candidate.personId }), let opening = data.openings.first(where: { $0.id == candidate.openingId }) {
                let closed = ["elected", "appointed", "withdrawn", "not_elected"].contains(candidate.stage) || opening.status != "open"
                let requirement = candidate.requiresVote ?? (opening.subRoleId != nil && (model.roles.first { $0.id == opening.roleId }?.requiresVote == true || model.subRoles.first { $0.id == opening.subRoleId }?.requiresVote == true))
                Section(person.displayName) {
                    Text("\(placementLabel(candidate.response)) · \(placementLabel(candidate.stage))")
                    ForEach([person.mobilePhone, person.homePhone].compactMap { $0 }.filter { !$0.isEmpty }, id: \.self) { phone in
                        if let url = URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" }) { Link(phone, destination: url) }
                    }
                    if let email = person.email, let url = URL(string: "mailto:\(email)") { Link(email, destination: url) }
                    Text("Assigned caller: \(data.staff.first { $0.userId == candidate.assignedTo }?.displayName ?? "Unassigned")")
                    if let due = candidate.followUp { Text("Follow up: \(due)") }
                    ForEach(model.assignments.filter { $0.personId == person.id && $0.isCurrentPlacement }) { assignment in Text("Serving: \(assignment.roleName) · \(assignment.subRoleName ?? "Team member")") }
                    if data.candidates.contains(where: { other in other.personId == person.id && other.id != candidate.id && other.assignedTo != nil && data.openings.contains { $0.id == other.openingId && $0.status == "open" } }) { Text("This person has other assigned recruitment activity. Review their history before calling.") }
                }
                if let error { Text(error).foregroundStyle(.red) }
                if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
                if model.isAdministrator && !closed {
                    Section("Assign Call") {
                        Picker("Caller", selection: $assignee) {
                            Text("Unassigned").tag("")
                            ForEach(data.staff) { Text($0.displayName).tag($0.userId.uuidString) }
                        }
                        Button("Save Call Assignment") { Task { await execute("assign_call") } }.disabled(model.isBusy)
                    }
                }
                if model.canEdit {
                    Section("Record Call") {
                        if model.isAdministrator {
                            Picker("Call made by", selection: $callerId) { ForEach(data.staff) { Text($0.displayName).tag($0.userId.uuidString) } }
                        } else { Text("Call made by you. Only an admin may enter another caller’s results.") }
                        DatePicker("Call date", selection: $callDate, in: ...Date(), displayedComponents: .date)
                        Picker("Response", selection: $response) { ForEach(placementResponses, id: \.self) { Text(placementLabel($0)).tag($0) } }
                        Toggle("Schedule follow-up", isOn: $includeFollowUp)
                        if includeFollowUp { DatePicker("Follow up", selection: $followUp, displayedComponents: .date) }
                        TextField("Notes / explanation", text: $notes, axis: .vertical)
                        Button("Save Call to Person’s History") { Task { await execute("call") } }.disabled(model.isBusy || (response == "other" && notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    }
                }
                if model.canEdit && !closed {
                    Section("Selection and Approval") {
                        Text(requirement ? "Church vote required" : "Appointment — no church vote required")
                        if let date = candidate.nominatedOn { Text("Nominated: \(date)") }
                        if let date = candidate.firstReading { Text("First reading: \(date)") }
                        if let date = candidate.secondReading { Text("Second reading: \(date)") }
                        DatePicker("Actual action date", selection: $actionDate, in: ...Date(), displayedComponents: .date)
                        if candidate.stage == "considering" && candidate.response == "yes" { actionButton(requirement ? "Nominate — Pending Vote" : "Appoint Volunteer", requirement ? "nominate" : "appoint") }
                        if candidate.stage == "nominated" { actionButton("Record First Reading", "first_reading") }
                        if candidate.stage == "first_reading" { actionButton("Record Second Reading", "second_reading") }
                        if candidate.stage == "second_reading" { actionButton("Vote Passed — Activate", "vote_passed"); actionButton("Vote Did Not Pass", "vote_failed") }
                        if ["nominated", "first_reading", "second_reading"].contains(candidate.stage) { actionButton("Defer", "defer") }
                        if candidate.stage == "deferred" { actionButton("Resume Nomination", "resume") }
                        actionButton("Withdraw Candidate", "withdraw")
                    }
                }
                Section("Person’s Volunteer Contact History") { VolunteerHistoryRows(entries: data.history.filter { $0.personId == person.id }) }
            }
        }.navigationTitle("Candidate")
            .onAppear { callerId = model.currentProfile?.userId.uuidString ?? ""; assignee = data.candidates.first { $0.id == candidateId }?.assignedTo?.uuidString ?? "" }
            .task { do { data = try await model.loadPlacementWorkflow() } catch { self.error = error.localizedDescription } }
    }
    private func actionButton(_ title: String, _ action: String) -> some View {
        Button(title) { Task { await execute(action) } }.disabled(model.isBusy)
    }
}
