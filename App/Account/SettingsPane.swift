import SwiftUI

/// The pages of Settings, in sidebar order.
enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case account, spending, generation, storage, notifications, diagnostics, about

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .account: "Account"
        case .spending: "Spending and Limits"
        case .generation: "Generation"
        case .storage: "Downloads and Storage"
        case .notifications: "Notifications"
        case .diagnostics: "Diagnostics"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .account: "person.crop.circle"
        case .spending: "creditcard"
        case .generation: "wand.and.stars"
        case .storage: "internaldrive"
        case .notifications: "bell.badge"
        case .diagnostics: "stethoscope"
        case .about: "info.circle"
        }
    }

    /// The labels of the settings on the page, so search finds "cellular" under Downloads and Storage.
    private var terms: [LocalizedStringResource] {
        switch self {
        case .account: ["API key", "Sign Out"]
        case .spending: ["Daily cap", "Charged", "Use Unlimited when the plan has it", "Warn below"]
        case .generation:
            ["Default task", "Model", "Resolution", "Draft resolution", "Aspect ratio", "Sound", "Jobs at once"]
        case .storage:
            [
                "Download over cellular", "File names", "Include JSON Sidecar", "Clear Inputs and Cache",
                "Remove old cache",
            ]
        case .notifications: ["When a take is ready", "When a job fails", "Sound"]
        case .diagnostics: ["Share Diagnostics"]
        case .about: ["Version", "Source Code", "License"]
        }
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return ([title] + terms).contains { String(localized: $0).localizedStandardContains(query) }
    }

    @ViewBuilder var page: some View {
        switch self {
        case .account: AccountPane()
        case .spending: SpendingPane()
        case .generation: GenerationPane()
        case .storage: StoragePane()
        case .notifications: NotificationsPane()
        case .diagnostics: Form { DiagnosticsSection() }.settingsPage(self)
        case .about: AboutPane()
        }
    }
}

extension View {
    func settingsPage(_ pane: SettingsPane) -> some View {
        navigationTitle(Text(pane.title))
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// The last section of a settings page: puts the page's settings back to their defaults, after asking.
struct ResetSection: View {
    let reset: @MainActor () -> Void
    @State private var asks = false

    var body: some View {
        Section {
            Button("Reset to Defaults", role: .destructive) { asks = true }
                .confirmationDialog(
                    "Reset the settings on this page to their defaults?", isPresented: $asks, titleVisibility: .visible
                ) {
                    Button("Reset", role: .destructive, action: reset)
                }
        }
    }
}
