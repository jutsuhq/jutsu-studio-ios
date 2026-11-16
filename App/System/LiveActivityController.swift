import ActivityKit
import Foundation
import JutsuCore
import Presentation
import os

nonisolated private let logger = Logger.jutsu("LiveActivity")

/// One Live Activity while Higgsfield is working on something: started on the first job sent or image requested,
/// updated on every engine event and image run the app sees, and ended with an "all done" content once nothing is
/// left, which stays on the Lock Screen for a few minutes. Updated only from the app (there is no push server), so
/// the stale date tells the system when to dim it.
final class LiveActivityController {
    /// The activity's ID: `Activity` isn't Sendable, so each update looks it up off the main actor.
    private var activityID: String?
    private var finished = 0
    /// The image requests running at the last update, so the ones that finished since are counted.
    private var runningImages: Set<UUID> = []
    /// Set when the person dismissed the activity: no new one until the run ends.
    private var isDismissed = false
    /// The last update or end sent; each waits for the one before, so older content never lands last.
    private var pending: Task<Void, Never>?

    /// Adopts the activity a previous launch left running and ends any others; the next update decides whether the
    /// adopted one still has something to show.
    init() {
        let existing = Activity<RenderActivity>.activities
        activityID = existing.first { Self.isShowing($0) }?.id
        for activity in existing where activity.id != activityID {
            let id = activity.id
            Task.detached { await Self.activity(id)?.end(nil, dismissalPolicy: .immediate) }
        }
    }

    func update(with jobs: LiveJobs, images runs: [ImageRun]) {
        // Paused jobs wait for the person; the Queue's badge says so, the island doesn't count them.
        let running = jobs.active.filter { if case .paused = $0.state { false } else { true } }
        let imageRuns = runs.filter { $0.state == .running }
        for run in runs where runningImages.contains(run.id) && run.state == .finished { finished += 1 }
        runningImages = Set(imageRuns.map(\.id))
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        #if DEBUG
            if UserDefaults.standard.bool(forKey: "debug.sampleActivity") { return }
        #endif
        if running.isEmpty && imageRuns.isEmpty {
            end()
            return
        }
        if let id = activityID, Self.activity(id).map(Self.isShowing) != true {
            activityID = nil
            isDismissed = true
        }
        guard !isDismissed else { return }
        let headline =
            running.first.map { "\($0.spec.model.title) · \($0.spec.mode.title)" } ?? imageRuns.first?.model ?? ""
        let state = RenderActivity.ContentState(
            running: running.count, images: imageRuns.count, finished: finished, startedAt: startedAt(running),
            checkedAt: .now, headline: headline)
        let content = ActivityContent(state: state, staleDate: Date(timeIntervalSinceNow: 15 * 60))
        if let activityID {
            let previous = pending
            pending = Task.detached {
                await previous?.value
                await Self.activity(activityID)?.update(content)
            }
        } else {
            do {
                activityID = try Activity.request(attributes: RenderActivity(), content: content).id
            } catch {
                logger.info("No Live Activity: \(String(describing: error), privacy: .private)")
            }
        }
    }

    func noteFinished(_ job: Job) {
        if job.state == .done { finished += 1 }
    }

    /// When the run began: the activity's own start while it lasts, else the oldest job sent.
    private func startedAt(_ running: [Job]) -> Date {
        if let activityID, let shown = Self.activity(activityID)?.content.state.startedAt { return shown }
        return running.compactMap(\.submittedAt).min() ?? .now
    }

    /// Ends the run: with "all done" and what was made when something finished, left a few minutes on the Lock
    /// Screen; at once when nothing did.
    private func end() {
        let made = finished
        isDismissed = false
        finished = 0
        guard let activityID else { return }
        self.activityID = nil
        let previous = pending
        pending = Task.detached {
            await previous?.value
            guard let activity = Self.activity(activityID) else { return }
            guard made > 0 else {
                await activity.end(nil, dismissalPolicy: .immediate)
                return
            }
            var state = activity.content.state
            state.running = 0
            state.images = 0
            state.finished = made
            state.isDone = true
            state.checkedAt = .now
            await activity.end(
                ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(.now.addingTimeInterval(5 * 60)))
        }
    }

    #if DEBUG
        /// A sample run for a screenshot of the Dynamic Island: `-debug.sampleActivity YES`. Debug builds only.
        func startSample() {
            guard UserDefaults.standard.bool(forKey: "debug.sampleActivity"), activityID == nil else { return }
            let state = RenderActivity.ContentState(
                running: 2, images: 1, finished: 1, startedAt: .now.addingTimeInterval(-94), checkedAt: .now,
                headline: "Kling 3.0 · Motion transfer")
            activityID = try? Activity.request(
                attributes: RenderActivity(), content: ActivityContent(state: state, staleDate: nil)
            ).id
        }
    #endif

    nonisolated private static func activity(_ id: String) -> Activity<RenderActivity>? {
        Activity<RenderActivity>.activities.first { $0.id == id }
    }

    nonisolated private static func isShowing(_ activity: Activity<RenderActivity>) -> Bool {
        activity.activityState == .active || activity.activityState == .stale
    }
}
