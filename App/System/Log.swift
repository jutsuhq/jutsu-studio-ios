import os

extension Logger {
    /// The app's logger for `category`; the packages log under their own subsystem.
    nonisolated static func jutsu(_ category: String) -> Logger {
        Logger(subsystem: "ai.jutsustudio.ios", category: category)
    }
}
