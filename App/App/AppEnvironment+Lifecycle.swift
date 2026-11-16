import Foundation
import JobEngine
import JutsuCore
import Presentation
import UIKit
import WidgetKit
import os

nonisolated private let logger = Logger.jutsu("Lifecycle")

/// The app leaving and coming back: the engine runs only while the app or a background task can use it, and the
/// widget shows what it last saw.
extension AppEnvironment {
    /// Updates the Home Screen widget: what runs, what is ready today and today's spend.
    func writeWidgetSnapshot() {
        // `LiveJobs` keeps every job finished today.
        let today = SpendingSummary(liveJobs.all, images: spending.images.charges, period: .today, now: .now)
        let ready = liveJobs.recentFinished(limit: .max).filter {
            $0.state == .done && Calendar.current.isDateInToday($0.finishedAt ?? .distantPast)
        }.count
        WidgetSnapshot(
            running: liveJobs.activeCount, ready: ready, spentToday: today.charged.text(in: connection.state.costUnit),
            updatedAt: .now
        )
        .write()
        WidgetCenter.shared.reloadTimelines(ofKind: "JutsuStatus")
    }

    /// Jobs still on this iPhone: preparing, uploading or waiting to be sent.
    var unsentJobCount: Int {
        liveJobs.active.filter { [.preparing, .uploading, .waitingForSlot].contains($0.state) }.count
    }

    /// Jobs Higgsfield has, which a background check can follow.
    var hasSubmittedJobs: Bool {
        liveJobs.active.contains { $0.state == .queued || $0.state == .processing || $0.state == .downloading }
    }

    /// Leaving the app: unsent jobs keep going in the continued processing task when there is one; otherwise the
    /// engine stops, letting submits already sent finish. Downloads go on in the background session either way.
    func didEnterBackground() async {
        background?.scheduleCheck()
        guard background?.isSending != true else { return }
        await engine.stop(finishingSubmitsWithin: .seconds(5))
    }

    /// A background refresh: the engine polls what Higgsfield has for `duration`, then stops again unless the app
    /// came to the front or a send still needs it.
    func checkInBackground(for duration: Duration) async {
        do {
            try await engine.start()
            try await Task.sleep(for: duration)
        } catch {
            logger.info("Background check ended early: \(String(describing: error), privacy: .private)")
        }
        guard UIApplication.shared.applicationState == .background, background?.isSending != true else { return }
        await engine.stop(finishingSubmitsWithin: .seconds(3))
    }

    /// At launch the scene turns active while `start()` still runs; the engine waits for it.
    func willEnterForeground() async {
        await start()
        do {
            try await engine.start()
        } catch {
            logger.error("Can't resume jobs: \(String(describing: error), privacy: .private)")
        }
    }
}
