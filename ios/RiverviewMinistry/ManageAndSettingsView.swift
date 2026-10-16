import SwiftUI
import UniformTypeIdentifiers

struct ManageView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editingRole: MinistryRole?
    @State private var showingNewRole = false
    @State private var showingNewTerm = false

    var body: some View {
        Form {
            Section {
                ForEach(activeRoles) { role in
                    ministryButton(role)
                }
                Button {
                    showingNewRole = true
                } label: {
                    Label("Add ministry", systemImage: "plus.circle")
                }
            } header: {
                Text("Ministries & positions")
            } footer: {
                Text(
                    "Open a ministry to rename it, set its church-vote requirement, " +
                    "and manage the positions available within it."
                )
            }

            if !archivedRoles.isEmpty {
                Section {
                    ForEach(archivedRoles) { role in
                        ministryButton(role)
                    }
                } header: {
                    Label("Archived ministries", systemImage: "archivebox")
                } footer: {
                    Text(
                        "Archived ministries stay available for history and can be restored, " +
                        "but are excluded from assignment entry, current directories, reports, " +
                        "the Votes queue, and the public iframe."
                    )
                }
            }

            Section {
                ForEach(model.terms) { term in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(term.name)
                            Text(term.dateRangeLabel)
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(term.termType.capitalized)
                            .appFont(.caption)
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
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 920)
        .frame(maxWidth: .infinity)
        .background(AppTheme.pageBackground)
        .navigationTitle("Manage Ministries & Terms")
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

    private func positions(for role: MinistryRole) -> [MinistrySubRole] {
        model.subRoles.filter { $0.roleId == role.id && $0.isActive }
    }

    private var activeRoles: [MinistryRole] {
        model.roles.filter(\.isActive)
    }

    private var archivedRoles: [MinistryRole] {
        model.roles.filter { !$0.isActive }
    }

    private func ministryButton(_ role: MinistryRole) -> some View {
        Button {
            editingRole = role
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(role.name)
                        .appFont(.headline, weight: .semibold)
                        .foregroundStyle(.primary)
                    Text(
                        "\(positions(for: role).count) " +
                        (positions(for: role).count == 1 ? "position" : "positions")
                    )
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.riverBlue)
                    HStack(spacing: 8) {
                        if role.requiresVote {
                            Label("Vote required", systemImage: "checkmark.seal")
                        }
                        if !role.isPublic {
                            Label("Private", systemImage: "lock")
                        }
                        if !role.isActive {
                            Label("Archived", systemImage: "archivebox")
                        }
                    }
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct EditRoleSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var role: MinistryRole
    @State private var editingPosition: MinistrySubRole?
    @State private var showingNewPosition = false
    @State private var showingArchiveConfirmation = false

    init(role: MinistryRole) {
        _role = State(initialValue: role)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Ministry") {
                    TextField("Ministry name", text: $role.name)
                    TextField(
                        "Description (optional)",
                        text: Binding(
                            get: { role.description ?? "" },
                            set: { role.description = $0.nilIfBlank }
                        ),
                        axis: .vertical
                    )
                    Toggle("Ministry requires a church vote", isOn: $role.requiresVote)
                    Toggle("Show in public directory", isOn: $role.isPublic)
                    LabeledContent("Status", value: role.isActive ? "Current" : "Archived")
                }

                Section {
                    ForEach(positions) { position in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(position.name)
                                        .foregroundStyle(.primary)
                                    Text("Sort priority \(position.leadershipRank)")
                                        .appFont(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Button {
                                    editingPosition = position
                                } label: {
                                    Label("Edit", systemImage: "square.and.pencil")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(AppTheme.riverBlue)
                                .accessibilityLabel("Edit \(position.name)")
                            }

                            PositionVoteToggle(position: position)
                                .environmentObject(model)
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        showingNewPosition = true
                    } label: {
                        Label("Add position to this ministry", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Available positions")
                } footer: {
                    Text(
                        "Each position belongs only to this ministry. Leave the vote date blank " +
                        "to place a vote-required assignment in Needing Votes."
                    )
                }

                Section {
                    if role.isActive {
                        Button("Archive this ministry", role: .destructive) {
                            showingArchiveConfirmation = true
                        }
                    } else {
                        Button {
                            Task {
                                if await model.setMinistryArchived(role, archived: false) {
                                    dismiss()
                                }
                            }
                        } label: {
                            Label("Restore this ministry", systemImage: "arrow.uturn.backward")
                        }
                    }
                } footer: {
                    Text(
                        role.isActive
                            ? "Archiving preserves all volunteer history while removing this " +
                                "ministry from current directories, reports, assignment entry, " +
                                "the Votes queue, and the public iframe."
                            : "Restoring makes this ministry available for current use again."
                    )
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle("Edit Ministry")
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
        .platformSheetFrame(minWidth: 540, minHeight: 560)
        .sheet(item: $editingPosition) { position in
            EditSubRoleSheet(position: position)
                .environmentObject(model)
        }
        .sheet(isPresented: $showingNewPosition) {
            NewSubRoleSheet(role: role)
                .environmentObject(model)
        }
        .confirmationDialog(
            "Archive \(role.name)?",
            isPresented: $showingArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Archive Ministry", role: .destructive) {
                Task {
                    if await model.setMinistryArchived(role, archived: true) {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Volunteer history is preserved and the ministry can be restored later.")
        }
    }

    private var positions: [MinistrySubRole] {
        model.subRoles
            .filter { $0.roleId == role.id }
            .sorted {
                if $0.leadershipRank != $1.leadershipRank {
                    return $0.leadershipRank < $1.leadershipRank
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }
}

private struct PositionVoteToggle: View {
    @EnvironmentObject private var model: AppModel
    let position: MinistrySubRole
    @State private var requiresVote: Bool

    init(position: MinistrySubRole) {
        self.position = position
        _requiresVote = State(initialValue: position.requiresVote)
    }

    var body: some View {
        Toggle("Requires a church vote", isOn: $requiresVote)
            .disabled(model.isBusy || !position.isActive)
            .onChange(of: requiresVote) { _, newValue in
                guard newValue != position.requiresVote else { return }
                var updated = position
                updated.requiresVote = newValue
                Task {
                    if !(await model.updateSubRole(updated)) {
                        requiresVote = position.requiresVote
                    }
                }
            }
    }
}

private struct EditSubRoleSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var position: MinistrySubRole

    init(position: MinistrySubRole) {
        _position = State(initialValue: position)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Position") {
                    TextField("Position name", text: $position.name)
                    Toggle("Requires a church vote", isOn: $position.requiresVote)
                    Toggle("Active", isOn: $position.isActive)
                }
                Section {
                    Stepper(
                        "Sort priority: \(position.leadershipRank)",
                        value: $position.leadershipRank,
                        in: 0...1000,
                        step: 10
                    )
                } footer: {
                    Text(
                        "Lower numbers appear first. Suggested values: Head/Lead 10, " +
                        "Co-Head/Co-Lead 20, Assistant 30, all other positions 100."
                    )
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle("Edit Position")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await model.updateSubRole(position) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(position.name.nilIfBlank == nil || model.isBusy)
                }
            }
        }
        .platformSheetFrame(minWidth: 460, minHeight: 390)
    }
}

struct NewSubRoleSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let role: MinistryRole
    let onCreated: (MinistrySubRole) -> Void
    @State private var draft: SubRoleDraft

    init(
        role: MinistryRole,
        onCreated: @escaping (MinistrySubRole) -> Void = { _ in }
    ) {
        self.role = role
        self.onCreated = onCreated
        _draft = State(initialValue: SubRoleDraft(roleId: role.id))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("\(role.name) position") {
                    TextField("Position name", text: $draft.name)
                    Toggle("Requires a church vote", isOn: $draft.requiresVote)
                }
                Section {
                    Stepper(
                        "Sort priority: \(draft.leadershipRank)",
                        value: $draft.leadershipRank,
                        in: 0...1000,
                        step: 10
                    )
                } footer: {
                    Text("Lower numbers appear first; use 100 for a general position.")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle("New Position")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            if let position = await model.addSubRole(draft) {
                                onCreated(position)
                                dismiss()
                            }
                        }
                    }
                    .disabled(draft.name.nilIfBlank == nil || model.isBusy)
                }
            }
        }
        .platformSheetFrame(minWidth: 460, minHeight: 380)
    }
}

private struct NewRoleSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = RoleDraft()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Ministry name", text: $draft.name)
                TextField("Description (optional)", text: $draft.description, axis: .vertical)
                Toggle("Ministry requires a church vote", isOn: $draft.requiresVote)
                Toggle("Show in public directory", isOn: $draft.isPublic)
            }
            .formStyle(.grouped)
            .navigationTitle("New Ministry")
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
        .platformSheetFrame(minWidth: 440, minHeight: 360)
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
        .platformSheetFrame(minWidth: 440, minHeight: 400)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(AppTextSize.storageKey) private var textSizeRaw = AppTextSize.large.rawValue
    @State private var importKind: CSVImportKind = .members
    @State private var showingImporter = false
    @State private var showingConnection = false
    @State private var showingDeleteAccount = false
    @State private var inviteEmail = ""
    @State private var temporaryPassword = ""
    @State private var appUsers: [ManagedAppUser] = []
    @State private var inviteRole: AppUserRole = .editor
    @State private var pcoApplicationId = ""
    @State private var pcoSecret = ""

    var body: some View {
        Form {
            Section {
                Picker("Text size", selection: $textSizeRaw) {
                    ForEach(AppTextSize.allCases) { size in
                        Text(size.shortLabel)
                            .tag(size.rawValue)
                            .accessibilityLabel(size.description)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("Current size") {
                    Text(selectedTextSize.description)
                        .foregroundStyle(AppTheme.riverBlueDark)
                }
            } header: {
                Text("Appearance")
            } footer: {
                Text(
                    "S, M, L, and XL resize text throughout the app. L is the default " +
                    "for comfortable reading on Mac and iPad."
                )
            }

            Section {
                LabeledContent("Church") {
                    Text(model.currentChurch?.name ?? "Loading…")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Connection") {
                    Text(model.planningCenterStatus?.connected == true ? "Connected" : "Not connected")
                        .foregroundStyle(model.planningCenterStatus?.connected == true ? .green : .secondary)
                }

                if model.isAdministrator {
                    SecureField("Personal Access Token application ID", text: $pcoApplicationId)
                        .textContentType(.none)
                    SecureField("Personal Access Token secret", text: $pcoSecret)
                        .textContentType(.password)

                    Button {
                        Task {
                            if await model.configurePlanningCenter(
                                applicationId: pcoApplicationId,
                                secret: pcoSecret
                            ) {
                                pcoApplicationId = ""
                                pcoSecret = ""
                            }
                        }
                    } label: {
                        Label("Save Planning Center Connection", systemImage: "key")
                    }
                    .disabled(
                        pcoApplicationId.nilIfBlank == nil
                            || pcoSecret.nilIfBlank == nil
                            || model.isBusy
                    )
                }

                Link(
                    "Where to create a Planning Center Personal Access Token",
                    destination: URL(
                        string: "https://api.planningcenteronline.com/docs/overview/authentication"
                    )!
                )

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
                    "Each church uses its own encrypted Planning Center credentials. " +
                    "Synchronization is one-way: Planning Center replaces names, contact " +
                    "details, membership status, and active status here. This app never " +
                    "writes changes back to Planning Center. Webhooks can keep people " +
                    "synchronized; this button provides a full reconciliation."
                )
            }

            if model.isAdministrator {
                Section {
                    TextField("Email address", text: $inviteEmail)
                        .textContentType(.emailAddress)
                        .withoutAutocapitalization()
                        .autocorrectionDisabled()

                    Picker("Access level", selection: $inviteRole) {
                        ForEach(AppUserRole.invitationChoices) { role in
                            Text(role.label).tag(role)
                        }
                    }

                    SecureField("Temporary password (optional)", text: $temporaryPassword)
                    Text("Temporary passwords must have at least 14 characters. The user must change it at first login.")
                    Text(inviteRole.invitationDescription)
                        .foregroundStyle(.secondary)

                    Button {
                        Task {
                            if await model.inviteAppUser(
                                email: inviteEmail,
                                role: inviteRole, temporaryPassword: temporaryPassword.nilIfBlank
                            ) {
                                inviteEmail = ""
                                temporaryPassword = ""
                                appUsers = await model.loadAppUsers()
                            }
                        }
                    } label: {
                        Label(
                            temporaryPassword.isEmpty ? "Create or Resend Setup Email" : "Create with Temporary Password",
                            systemImage: "person.badge.plus"
                        )
                    }
                    .disabled(inviteEmail.nilIfBlank == nil || model.isBusy || (!temporaryPassword.isEmpty && temporaryPassword.count < 14))
                } header: {
                    Text("Team Access")
                } footer: {
                    Text(
                        "Administrator only. Leave the temporary password blank for a setup " +
                        "email valid for 24 hours, or provide a temporary password separately. " +
                        "Password accounts must change their password at first login."
                    )
                }
            }

            if model.isAdministrator {
                Section("Manage App Users") {
                    Button("Refresh Users") { Task { appUsers = await model.loadAppUsers() } }
                    ForEach(appUsers) { user in
                        AppAccessRow(user: user) { appUsers = await model.loadAppUsers() }
                    }
                }.task { appUsers = await model.loadAppUsers() }
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
                Button("Delete My Account", role: .destructive) {
                    showingDeleteAccount = true
                }
                .disabled(model.isBusy)
            } footer: {
                Text("Deleting your account permanently removes your login and account profile. Church-owned volunteer records and assignments remain with the church; Planning Center records are not changed.")
            }
        }
        .task {
            await model.loadPlanningCenterStatus()
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 920)
        .frame(maxWidth: .infinity)
        .background(AppTheme.pageBackground)
        .navigationTitle("Settings & Import")
        .confirmationDialog("Permanently delete your account?", isPresented: $showingDeleteAccount, titleVisibility: .visible) {
            Button("Delete My Account Permanently", role: .destructive) {
                Task { await model.deleteOwnAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Your login and account profile will be deleted and you will be signed out. Church-owned records are retained. If you are the only administrator, arrange another administrator first so your church can continue managing its records.")
        }
        .sheet(isPresented: $showingConnection) {
            ConfigurationView(isInitialSetup: false)
                .environmentObject(model)
                .platformSheetFrame(minWidth: 460, minHeight: 440)
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

    private var selectedTextSize: AppTextSize {
        AppTextSize(rawValue: textSizeRaw) ?? .large
    }
}

private struct AppAccessRow: View {
 @EnvironmentObject private var model: AppModel
 let user: ManagedAppUser
 let refresh: () async -> Void
 @State private var role: AppUserRole
 @State private var showingDeleteUser = false
 init(user: ManagedAppUser, refresh: @escaping () async -> Void) { self.user=user; self.refresh=refresh; _role=State(initialValue:user.appRole) }
 private var protectedUser: Bool { user.userId == model.currentProfile?.userId || user.isPlatformAdmin || (model.currentProfile?.isPlatformAdmin != true && user.appRole == .admin) }
 var body: some View {
  VStack(alignment: .leading, spacing: 10) {
   Text(user.email).fontWeight(.semibold)
   Text(user.accessDisabled ? "Access removed" : user.mustChangePassword ? "Password change required" : user.enrolled ? "Active" : "Invitation pending").foregroundStyle(.secondary)
   Picker("Permissions", selection: $role) {
    if model.currentProfile?.isPlatformAdmin == true { Text("Administrator").tag(AppUserRole.admin) }
    Text("Editor").tag(AppUserRole.editor)
    Text("Viewer").tag(AppUserRole.viewer)
   }.disabled(protectedUser || user.accessDisabled || model.isBusy)
   Button("Save Permissions") { Task { if await model.updateAppUser(user.userId, action: "update_role", role: role) { await refresh() } } }.disabled(protectedUser || user.accessDisabled || model.isBusy || role == user.appRole)
   Button(user.accessDisabled ? "Restore Access" : "Remove Access") { Task { if await model.updateAppUser(user.userId, action: user.accessDisabled ? "restore_access" : "remove_access") { await refresh() } } }.disabled(protectedUser || model.isBusy)
   Button("Delete User Permanently", role: .destructive) { showingDeleteUser = true }
    .disabled(protectedUser || model.isBusy)
  }
  .confirmationDialog("Delete \(user.email) permanently?", isPresented: $showingDeleteUser, titleVisibility: .visible) {
   Button("Delete User Permanently", role: .destructive) {
    Task { if await model.updateAppUser(user.userId, action: "delete_user") { await refresh() } }
   }
   Button("Cancel", role: .cancel) {}
  } message: {
   Text("This deletes the user's login and account profile. Church-owned volunteer records and assignments are preserved. This cannot be undone.")
  }
 }
}

struct DeleteOwnAccountButton: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirming = false

    var body: some View {
        Button("Delete My Account", role: .destructive) { confirming = true }
            .disabled(model.isBusy)
            .confirmationDialog("Permanently delete your account?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Delete My Account Permanently", role: .destructive) {
                    Task { await model.deleteOwnAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your login and account profile. Church-owned volunteer records and assignments remain with the church; Planning Center records are not changed.")
            }
    }
}
