import Foundation
import JutsuCore

/// The files of library results. iOS has no Trash the person can open, so the app removes a deleted result's file.
public protocol LibraryFiles {
    /// Whether there is a file at `url` to remove.
    func fileExists(at url: URL) -> Bool
    /// Moves the file at `url` out of the way and returns where it went, so it can be put back or removed.
    func setAside(_ url: URL) throws -> URL
    /// Moves a file set aside back to `url`.
    func putBack(_ setAside: URL, at url: URL) throws
    func remove(_ url: URL) throws
}

/// The stored records of library results. The app removes `MaterialRecord`s from its main context.
@MainActor
public protocol LibraryRecords {
    /// Marks the record of the result with `id` for removal; nothing for a result without one. `save()` removes it.
    func delete(_ id: UUID)
    func save() throws
    /// Puts back the records `delete` marked, after `save()` failed.
    func rollback()
}

/// Delete from Library: each file is set aside first, then its record is removed, and only once that is saved are the
/// files removed. A record whose file couldn't be set aside is kept, and a save that fails puts every file back, so
/// nothing is lost silently.
public enum LibraryDeletion {
    /// Deletes `items` and returns the results whose files and records are gone, and what to tell the user when
    /// something was left (`nil` when everything was deleted). A save that fails puts the records back, so nothing
    /// is hidden that the store still has.
    /// An item without a record only loses its file.
    @MainActor
    public static func delete(
        _ items: [LibraryItemModel], files: any LibraryFiles, records: any LibraryRecords
    ) -> (deleted: Set<UUID>, message: UserMessage?) {
        var notRemoved: [any Error] = []
        var deleted: Set<UUID> = []
        var setAside: [(original: URL, moved: URL)] = []
        for item in items {
            var moved: [(original: URL, moved: URL)] = []
            do {
                for url in [item.outputFile].compactMap(\.self) where files.fileExists(at: url) {
                    moved.append((url, try files.setAside(url)))
                }
            } catch {
                putBack(moved, files: files)
                notRemoved.append(error)
                continue
            }
            setAside += moved
            records.delete(item.id)
            deleted.insert(item.id)
        }
        do {
            try records.save()
        } catch {
            records.rollback()
            putBack(setAside, files: files)
            let failure = UserMessage(
                title: String(localized: "Can't remove the result from the Library", bundle: .module),
                message: error.localizedDescription)
            return (deleted: [], message: failure)
        }
        // The records are gone, so a file that stays set aside is only space the system reclaims, never a lost take.
        for file in setAside { try? files.remove(file.moved) }
        let message: UserMessage?
        switch notRemoved.count {
        case 0:
            message = nil
        case 1:
            message = UserMessage(
                title: String(localized: "Can't delete the file", bundle: .module),
                message: notRemoved[0].localizedDescription)
        case let count:
            message = UserMessage(
                title: String(localized: "Can't delete \(count) files", bundle: .module),
                message: String(
                    localized: "They stay in the Library. \(notRemoved[0].localizedDescription)", bundle: .module))
        }
        return (deleted: deleted, message: message)
    }

    private static func putBack(_ moved: [(original: URL, moved: URL)], files: any LibraryFiles) {
        for file in moved.reversed() { try? files.putBack(file.moved, at: file.original) }
    }
}
