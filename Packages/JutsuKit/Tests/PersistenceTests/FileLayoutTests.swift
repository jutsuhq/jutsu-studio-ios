import Foundation
import JutsuCore
import Persistence
import Testing

@Suite struct FileLayoutTests {
    let temp: URL
    let layout: FileLayout

    init() {
        temp = FileManager.default.temporaryDirectory.appending(path: "PersistenceTests-\(UUID().uuidString)")
        layout = FileLayout(root: temp.appending(path: "support"), defaultOutputFolder: temp.appending(path: "Movies"))
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    @Test func clearCacheRemovesOnlySourcesCacheAndDownloadedInputs() throws {
        defer { try? FileManager.default.removeItem(at: temp) }
        try layout.prepareDirectories()
        try Data("store".utf8).write(to: layout.storeURL)
        for folder in layout.downloadedInputFolders {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("input".utf8).write(to: folder.appending(path: "input.mp4"))
        }
        try Data("clip".utf8).write(to: layout.sourcesFolder.appending(path: "clip.mp4"))
        try Data("{}".utf8).write(to: layout.presetCacheFolder.appending(path: "catalog.json"))
        let output = try layout.outputFolder()
        try Data("result".utf8).write(to: output.appending(path: "result.mp4"))
        let image = temp.appending(path: "face.png")
        try Data("png".utf8).write(to: image)
        let copies = try layout.copyTemplateImages([image], templateID: UUID())

        try layout.clearCache()
        try layout.clearCache()

        #expect(!exists(layout.sourcesFolder))
        #expect(!exists(layout.cacheFolder))
        #expect(!exists(layout.motionLibraryFolder))
        #expect(!exists(layout.accountMediaFolder))
        #expect(exists(layout.storeURL))
        #expect(exists(output.appending(path: "result.mp4")))
        #expect(copies.allSatisfy { exists($0) })
    }

    @Test func clearCacheKeepsTheFilesItIsToldToKeep() throws {
        defer { try? FileManager.default.removeItem(at: temp) }
        try layout.prepareDirectories()
        let pasted = layout.pastedImagesFolder.appending(path: "paste.png")
        let link = layout.linkedMediaFolder.appending(path: "a/clip.mp4")
        let otherLink = layout.linkedMediaFolder.appending(path: "b/clip.mp4")
        let generated = layout.generatedImagesFolder.appending(path: "c/image.png")
        let otherPaste = layout.pastedImagesFolder.appending(path: "old.png")
        for file in [pasted, link, otherLink, generated, otherPaste] {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("media".utf8).write(to: file)
        }
        let elsewhere = temp.appending(path: "Desktop/face.png")

        let remote = try #require(URL(string: "https://example.com/a.png"))
        try layout.clearCache(keeping: [pasted, link, elsewhere, remote])

        #expect(exists(pasted))
        #expect(exists(link))
        #expect(!exists(otherPaste))
        #expect(!exists(otherLink.deletingLastPathComponent()))
        #expect(!exists(layout.generatedImagesFolder))
        #expect(!exists(layout.sourcesFolder))
        #expect(!exists(layout.motionLibraryFolder))
    }

    @Test func clearingAFolderKeepsTheFilesStillUsed() throws {
        defer { try? FileManager.default.removeItem(at: temp) }
        let inbox = temp.appending(path: "inbox", directoryHint: .isDirectory)
        let used = inbox.appending(path: "a/used.png")
        let unused = inbox.appending(path: "b/unused.png")
        for file in [used, unused] {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("png".utf8).write(to: file)
        }

        try FileLayout.clear(inbox, keeping: [used])

        #expect(exists(used))
        #expect(!exists(unused.deletingLastPathComponent()))
        try FileLayout.clear(inbox, keeping: [])
        #expect(!exists(inbox))
        try FileLayout.clear(inbox, keeping: [])
    }
}
