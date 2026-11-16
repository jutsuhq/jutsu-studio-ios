import ActivityKit
import Foundation

/// The Live Activity of what Higgsfield is working on: video jobs and image requests. Shared by the app, which starts
/// and updates it, and the widget extension, which draws it in the Dynamic Island and on the Lock Screen. Without a
/// push server it is updated only while the app runs, so it carries when it was last checked and the timer runs on
/// its own (`Text(timerInterval:)`).
nonisolated struct RenderActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Video jobs being sent, queued or rendered.
        var running: Int
        /// Image requests being made.
        var images = 0
        /// Takes and image requests finished since the activity started.
        var finished: Int
        var startedAt: Date
        var checkedAt: Date
        /// "Kling 3.0 · Motion transfer" for the first video, "Nano Banana Pro" for images alone.
        var headline: String
        /// Everything finished: the last content, left on the Lock Screen for a while.
        var isDone = false

        var working: Int { running + images }
    }

    /// Opens the Queue when the activity is tapped.
    static let queueURL = URL(string: "jutsustudio://queue")!
}
