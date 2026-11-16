import Foundation
import JutsuCore
import Persistence
import SwiftData
import Testing

@Suite struct ContainerRelocationTests {
    let temp = FileManager.default.temporaryDirectory.appending(path: "Relocation-\(UUID().uuidString)")

    /// Laid out as on iOS: the store in Application Support, results in Documents. The space checks percent-encoding.
    private func layout(in home: URL) -> FileLayout {
        FileLayout(
            root: home.appending(path: "Library/Application Support/Jutsu", directoryHint: .isDirectory),
            defaultOutputFolder: home.appending(path: "Documents", directoryHint: .isDirectory))
    }

    @Test func storedPathsFollowAMovedContainer() async throws {
        defer { try? FileManager.default.removeItem(at: temp) }
        let oldHome = temp.appending(path: "old home", directoryHint: .isDirectory)
        let newHome = temp.appending(path: "new home", directoryHint: .isDirectory)
        let before = layout(in: oldHome)
        let after = layout(in: newHome)
        func inbox(_ layout: FileLayout) -> URL { layout.root.appending(path: "inbox/clip one.mov") }

        var done = makeJob(state: .done)
        done.spec.source?.fileURL = inbox(before)
        done.outputFile = before.defaultOutputFolder.appending(path: "result.mp4")
        var downloading = makeJob(state: .downloading)
        downloading.downloadFolder = before.defaultOutputFolder
        do {
            let store = try SwiftDataStore(
                modelContainer: StoreContainer.make(inMemory: false, layout: before, home: oldHome))
            try await store.save(done)
            try await store.save(downloading)
            try JSONEncoder().encode(["source": inbox(before)]).write(to: before.createDraftURL)
        }
        try FileManager.default.moveItem(at: oldHome, to: newHome)

        let store = try SwiftDataStore(
            modelContainer: StoreContainer.make(inMemory: false, layout: after, home: newHome))

        let path = { (url: URL?) in url?.path(percentEncoded: false) }
        let movedDone = try #require(try await store.job(id: done.id))
        #expect(path(movedDone.outputFile) == path(after.defaultOutputFolder.appending(path: "result.mp4")))
        #expect(path(movedDone.spec.source?.fileURL) == path(inbox(after)))
        #expect(path(try await store.job(id: downloading.id)?.downloadFolder) == path(after.defaultOutputFolder))
        #expect(path(try await store.material(id: done.id)?.current.fileURL) == path(movedDone.outputFile))
        let draft = try JSONDecoder().decode([String: URL].self, from: Data(contentsOf: after.createDraftURL))
        #expect(path(draft["source"]) == path(inbox(after)))

        // The source the library knows is matched again by its new path rather than added a second time.
        let count = try await store.materials().count
        var next = makeJob()
        next.spec.source?.fileURL = inbox(after)
        try await store.save(next)
        #expect(try await store.materials().count == count)
    }

    @Test func aContainerThatStaysPutChangesNothing() async throws {
        defer { try? FileManager.default.removeItem(at: temp) }
        let home = temp.appending(path: "home", directoryHint: .isDirectory)
        let files = layout(in: home)
        var job = makeJob(state: .done)
        job.outputFile = files.defaultOutputFolder.appending(path: "result.mp4")
        do {
            let store = try SwiftDataStore(
                modelContainer: StoreContainer.make(inMemory: false, layout: files, home: home))
            try await store.save(job)
        }

        let store = try SwiftDataStore(
            modelContainer: StoreContainer.make(inMemory: false, layout: files, home: home))

        #expect(try await store.job(id: job.id) == job)
    }
}
