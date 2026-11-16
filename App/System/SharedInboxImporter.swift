import Foundation
import JutsuCore
import Presentation
import UniformTypeIdentifiers

/// Takes in what "Share → Jutsu" left in the app group: each file is copied into the app's inbox and read, and its
/// group folder is removed either way, so a file the app can't read is reported once, not on every activation.
enum SharedInboxImporter {
    enum Item {
        case video(SourceVideo)
        case image(LocalImage)
    }

    /// The shared files in the order they arrived, and how many couldn't be read.
    static func take() async -> (items: [Item], unreadable: Int) {
        let manager = FileManager.default
        guard let inbox = SharedInbox.folder,
            let folders = try? manager.contentsOfDirectory(at: inbox, includingPropertiesForKeys: [.creationDateKey])
        else { return ([], 0) }
        var items: [Item] = []
        var unreadable = 0
        let arrival = { (folder: URL) -> Date in
            (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
        }
        for folder in folders.sorted(by: { arrival($0) < arrival($1) }) {
            defer { try? manager.removeItem(at: folder) }
            guard let file = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first,
                let copied = try? Inbox.copy(file)
            else {
                unreadable += 1
                continue
            }
            if UTType(filenameExtension: copied.pathExtension)?.conforms(to: .movie) == true {
                guard let video = try? await SourceVideo.probing(copied) else {
                    try? manager.removeItem(at: copied.deletingLastPathComponent())
                    unreadable += 1
                    continue
                }
                items.append(.video(video))
            } else {
                items.append(.image(LocalImage(fileURL: copied)))
            }
        }
        return (items, unreadable)
    }
}
