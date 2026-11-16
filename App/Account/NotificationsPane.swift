import Presentation
import SwiftUI

/// Which job outcomes post a notification. VoiceOver announces every outcome while the app is open regardless.
struct NotificationsPane: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var phase
    @Environment(AppEnvironment.self) private var environment
    @AppStorage(AppSettings.notifyOnDoneKey) private var notifyOnDone = AppSettings.defaultNotify
    @AppStorage(AppSettings.notifyOnProblemsKey) private var notifyOnProblems = AppSettings.defaultNotify
    @AppStorage(AppSettings.notificationSoundKey) private var notificationSound = AppSettings.defaultNotificationSound

    private var notifications: Notifications { environment.notifications }

    var body: some View {
        Form {
            permissionSection
            Section {
                Toggle("When a take is ready", isOn: $notifyOnDone)
                Toggle("When a job fails", isOn: $notifyOnProblems)
                Toggle("Sound", isOn: $notificationSound)
                    .disabled(!notifyOnDone && !notifyOnProblems)
            } footer: {
                Text("Jobs rejected by moderation count as failed. They are never billed.")
            }
            Section {
                Button("Notification Settings", action: openSettings)
            } footer: {
                Text("Banners, Lock Screen and Focus are set in iOS Settings.")
            }
            ResetSection(reset: reset)
        }
        .settingsPage(.notifications)
        .task { await notifications.refreshPermission() }
        // Back from iOS Settings, where the person may have turned them on.
        .onChange(of: phase) { _, phase in
            if phase == .active { Task { await notifications.refreshPermission() } }
        }
        .onChange(of: notifyOnDone) { _, isOn in askIfTurnedOn(isOn) }
        .onChange(of: notifyOnProblems) { _, isOn in askIfTurnedOn(isOn) }
    }

    @ViewBuilder
    private var permissionSection: some View {
        switch notifications.permission {
        case .notAsked:
            Section {
                Button("Allow Notifications", systemImage: "bell.badge") {
                    Task { await notifications.requestAuthorizationIfNeeded() }
                }
            } footer: {
                Text("iOS asks once. Jutsu tells you when a take is ready or a job fails, even when it's closed.")
            }
        case .denied:
            Section {
                Label("Notifications are off", systemImage: "bell.slash")
                    .foregroundStyle(Theme.warning)
                Button("Turn On in Settings", systemImage: "gear", action: openSettings)
            } footer: {
                Text("Jutsu can't tell you when a take is ready until notifications are on in iOS Settings.")
            }
        case .allowed:
            EmptyView()
        }
    }

    private func askIfTurnedOn(_ isOn: Bool) {
        guard notifications.permission.asks(whenTurning: isOn) else { return }
        Task { await notifications.requestAuthorizationIfNeeded() }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
    }

    private func reset() {
        notifyOnDone = AppSettings.defaultNotify
        notifyOnProblems = AppSettings.defaultNotify
        notificationSound = AppSettings.defaultNotificationSound
    }
}
