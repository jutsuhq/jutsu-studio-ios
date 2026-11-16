import Foundation

/// What the Home Screen widget shows, written by the app into the app group after every engine change.
nonisolated struct WidgetSnapshot: Codable, Hashable {
    var running: Int
    var ready: Int
    var spentToday: String
    var updatedAt: Date

    static let empty = WidgetSnapshot(running: 0, ready: 0, spentToday: "—", updatedAt: .distantPast)

    private static var file: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedInbox.appGroup)?
            .appending(path: "widget.json")
    }

    static func read() -> WidgetSnapshot {
        guard let file, let data = try? Data(contentsOf: file) else { return .empty }
        return (try? JSONDecoder().decode(WidgetSnapshot.self, from: data)) ?? .empty
    }

    /// The snapshot as of `date`: what was ready and spent counts only on the day it was written.
    func asOf(_ date: Date) -> WidgetSnapshot {
        guard !Calendar.current.isDate(updatedAt, inSameDayAs: date) else { return self }
        return WidgetSnapshot(running: running, ready: 0, spentToday: Self.empty.spentToday, updatedAt: updatedAt)
    }

    func write() {
        guard let file = Self.file, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
