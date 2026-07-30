import SwiftUI
import UniformTypeIdentifiers

struct ManageView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editingRole: MinistryRole?
    @State private var showingNewRole = false
    @State private var showingNewTerm = false

    var body: some View {
        List {
            Section {
                ForEach(model.roles) { role in
                    Button {
                        editingRole = role
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(role.name)
                                    .foregroundStyle(.primary)
                                HStack(spacing: 8) {
                                    if role.requiresVote {
                                        Label("Vote required", systemImage: "checkmark.seal")
                                    }
                                    if !role.isPublic {
                                        Label("Private", systemImage: "lock")
                                    }
                                    if !role.isActive {
                                        Text("Inactive")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    showingNewRole = true
                } label: {
                    Label("Add ministry role", systemImage: "plus.circle")
                }
            } header: {
                Text("Ministry roles")
            } footer: {
                Text(
                    "Renaming a role updates it everywhere; existing assignments keep " +
                    "their link to the same role record."
                )
            }

            Section {
                ForEach(model.terms) { term in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(term.name)
                            Text(term.dateRangeLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(term.termType.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    showingNewTerm = true
                } label: {
                    Label("Add term", systemImage: "calendar.badge.plus")
                }
            } header: {
                Text("Terms")
            } footer: {
                Text(
                    "Add each new two-year term once, then it becomes available on " +
                    "every volunteer assignment."
                )
            }
        }
        .navigationTitle("Manage Roles & Terms")
        .sheet(item: $editingRole) { role in
            EditRoleSheet(role: role)
                .environmentObject(model)
        }
        .sheet(isPresented: $showingNewRole) {
            NewRoleSheet()
                .environmentObject(model)
        }
        .sheet(isPresented: $showingNewTerm) {
            NewTermSheet()
                .environmentObject(model)
        }
    }
}

private struct EditRoleSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var role: MinistryRole

    init(role: MinistryRole) {
        _role = State(initialValue: role)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Role name", text: $role.name)
                TextField(
                    "Description (optional)",
                    text: Binding(
                        get: { role.description ?? "" },
                        set: { role.description = $0.nilIfBlank }
                    ),
                    axis: .vertical
                )
                Toggle("Church vote required", isOn: $role.requiresVote)
                Toggle("Show in public directory", isOn: $role.isPublic)
                Toggle("Active", isOn: $role.isActive)
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Role")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await model.updateRole(role) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(role.name.nilIfBlank == nil || model.isBusy)
                }
            }
        }
        .frame(minWidth: 440, minHeight: 360)
    }
}

private struct NewRoleSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = RoleDraft()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Role name", text: $draft.name)
                TextField("Description (optional)", text: $draft.description, axis: .vertical)
                Toggle("Church vote required", isOn: $draft.requiresVote)
                Toggle("Show in public directory", isOn: $draft.isPublic)
            }
            .formStyle(.grouped)
            .navigationTitle("New Ministry Role")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            if await model.addRole(draft) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(draft.name.nilIfBlank == nil || model.isBusy)
                }
            }
        }
        .frame(minWidth: 440, minHeight: 360)
    }
}

private struct NewTermSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = TermDraft()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Term name", text: $draft.name)
                Picker("Term type", selection: $draft.termType) {
                    Text("Calendar year").tag("calendar")
                    Text("July–June / fiscal").tag("fiscal")
                    Text("Seasonal").tag("seasonal")
                    Text("Custom").tag("custom")
                    Text("Ongoing").tag("ongoing")
                }
                if draft.termType != "ongoing" {
                    DatePicker(
                        "Start date",
                        selection: $draft.startDate,
                        displayedComponents: .date
                    )
                    DatePicker(
                        "End date",
                        selection: $draft.endDate,
                        in: draft.startDate...,
                        displayedComponents: .date
                    )
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Term")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            if await model.addTerm(draft) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(draft.name.nilIfBlank == nil || model.isBusy)
                }
            }
        }
        .frame(minWidth: 440, minHeight: 400)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var importKind: CSVImportKind = .members
    @State private var showingImporter = false
    @State private var showingConnection = false

    var body: some View {
        Form {
            Section {
                Button {
                    Task { await model.syncPlanningCenter() }
                } label: {
                    Label("Sync Planning Center People", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(model.isBusy)
            } header: {
                Text("Planning Center")
            } footer: {
                Text(
                    "Planning Center credentials live only in the Supabase Edge Function. " +
                    "They are never stored in this app. Webhooks can keep new and updated " +
                    "people synchronized; this button provides a full reconciliation."
                )
            }

            Section {
                Picker("CSV type", selection: $importKind) {
                    ForEach(CSVImportKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                Button {
                    showingImporter = true
                } label: {
                    Label("Choose \(importKind.rawValue) CSV", systemImage: "square.and.arrow.down")
                }
                .disabled(model.isBusy)
            } header: {
                Text("CSV import")
            } footer: {
                Text(
                    "Import Members first, then Assignments. Exact source IDs are reused. " +
                    "A person is merged only when name plus email or phone safely identifies " +
                    "one record; ambiguous matches are logged for review. Blank contact fields " +
                    "may be enriched, but existing values are not silently overwritten."
                )
            }

            Section("Connection") {
                LabeledContent("Project") {
                    Text(URL(string: model.configuration.projectURL)?.host ?? "Not configured")
                        .foregroundStyle(.secondary)
                }
                Button("Change Supabase connection") {
                    showingConnection = true
                }
                Button("Reload all data") {
                    Task { await model.reload() }
                }
                .disabled(model.isBusy)
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    model.signOut()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings & Import")
        .sheet(isPresented: $showingConnection) {
            ConfigurationView(isInitialSetup: false)
                .environmentObject(model)
                .frame(minWidth: 460, minHeight: 440)
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let gainedAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if gainedAccess { url.stopAccessingSecurityScopedResource() }
                }
                do {
                    let data = try Data(contentsOf: url)
                    let fileName = url.lastPathComponent
                    Task {
                        await model.importCSV(
                            data: data,
                            fileName: fileName,
                            kind: importKind
                        )
                    }
                } catch {
                    model.errorMessage = error.localizedDescription
                }
            case .failure(let error):
                model.errorMessage = error.localizedDescription
            }
        }
    }
}
