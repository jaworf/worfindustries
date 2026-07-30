import SwiftUI

private enum PersonEntryMode: String, CaseIterable, Identifiable {
    case existing = "Find person"
    case new = "New person"

    var id: String { rawValue }
}

struct AssignmentEntryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var mode: PersonEntryMode = .existing
    @State private var personSearch = ""
    @State private var assignment = AssignmentDraft()
    @State private var newPerson = PersonDraft()
    @State private var includeVoteDate = false
    @State private var selectedVoteDate = Date()

    private var selectedPerson: Person? {
        model.people.first(where: { $0.id == assignment.personId })
    }

    private var selectedRole: MinistryRole? {
        model.roles.first(where: { $0.id == assignment.roleId })
    }

    private var matchingPeople: [Person] {
        let query = personSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = query.isEmpty ? model.people : model.people.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || ($0.email?.localizedCaseInsensitiveContains(query) ?? false)
                || ($0.mobilePhone?.localizedCaseInsensitiveContains(query) ?? false)
        }
        return Array(source.prefix(12))
    }

    private var availableSubRoles: [MinistrySubRole] {
        model.subRoles.filter {
            $0.isActive && ($0.roleId == nil || $0.roleId == assignment.roleId)
        }
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
                Picker("Ministry role", selection: $assignment.roleId) {
                    Text("Choose a role").tag(UUID?.none)
                    ForEach(model.roles.filter(\.isActive)) { role in
                        Text(role.name).tag(Optional(role.id))
                    }
                }

                Picker("Position / sub-role", selection: $assignment.subRoleId) {
                    Text("Volunteer").tag(UUID?.none)
                    ForEach(availableSubRoles) { subRole in
                        Text(subRole.name).tag(Optional(subRole.id))
                    }
                }

                Picker("Term", selection: $assignment.termId) {
                    Text("Choose a term").tag(UUID?.none)
                    ForEach(model.terms.filter(\.isActive)) { term in
                        Text("\(term.name) — \(term.dateRangeLabel)")
                            .tag(Optional(term.id))
                    }
                }
            }

            Section("Record details") {
                if selectedRole?.requiresVote == true {
                    LabeledContent("Church vote") {
                        Text("Required")
                            .foregroundStyle(.orange)
                    }
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

                TextField("Notes (optional)", text: $assignment.notes, axis: .vertical)
                    .lineLimit(2...5)
                Toggle("Show this assignment in the public directory", isOn: $assignment.isPublic)
            }

            Section {
                Button {
                    Task { await save() }
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
                .disabled(!canSave || model.isBusy)
            } footer: {
                Text(
                    "Changing a role name later updates every assignment because " +
                    "assignments reference the role record, not a copied name."
                )
            }
        }
        .formStyle(.grouped)
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
            includeVoteDate = selectedRole?.requiresVote == true
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Change") {
                        assignment.personId = nil
                    }
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
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
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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

    private var canSave: Bool {
        let hasPerson = mode == .existing
            ? assignment.personId != nil
            : (newPerson.firstName.nilIfBlank != nil && newPerson.lastName.nilIfBlank != nil)
        return hasPerson && assignment.roleId != nil && assignment.termId != nil
    }

    private func save() async {
        assignment.voteDate = includeVoteDate ? selectedVoteDate : nil
        let succeeded = await model.saveAssignment(
            assignment,
            newPerson: mode == .new ? newPerson : nil
        )
        if succeeded {
            assignment = AssignmentDraft()
            newPerson = PersonDraft()
            personSearch = ""
            includeVoteDate = false
            selectedVoteDate = Date()
            mode = .existing
        }
    }
}
