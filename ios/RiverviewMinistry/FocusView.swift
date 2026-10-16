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
