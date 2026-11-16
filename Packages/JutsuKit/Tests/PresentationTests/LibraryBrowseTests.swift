import Foundation
import JutsuCore
import Testing

@testable import Presentation

@Suite("Library browsing and search")
struct LibraryBrowseTests {
    private static let video = URL(string: "https://cdn.example/out.mp4")!
    private static let thumb = URL(string: "https://cdn.example/out.webp")!

    private func historyVideo(
        id: String, model: VideoModel = .seedance25, prompt: String = "", secondsAgo: TimeInterval = 0
    ) -> HistoryItem {
        HistoryItem(
            id: id, mode: .motionTransfer, model: model,
            createdAt: LibraryFixture.now.addingTimeInterval(-secondsAgo), outputURL: Self.video,
            duration: 3.71, pixelSize: PixelSize(width: 480, height: 854), resolution: .p480, prompt: prompt,
            inputs: RemoteInputs(video: nil, images: []))
    }

    private func historyImage(
        id: String, model: String, prompt: String = "", secondsAgo: TimeInterval = 0
    )
        -> HistoryImageItem
    {
        HistoryImageItem(
            id: id, prompt: prompt, model: model, createdAt: LibraryFixture.now.addingTimeInterval(-secondsAgo),
            outputURL: URL(string: "https://cdn.example/\(id).png")!, pixelSize: PixelSize(width: 1024, height: 1024))
    }

    private func history(videos: [HistoryItem], images: [HistoryImageItem]) throws -> AccountHistory {
        var history = AccountHistory(owner: "me")
        let next = history.beginLoad(refresh: true)
        let request = try #require(next)
        history.receive(HistoryPage(items: videos, images: images, nextCursor: nil), for: request)
        return history
    }

    @Test func historyRowsInterleaveVideosAndImagesNewestFirst() throws {
        let rows = LibraryBrowse.historyRows(
            try history(
                videos: [historyVideo(id: "v1", secondsAgo: 10), historyVideo(id: "v2", secondsAgo: 300)],
                images: [historyImage(id: "i1", model: "nano_banana_pro", secondsAgo: 60)]))
        #expect(rows.map(\.isVideo) == [true, false, true])
    }

    @Test func aHistoryCardShowsTheThumbnailAndFallsBackToTheVideo() {
        var item = historyVideo(id: "v1")
        #expect(LibraryItemModel(history: item).thumbnailURL == Self.video)
        item.thumbnailURL = Self.thumb
        #expect(LibraryItemModel(history: item).thumbnailURL == Self.thumb)
    }

    @Test func searchMatchesEveryWordAcrossPromptAndModel() {
        let rows: [LibraryMediaItem] = [
            .video(LibraryItemModel(history: historyVideo(id: "v1", prompt: "A dancer on a neon rooftop"))),
            .video(
                LibraryItemModel(history: historyVideo(id: "v2", model: .klingMotionControl, prompt: "rooftop chase"))),
            .remoteImage(historyImage(id: "i1", model: "nano_banana_pro", prompt: "Portrait at dusk")),
        ]
        #expect(LibraryBrowse.search("rooftop", in: rows).map(\.id) == [rows[0].id, rows[1].id])
        #expect(LibraryBrowse.search("ROOFTOP dancer", in: rows).map(\.id) == [rows[0].id])
        #expect(LibraryBrowse.search("seedance", in: rows).map(\.id) == [rows[0].id])
        #expect(LibraryBrowse.search("banana dusk", in: rows).map(\.id) == [rows[2].id])
        #expect(LibraryBrowse.search("  ", in: rows).isEmpty)
    }

    @Test func suggestionsAreTheMostUsedModelsMatchingWhatWasTyped() {
        let rows: [LibraryMediaItem] = [
            .video(LibraryItemModel(history: historyVideo(id: "v1"))),
            .video(LibraryItemModel(history: historyVideo(id: "v2"))),
            .video(LibraryItemModel(history: historyVideo(id: "v3", model: .klingMotionControl))),
            .remoteImage(historyImage(id: "i1", model: "nano_banana_pro")),
        ]
        let seedance = VideoModel.seedance25.title
        #expect(LibraryBrowse.suggestions(for: "", in: rows).first == seedance)
        #expect(LibraryBrowse.suggestions(for: "", in: rows).count == 3)
        #expect(LibraryBrowse.suggestions(for: "ban", in: rows) == ["Nano Banana Pro"])
        #expect(LibraryBrowse.suggestions(for: "nano banana pro", in: rows).isEmpty)
    }

    @Test func serverModelIDsReadAsNames() {
        #expect(LibraryBrowse.readableModel("nano_banana_pro") == "Nano Banana Pro")
        #expect(LibraryBrowse.readableModel("soul-2") == "Soul 2")
        #expect(LibraryBrowse.readableModel("Higgsfield Soul 2.0") == "Higgsfield Soul 2.0")
    }

    @Test func aSavedImageReadsItsPromptFromItsNameAndKeepsItsID() {
        let file = URL(fileURLWithPath: "/Documents/Images/2026-10-15 10.41.03 A knight in silver armor.png")
        let image = LibraryBrowse.savedImage(at: file, modified: LibraryFixture.now)
        #expect(image.prompt == "A knight in silver armor")
        #expect(image.id == LibraryBrowse.savedImage(at: file, modified: .distantPast).id)
        let other = URL(fileURLWithPath: "/Documents/Images/sheet.png")
        #expect(LibraryBrowse.savedImage(at: other, modified: LibraryFixture.now).prompt == "sheet")
        #expect(LibraryBrowse.savedImage(at: other, modified: LibraryFixture.now).id != image.id)
        let dateOnly = URL(fileURLWithPath: "/Documents/Images/2026-10-15 10.41.03.png")
        #expect(LibraryBrowse.savedImage(at: dateOnly, modified: LibraryFixture.now).prompt.isEmpty)
    }

    @Test func detailsOfAHistoryVideoListWhatTheServerSaid() {
        let details = LibraryItemDetails(
            .video(LibraryItemModel(history: historyVideo(id: "v1", prompt: "neon rooftop"))), isOnDevice: false)
        #expect(details.prompt == "neon rooftop")
        let facts = Dictionary(uniqueKeysWithValues: details.facts.map { ($0.title, $0.value) })
        #expect(facts["Model"] == VideoModel.seedance25.title)
        #expect(facts["Length"] == "3.7 s")
        #expect(facts["Size"] == "480 × 854")
        #expect(facts["Where"] == "On Higgsfield, not downloaded")
        #expect(details.facts.first?.title == "Model")
    }

    @Test func detailsOfAnImageReadTheModelAndShape() {
        let details = LibraryItemDetails(
            .remoteImage(historyImage(id: "i1", model: "nano_banana_pro")), isOnDevice: true)
        let facts = Dictionary(uniqueKeysWithValues: details.facts.map { ($0.title, $0.value) })
        #expect(facts["Model"] == "Nano Banana Pro")
        #expect(facts["Aspect ratio"] == "1:1")
        #expect(facts["Where"] == "On this iPhone")
    }
}
