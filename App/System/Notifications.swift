import Foundation
import JutsuCore
import Presentation
import UserNotifications
import os

nonisolated private let logger = Logger.jutsu("Notifications")

/// Local notifications only: there is no server to push from. Posted when the engine learns a job's outcome.
@Observable
final class Notifications: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let takeReadyCategory = "TAKE_READY"
    nonisolated static let viewAction = "VIEW"
    nonisolated static let jobIDKey = "jobID"

    /// Called with the job a tapped notification is about.
    @ObservationIgnored var onOpen: ((UUID) -> Void)?

    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    /// What iOS allows, as of the last `refreshPermission()`.
    private(set) var permission = NotificationPermission.notAsked

    override init() {
        super.init()
        center.delegate = self
        let view = UNNotificationAction(
            identifier: Self.viewAction, title: String(localized: "View"), options: .foreground)
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.takeReadyCategory, actions: [view], intentIdentifiers: [])
        ])
    }

    /// Asked after the first queued job or when the person turns a notification on, when the reason is obvious
    /// (HIG, Privacy); never at launch.
    func requestAuthorizationIfNeeded() async {
        await refreshPermission()
        guard permission == .notAsked else { return }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            logger.error("Can't ask for notifications: \(String(describing: error), privacy: .private)")
        }
        await refreshPermission()
    }

    /// Reads what iOS allows again; the person may have changed it in Settings.
    func refreshPermission() async {
        permission = NotificationPermission(await center.notificationSettings().authorizationStatus)
    }

    /// One notification per finished job: done, failed or rejected. Canceled jobs were the person's own doing.
    /// VoiceOver says the same while the app is open, whatever the notification settings.
    func post(for job: Job) {
        guard let title = Self.title(for: job.state) else { return }
        let body = "\(job.spec.model.title) · \(job.spec.mode.title)"
        VoiceOver.announce("\(title). \(body)")
        let preferences = AppSettings.notificationPreferences(in: .standard)
        let isDone = if case .done = job.state { true } else { false }
        guard isDone ? preferences.onDone : preferences.onProblems else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        if isDone { content.categoryIdentifier = Self.takeReadyCategory }
        content.body = body
        content.sound = preferences.playsSound ? .default : nil
        content.userInfo = [Self.jobIDKey: job.id.uuidString]
        let request = UNNotificationRequest(identifier: job.id.uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error { logger.error("Can't post: \(String(describing: error), privacy: .private)") }
        }
    }

    private static func title(for state: JobState) -> String? {
        switch state {
        case .done: String(localized: "Take ready")
        case .failed: String(localized: "A job failed")
        case .rejected: String(localized: "Rejected by moderation · not billed")
        default: nil
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard let id = (response.notification.request.content.userInfo[Self.jobIDKey] as? String).flatMap(UUID.init)
        else { return }
        await MainActor.run { self.onOpen?(id) }
    }
}

extension NotificationPermission {
    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notAsked
        case .authorized, .provisional, .ephemeral: self = .allowed
        case .denied: self = .denied
        @unknown default: self = .denied
        }
    }
}
