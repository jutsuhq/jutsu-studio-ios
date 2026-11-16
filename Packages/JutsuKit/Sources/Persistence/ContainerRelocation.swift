import Foundation
import SwiftData

/// iOS moves the app's container folder on an update or a restore from backup, while the store and the JSON files in
/// `layout.root` keep absolute file URLs and paths into it. On the first launch in a moved container, every stored
/// path into the old one is moved onto the new one. The container's path of the last launch is noted in `noteURL`.
struct ContainerRelocation {
    let layout: FileLayout
    /// Every file the app keeps lies in this folder.
    let home: URL

    var noteURL: URL { layout.root.appending(path: "container-path.txt", directoryHint: .notDirectory) }

    /// Rebases the store and the JSON files when the container moved, then notes where it is now. Running it again
    /// after a failure part way is safe: a rebased path no longer starts with the old container's.
    func run(in container: ModelContainer) throws {
        let current = Self.containerPath(home)
        let noted = try? String(contentsOf: noteURL, encoding: .utf8)
        guard noted != current else { return }
        if let noted, !noted.isEmpty {
            let rebase = PathRebase(from: noted, to: current)
            try rebaseFiles(rebase)
            try rebaseStore(container, rebase)
        }
        try current.write(to: noteURL, atomically: true, encoding: .utf8)
    }

    /// The Create draft, its backup and the logs.
    private func rebaseFiles(_ rebase: PathRebase) throws {
        let files = try FileManager.default.contentsOfDirectory(at: layout.root, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "json" {
            let data = try Data(contentsOf: file)
            let rebased = rebase(data)
            if rebased != data { try rebased.write(to: file, options: .atomic) }
        }
    }

    private func rebaseStore(_ container: ModelContainer, _ rebase: PathRebase) throws {
        let context = ModelContext(container)
        for record in try context.fetch(FetchDescriptor<JobRecord>()) { record.relocate(rebase) }
        for record in try context.fetch(FetchDescriptor<MaterialRecord>()) { record.relocate(rebase) }
        for record in try context.fetch(FetchDescriptor<TemplateRecord>()) { record.relocate(rebase) }
        if context.hasChanges { try context.save() }
    }

    /// Without "/private", which only some APIs put in front of "/var"; matching a substring then covers both.
    static func containerPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        if path.hasPrefix("/private/") { path.removeFirst("/private".count) }
        return path
    }
}

/// Replaces the old container's path with the new one wherever a stored path or file URL starts with it: plain or
/// percent-encoded, and with JSON's escaped slashes or without.
struct PathRebase: Sendable {
    private let replacements: [(old: String, new: String)]

    init(from old: String, to new: String) {
        func encoded(_ path: String) -> String {
            URL(filePath: path, directoryHint: .isDirectory).path(percentEncoded: true)
        }
        let forms = [(old + "/", new + "/"), (encoded(old), encoded(new))]
        var replacements: [(old: String, new: String)] = []
        for (old, new) in forms {
            for pair in [(old, new), (Self.escapingSlashes(old), Self.escapingSlashes(new))]
            where !replacements.contains(where: { $0.old == pair.0 }) {
                replacements.append((old: pair.0, new: pair.1))
            }
        }
        self.replacements = replacements
    }

    private static func escapingSlashes(_ text: String) -> String {
        text.replacingOccurrences(of: "/", with: "\\/")
    }

    func callAsFunction(_ text: String) -> String {
        replacements.reduce(text) { $0.replacingOccurrences(of: $1.old, with: $1.new) }
    }

    func callAsFunction(_ data: Data) -> Data {
        guard let text = String(data: data, encoding: .utf8) else { return data }
        let rebased = self(text)
        return rebased == text ? data : Data(rebased.utf8)
    }
}
