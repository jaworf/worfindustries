import SwiftUI

enum AppTextSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case extraLarge

    static let storageKey = "app-text-size"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        case .extraLarge: "XL"
        }
    }

    var description: String {
        switch self {
        case .small: "Compact"
        case .medium: "Comfortable"
        case .large: "Large"
        case .extraLarge: "Extra large"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small: 1.0
        case .medium: 1.10
        case .large: 1.20
        case .extraLarge: 1.35
        }
    }

    var bodyPointSize: CGFloat { 15.5 * scale }
}

enum AppTextStyle {
    case largeTitle
    case title
    case title2
    case title3
    case headline
    case body
    case callout
    case subheadline
    case footnote
    case caption
    case caption2

    var basePointSize: CGFloat {
        switch self {
        case .largeTitle: 31
        case .title: 26
        case .title2: 22
        case .title3: 19
        case .headline: 16.5
        case .body: 15.5
        case .callout: 15
        case .subheadline: 14.5
        case .footnote: 13.5
        case .caption: 12.75
        case .caption2: 11.75
        }
    }

}

private struct AppTextSizeKey: EnvironmentKey {
    static let defaultValue = AppTextSize.large
}

extension EnvironmentValues {
    var appTextSize: AppTextSize {
        get { self[AppTextSizeKey.self] }
        set { self[AppTextSizeKey.self] = newValue }
    }
}

private struct AppFontModifier: ViewModifier {
    @Environment(\.appTextSize) private var textSize
    let style: AppTextStyle
    let weight: Font.Weight

    func body(content: Content) -> some View {
        content.font(
            .system(
                size: style.basePointSize * textSize.scale,
                weight: weight
            )
        )
    }
}

extension View {
    func appFont(
        _ style: AppTextStyle = .body,
        weight: Font.Weight = .regular
    ) -> some View {
        modifier(AppFontModifier(style: style, weight: weight))
    }
}

enum AppTheme {
    static let riverBlue = Color(red: 31 / 255, green: 95 / 255, blue: 139 / 255)
    static let riverBlueDark = Color(red: 18 / 255, green: 62 / 255, blue: 95 / 255)
    static let riverBlueSoft = Color(red: 232 / 255, green: 242 / 255, blue: 248 / 255)
    static let canvas = Color(red: 246 / 255, green: 249 / 255, blue: 251 / 255)
    static let pageBackground = LinearGradient(
        colors: [riverBlueSoft.opacity(0.72), canvas, Color.white],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

@main
struct RiverviewMinistryApp: App {
    @StateObject private var model = AppModel()
    @AppStorage(AppTextSize.storageKey) private var textSizeRaw = AppTextSize.large.rawValue

    private var selectedTextSize: AppTextSize {
        AppTextSize(rawValue: textSizeRaw) ?? .large
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environment(\.appTextSize, selectedTextSize)
                .environment(\.colorScheme, .light)
                .font(selectedTextSize.bodyFont)
                .tint(AppTheme.riverBlue)
                .preferredColorScheme(.light)
                .frame(minWidth: 390, minHeight: 560)
        }
    }
}

private extension AppTextSize {
    var bodyFont: Font {
        .system(size: bodyPointSize)
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
                    .appFont(.callout)
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
            .foregroundStyle(model.errorMessage == nil ? AppTheme.riverBlueDark : Color.red)
            .padding(12)
            .background(
                model.errorMessage == nil
                    ? AppTheme.riverBlueSoft
                    : Color.red.opacity(0.1),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        model.errorMessage == nil
                            ? AppTheme.riverBlue.opacity(0.28)
                            : Color.red.opacity(0.28)
                    )
            }
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            .padding()
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(10)
            .task(id: model.noticeMessage) {
                guard
                    model.errorMessage == nil,
                    let displayedNotice = model.noticeMessage
                else {
                    return
                }

                try? await Task.sleep(for: .seconds(4))
                guard
                    !Task.isCancelled,
                    model.errorMessage == nil,
                    model.noticeMessage == displayedNotice
                else {
                    return
                }

                withAnimation {
                    model.noticeMessage = nil
                }
            }
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
            .navigationTitle(
                isInitialSetup ? "Set Up Riverview Ministry Volunteers" : "Database Connection"
            )
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
            ZStack {
                AppTheme.pageBackground
                    .ignoresSafeArea()

                VStack(spacing: 26) {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(AppTheme.riverBlueSoft)
                            .frame(width: 92, height: 92)
                        Image(systemName: "person.3.sequence.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(AppTheme.riverBlue)
                    }
                    VStack(spacing: 8) {
                        Text("Riverview Ministry Volunteers")
                            .appFont(.largeTitle, weight: .bold)
                            .multilineTextAlignment(.center)
                        Text("Volunteer placement and term records")
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 16) {
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
                        .controlSize(.large)
                        .disabled(email.nilIfBlank == nil || password.isEmpty || model.isBusy)
                    }
                    .padding(24)
                    .frame(maxWidth: 470)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(AppTheme.riverBlue.opacity(0.18))
                    }
                    .shadow(color: AppTheme.riverBlueDark.opacity(0.1), radius: 18, y: 8)

                    Button("Change Supabase connection") {
                        showingConnection = true
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(30)
            }
            .sheet(isPresented: $showingConnection) {
                ConfigurationView(isInitialSetup: false)
                    .environmentObject(model)
                    .frame(minWidth: 420, minHeight: 440)
            }
        }
    }
}

enum AppTab: Hashable {
    case assign
    case ministries
    case people
    case focus
    case votes
    case reports
    case manage
    case settings
}

struct AssignmentRoute: Equatable, Identifiable {
    let id = UUID()
    var personId: UUID?
    var roleId: UUID?
    var subRoleId: UUID?
}

struct MainShellView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab: AppTab = .assign
    @State private var assignmentRoute: AssignmentRoute?

    private var ministryWatchCount: Int {
        PlacementFocusSnapshot(
            roles: model.roles,
            subRoles: model.subRoles,
            assignments: model.assignments
        ).ministryNeeds.count
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                AssignmentEntryView(route: $assignmentRoute)
            }
            .tabItem { Label("Assign", systemImage: "person.badge.plus") }
            .tag(AppTab.assign)

            NavigationStack {
                DirectoryView()
            }
            .tabItem { Label("Ministries", systemImage: "person.3") }
            .tag(AppTab.ministries)

            NavigationStack {
                PeopleDirectoryView()
            }
            .tabItem { Label("People", systemImage: "person.text.rectangle") }
            .tag(AppTab.people)

            NavigationStack {
                FocusView { route in
                    assignmentRoute = route
                    selectedTab = .assign
                }
            }
            .tabItem { Label("Focus", systemImage: "scope") }
            .badge(ministryWatchCount)
            .tag(AppTab.focus)

            NavigationStack {
                VoteQueueView()
            }
            .tabItem { Label("Votes", systemImage: "checkmark.seal") }
            .badge(model.assignments.filter { $0.isCurrentPlacement && $0.voteMissing }.count)
            .tag(AppTab.votes)

            NavigationStack {
                ReportsView()
            }
            .tabItem { Label("Reports", systemImage: "doc.richtext") }
            .tag(AppTab.reports)

            NavigationStack {
                ManageView()
            }
            .tabItem { Label("Manage", systemImage: "slider.horizontal.3") }
            .tag(AppTab.manage)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(AppTab.settings)
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
