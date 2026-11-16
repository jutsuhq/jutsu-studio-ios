import BackgroundTasks
import Foundation
import JutsuCore
import Presentation
import UIKit
import os

nonisolated private let logger = Logger.jutsu("Background")

/// What runs while the app isn't in front (docs/ios-architecture.md §5):
/// - sending: jobs not yet submitted keep preparing, uploading and submitting in a `BGContinuedProcessingTask`, started
///   by the person's own Generate, with the system's progress UI;
/// - checking: a `BGAppRefreshTask` polls submitted jobs once whenever iOS grants one;
/// - downloading: `BackgroundDownloader`'s background session, which needs neither.
final class BackgroundWork {
    nonisolated static let refreshID = "ai.jutsustudio.ios.refresh"
    nonisolated static let sendPrefix = "ai.jutsustudio.ios.send"

    weak var environment: AppEnvironment?
    private(set) var isSending = false

    /// Before launch finishes, as BackgroundTasks requires.
    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshID, using: .main) { [weak self] task in
            MainActor.assumeIsolated { self?.check(task as? BGAppRefreshTask) }
        }
        if #available(iOS 26, *) {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: "\(Self.sendPrefix).*", using: .main) {
                [weak self] task in
                MainActor.assumeIsolated { self?.send(task as? BGContinuedProcessingTask) }
            }
        }
    }

    /// Called right after Generate, in the foreground: asks iOS to let the unsent jobs finish sending if the person
    /// leaves the app. Nothing happens when one is already running, or before iOS 26, which has no continued processing:
    /// there unsent jobs wait for the app to come back.
    func startSending(count: Int) {
        guard #available(iOS 26, *), !isSending, count > 0 else { return }
        // Set before the request goes out, so a second Generate meanwhile doesn't ask again.
        isSending = true
        Task {
            do {
                try await Self.submit {
                    let request = BGContinuedProcessingTaskRequest(
                        identifier: "\(Self.sendPrefix).\(UUID().uuidString)",
                        title: String(localized: "Sending to Higgsfield"),
                        subtitle: String(localized: "\(count) take(s)"))
                    request.strategy = .fail
                    return request
                }
            } catch {
                isSending = false
                logger.info("No continued processing: \(String(describing: error), privacy: .private)")
            }
        }
    }

    /// Asks for a check of submitted jobs in a while; iOS decides when.
    func scheduleCheck() {
        guard let environment, environment.hasSubmittedJobs else { return }
        Task {
            do {
                try await Self.submit {
                    let request = BGAppRefreshTaskRequest(identifier: Self.refreshID)
                    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
                    return request
                }
            } catch {
                logger.info("Can't schedule a check: \(String(describing: error), privacy: .private)")
            }
        }
    }

    /// Off the main thread, where BackgroundTasks asks for submissions to be made.
    private nonisolated static func submit(_ request: @escaping @Sendable () -> BGTaskRequest) async throws {
        try await Task.detached {
            // The async submit exists from the iOS 27 SDK (Swift 6.4); older Xcodes, such as CI's, build the sync one.
            #if compiler(>=6.4)
                if #available(iOS 27, *) {
                    try await BGTaskScheduler.shared.submitTaskRequest(request())
                    return
                }
            #endif
            try BGTaskScheduler.shared.submit(request())
        }.value
    }

    @available(iOS 26, *)
    private func send(_ task: BGContinuedProcessingTask?) {
        guard let task, let environment else {
            task?.setTaskCompleted(success: false)
            return
        }
        let work = Task {
            var total = environment.unsentJobCount
            var previous = total
            while !Task.isCancelled {
                let left = environment.unsentJobCount
                total += max(left - previous, 0)
                previous = left
                task.progress.totalUnitCount = Int64(max(total, 1))
                task.progress.completedUnitCount = Int64(total - left)
                if left == 0 { break }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        task.expirationHandler = {
            work.cancel()
        }
        Task {
            await work.value
            task.setTaskCompleted(success: environment.unsentJobCount == 0)
            isSending = false
            if UIApplication.shared.applicationState == .background {
                await environment.didEnterBackground()
            }
        }
    }

    private func check(_ task: BGAppRefreshTask?) {
        guard let task, let environment else {
            task?.setTaskCompleted(success: false)
            return
        }
        let work = Task {
            await environment.start()
            await environment.checkInBackground(for: .seconds(20))
        }
        task.expirationHandler = { work.cancel() }
        Task {
            await work.value
            scheduleCheck()
            task.setTaskCompleted(success: true)
        }
    }
}

/// Background URL session events and BackgroundTasks registration, which both need an app delegate.
final class AppDelegate: NSObject, UIApplicationDelegate {
    let background = BackgroundWork()
    /// Made with the delegate, not a scene: a background launch has no scene, and its tasks need the environment.
    let environment = AppEnvironment.launch()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        background.environment = environment
        environment?.background = background
        background.register()
        BackgroundDownloader.shared.activate()
        // Once per process, background launches included; it only registers, payloads come later.
        Diagnostics.shared.start()
        return true
    }

    func application(
        _ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BackgroundDownloader.sessionID else { return completionHandler() }
        BackgroundDownloader.shared.handleEvents(completion: completionHandler)
    }
}
