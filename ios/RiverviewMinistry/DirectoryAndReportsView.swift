import PDFKit
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct AssignmentFilter: Sendable {
    var search = ""
    var roleId: UUID?
    var endingWindow: EndingWindow = .all
    var voteStatus: VoteStatusFilter = .all

    func apply(
        to assignments: [AssignmentDetail],
        now: Date = Date()
    ) -> [AssignmentDetail] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: now)
        let windowEnd = endingWindow.monthCount.flatMap {
            calendar.date(byAdding: .month, value: $0, to: today)
        }

        return assignments
            .filter { assignment in
                guard assignment.isCurrentPlacement else { return false }
                if let roleId, assignment.roleId != roleId { return false }
                if voteStatus == .awaiting, !assignment.voteMissing { return false }
                if !query.isEmpty {
                    let values = [
                        assignment.personName,
                        assignment.roleName,
                        assignment.subRoleName ?? "",
                        assignment.termName ?? "",
                        assignment.notes ?? ""
                    ]
                    guard values.contains(where: {
                        $0.localizedCaseInsensitiveContains(query)
                    }) else {
                        return false
                    }
                }
                if let windowEnd {
                    guard
                        let endDate = assignment.endDateValue,
                        endDate >= today,
                        endDate <= windowEnd
                    else {
                        return false
                    }
                }
                return true
            }
            .sorted(by: AssignmentFilter.reportOrder)
    }

    func description(roles: [MinistryRole]) -> String {
        var parts: [String] = []
        if let roleId, let role = roles.first(where: { $0.id == roleId }) {
            parts.append("Ministry: \(role.name)")
        }
        if let query = search.nilIfBlank {
            parts.append("Search: \(query)")
        }
        if endingWindow != .all {
            parts.append(endingWindow.rawValue)
        }
        if voteStatus != .all {
            parts.append(voteStatus.rawValue)
        }
        return parts.isEmpty ? "All active assignments" : parts.joined(separator: " • ")
    }

    private static func reportOrder(
        _ left: AssignmentDetail,
        _ right: AssignmentDetail
    ) -> Bool {
        let roleOrder = left.roleName.localizedCaseInsensitiveCompare(right.roleName)
        if roleOrder != .orderedSame { return roleOrder == .orderedAscending }
        if left.leadershipRank != right.leadershipRank {
            return left.leadershipRank < right.leadershipRank
        }
        let lastOrder = left.lastName.localizedCaseInsensitiveCompare(right.lastName)
        if lastOrder != .orderedSame { return lastOrder == .orderedAscending }
        return left.firstName.localizedCaseInsensitiveCompare(right.firstName)
            == .orderedAscending
    }
}

struct AssignmentFilterControls: View {
    @Binding var filter: AssignmentFilter
    let roles: [MinistryRole]
    var includeVoteFilter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Search person, role, position, term, or note", text: $filter.search)
                .textFieldStyle(.roundedBorder)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    pickerControls
                }
                VStack(alignment: .leading, spacing: 10) {
                    pickerControls
                }
            }
        }
    }

    @ViewBuilder
    private var pickerControls: some View {
        Picker("Ministry", selection: $filter.roleId) {
            Text("All ministries").tag(UUID?.none)
            ForEach(roles.filter(\.isActive)) { role in
                Text(role.name).tag(Optional(role.id))
            }
        }
        Picker("Term ending", selection: $filter.endingWindow) {
            ForEach(EndingWindow.allCases) { window in
                Text(window.rawValue).tag(window)
            }
        }
        if includeVoteFilter {
            Picker("Church vote", selection: $filter.voteStatus) {
                ForEach(VoteStatusFilter.allCases) { status in
                    Text(status.rawValue).tag(status)
                }
            }
        }
        if filter.roleId != nil || filter.search.nilIfBlank != nil
            || filter.endingWindow != .all || filter.voteStatus != .all
        {
            Button("Clear") {
                filter = AssignmentFilter()
            }
        }
    }
}

struct DirectoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var filter = AssignmentFilter()
    @State private var editingAssignment: AssignmentDetail?

    private var filtered: [AssignmentDetail] {
        filter.apply(to: model.assignments)
    }

    private var grouped: [(String, [AssignmentDetail])] {
        Dictionary(grouping: filtered, by: \.roleName)
            .map { ($0.key, $0.value) }
            .sorted {
                $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending
            }
    }

    var body: some View {
        Form {
            Section {
                AssignmentFilterControls(filter: $filter, roles: model.roles)
            } header: {
                Text("Find assignments")
            } footer: {
                Text("Search names, ministries, positions, terms, or assignment notes.")
            }

            if grouped.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No matching assignments",
                        systemImage: "person.3",
                        description: Text("Try clearing one or more filters.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            } else {
                ForEach(grouped, id: \.0) { roleName, assignments in
                    Section {
                        ForEach(assignments) { assignment in
                            Button {
                                editingAssignment = assignment
                            } label: {
                                AssignmentDirectoryRow(assignment: assignment)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                "Edit assignment for \(assignment.personName), \(assignment.roleName)"
                            )
                        }
                    } header: {
                        Text(roleName)
                            .appFont(.title, weight: .bold)
                            .foregroundStyle(AppTheme.riverBlueDark)
                            .textCase(nil)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 920)
        .frame(maxWidth: .infinity)
        .background(AppTheme.pageBackground)
        .navigationTitle("Ministry Directory")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Text("\(filtered.count)")
                    .monospacedDigit()
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.riverBlueDark)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(AppTheme.riverBlueSoft, in: Capsule())
                    .accessibilityLabel("\(filtered.count) assignments")
            }
        }
        .sheet(item: $editingAssignment) { assignment in
            AssignmentEditor(assignment: assignment)
                .environmentObject(model)
        }
    }
}

private enum OrdinationDirectoryFilter: String, CaseIterable, Identifiable {
    case all = "All people"
    case deacon = "Ordained Deacons"
    case deaconess = "Ordained Deaconesses"
    case elder = "Ordained Elders"
    case notOrdained = "Not ordained"

    var id: String { rawValue }

    func includes(_ person: Person) -> Bool {
        switch self {
        case .all: true
        case .deacon: person.isOrdainedDeacon
        case .deaconess: person.isOrdainedDeaconess
        case .elder: person.isOrdainedElder
        case .notOrdained: person.ordinationLabels.isEmpty
        }
    }
}

struct PeopleDirectoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""
    @State private var ordinationFilter = OrdinationDirectoryFilter.all
    @State private var selectedPerson: Person?

    private var matchingPeople: [Person] {
        let query = search.nilIfBlank
        guard query != nil || ordinationFilter != .all else { return [] }
        return model.people
            .filter { person in
                guard ordinationFilter.includes(person) else { return false }
                guard let query else { return true }
                return ([
                    person.displayName,
                    person.email ?? "",
                    person.mobilePhone ?? "",
                    person.homePhone ?? "",
                    person.membershipStatus ?? ""
                ] + person.ordinationLabels).contains {
                    $0.localizedCaseInsensitiveContains(query)
                }
            }
            .sorted {
                let lastOrder = $0.lastName.localizedCaseInsensitiveCompare($1.lastName)
                if lastOrder != .orderedSame { return lastOrder == .orderedAscending }
                return $0.firstName.localizedCaseInsensitiveCompare($1.firstName)
                    == .orderedAscending
            }
    }

    var body: some View {
        Form {
            Section("Ministry discovery") {
                NavigationLink("Search skills and assessment results") { DiscoveryProfilesView() }
            }
            Section {
                TextField(
                    "Search name, contact, membership, or ordination",
                    text: $search
                )
                .textFieldStyle(.roundedBorder)

                Picker("Ordination", selection: $ordinationFilter) {
                    ForEach(OrdinationDirectoryFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
            } header: {
                Text("Find a person")
            } footer: {
                Text(
                    "Select a person to see both current ministry placements and archived history."
                )
            }

            if search.nilIfBlank == nil, ordinationFilter == .all {
                Section {
                    ContentUnavailableView(
                        "Search the People Directory",
                        systemImage: "person.text.rectangle",
                        description: Text(
                            "Search by person details, or choose an ordination filter."
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            } else if matchingPeople.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No matching people",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("Try a broader search.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            } else {
                Section("People") {
                    ForEach(matchingPeople) { person in
                        Button {
                            selectedPerson = person
                        } label: {
                            PersonDirectoryRow(
                                person: person,
                                assignments: model.assignments.filter {
                                    $0.personId == person.id
                                }
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 920)
        .frame(maxWidth: .infinity)
        .background(AppTheme.pageBackground)
        .navigationTitle("People Directory")
        .sheet(item: $selectedPerson) { person in
            PersonMinistryHistory(person: person)
                .environmentObject(model)
        }
    }
}

private struct PersonDirectoryRow: View {
    let person: Person
    let assignments: [AssignmentDetail]

    private var currentCount: Int {
        assignments.filter(\.isCurrentPlacement).count
    }

    private var historyCount: Int {
        assignments.filter { !$0.isCurrentPlacement }.count
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(person.displayName)
                    .appFont(.headline, weight: .semibold)
                Text(person.email ?? person.mobilePhone ?? person.homePhone ?? "No contact detail")
                    .appFont(.callout)
                    .foregroundStyle(.secondary)
                if let membership = person.membershipStatus.nilIfBlank {
                    Text(membership)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(person.ordinationLabels, id: \.self) { label in
                    Label(label, systemImage: "checkmark.seal.fill")
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(AppTheme.riverBlue)
                }
                if !person.isActive {
                    Label("Inactive person record", systemImage: "archivebox")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(currentCount) current")
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(AppTheme.riverBlue)
                if historyCount > 0 {
                    Text("\(historyCount) archived/history")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PersonMinistryHistory: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let person: Person
    @State private var editingAssignment: AssignmentDetail?
    @State private var ordination: PersonOrdinationDraft

    init(person: Person) {
        self.person = person
        _ordination = State(initialValue: PersonOrdinationDraft(person: person))
    }

    private var assignments: [AssignmentDetail] {
        model.assignments
            .filter { $0.personId == person.id }
            .sorted {
                if $0.isCurrentPlacement != $1.isCurrentPlacement {
                    return $0.isCurrentPlacement
                }
                return $0.roleName.localizedCaseInsensitiveCompare($1.roleName)
                    == .orderedAscending
            }
    }

    private var currentAssignments: [AssignmentDetail] {
        assignments.filter(\.isCurrentPlacement)
    }

    private var historicalAssignments: [AssignmentDetail] {
        assignments.filter { !$0.isCurrentPlacement }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Person") {
                    LabeledContent("Name", value: person.displayName)
                    if let email = person.email.nilIfBlank {
                        LabeledContent("Email", value: email)
                    }
                    if let phone = person.mobilePhone.nilIfBlank ?? person.homePhone.nilIfBlank {
                        LabeledContent("Phone", value: phone)
                    }
                    if let membership = person.membershipStatus.nilIfBlank {
                        LabeledContent("Membership", value: membership)
                    }
                }

                Section {
                    Toggle("Ordained Deacon", isOn: $ordination.isOrdainedDeacon)
                    Toggle("Ordained Deaconess", isOn: $ordination.isOrdainedDeaconess)
                    Toggle("Ordained Elder", isOn: $ordination.isOrdainedElder)

                    if model.canEdit {
                        Button {
                            Task {
                                _ = await model.updatePersonOrdination(
                                    personId: person.id,
                                    ordination: ordination
                                )
                            }
                        } label: {
                            Label("Save Ordination Status", systemImage: "checkmark.seal")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isBusy)
                    }
                } header: {
                    Text("Ordination")
                } footer: {
                    Text(
                        model.canEdit
                            ? "Ordination stays with this person even after all ministry roles are archived."
                            : "Your account can view ordination status but cannot change it."
                    )
                }
                .disabled(!model.canEdit)

                Section("Ministry discovery") {
                    NavigationLink("Skills and assessment summary") { DiscoveryProfilesView(personId: person.id) }
                }

                Section("Current ministries") {
                    if currentAssignments.isEmpty {
                        Text("No current ministry assignments")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(currentAssignments) { assignment in
                            historyButton(assignment)
                        }
                    }
                }

                Section {
                    if historicalAssignments.isEmpty {
                        Text("No archived ministry history")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(historicalAssignments) { assignment in
                            historyButton(assignment)
                        }
                    }
                } header: {
                    Text("Archived & historical ministries")
                } footer: {
                    Text(
                        "Archived assignments remain here permanently unless restored. " +
                        "Assignments also appear here while their ministry is archived."
                    )
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle("Ministry History")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 620)
        #endif
        .sheet(item: $editingAssignment) { assignment in
            AssignmentEditor(assignment: assignment)
                .environmentObject(model)
        }
    }

    private func historyButton(_ assignment: AssignmentDetail) -> some View {
        Button {
            editingAssignment = assignment
        } label: {
            PersonHistoryAssignmentRow(assignment: assignment)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit \(assignment.roleName) assignment")
    }
}

private struct PersonHistoryAssignmentRow: View {
    let assignment: AssignmentDetail

    private var statusLabel: String {
        if !assignment.ministryIsActive { return "Ministry archived" }
        if assignment.status == "completed" { return "Assignment archived" }
        return assignment.status.capitalized
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(assignment.roleName)
                    .appFont(.headline, weight: .semibold)
                Text(
                    [assignment.subRoleName, assignment.termName]
                        .compactMap { $0?.nilIfBlank }
                        .joined(separator: " • ")
                )
                .appFont(.callout)
                .foregroundStyle(.secondary)

                if
                    let storedDate = assignment.voteDate,
                    let date = AppDate.parse(storedDate)
                {
                    Label("Voted \(AppDate.display(date))", systemImage: "checkmark.seal")
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.riverBlue)
                } else if assignment.requiresVote {
                    Label("Vote missing", systemImage: "exclamationmark.circle")
                        .appFont(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(statusLabel)
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(
                        assignment.isCurrentPlacement ? AppTheme.riverBlue : Color.secondary
                    )
                if
                    let archivedAt = assignment.archivedAt,
                    let archivedDate = AppDate.displayTimestamp(archivedAt)
                {
                    Text("Archived \(archivedDate)")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(AppTheme.riverBlue)
            }
        }
        .padding(.vertical, 4)
    }
}

struct VoteQueueView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""

    private var awaitingVotes: [AssignmentDetail] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.assignments
            .filter { assignment in
                guard assignment.isCurrentPlacement, assignment.voteMissing else {
                    return false
                }
                guard !query.isEmpty else { return true }
                return [
                    assignment.personName,
                    assignment.roleName,
                    assignment.subRoleName ?? "",
                    assignment.termName ?? ""
                ].contains { $0.localizedCaseInsensitiveContains(query) }
            }
            .sorted {
                let roleOrder = $0.roleName.localizedCaseInsensitiveCompare($1.roleName)
                if roleOrder != .orderedSame { return roleOrder == .orderedAscending }
                let lastOrder = $0.lastName.localizedCaseInsensitiveCompare($1.lastName)
                if lastOrder != .orderedSame { return lastOrder == .orderedAscending }
                return $0.firstName.localizedCaseInsensitiveCompare($1.firstName)
                    == .orderedAscending
            }
    }

    private var grouped: [(String, [AssignmentDetail])] {
        Dictionary(grouping: awaitingVotes, by: \.roleName)
            .map { ($0.key, $0.value) }
            .sorted {
                $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending
            }
    }

    var body: some View {
        Form {
            Section {
                TextField(
                    "Search person, ministry, position, or term",
                    text: $search
                )
                .textFieldStyle(.roundedBorder)

                LabeledContent("Assignments awaiting a vote") {
                    Text("\(awaitingVotes.count)")
                        .monospacedDigit()
                        .fontWeight(.semibold)
                        .foregroundStyle(awaitingVotes.isEmpty ? Color.secondary : Color.orange)
                }
            } header: {
                Text("Church vote work queue")
            } footer: {
                Text(
                    "An assignment appears here when either its ministry or position " +
                    "requires a church vote and no vote date has been recorded."
                )
            }

            if grouped.isEmpty {
                Section {
                    ContentUnavailableView(
                        search.nilIfBlank == nil ? "No votes awaiting" : "No matching votes",
                        systemImage: "checkmark.seal.fill",
                        description: Text(
                            search.nilIfBlank == nil
                                ? "Every required church vote has a recorded date."
                                : "Try a different search or clear the search field."
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            } else {
                ForEach(grouped, id: \.0) { ministryName, assignments in
                    Section {
                        ForEach(assignments) { assignment in
                            PendingVoteRow(assignment: assignment)
                                .environmentObject(model)
                        }
                    } header: {
                        Text(ministryName)
                            .appFont(.title2, weight: .bold)
                            .foregroundStyle(AppTheme.riverBlueDark)
                            .textCase(nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 920)
        .frame(maxWidth: .infinity)
        .background(AppTheme.pageBackground)
        .navigationTitle("Awaiting Church Vote")
    }
}

struct PendingVoteRow: View {
    @EnvironmentObject private var model: AppModel
    let assignment: AssignmentDetail
    @State private var voteDate = Date()

    private var requirementLabel: String {
        switch (assignment.ministryRequiresVote, assignment.positionRequiresVote) {
        case (true, true): "Ministry and position require a vote"
        case (true, false): "Ministry requires a vote"
        case (false, true): "Position requires a vote"
        case (false, false): "Vote required"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(assignment.personName)
                        .appFont(.headline, weight: .semibold)
                    Text(
                        [assignment.subRoleName, assignment.termName]
                            .compactMap { $0?.nilIfBlank }
                            .joined(separator: " • ")
                    )
                    .appFont(.callout)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Label(requirementLabel, systemImage: "exclamationmark.circle")
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.orange)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    DatePicker(
                        "Vote date",
                        selection: $voteDate,
                        displayedComponents: .date
                    )
                    Spacer()
                    recordButton
                }
                VStack(alignment: .leading, spacing: 10) {
                    DatePicker(
                        "Vote date",
                        selection: $voteDate,
                        displayedComponents: .date
                    )
                    recordButton
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var recordButton: some View {
        Button {
            Task {
                await model.recordAssignmentVote(
                    assignmentId: assignment.id,
                    voteDate: voteDate
                )
            }
        } label: {
            Label("Record Vote", systemImage: "checkmark.seal")
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.isBusy)
    }
}

private struct AssignmentDirectoryRow: View {
    let assignment: AssignmentDetail

    private var usesPhoneLayout: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    var body: some View {
        if usesPhoneLayout {
            phoneLayout
        } else {
            regularLayout
        }
    }

    private var phoneLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(assignment.personName)
                    .fontWeight(assignment.leadershipRank < 100 ? .semibold : .regular)
                Spacer(minLength: 8)
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(AppTheme.riverBlue)
                    .accessibilityHidden(true)
            }

            if let subRole = assignment.subRoleName.nilIfBlank {
                positionBadge(subRole, keepsOneLine: true)
            }

            if assignment.endDateValue != nil || assignment.requiresVote {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        phoneEndDate
                        phoneVoteStatus
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        phoneEndDate
                        phoneVoteStatus
                    }
                }
            }

            noteBlock
        }
        .padding(.vertical, 3)
    }

    private var regularLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(assignment.personName)
                    .fontWeight(assignment.leadershipRank < 100 ? .semibold : .regular)
                HStack(spacing: 6) {
                    if let subRole = assignment.subRoleName {
                        positionBadge(subRole)
                    }
                    Text(assignment.termName ?? "No term")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
                noteBlock
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(AppTheme.riverBlue)
                    .accessibilityHidden(true)
                if let end = assignment.endDateValue {
                    Text("Ends \(AppDate.display(end))")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
                if assignment.requiresVote {
                    if
                        let storedDate = assignment.voteDate,
                        let date = AppDate.parse(storedDate)
                    {
                        Label(
                            "Voted \(AppDate.display(date))",
                            systemImage: "checkmark.seal"
                        )
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.riverBlue)
                    } else {
                        Label("Vote missing", systemImage: "exclamationmark.circle")
                            .appFont(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func positionBadge(
        _ title: String,
        keepsOneLine: Bool = false
    ) -> some View {
        Text(title)
            .appFont(.caption, weight: .medium)
            .lineLimit(keepsOneLine ? 1 : nil)
            .minimumScaleFactor(keepsOneLine ? 0.8 : 1)
            .allowsTightening(keepsOneLine)
            .truncationMode(.tail)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                assignment.leadershipRank < 100
                    ? Color.accentColor.opacity(0.15)
                    : Color.secondary.opacity(0.12),
                in: Capsule()
            )
    }

    @ViewBuilder
    private var phoneEndDate: some View {
        if let end = assignment.endDateValue {
            Text("Ends \(AppDate.display(end))")
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var phoneVoteStatus: some View {
        if assignment.requiresVote {
            if
                let storedDate = assignment.voteDate,
                let date = AppDate.parse(storedDate)
            {
                Text("Voted \(AppDate.display(date))")
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.riverBlue)
            } else {
                Label("Vote missing", systemImage: "exclamationmark.circle")
                    .appFont(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var noteBlock: some View {
        if let note = assignment.notes.nilIfBlank {
            Text(note)
                .appFont(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.top, 3)
            Label(
                assignment.noteIsPublic ? "Reports & web" : "Staff only",
                systemImage: assignment.noteIsPublic ? "eye" : "lock"
            )
            .appFont(.caption2, weight: .semibold)
            .foregroundStyle(
                assignment.noteIsPublic ? AppTheme.riverBlue : Color.secondary
            )
        }
    }
}

private struct AssignmentEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let assignment: AssignmentDetail
    @State private var subRoleId: UUID?
    @State private var termId: UUID?
    @State private var notes: String
    @State private var noteIsPublic: Bool
    @State private var hasVoteDate: Bool
    @State private var voteDate: Date
    @State private var showingArchiveConfirmation = false

    init(assignment: AssignmentDetail) {
        self.assignment = assignment
        _subRoleId = State(initialValue: assignment.subRoleId)
        _termId = State(initialValue: assignment.termId)
        _notes = State(initialValue: assignment.notes ?? "")
        _noteIsPublic = State(initialValue: assignment.noteIsPublic)
        let storedVoteDate = assignment.voteDate.flatMap(AppDate.parse)
        _hasVoteDate = State(initialValue: storedVoteDate != nil)
        _voteDate = State(initialValue: storedVoteDate ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Assignment") {
                    LabeledContent("Volunteer", value: assignment.personName)
                    LabeledContent("Ministry", value: assignment.roleName)

                    Picker("Position", selection: $subRoleId) {
                        Text("No position — team member").tag(UUID?.none)
                        ForEach(availablePositions) { position in
                            Text(position.name).tag(Optional(position.id))
                        }
                    }
                    .onChange(of: subRoleId) { _, value in
                        if value == nil {
                            termId = nil
                            hasVoteDate = false
                        }
                    }

                    Picker("Term", selection: $termId) {
                        Text(
                            placementRequirements.requiresTerm
                                ? "Choose a term"
                                : "No term (optional)"
                        )
                        .tag(UUID?.none)
                        ForEach(availableTerms) { term in
                            Text("\(term.name) — \(term.dateRangeLabel)")
                                .tag(Optional(term.id))
                        }
                    }
                    .disabled(subRoleId == nil)

                    if placementRequirements.requiresTerm {
                        Text("A term is required because this placement requires a church vote.")
                            .appFont(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(subRoleId == nil
                            ? "Team members do not need a position, term, or church vote."
                            : "A term is optional because this placement does not require a church vote.")
                            .appFont(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let saveRequirementMessage {
                        Label(saveRequirementMessage, systemImage: "exclamationmark.circle.fill")
                            .appFont(.footnote, weight: .semibold)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    LabeledContent("Requirement") {
                        Text(voteRequirementLabel)
                            .foregroundStyle(
                                placementRequirements.requiresChurchVote
                                    ? Color.orange
                                    : Color.secondary
                            )
                    }
                    Toggle("Church vote recorded", isOn: $hasVoteDate)
                        .disabled(subRoleId == nil)
                    if hasVoteDate {
                        DatePicker(
                            "Vote date",
                            selection: $voteDate,
                            displayedComponents: .date
                        )
                    }
                } header: {
                    Label("Church vote", systemImage: "checkmark.seal")
                } footer: {
                    Text(
                        "Correct the date here, or turn off ‘Church vote recorded’ to " +
                        "return a required assignment to the Votes queue."
                    )
                }

                Section {
                    TextEditor(text: $notes)
                        .frame(minHeight: 150)
                        .padding(8)
                        .background(AppTheme.riverBlueSoft.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Toggle(
                        "Include this note in reports and the public web directory",
                        isOn: $noteIsPublic
                    )
                    .disabled(notes.nilIfBlank == nil)
                } header: {
                    Label("Note", systemImage: "note.text")
                } footer: {
                    Text(
                        "Off keeps the note inside the staff app. On includes it in " +
                        "reports and, when the assignment and ministry are public, the iframe directory."
                    )
                }

                Section {
                    if assignment.status == "completed" {
                        Button {
                            Task {
                                if await model.setAssignmentArchived(
                                    assignmentId: assignment.id,
                                    archived: false
                                ) {
                                    dismiss()
                                }
                            }
                        } label: {
                            Label("Restore this assignment", systemImage: "arrow.uturn.backward")
                        }
                    } else if assignment.isCurrentPlacement {
                        Button("Archive this assignment", role: .destructive) {
                            showingArchiveConfirmation = true
                        }
                    } else {
                        Label(
                            "This assignment is historical because its ministry is archived.",
                            systemImage: "archivebox"
                        )
                        .foregroundStyle(.secondary)
                    }
                } footer: {
                    if assignment.status == "completed" {
                        Text("Restoring returns this assignment to current directories and reports.")
                    } else if assignment.isCurrentPlacement {
                        Text(
                            "Archiving ends this placement and removes it from current directories, " +
                            "reports, the Votes queue, and the public iframe. Its history remains in " +
                            "the People Directory and can be restored."
                        )
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle("Edit Assignment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await model.updateAssignmentDetails(
                                assignmentId: assignment.id,
                                subRoleId: subRoleId,
                                termId: termId,
                                notes: notes,
                                noteIsPublic: noteIsPublic,
                                voteDate: hasVoteDate ? voteDate : nil
                            ) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(model.isBusy || saveRequirementMessage != nil)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 620)
        #endif
        .confirmationDialog(
            "Archive this volunteer assignment?",
            isPresented: $showingArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Archive Assignment", role: .destructive) {
                Task {
                    if await model.setAssignmentArchived(
                        assignmentId: assignment.id,
                        archived: true
                    ) {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The assignment remains available in the volunteer's People Directory history.")
        }
        .onChange(of: notes) { _, value in
            if value.nilIfBlank == nil {
                noteIsPublic = false
            }
        }
    }

    private var availablePositions: [MinistrySubRole] {
        model.subRoles
            .filter {
                $0.roleId == assignment.roleId
                    && ($0.isActive || $0.id == subRoleId)
            }
            .sorted { left, right in
                if left.leadershipRank != right.leadershipRank {
                    return left.leadershipRank < right.leadershipRank
                }
                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }
    }

    private var availableTerms: [MinistryTerm] {
        model.terms.filter { $0.isActive || $0.id == termId }
    }

    private var selectedPosition: MinistrySubRole? {
        model.subRoles.first(where: { $0.id == subRoleId })
    }

    private var ministryRequiresVote: Bool {
        model.roles.first(where: { $0.id == assignment.roleId })?.requiresVote
            ?? assignment.ministryRequiresVote
    }

    private var positionRequiresVote: Bool {
        selectedPosition?.requiresVote
            ?? (subRoleId == assignment.subRoleId && assignment.positionRequiresVote)
    }

    private var placementRequirements: AssignmentRequirements {
        AssignmentRequirements(
            ministryRequiresVote: ministryRequiresVote,
            positionRequiresVote: positionRequiresVote,
            hasPosition: subRoleId != nil
        )
    }

    private var saveRequirementMessage: String? {
        if placementRequirements.requiresTerm, termId == nil {
            return "Choose a term because this placement requires a church vote."
        }
        return nil
    }

    private var voteRequirementLabel: String {
        guard subRoleId != nil else { return "Not required for team membership" }
        return switch (ministryRequiresVote, positionRequiresVote) {
        case (true, true): "Required by ministry and position"
        case (true, false): "Required by ministry"
        case (false, true): "Required by position"
        case (false, false): "Not required"
        }
    }
}

private enum ReportChoice: String, CaseIterable, Identifiable {
    case directory = "Ministry directory"
    case awaiting = "Awaiting church vote"
    case ending = "Terms ending in six months"
    var id: String { rawValue }
}

struct ReportsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var filter = AssignmentFilter()
    @State private var choice: ReportChoice = .directory
    @State private var previewDocument: ReportPreviewDocument?

    private var filtered: [AssignmentDetail] { filter.apply(to: model.assignments) }

    var body: some View {
        Form {
            Section {
                Picker("Report", selection: $choice) {
                    ForEach(ReportChoice.allCases) { report in Text(report.rawValue).tag(report) }
                }
                .onChange(of: choice) { _, value in
                    filter = AssignmentFilter()
                    if value == .awaiting { filter.voteStatus = .awaiting }
                    if value == .ending { filter.endingWindow = .sixMonths }
                }
            } header: { Text("1. Choose a report") }

            Section {
                AssignmentFilterControls(filter: $filter, roles: model.roles, includeVoteFilter: true)
                    .padding(.vertical, 8)
                Button("Reset Filters") { choice = .directory; filter = AssignmentFilter() }
            } header: { Text("2. Narrow the report (optional)") }

            Section {
                LabeledContent("Assignments included") { Text("\(filtered.count)").monospacedDigit() }
                Text(filter.description(roles: model.roles))
                    .appFont(.callout).foregroundStyle(.secondary)
                Button { buildReport() } label: {
                    Label("Preview Report", systemImage: "doc.richtext")
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(filtered.isEmpty)
                if filtered.isEmpty { Text("No assignments match. Try another ministry or reset the filters.").foregroundStyle(.secondary) }
            } header: { Text("3. Preview, print or save") }
              footer: { Text("Your church’s name and logo appear on the PDF. Volunteers are grouped by ministry with leaders first. Only approved notes are included; contact details and ordination status stay private.") }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 920)
        .frame(maxWidth: .infinity)
        .background(AppTheme.pageBackground)
        .navigationTitle("Reports")
        .sheet(item: $previewDocument) { document in PDFReportPreview(data: document.data) }
    }

    private func buildReport() {
        do {
            let data = try ReportGenerator.makePDF(assignments: filtered,
                filterDescription: filter.description(roles: model.roles), groupByRole: true,
                churchName: model.currentChurch?.name ?? "Ministry Volunteers", churchLogoData: model.churchLogoData)
            previewDocument = try ReportPreviewDocument(data: data)
        } catch { model.errorMessage = error.localizedDescription }
    }
}

private struct PDFReportPreview: View {
    @Environment(\.dismiss) private var dismiss
    let data: Data
    @State private var exporting = false

    var body: some View {
        NavigationStack {
            PDFPreview(data: data)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Report Preview")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            printPDF(data)
                        } label: {
                            Label("Print", systemImage: "printer")
                        }
                        Button {
                            exporting = true
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                    }
                }
        }
        #if os(macOS)
        .frame(width: 780, height: 580)
        #endif
        .fileExporter(
            isPresented: $exporting,
            document: PDFReportDocument(data: data),
            contentType: .pdf,
            defaultFilename: "Volunteer-Ministry-Directory"
        ) { _ in }
    }

    private func printPDF(_ data: Data) {
        #if os(iOS)
        let controller = UIPrintInteractionController.shared
        controller.printingItem = data
        controller.present(animated: true)
        #elseif os(macOS)
        guard let document = PDFDocument(data: data) else { return }
        let view = PDFView(
            frame: CGRect(origin: .zero, size: CGSize(width: 792, height: 612))
        )
        view.document = document
        NSPrintOperation(view: view).run()
        #endif
    }
}



struct DiscoveryProfilesView: View {
    @EnvironmentObject private var model: AppModel
    var personId: UUID? = nil
    @State private var query = ""
    @State private var skill = ""
    @State private var motivation = ""
    @State private var availability = ""
    @State private var pending = false
    @State private var offset = 0
    @State private var result: DiscoverySearchResult?
    @State private var error = ""
    @State private var busy = false
    private let areas = [("A", "Pioneering and mission"), ("P", "Faithfulness and discernment"), ("E", "Sharing faith"), ("S", "Care and belonging"), ("T", "Teaching and understanding")]

    var body: some View {
        List {
            if personId == nil {
                Section("Search ministry profiles") {
                    TextField("Name, email, or shared interests", text: $query)
                    TextField("Skill", text: $skill)
                    Picker("Leading motivation", selection: $motivation) {
                        Text("Any").tag("")
                        ForEach(areas, id: \.0) { item in Text(item.1).tag(item.0) }
                    }
                    Picker("Availability", selection: $availability) {
                        Text("Any").tag("")
                        Text("Available").tag("available")
                        Text("Limited").tag("limited")
                        Text("Unavailable").tag("unavailable")
                        Text("Unsure").tag("unsure")
                    }
                    Toggle("Awaiting a People match", isOn: $pending)
                    Button("Search profiles") { offset = 0; Task { await load() } }
                        .disabled(busy)
                }
            }
            if busy { ProgressView("Loading profiles") }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            if let result {
                Section("\(result.total) profiles") {
                    ForEach(result.items) { person in
                        NavigationLink {
                            DiscoveryPersonView(person: person)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(person.displayName).font(.headline)
                                Text(person.personId == nil ? "Awaiting a People match" : "Linked to People").font(.caption)
                                Text(person.profile?.skills.map(\.name).joined(separator: ", ") ?? "No shared skills")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if result.items.isEmpty { Text("No matching ministry profile.") }
                }
                if personId == nil {
                    Section {
                        Button("Previous") { offset = max(0, offset - 20); Task { await load() } }
                            .disabled(offset == 0 || busy)
                        Button("Next") { offset += 20; Task { await load() } }
                            .disabled(offset + 20 >= result.total || busy)
                    }
                }
            }
        }
        .navigationTitle("Ministry profiles")
        .task { await load() }
    }
    private func load() async {
        busy = true
        defer { busy = false }
        do {
            var filters = ["q": query, "skill": skill, "motivation": motivation, "availability": availability, "pending": pending ? "true" : ""]
            if let personId { filters["person_id"] = personId.uuidString.lowercased() }
            result = try await model.discoverySearch(filters: filters, offset: offset)
            error = ""
        } catch { self.error = error.localizedDescription }
    }
}

struct DiscoveryPersonView: View {
    @EnvironmentObject private var model: AppModel
    @State var person: DiscoveryPerson
    @State private var query = ""
    @State private var candidates: [DiscoveryCandidate] = []
    @State private var selected: UUID?
    @State private var note = ""
    @State private var error = ""
    @State private var busy = false
    @State private var confirmLink = false
    @State private var confirmCreate = false

    var body: some View {
        Form {
            Section("Participant") {
                Text(person.displayName).font(.headline)
                Text(person.email)
            }
            if person.personId == nil && model.canEdit {
                Section("Confirm the People match") {
                    TextField("Search another name or email", text: $query)
                    Button("Find matches") { Task { await find() } }
                    ForEach(candidates) { candidate in
                        Button {
                            selected = candidate.id
                        } label: {
                            VStack(alignment: .leading) {
                                Text(candidate.firstName + " " + candidate.lastName + (selected == candidate.id ? " ✓" : ""))
                                Text(candidate.email ?? "No email").font(.caption)
                                Text(candidate.reason).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("Approve selected match") { confirmLink = true }.disabled(selected == nil || busy)
                    Button("Create a new People record") { confirmCreate = true }.disabled(busy)
                }
            }
            if let profile = person.profile {
                Section("Shared welcome answers") {
                    answer("Connection to the church", profile.connection)
                    answer("Service experience", profile.service)
                    answer("What brings joy", profile.joy)
                    answer("Abilities and gifts", profile.abilities)
                    answer("Hopes and interests", profile.hope)
                    answer("Occupation or training", profile.occupation)
                    answer("Ministry interests", profile.interests)
                    answer("Availability", profile.availability)
                    answer("Contact preference", profile.contact)
                }
                Section("Skills reported by the member") {
                    ForEach(Array(profile.skills.enumerated()), id: \.offset) { _, skill in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(skill.name).font(.headline)
                            Text([skill.experience, skill.interest].compactMap { $0 }.joined(separator: " · "))
                            if let notes = skill.notes, !notes.isEmpty { Text(notes) }
                        }
                    }
                }
            } else { Section { Text("The participant has not shared their profile yet.") } }
            scoreSection("Ministry Motivations", person.motivations, motivations: true)
            scoreSection("Big Five summary", person.bigfive, motivations: false)
            Section("Leader observations") {
                ForEach(person.observations) { observation in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(observation.note)
                        Text(observation.author).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if model.canEdit {
                    TextEditor(text: $note).frame(minHeight: 80)
                    Button("Save observation") {
                        Task { await perform { try await model.discoveryObserve(member: person.id, note: note) }; note = "" }
                    }.disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                }
            }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Ministry profile")
        .task { if person.personId == nil { await find() } }
        .alert("Link this person?", isPresented: $confirmLink) {
            Button("Approve") { Task { await perform { try await model.discoveryLink(member: person.id, person: selected, create: false) } } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Confirm the participant's identity before linking the selected People record.") }
        .alert("Create a new People record?", isPresented: $confirmCreate) {
            Button("Create") { Task { await perform { try await model.discoveryLink(member: person.id, person: nil, create: true) } } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Check that an existing person does not match first. The new record will be private.") }
    }
    @ViewBuilder private func answer(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty { VStack(alignment: .leading) { Text(title).font(.headline); Text(value) } }
    }
    @ViewBuilder private func scoreSection(_ title: String, _ scores: DiscoveryScores?, motivations: Bool) -> some View {
        Section(title) {
            if let scores {
                ForEach(scores.domains.keys.sorted(), id: \.self) { key in
                    let labels = motivations
                        ? ["A":"Pioneering and mission","P":"Faithfulness and discernment","E":"Sharing faith","S":"Care and belonging","T":"Teaching and understanding"]
                        : ["O":"Creativity and exploration","C":"Organization and follow-through","E":"Social engagement","A":"Cooperation and directness"]
                    LabeledContent(labels[key] ?? key) {
                        if let wrapped = scores.domains[key], let value = wrapped { Text(String(format: "%.1f / 5", value)) }
                        else { Text("Not enough answers") }
                    }
                }
                Text("Completed " + String(scores.submittedAt.prefix(10))).font(.caption)
            } else { Text("No submitted result.") }
        }
    }
    private func find() async {
        do { candidates = try await model.discoveryCandidates(member: person.id, query: query); selected = candidates.first?.id; error = "" }
        catch { self.error = error.localizedDescription }
    }
    private func perform(_ action: () async throws -> Void) async {
        busy = true; defer { busy = false }
        do {
            try await action()
            if let updated = try await model.discoverySearch(filters: ["member_id": person.id.uuidString.lowercased()]).items.first { person = updated }
            error = ""
        } catch { self.error = error.localizedDescription }
    }
}

struct DiscoveryRegistrationView: View {
    @EnvironmentObject private var model: AppModel
    @State private var registration: DiscoveryRegistration?
    @State private var error = ""
    var body: some View {
        Form {
            Section("Participant access") {
                Text("Leaders and participants can use the same account. The participant workflow is available on the web.")
                Link("Open my participant profile", destination: URL(string: "https://ministryvolunteers.worf.app/discover")!)
            }
            if model.isAdministrator {
                Section("This church's registration link") {
                    if let registration {
                        Text(registration.url.absoluteString).textSelection(.enabled)
                        ShareLink("Share registration link", item: registration.url)
                        Link("Open registration", destination: registration.url)
                        Text(registration.enabled ? "Registration is open." : "Registration is paused.")
                    }
                    if !error.isEmpty { Text(error).foregroundStyle(.red) }
                }
            }
        }
        .navigationTitle("Member registration")
        .task {
            if model.isAdministrator {
                do { registration = try await model.discoveryRegistration() }
                catch { self.error = error.localizedDescription }
            }
        }
    }
}
