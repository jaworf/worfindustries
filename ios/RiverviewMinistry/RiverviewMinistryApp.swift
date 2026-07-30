import SwiftUI

@main
struct RiverviewMinistryApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 390, minHeight: 560)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if !model.isConfigured {
                ConfigurationView(isInitialSetup: true)
            } else if !model.isSignedIn {
                LoginView()
            } else {
                MainShellView()
                    .task {
                        if model.assignments.isEmpty {
                            await model.reload()
                        }
                    }
            }
        }
        .overlay(alignment: .top) {
            MessageBanner()
        }
    }
}

private struct MessageBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let message = model.errorMessage ?? model.noticeMessage {
            HStack(spacing: 10) {
                Image(systemName: model.errorMessage == nil
                    ? "checkmark.circle.fill"
                    : "exclamationmark.triangle.fill")
                Text(message)
                    .font(.callout)
                Spacer()
                Button {
                    model.errorMessage = nil
                    model.noticeMessage = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .foregroundStyle(model.errorMessage == nil ? Color.green : Color.red)
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 8, y: 3)
            .padding()
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(10)
        }
    }
}

struct ConfigurationView: View {
    @EnvironmentObject private var model: AppModel
    let isInitialSetup: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "https://your-project.supabase.co",
                        text: $model.configuration.projectURL
                    )
                    .textContentType(.URL)
                    .withoutAutocapitalization()
                    .autocorrectionDisabled()

                    SecureField(
                        "Publishable key",
                        text: $model.configuration.publishableKey
                    )
                    .withoutAutocapitalization()
                    .autocorrectionDisabled()
                } header: {
                    Text("Supabase connection")
                } footer: {
                    Text(
                        "The publishable key is intended for apps. Row Level Security " +
                        "still requires each staff member to sign in. Never paste the " +
                        "Supabase service-role key here."
                    )
                }

                Section {
                    Button(isInitialSetup ? "Save connection" : "Replace connection") {
                        model.saveConfiguration()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.configuration.isValid)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isInitialSetup ? "Set Up Riverview Ministry" : "Database Connection")
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var model: AppModel
    @State private var email = ""
    @State private var password = ""
    @State private var showingConnection = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "person.3.sequence.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(Color.accentColor)
                VStack(spacing: 8) {
                    Text("Riverview Ministry")
                        .font(.largeTitle.bold())
                    Text("Volunteer placement and term records")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 14) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .withoutAutocapitalization()
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        Task { await model.signIn(email: email, password: password) }
                    } label: {
                        if model.isBusy {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Sign In")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(email.nilIfBlank == nil || password.isEmpty || model.isBusy)
                }
                .frame(maxWidth: 420)

                Button("Change Supabase connection") {
                    showingConnection = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(28)
            .sheet(isPresented: $showingConnection) {
                ConfigurationView(isInitialSetup: false)
                    .environmentObject(model)
                    .frame(minWidth: 420, minHeight: 440)
            }
        }
    }
}

struct MainShellView: View {
    var body: some View {
        TabView {
            NavigationStack {
                AssignmentEntryView()
            }
            .tabItem { Label("Assign", systemImage: "person.badge.plus") }

            NavigationStack {
                DirectoryView()
            }
            .tabItem { Label("Directory", systemImage: "person.3") }

            NavigationStack {
                ReportsView()
            }
            .tabItem { Label("Reports", systemImage: "doc.richtext") }

            NavigationStack {
                ManageView()
            }
            .tabItem { Label("Manage", systemImage: "slider.horizontal.3") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

extension View {
    @ViewBuilder
    func withoutAutocapitalization() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}
