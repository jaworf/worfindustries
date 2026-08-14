import SwiftUI

private enum PersonEntryMode: String, CaseIterable, Identifiable {
    case existing = "Find person"
    case new = "New person"

    var id: String { rawValue }
}

private enum PositionPickerChoice: Hashable {
    case none
    case position(UUID)
    case add
}

struct AssignmentEntryView: View {
    @EnvironmentObject private var model: AppModel
    @Binding private var route: AssignmentRoute?
    @State private var mode: PersonEntryMode = .existing
    @State private var personSearch = ""
    @State private var assignment = AssignmentDraft()
    @State private var newPerson = PersonDraft()
    @State private var existingOrdination = PersonOrdinationDraft()
    @State private var includeVoteDate = false
    @State private var selectedVoteDate = Date()
    @State private var roleForNewPosition: MinistryRole?
    @State private var showSaveRequirements = false

    init(route: Binding<AssignmentRoute?> = .constant(nil)) {
        _route = route
    }

    private var selectedPerson: Person? {
        model.people.first(where: { $0.id == assignment.personId })
    }

    private var selectedRole: MinistryRole? {
        model.roles.first(where: { $0.id == assignment.roleId })
    }

    private var selectedPosition: MinistrySubRole? {
        model.subRoles.first(where: { $0.id == assignment.subRoleId })
    }

    private var selectedOrdinationKind: OrdinationKind? {
        OrdinationKind.matching(ministryName: selectedRole?.name)
    }

    private var placementRequirements: AssignmentRequirements {
        AssignmentRequirements(
            ministryRequiresVote: selectedRole?.requiresVote == true,
            positionRequiresVote: selectedPosition?.requiresVote == true
        )
    }

    private var placementRequiresVote: Bool {
        placementRequirements.requiresChurchVote
    }

    private var matchingPeople: [Person] {
        let query = personSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let source = model.people.filter {
            $0.isActive && (
                $0.displayName.localizedCaseInsensitiveContains(query)
                || ($0.email?.localizedCaseInsensitiveContains(query) ?? false)
                || ($0.mobilePhone?.localizedCaseInsensitiveContains(query) ?? false)
            )
        }
        return Array(source.prefix(12))
    }

    private var availableSubRoles: [MinistrySubRole] {
        model.subRoles.filter {
            $0.isActive && $0.roleId == assignment.roleId
        }
    }

    private var positionPickerChoice: Binding<PositionPickerChoice> {
        Binding(
            get: {
                assignment.subRoleId.map(PositionPickerChoice.position) ?? .none
            },
            set: { choice in
                switch choice {
                case .none:
                    assignment.subRoleId = nil
                case let .position(id):
                    assignment.subRoleId = id
                case .add:
                    assignment.subRoleId = nil
                    guard let selectedRole else {
                        model.errorMessage = "Choose a ministry before adding a position."
                        return
                    }
                    roleForNewPosition = selectedRole
                }
            }
        )
    }

    var body: some View {
        Form {
            Section("Volunteer") {
                Picker("Person source", selection: $mode) {
                    ForEach(PersonEntryMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _, newMode in
                    if newMode == .new {
                        assignment.personId = nil
                    }
                }

                if mode == .existing {
                    existingPersonPicker
                } else {
                    newPersonFields
                }
            }

            Section("Ministry placement") {
                Picker("Ministry", selection: $assignment.roleId) {
                    Text("Choose a ministry").tag(UUID?.none)
                    ForEach(model.roles.filter(\.isActive)) { role in
                        Text(role.name).tag(Optional(role.id))
                    }
                }

                Picker("Position", selection: positionPickerChoice) {
                    Text("Choose a position").tag(PositionPickerChoice.none)
                    ForEach(availableSubRoles) { subRole in
                        Text(subRole.name)
                            .tag(PositionPickerChoice.position(subRole.id))
                    }
                    Label("Add a position…", systemImage: "plus.circle")
                        .tag(PositionPickerChoice.add)
                }

                Picker("Term", selection: $assignment.termId) {
                    Text(placementRequirements.requiresTerm ? "Choose a term" : "No term (optional)")
                        .tag(UUID?.none)
                    ForEach(model.terms.filter(\.isActive)) { term in
                        Text("\(term.name) — \(term.dateRangeLabel)")
                            .tag(Optional(term.id))
                    }
                }
                if placementRequirements.requiresTerm {
                    Text("A term is required because this placement requires a church vote.")
                        .appFont(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("A term is optional for placements that do not require a church vote.")
                        .appFont(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let ordinationKind = selectedOrdinationKind {
                Section("Ordination") {
                    Toggle(
                        ordinationKind.label,
                        isOn: ordinationBinding(for: ordinationKind)
                    )
                    Text(
                        "This is saved on the person and remains searchable even if this " +
                        "ministry assignment is later archived."
                    )
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Record details") {
                if placementRequiresVote {
                    LabeledContent("Church vote") {
                        Text("Required")
                            .foregroundStyle(.orange)
                    }
                    Text(voteRequirementDescription)
                        .appFont(.footnote)
                        .foregroundStyle(.secondary)
                    DatePicker(
                        "Vote date",
                        selection: $selectedVoteDate,
                        displayedComponents: .date
                    )
                    .onAppear { includeVoteDate = true }
                } else {
                    Toggle("Record a vote date", isOn: $includeVoteDate)
                    if includeVoteDate {
                        DatePicker(
                            "Vote date",
                            selection: $selectedVoteDate,
                            displayedComponents: .date
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Note", systemImage: "note.text")
                        .appFont(.headline, weight: .semibold)
                        .foregroundStyle(AppTheme.riverBlueDark)
                    TextField(
                        "Add context for this assignment (optional)",
                        text: $assignment.notes,
                        axis: .vertical
                    )
                    .lineLimit(3...7)
                    .padding(10)
                    .background(
                        AppTheme.riverBlueSoft.opacity(0.62),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                }
                Toggle(
                    "Include this note in reports and the public web directory",
                    isOn: $assignment.noteIsPublic
                )
                .disabled(assignment.notes.nilIfBlank == nil)
                Text("Notes remain staff-only unless this option is enabled.")
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
                Toggle("Show this assignment in the public directory", isOn: $assignment.isPublic)
            }

            Section {
                Button {
                    attemptSave()
                } label: {
                    if model.isBusy {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Save Assignment", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)

                if showSaveRequirements, let saveRequirementMessage {
                    Label(saveRequirementMessage, systemImage: "exclamationmark.circle.fill")
                        .appFont(.footnote, weight: .semibold)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("assignmentSaveRequirement")
                }
            } footer: {
                Text(
                    "Changing a ministry or position name later updates every assignment " +
                    "because placements reference records, not copied names."
                )
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 960)
        .frame(maxWidth: .infinity)
        .background(AppTheme.pageBackground)
        .navigationTitle("Assign a Volunteer")
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
        .onChange(of: assignment.roleId) { _, _ in
            if !availableSubRoles.contains(where: { $0.id == assignment.subRoleId }) {
                assignment.subRoleId = nil
            }
            includeVoteDate = placementRequiresVote
        }
        .onChange(of: assignment.subRoleId) { _, _ in
            includeVoteDate = placementRequiresVote
        }
        .onChange(of: assignment.personId) { _, _ in
            syncExistingOrdination()
        }
        .onChange(of: assignment.notes) { _, notes in
            if notes.nilIfBlank == nil {
                assignment.noteIsPublic = false
            }
        }
        .onAppear {
            applyRouteIfNeeded(route)
        }
        .onChange(of: route) { _, newRoute in
            applyRouteIfNeeded(newRoute)
        }
        .sheet(item: $roleForNewPosition) { role in
            NewSubRoleSheet(role: role) { createdPosition in
                assignment.subRoleId = createdPosition.id
            }
            .environmentObject(model)
        }
    }

    private var voteRequirementDescription: String {
        switch (selectedRole?.requiresVote == true, selectedPosition?.requiresVote == true) {
        case (true, true):
            "Both this ministry and this position require a church vote."
        case (true, false):
            "This ministry requires a church vote."
        case (false, true):
            "This position requires a church vote."
        case (false, false):
            ""
        }
    }

    private var existingPersonPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search name, email, or phone", text: $personSearch)
                .textFieldStyle(.roundedBorder)

            if let selectedPerson {
                HStack {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading) {
                        Text(selectedPerson.displayName)
                            .fontWeight(.semibold)
                        Text(
                            selectedPerson.email
                                ?? selectedPerson.mobilePhone
                                ?? "No contact detail"
                        )
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        if let membership = selectedPerson.membershipStatus.nilIfBlank {
                            Text("Membership: \(membership)")
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Change") {
                        assignment.personId = nil
                    }
                }
                .padding(10)
                .background(AppTheme.riverBlueSoft, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.riverBlue.opacity(0.25))
                }
            } else if personSearch.nilIfBlank == nil {
                Label(
                    "Start typing to find a volunteer by name, email, or phone.",
                    systemImage: "magnifyingglass"
                )
                .appFont(.callout)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
            } else {
                ForEach(matchingPeople) { person in
                    Button {
                        assignment.personId = person.id
                        personSearch = person.displayName
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(person.displayName)
                                    .foregroundStyle(.primary)
                                Text(person.email ?? person.mobilePhone ?? "No contact detail")
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                                if let membership = person.membershipStatus.nilIfBlank {
                                    Text("Membership: \(membership)")
                                        .appFont(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var newPersonFields: some View {
        Group {
            TextField("First name", text: $newPerson.firstName)
            TextField("Preferred name (optional)", text: $newPerson.preferredName)
            TextField("Last name", text: $newPerson.lastName)
            TextField("Suffix (optional)", text: $newPerson.suffix)
            TextField("Email (optional)", text: $newPerson.email)
                .textContentType(.emailAddress)
                .withoutAutocapitalization()
            TextField("Mobile phone (optional)", text: $newPerson.mobilePhone)
                .textContentType(.telephoneNumber)
            TextField("Home phone (optional)", text: $newPerson.homePhone)
                .textContentType(.telephoneNumber)
            Toggle("Allow this person's name in the public directory", isOn: $newPerson.isPublic)
        }
    }

    private var saveRequirementMessage: String? {
        if mode == .existing, assignment.personId == nil {
            return "Choose a volunteer before saving."
        }
        if mode == .new, newPerson.firstName.nilIfBlank == nil {
            return "Enter the volunteer's first name before saving."
        }
        if mode == .new, newPerson.lastName.nilIfBlank == nil {
            return "Enter the volunteer's last name before saving."
        }
        if assignment.roleId == nil {
            return "Choose a ministry before saving."
        }
        if assignment.subRoleId == nil {
            return "Choose a position before saving."
        }
        if placementRequirements.requiresTerm, assignment.termId == nil {
            return "Choose a term because this placement requires a church vote."
        }
        return nil
    }

    private func attemptSave() {
        guard saveRequirementMessage == nil else {
            showSaveRequirements = true
            return
        }

        showSaveRequirements = false
        Task { await save() }
    }

    private func save() async {
        assignment.voteDate = includeVoteDate ? selectedVoteDate : nil
        let succeeded = await model.saveAssignment(
            assignment,
            newPerson: mode == .new ? newPerson : nil,
            ordination: mode == .existing ? existingOrdination : nil
        )
        if succeeded {
            assignment = AssignmentDraft()
            newPerson = PersonDraft()
            existingOrdination = PersonOrdinationDraft()
            personSearch = ""
            showSaveRequirements = false
            includeVoteDate = false
            selectedVoteDate = Date()
            mode = .existing
        }
    }

    private func applyRouteIfNeeded(_ requestedRoute: AssignmentRoute?) {
        guard let requestedRoute else { return }

        mode = .existing
        assignment.personId = requestedRoute.personId
        assignment.roleId = requestedRoute.roleId
        assignment.subRoleId = requestedRoute.subRoleId

        if let personId = requestedRoute.personId,
           let person = model.people.first(where: { $0.id == personId }) {
            personSearch = person.displayName
            existingOrdination = PersonOrdinationDraft(person: person)
        } else {
            personSearch = ""
            existingOrdination = PersonOrdinationDraft()
        }

        includeVoteDate = placementRequiresVote
        route = nil
    }

    private func syncExistingOrdination() {
        existingOrdination = selectedPerson.map(PersonOrdinationDraft.init)
            ?? PersonOrdinationDraft()
    }

    private func ordinationBinding(for kind: OrdinationKind) -> Binding<Bool> {
        Binding(
            get: {
                switch (mode, kind) {
                case (.new, .deacon): newPerson.isOrdainedDeacon
                case (.new, .deaconess): newPerson.isOrdainedDeaconess
                case (.new, .elder): newPerson.isOrdainedElder
                case (.existing, .deacon): existingOrdination.isOrdainedDeacon
                case (.existing, .deaconess): existingOrdination.isOrdainedDeaconess
                case (.existing, .elder): existingOrdination.isOrdainedElder
                }
            },
            set: { isOrdained in
                switch (mode, kind) {
                case (.new, .deacon): newPerson.isOrdainedDeacon = isOrdained
                case (.new, .deaconess): newPerson.isOrdainedDeaconess = isOrdained
                case (.new, .elder): newPerson.isOrdainedElder = isOrdained
                case (.existing, .deacon): existingOrdination.isOrdainedDeacon = isOrdained
                case (.existing, .deaconess):
                    existingOrdination.isOrdainedDeaconess = isOrdained
                case (.existing, .elder): existingOrdination.isOrdainedElder = isOrdained
                }
            }
        )
    }
}
