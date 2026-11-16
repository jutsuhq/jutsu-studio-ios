import Foundation
import JutsuCore
import JutsuTestSupport
import Testing

@testable import Presentation

/// Files are "there" unless listed as missing; setting aside one listed as stuck fails. A file set aside goes to
/// `/aside` under its own path.
private final class FakeFiles: LibraryFiles {
    var missing: Set<URL> = []
    var stuck: Set<URL> = []
    private(set) var removed: [URL] = []
    private(set) var putBack: [URL] = []

    func fileExists(at url: URL) -> Bool { !missing.contains(url) }

    func setAside(_ url: URL) throws -> URL {
        if stuck.contains(url) { throw CocoaError(.fileWriteNoPermission) }
        return Self.aside(url)
    }

    func putBack(_ setAside: URL, at url: URL) throws { putBack.append(url) }

    func remove(_ url: URL) throws { removed.append(url) }

    static func aside(_ url: URL) -> URL { URL(fileURLWithPath: "/aside" + url.path(percentEncoded: false)) }
}

@MainActor
private final class FakeRecords: LibraryRecords {
    var failsSave = false
    private(set) var deleted: [UUID] = []
    private(set) var saves = 0
    private(set) var rollbacks = 0

    func delete(_ id: UUID) { deleted.append(id) }

    func save() throws {
        saves += 1
        if failsSave { throw CocoaError(.fileWriteOutOfSpace) }
    }

    func rollback() {
        rollbacks += 1
        deleted.removeAll()
    }
}

@MainActor
@Suite struct LibraryDeletionTests {
    static func item(_ name: String?) -> LibraryItemModel {
        var item = LibraryFixture.item()
        item.job.outputFile = name.map { URL(fileURLWithPath: "/home/me/Movies/Jutsu Studio/\($0).mp4") }
        return item
    }

    @Test func aFileThatCantBeRemovedKeepsItsRecordAndIsReported() throws {
        let items = [Self.item("kept"), Self.item("gone"), Self.item("missing")]
        let files = FakeFiles()
        files.stuck = [try #require(items[0].outputFile)]
        files.missing = [try #require(items[2].outputFile)]
        let records = FakeRecords()

        let result = LibraryDeletion.delete(items, files: files, records: records)
        let message = try #require(result.message)

        #expect(result.deleted == [items[1].id, items[2].id])
        #expect(records.deleted == [items[1].id, items[2].id])
        #expect(files.removed == [items[1].outputFile].compactMap(\.self).map(FakeFiles.aside))
        #expect(message.title == "Can't delete the file")
        #expect(message.message == CocoaError(.fileWriteNoPermission).localizedDescription)
    }

    @Test func aSaveThatFailsPutsTheRecordsBackAndDeletesNothing() throws {
        let items = [Self.item("kept")]
        let files = FakeFiles()
        let records = FakeRecords()
        records.failsSave = true

        let result = LibraryDeletion.delete(items, files: files, records: records)
        let message = try #require(result.message)

        #expect(result.deleted.isEmpty)
        #expect(records.rollbacks == 1)
        #expect(files.removed.isEmpty)
        #expect(files.putBack == [items[0].outputFile])
        #expect(message.title == "Can't remove the result from the Library")
    }
}
