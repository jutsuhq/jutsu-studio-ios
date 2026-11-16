import Foundation

/// Where the share extension leaves files for the app, in the app group's container.
nonisolated enum SharedInbox {
    static let appGroup = "group.ai.jutsustudio.ios"

    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "inbox", directoryHint: .isDirectory)
    }
}
