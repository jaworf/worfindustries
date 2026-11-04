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

private enum FocusArea: String, CaseIterable, Identifiable {
    case votes = "Needing Votes"
    case ordination = "Ordination Actions"
    case ending = "Terms ending in next 6 months"
    case ministries = "Ministries needing volunteers"
    case activation = "Volunteer Activation"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .votes: "checkmark.seal"
        case .ordination: "person.crop.circle.badge.checkmark"
        case .ending: "calendar"
        case .ministries: "person.3"
        case .activation: "person.badge.plus"
        }
    }
}

struct FocusAttentionCard: View {
    let title: String
    let symbol: String
    let count: Int?
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).frame(width: 26)
            Text(title).font(.headline).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Text(count.map(String.init) ?? "…").font(.title3.bold()).monospacedDigit()
            Image(systemName: "chevron.right").font(.caption.bold())
        }
        .foregroundStyle(Color.primary)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(count == nil ? Color.gray.opacity(0.08) : (count! > 0 ? Color.orange.opacity(0.15) : Color.green.opacity(0.09)), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(count == nil ? Color.gray.opacity(0.2) : (count! > 0 ? Color.orange.opacity(0.45) : Color.green.opacity(0.25))))
        .accessibilityElement(children: .combine)
    }
}

struct WorkflowCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.secondary.opacity(0.16)))
    }
}

struct FocusView: View {
    @EnvironmentObject private var model: AppModel
    @State private var expanded: FocusArea?
    @State private var overview: FocusOverview?
    @State private var error: String?
    @State private var search = ""
    let votes: () -> Void
    let assign: (AssignmentRoute) -> Void

    private var current: [AssignmentDetail] { model.assignments.filter(\.isCurrentPlacement) }
    private var ordinations: [OrdinationFocusNeed] { makeOrdinationFocusNeeds(people: model.people, assignments: model.assignments) }
    private var ending: [AssignmentDetail] {
        let start = Calendar.current.startOfDay(for: Date())
        let cutoff = Calendar.current.date(byAdding: .month, value: 6, to: start) ?? start
        return current.filter { $0.endDateValue.map { $0 >= start && $0 <= cutoff } ?? false }
            .sorted { ($0.endDate ?? "") < ($1.endDate ?? "") }
    }
    private var emptyMinistries: [MinistryRole] {
        let occupied = Set(current.map(\.roleId))
        return model.roles.filter { $0.isActive && !occupied.contains($0.id) }
    }
    private func count(_ area: FocusArea) -> Int? {
        switch area {
        case .votes: overview.map { $0.pendingNominations + current.filter(\.voteMissing).count }
        case .ordination: ordinations.count
        case .ending: ending.count
        case .ministries: emptyMinistries.count
        case .activation: overview?.people.count
        }
    }
    private func refresh() async {
        do { overview = try await model.loadFocusOverview(); error = nil }
        catch { self.error = error.localizedDescription }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let error { Text(error).foregroundStyle(.red).modifier(WorkflowCardStyle()) }
                if let expanded {
                    HStack {
                        Button { self.expanded = nil } label: { Label(expanded.rawValue, systemImage: "chevron.left").font(.headline) }
                            .buttonStyle(.plain).accessibilityLabel("Collapse " + expanded.rawValue)
                        Spacer(minLength: 8)
                        Button("Close") { self.expanded = nil }.buttonStyle(.bordered).controlSize(.small)
                    }.padding(.vertical, 6)
                    expandedContent(expanded)
                } else {
                    ForEach(FocusArea.allCases) { area in
                        Button {
                            if area == .votes { votes() } else { expanded = area }
                        } label: { FocusAttentionCard(title: area.rawValue, symbol: area.symbol, count: count(area)) }
                        .buttonStyle(.plain)
                    }
                }
            }.padding(16).frame(maxWidth: 960).frame(maxWidth: .infinity)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("Placement Focus")
        .task { await refresh() }
        .onChange(of: model.assignments) { _, _ in Task { await refresh() } }
        .refreshable { await model.reload(); await refresh() }
        .toolbar { Button { Task { await model.reload(); await refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }.disabled(model.isBusy) }
    }
    @ViewBuilder private func expandedContent(_ area: FocusArea) -> some View {
        switch area {
        case .votes: EmptyView()
        case .ordination:
            if ordinations.isEmpty { empty("No ordination actions needed") }
            ForEach(ordinations) { OrdinationFocusRow(need: $0).modifier(WorkflowCardStyle()) }
        case .ending:
            if ending.isEmpty { empty("No terms ending in the next six months") }
            ForEach(ending) { assignment in
                Button { assign(AssignmentRoute(personId: assignment.personId, roleId: assignment.roleId, subRoleId: assignment.subRoleId)) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(assignment.personName).font(.headline)
                        Text([assignment.roleName, assignment.subRoleName].compactMap { $0 }.joined(separator: " · ")).font(.subheadline)
                        Text("Term ends " + (assignment.endDate ?? "")).font(.caption).foregroundStyle(.secondary)
                    }.modifier(WorkflowCardStyle())
                }.buttonStyle(.plain).disabled(!model.canEdit)
            }
        case .ministries:
            if emptyMinistries.isEmpty { empty("Every active ministry has a volunteer") }
            ForEach(emptyMinistries) { ministry in
                Button { assign(AssignmentRoute(personId: nil, roleId: ministry.id, subRoleId: nil)) } label: {
                    HStack { Text(ministry.name).font(.headline); Spacer(); Image(systemName: "person.badge.plus") }.modifier(WorkflowCardStyle())
                }.buttonStyle(.plain).disabled(!model.canEdit)
            }
        case .activation:
            VStack(alignment: .leading, spacing: 10) {
                Text("The 100 newest eligible Planning Center contacts, excluding current volunteers.").font(.subheadline)
                Text("Membership: " + (overview?.preferences.selected.isEmpty == false ? overview!.preferences.selected.joined(separator: ", ") : "All membership types")).font(.caption).foregroundStyle(.secondary)
                if model.isAdministrator { NavigationLink("Change membership types") { FocusMembershipSettingsView() } }
                TextField("Search name or contact details", text: $search).textFieldStyle(.roundedBorder)
            }.modifier(WorkflowCardStyle())
            if overview == nil { ProgressView("Loading eligible contacts…") }
            else if activationPeople.isEmpty { empty("No eligible contacts match") }
            ForEach(activationPeople) { person in
                VolunteerActivationRow(person: person) { assign(AssignmentRoute(personId: person.id, roleId: nil, subRoleId: nil)) }
                    .modifier(WorkflowCardStyle())
            }
        }
    }
    private var activationPeople: [Person] {
        (overview?.people ?? []).filter { search.isEmpty || [$0.displayName, $0.email ?? "", $0.mobilePhone ?? "", $0.homePhone ?? ""].contains { $0.localizedCaseInsensitiveContains(search) } }
    }
    private func empty(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle").foregroundStyle(.secondary).modifier(WorkflowCardStyle())
    }
}

struct FocusMembershipSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var preferences = FocusPreferences()
    @State private var error: String?
    @State private var busy = false
    @State private var loading = true
    @State private var notice: String?
    private var options: [String] {
        var seen = Set<String>()
        return (preferences.options + preferences.selected).filter { seen.insert($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).inserted }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    private func refreshTypes() async {
        busy = true; defer { busy = false }
        do { preferences.options = try await model.refreshFocusMembershipTypes(); error = nil }
        catch { self.error = error.localizedDescription }
    }
    var body: some View {
        Form {
            Section {
                Text("Choose one or more membership types for the newest 100 Planning Center contacts who are not currently volunteering. These settings are shared with the web app.")
                ForEach(options, id: \.self) { value in
                    Toggle(value, isOn: Binding(get: { preferences.selected.contains { $0.caseInsensitiveCompare(value) == .orderedSame } }, set: { checked in
                        preferences.selected.removeAll { $0.caseInsensitiveCompare(value) == .orderedSame }
                        if checked { preferences.selected.append(value) }
                    }))
                }
                Button("Use all membership types") { preferences.selected = [] }
                Button("Refresh types from Planning Center") { Task { await refreshTypes() } }.disabled(busy || model.planningCenterStatus?.connected != true)
                Button("Save Membership Types") { Task { if await model.saveFocusMemberships(preferences.selected) { notice = "Membership types saved." } } }.disabled(busy || loading || model.isBusy)
            } header: { Text("Volunteer Activation") } footer: { Text("No selection means all membership types.") }
            if let error = error ?? model.errorMessage { Text(error).foregroundStyle(.red) }
            if let notice { Text(notice).foregroundStyle(.green) }
        }
        .navigationTitle("Membership Types")
        .task {
            defer { loading = false }
            do { preferences = try await model.loadFocusPreferences() } catch { self.error = error.localizedDescription }
            if model.planningCenterStatus?.connected == true { await refreshTypes() }
        }
    }
}

private struct OrdinationFocusRow: View {
    @EnvironmentObject private var model: AppModel
    let need: OrdinationFocusNeed
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(need.person.displayName).font(.headline)
            Text("\(need.ministryName) · \(need.kind.label) is not checked").font(.subheadline).foregroundStyle(.secondary)
            if model.canEdit {
                HStack { Spacer()
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
                .controlSize(.regular)
                .font(.callout).lineLimit(1).fixedSize()
                .disabled(model.isBusy)
                }
            }
        }
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
    @EnvironmentObject private var model: AppModel
    let person: Person
    let assign: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(person.displayName).font(.headline)
            Text(person.membershipStatus.nilIfBlank ?? "No membership status").font(.caption).foregroundStyle(.secondary)
            if let added = person.addedDate { Text("Added " + AppDate.display(added)).font(.caption).foregroundStyle(.secondary) }
            if let phone = person.mobilePhone.nilIfBlank ?? person.homePhone.nilIfBlank,
               let url = URL(string:"tel:" + phone.filter { $0.isNumber || $0 == "+" }) { Link(destination:url) { Label(phone,systemImage:"phone") }.font(.callout) }
            if let email = person.email.nilIfBlank, let url = URL(string:"mailto:" + email) { Link(destination:url) { Label(email,systemImage:"envelope") }.font(.callout).lineLimit(1).truncationMode(.middle) }
            HStack {
                Spacer()
                Button("Assign", action: assign).buttonStyle(.borderedProminent).controlSize(.regular).font(.callout).lineLimit(1).fixedSize().disabled(!model.canEdit || model.isBusy)
            }
        }
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

struct NativeSearchOption: Identifiable {
    let id: String
    let title: String
    var detail: String? = nil
}

struct NativeSearchPicker: View {
    let title: String
    @Binding var selection: String
    let options: [NativeSearchOption]
    var createTitle: String? = nil
    var create: ((String) -> Void)? = nil
    @State private var showing = false
    @State private var query = ""
    @FocusState private var searching: Bool
    private var matches: [NativeSearchOption] { options.filter { query.isEmpty || [$0.title, $0.detail ?? ""].contains { $0.localizedCaseInsensitiveContains(query) } } }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Button { query = ""; showing = true } label: {
                HStack {
                    Text(options.first { $0.id == selection }?.title ?? "Choose…").multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down").font(.caption.bold())
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).accessibilityLabel(title + ": " + (options.first { $0.id == selection }?.title ?? "Choose"))
        }
        .sheet(isPresented: $showing) {
            NavigationStack {
                List {
                    TextField("Type to filter " + title.lowercased(), text: $query).textFieldStyle(.roundedBorder).focused($searching)
                    ForEach(matches) { option in
                        Button {
                            selection = option.id; showing = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(option.title)
                                    if let detail = option.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer(minLength: 6)
                                if selection == option.id { Image(systemName: "checkmark") }
                            }
                        }.buttonStyle(.plain)
                    }
                    if let create, let createTitle, let name = query.nilIfBlank,
                       !options.contains(where: { $0.title.caseInsensitiveCompare(name) == .orderedSame }) {
                        Button { create(name); showing = false } label: { Label(createTitle + ": " + name, systemImage: "plus.circle") }
                    } else if matches.isEmpty { Text("No matches").foregroundStyle(.secondary) }
                }
                .navigationTitle(title)
                .toolbar { Button("Close") { showing = false } }
                .task { searching = true }
            }.frame(minWidth: 300, minHeight: 360)
        }
    }
}

struct PlacementCandidateCard: View {
    @EnvironmentObject private var model: AppModel
    let candidate: PlacementCandidate
    let person: Person
    let title: String
    let data: PlacementSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            NavigationLink { PlacementCandidateView(candidateId: candidate.id, data: data) } label: {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(person.displayName).font(.headline)
                        Text(title).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 5)
                    Text(["nominated", "first_reading", "second_reading"].contains(candidate.stage) ? (candidate.firstReading == nil ? "First reading" : "Vote pending") : placementLabel(candidate.response)).font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption)
                }.foregroundStyle(.primary)
            }.buttonStyle(.plain)
            HStack(spacing: 16) {
                if let phone = person.mobilePhone.nilIfBlank ?? person.homePhone.nilIfBlank,
                   let url = URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" }) {
                    Link(destination: url) { Label(phone, systemImage: "phone") }.lineLimit(1)
                }
                if let email = person.email.nilIfBlank, let url = URL(string: "mailto:" + email) {
                    Link(destination: url) { Label(email, systemImage: "envelope") }.lineLimit(1).truncationMode(.middle)
                }
            }.font(.caption)
            let serving = model.assignments.filter { $0.personId == person.id && $0.isCurrentPlacement }.map { $0.roleName + ($0.subRoleName.map { " · " + $0 } ?? "") }
            Text(serving.isEmpty ? "No current positions" : "Serving: " + serving.joined(separator: "; ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if let due = candidate.followUp { Text("Follow up: " + due).font(.caption).foregroundStyle(.secondary) }
        }.modifier(WorkflowCardStyle())
    }
}

struct PlacementOpeningCard: View {
    let title: String
    let status: String
    let candidates: Int
    let expanded: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.clipboard").font(.title3).foregroundStyle(AppTheme.riverBlue)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline).multilineTextAlignment(.leading)
                    Text("\(candidates) candidate\(candidates == 1 ? "" : "s") · \(placementLabel(status))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption.bold())
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(expanded ? AppTheme.riverBlueSoft : Color.white, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(expanded ? AppTheme.riverBlue : Color.secondary.opacity(0.18)))
                .foregroundStyle(.primary)
        }.buttonStyle(.plain).accessibilityValue(expanded ? "Expanded" : "Collapsed")
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
    @State private var trashOpening: UUID?
    @State private var showingTrashConfirmation = false
    let onVotes: () -> Void
    private func title(_ opening: PlacementOpening) -> String {
        [model.roles.first { $0.id == opening.roleId }?.name,
         model.subRoles.first { $0.id == opening.subRoleId }?.name,
         model.terms.first { $0.id == opening.termId }?.name].compactMap { $0 }.joined(separator: " · ")
    }
    private var openings: [PlacementOpening] {
        data.openings.filter { $0.status == (scope == "Trash" ? "cancelled" : scope == "Completed" ? "filled" : "open") }
    }
    private var otherCandidates: [PlacementCandidate] {
        data.candidates.filter { candidate in
            if scope == "My Calls" {
                return candidate.assignedTo == model.currentProfile?.userId && data.openings.contains { $0.id == candidate.openingId && $0.status == "open" }
                    && !["elected", "appointed", "withdrawn", "not_elected"].contains(candidate.stage)
                    && (!["yes", "no"].contains(candidate.response) || candidate.followUp != nil)
            }
            return scope == "Completed" && ["elected", "appointed", "withdrawn", "not_elected"].contains(candidate.stage)
                && !data.openings.contains { $0.id == candidate.openingId && $0.status == "filled" }
        }
    }
    private func refresh() async {
        do { data = try await model.loadPlacementWorkflow(); error = nil }
        catch { self.error = error.localizedDescription }
    }
    @discardableResult private func command(_ action: String, _ values: [String: String]) async -> Bool {
        if await model.savePlacementAction(action, data: values) { await refresh(); return true }
        return false
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["Openings", "My Calls", "Completed", "Trash"], id: \.self) { value in
                            Button(value) { scope = value; selectedOpening = nil; personId = "" }
                                .buttonStyle(.bordered).tint(scope == value ? AppTheme.riverBlue : .secondary).fixedSize()
                        }
                        Button("Needing Votes", action: onVotes).buttonStyle(.bordered).fixedSize()
                    }
                }
                if let error = error ?? model.errorMessage { Text(error).foregroundStyle(.red).modifier(WorkflowCardStyle()) }
                if scope == "Openings" && model.canEdit {
                    Button { showingOpening = true } label: { Label("Create Opening", systemImage: "plus") }.buttonStyle(.borderedProminent).controlSize(.regular)
                }
                if scope == "Trash" { Text("Canceled openings are kept here with their candidates and history. Restore an opening to resume recruitment.").font(.subheadline).foregroundStyle(.secondary) }
                if scope != "My Calls" {
                    ForEach(openings) { opening in
                        PlacementOpeningCard(title: title(opening), status: opening.status, candidates: data.candidates.filter { $0.openingId == opening.id }.count, expanded: selectedOpening == opening.id) {
                            selectedOpening = selectedOpening == opening.id ? nil : opening.id; personId = ""
                        }
                        if selectedOpening == opening.id {
                            openingDetails(opening)
                            ForEach(data.candidates.filter { $0.openingId == opening.id }) { candidate in candidateCard(candidate) }
                        }
                    }
                    if openings.isEmpty && otherCandidates.isEmpty { Text("No \(scope.lowercased()) to show.").foregroundStyle(.secondary).padding(.vertical) }
                }
                ForEach(otherCandidates) { candidate in candidateCard(candidate) }
                if scope == "My Calls" && otherCandidates.isEmpty { Text("No calls assigned to you.").foregroundStyle(.secondary).padding(.vertical) }
            }.padding(16).frame(maxWidth: 960).frame(maxWidth: .infinity)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("Placement Process")
        .task { await refresh() }
        .refreshable { await refresh() }
        .toolbar { Button { Task { await refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") } }
        .sheet(isPresented: $showingOpening, onDismiss: { Task { await refresh() } }) { NewPlacementOpeningView(openings: data.openings) }
        .confirmationDialog("Move opening to Trash?", isPresented: $showingTrashConfirmation) {
            Button("Move to Trash", role: .destructive) {
                if let id = trashOpening { Task { if await command("cancel_opening", ["opening_id":id.uuidString]) { selectedOpening = nil }; trashOpening = nil } }
            }
        } message: { Text("Candidate records and call history are preserved.") }
    }
    @ViewBuilder private func candidateCard(_ candidate: PlacementCandidate) -> some View {
        if let person = model.people.first(where: { $0.id == candidate.personId }), let opening = data.openings.first(where: { $0.id == candidate.openingId }) {
            PlacementCandidateCard(candidate: candidate, person: person, title: title(opening), data: data)
        }
    }
    private func openingDetails(_ opening: PlacementOpening) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !opening.notes.isEmpty { Text(opening.notes).font(.subheadline) }
            if model.canEdit {
                if opening.status == "open" {
                    NativeSearchPicker(title: "Add a candidate", selection: $personId, options: model.people.filter { person in person.isActive && !data.candidates.contains { $0.openingId == opening.id && $0.personId == person.id } }.map { NativeSearchOption(id: $0.id.uuidString, title: $0.displayName, detail: [$0.email, $0.mobilePhone].compactMap { $0 }.joined(separator: " · ")) })
                    Button("Add Candidate") { Task { await command("candidate", ["opening_id": opening.id.uuidString, "person_id": personId]); personId = "" } }.buttonStyle(.borderedProminent).disabled(personId.isEmpty || model.isBusy)
                    HStack {
                        Button("Finish Recruiting") { Task { if await command("finish_opening", ["opening_id":opening.id.uuidString]) { selectedOpening = nil } } }
                        Spacer(minLength: 10)
                        Button("Move to Trash", role: .destructive) { trashOpening = opening.id; showingTrashConfirmation = true }
                    }.font(.callout).disabled(model.isBusy)
                } else {
                    Button(opening.status == "cancelled" ? "Restore Opening" : "Reopen Recruitment") { Task { if await command("restore_opening", ["opening_id":opening.id.uuidString]) { selectedOpening = nil } } }.buttonStyle(.bordered).disabled(model.isBusy)
                }
            }
        }.modifier(WorkflowCardStyle())
    }
}

private struct NewPlacementOpeningView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let openings: [PlacementOpening]
    @State private var roleId = ""
    @State private var positionId = ""
    @State private var termId = ""
    @State private var newMinistry = ""
    @State private var newPosition = ""
    @State private var newTerm = ""
    @State private var voteRequired = false
    @State private var termStart = Date()
    @State private var termEnd = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var notes = ""
    private var requiresTerm: Bool {
        !positionId.isEmpty && (model.roles.first { $0.id.uuidString == roleId }?.requiresVote == true || (positionId == "new" ? voteRequired : model.subRoles.first { $0.id.uuidString == positionId }?.requiresVote == true))
    }
    private var duplicate: Bool { roleId != "new" && positionId != "new" && termId != "new" && openings.contains { $0.status == "open" && $0.roleId.uuidString == roleId && ($0.subRoleId?.uuidString ?? "") == positionId && ($0.termId?.uuidString ?? "") == termId } }
    var body: some View {
        NavigationStack {
            Form {
                NativeSearchPicker(title: "Ministry", selection: $roleId, options: model.roles.filter(\.isActive).map { NativeSearchOption(id:$0.id.uuidString,title:$0.name) } + (newMinistry.isEmpty ? [] : [NativeSearchOption(id:"new",title:newMinistry)]), createTitle: "Create a new ministry", create: { newMinistry = $0; roleId = "new" })
                    .onChange(of: roleId) { _, _ in positionId = ""; newPosition = "" }
                NativeSearchPicker(title: "Position", selection: $positionId, options: [NativeSearchOption(id:"",title:"Team member — no vote")] + model.subRoles.filter { $0.roleId?.uuidString == roleId && $0.isActive }.map { NativeSearchOption(id:$0.id.uuidString,title:$0.name) } + (newPosition.isEmpty ? [] : [NativeSearchOption(id:"new",title:newPosition)]), createTitle: "Create a new position", create: { newPosition = $0; positionId = "new" }).disabled(roleId.isEmpty)
                if positionId == "new" { Toggle("Position requires a church vote", isOn: $voteRequired) }
                NativeSearchPicker(title: requiresTerm ? "Term (required)" : "Term", selection: $termId, options: [NativeSearchOption(id:"",title:"No term")] + model.terms.filter(\.isActive).map { NativeSearchOption(id:$0.id.uuidString,title:$0.name) } + (newTerm.isEmpty ? [] : [NativeSearchOption(id:"new",title:newTerm)]), createTitle: "Create a new term", create: { newTerm = $0; termId = "new" })
                if termId == "new" {
                    DatePicker("Term starts", selection:$termStart, displayedComponents:.date)
                    DatePicker("Term ends", selection:$termEnd, in:termStart..., displayedComponents:.date)
                }
                TextField("Committee notes", text: $notes, axis: .vertical)
                if duplicate { Label("An open recruitment already exists for this ministry, position and term.",systemImage:"exclamationmark.triangle").foregroundStyle(.orange) }
                if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
                Button("Create Opening") {
                    Task {
                        var body = ["notes": notes]
                        if roleId == "new" { body["new_role_name"] = newMinistry } else { body["role_id"] = roleId }
                        if positionId == "new" { body["new_position_name"] = newPosition; body["new_position_vote"] = String(voteRequired) } else if !positionId.isEmpty { body["sub_role_id"] = positionId }
                        if termId == "new" { body["new_term_name"] = newTerm; body["term_start"] = AppDate.storage(termStart); body["term_end"] = AppDate.storage(termEnd) } else if !termId.isEmpty { body["term_id"] = termId }
                        if await model.savePlacementAction("opening", data: body) { dismiss() }
                    }
                }.disabled(roleId.isEmpty || model.isBusy || duplicate || (requiresTerm && termId.isEmpty))
            }
            .navigationTitle("Create Opening")
            .toolbar { Button("Cancel") { dismiss() } }
        }
    }
}

struct PlacementCandidateView: View {
    @EnvironmentObject private var model: AppModel
    let candidateId: UUID
    @State var data: PlacementSnapshot
    @State private var callerId = ""
    @State private var assignee = ""
    @State private var response = ""
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
                        NativeSearchPicker(title: "Assign caller", selection: $assignee, options: [NativeSearchOption(id:"",title:"Unassigned")] + data.staff.map { NativeSearchOption(id:$0.userId.uuidString,title:$0.displayName) })
                        Toggle("Schedule follow-up", isOn: $includeFollowUp)
                        if includeFollowUp { DatePicker("Follow up", selection: $followUp, displayedComponents: .date) }
                        Button("Save Call Assignment") { Task { await execute("assign_call") } }.disabled(model.isBusy)
                    }
                }
                if model.canEdit && !closed {
                    Section("Record Call") {
                        if model.isAdministrator {
                            NativeSearchPicker(title: "Call made by", selection: $callerId, options: data.staff.map { NativeSearchOption(id:$0.userId.uuidString,title:$0.displayName) })
                        } else { Text("Call made by you. Only an admin may enter another caller’s results.") }
                        DatePicker("Call date", selection: $callDate, in: ...Date(), displayedComponents: .date)
                        Picker("Response", selection: $response) { Text("Choose response").tag(""); ForEach(placementResponses, id: \.self) { Text(placementLabel($0)).tag($0) } }
                        Toggle("Schedule follow-up", isOn: $includeFollowUp)
                        if includeFollowUp { DatePicker("Follow up", selection: $followUp, displayedComponents: .date) }
                        TextField("Notes / explanation", text: $notes, axis: .vertical)
                        Button("Save Call to Person’s History") { Task { await execute("call") } }.disabled(model.isBusy || response.isEmpty || (response == "other" && notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    }
                }
                if model.canEdit && !closed {
                    Section("Selection and Approval") {
                        Text(requirement ? "Church vote required" : "Appointment — no church vote required")
                        if let date = candidate.nominatedOn { Text("Nominated: \(date)") }
                        if ["nominated", "first_reading", "second_reading"].contains(candidate.stage) {
                            Toggle("First reading published", isOn: Binding(get: { candidate.firstReading != nil }, set: { checked in Task { await execute(checked ? "first_reading" : "unpublish_first_reading") } }))
                                .disabled(model.isBusy)
                        }
                        if ["first_reading", "second_reading"].contains(candidate.stage) { Text("Recording the vote confirms the second reading.") }
                        if candidate.stage != "nominated" { DatePicker(["first_reading", "second_reading"].contains(candidate.stage) ? "Vote date" : "Actual action date", selection: $actionDate, in: ...Date(), displayedComponents: .date) }
                        if candidate.stage == "considering" && candidate.response == "yes" { actionButton(requirement ? "Nominate — Pending Vote" : "Appoint Volunteer", requirement ? "nominate" : "appoint") }
                        if ["first_reading", "second_reading"].contains(candidate.stage) { actionButton("Vote Passed — Activate", "vote_passed"); actionButton("Vote Did Not Pass", "vote_failed") }
                        if ["nominated", "first_reading", "second_reading"].contains(candidate.stage) { actionButton("Defer", "defer") }
                        if candidate.stage == "deferred" { actionButton("Resume Nomination", "resume") }
                        actionButton("Withdraw Candidate", "withdraw")
                    }
                }
                Section("Person’s Volunteer Contact History") { VolunteerHistoryRows(entries: data.history.filter { $0.personId == person.id }) }
            }
        }.navigationTitle("Candidate")
            .onAppear {
                let candidate = data.candidates.first { $0.id == candidateId }
                callerId = (model.isAdministrator ? candidate?.assignedTo : nil)?.uuidString ?? model.currentProfile?.userId.uuidString ?? ""
                assignee = candidate?.assignedTo?.uuidString ?? ""
                if let due = candidate?.followUp.flatMap(AppDate.parse) { includeFollowUp = true; followUp = due }
            }
            .task { do { data = try await model.loadPlacementWorkflow() } catch { self.error = error.localizedDescription } }
    }
    private func actionButton(_ title: String, _ action: String) -> some View {
        Button(title) { Task { await execute(action) } }.disabled(model.isBusy)
    }
}

struct BulletinSuggestionsSection: View {
    @EnvironmentObject private var model: AppModel
    let data: PlacementSnapshot
    @State private var expanded = false
    var body: some View {
        DisclosureGroup("Bulletin Suggestions", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text("First reading").font(.headline)
                Text(bulletin(stage: "nominated")).font(.subheadline).textSelection(.enabled)
                Text("Second reading").font(.headline)
                Text(bulletin(stage: "first_reading")).font(.subheadline).textSelection(.enabled)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
        }.font(.headline).modifier(WorkflowCardStyle())
    }
    private func bulletin(stage: String) -> String {
        let lines = data.candidates.filter { stage == "nominated" ? $0.stage == "nominated" : ["first_reading", "second_reading"].contains($0.stage) }.compactMap { candidate -> String? in
            guard let person = model.people.first(where: { $0.id == candidate.personId }), let opening = data.openings.first(where: { $0.id == candidate.openingId }) else { return nil }
            return "\(person.displayName) — \([model.roles.first { $0.id == opening.roleId }?.name, model.subRoles.first { $0.id == opening.subRoleId }?.name, model.terms.first { $0.id == opening.termId }?.name].compactMap { $0 }.joined(separator: " · "))"
        }
        let existing = model.assignments.filter { $0.isCurrentPlacement && $0.voteMissing && (stage == "nominated" ? $0.firstReadingPublished != true : $0.firstReadingPublished == true) }.map { "\($0.personName) — \($0.roleName)\($0.subRoleName.map { " · " + $0 } ?? "")" }
        return (existing + lines).isEmpty ? "None" : (existing + lines).joined(separator: "\n")
    }
}
