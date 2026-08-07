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
        VStack(alignment: .leading, spacing: 10) {
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

struct PeopleDirectoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""
    @State private var selectedPerson: Person?

    private var matchingPeople: [Person] {
        guard let query = search.nilIfBlank else { return [] }
        return model.people
            .filter { person in
                [
                    person.displayName,
                    person.email ?? "",
                    person.mobilePhone ?? "",
                    person.homePhone ?? "",
                    person.membershipStatus ?? ""
                ].contains { $0.localizedCaseInsensitiveContains(query) }
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
            Section {
                TextField(
                    "Search name, email, phone, or membership status",
                    text: $search
                )
                .textFieldStyle(.roundedBorder)
            } header: {
                Text("Find a person")
            } footer: {
                Text(
                    "Select a person to see both current ministry placements and archived history."
                )
            }

            if search.nilIfBlank == nil {
                Section {
                    ContentUnavailableView(
                        "Search the People Directory",
                        systemImage: "person.text.rectangle",
                        description: Text(
                            "Enter part of a name, email address, phone number, or membership status."
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

private struct PendingVoteRow: View {
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
                        Text("Choose a position").tag(UUID?.none)
                        ForEach(availablePositions) { position in
                            Text(position.name).tag(Optional(position.id))
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

                    if placementRequirements.requiresTerm {
                        Text("A term is required because this placement requires a church vote.")
                            .appFont(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("A term is optional because this placement does not require a church vote.")
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
            positionRequiresVote: positionRequiresVote
        )
    }

    private var saveRequirementMessage: String? {
        if subRoleId == nil {
            return "Choose a position before saving."
        }
        if placementRequirements.requiresTerm, termId == nil {
            return "Choose a term because this placement requires a church vote."
        }
        return nil
    }

    private var voteRequirementLabel: String {
        switch (ministryRequiresVote, positionRequiresVote) {
        case (true, true): "Required by ministry and position"
        case (true, false): "Required by ministry"
        case (false, true): "Required by position"
        case (false, false): "Not required"
        }
    }
}

struct ReportsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var filter = AssignmentFilter()
    @State private var pdfData: Data?
    @State private var showingPreview = false

    private var filtered: [AssignmentDetail] {
        filter.apply(to: model.assignments)
    }

    var body: some View {
        Form {
            Section("Report filters") {
                AssignmentFilterControls(
                    filter: $filter,
                    roles: model.roles,
                    includeVoteFilter: true
                )
            }

            Section {
                LabeledContent("Assignments included") {
                    Text("\(filtered.count)")
                        .monospacedDigit()
                }
                Text(filter.description(roles: model.roles))
                    .appFont(.callout)
                    .foregroundStyle(.secondary)

                Button {
                    buildReport()
                } label: {
                    Label("Build PDF Report", systemImage: "doc.richtext")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } header: {
                Text("Preview")
            } footer: {
                Text(
                    "The all-ministries PDF groups volunteers under ministry headings. " +
                    "Each ministry uses the same leadership-first ordering as the directory: " +
                    "Head/Lead, Co-Head/Co-Lead, Assistant Head, then last and first name. " +
                    "Only notes marked for reports and the web are included."
                )
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 920)
        .frame(maxWidth: .infinity)
        .background(AppTheme.pageBackground)
        .navigationTitle("Reports")
        .sheet(isPresented: $showingPreview) {
            if let pdfData {
                PDFReportPreview(data: pdfData)
            }
        }
    }

    private func buildReport() {
        do {
            pdfData = try ReportGenerator.makePDF(
                assignments: filtered,
                filterDescription: filter.description(roles: model.roles),
                groupByRole: filter.roleId == nil
            )
            showingPreview = true
        } catch {
            model.errorMessage = error.localizedDescription
        }
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
                .navigationTitle("Volunteer Directory PDF")
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
            defaultFilename: "Riverview-Volunteer-Directory"
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
            Section {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) { summaryCards(data: data) }
                    VStack(spacing: 10) { summaryCards(data: data) }
                }
            } header: {
                Text("Placement overview")
            } footer: {
                Text(
                    "Queues update automatically as assignments are added, terms end, " +
                    "or people arrive from Planning Center."
                )
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
                Text("Ministry Watch")
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
