import Foundation
import HiggsfieldCore
import HiggsfieldTestSupport
import Testing

@testable import HiggsfieldMCP

@Suite("History thumbnails")
struct GenerationThumbnailTests {
    private func generation(results: [String: JSONValue]) throws -> PastGeneration {
        let value: JSONValue = .object([
            "id": "job-1", "type": "video", "status": "completed", "model": "seedance_2_5",
            "createdAt": 1_791_032_606, "results": .object(results),
        ])
        return try #require(PastGeneration(value))
    }

    @Test func readsTheThumbnailBeforeTheSmallRendition() throws {
        let item = try generation(results: [
            "rawUrl": "https://cdn.example/out.mp4", "minUrl": "https://cdn.example/out-min.webp",
            "thumbnailUrl": "https://cdn.example/out-thumb.webp",
        ])
        #expect(item.outputURL == URL(string: "https://cdn.example/out.mp4"))
        #expect(item.thumbnailURL == URL(string: "https://cdn.example/out-thumb.webp"))
    }

    @Test func fallsBackToTheSmallRendition() throws {
        let item = try generation(results: [
            "rawUrl": "https://cdn.example/out.png", "minUrl": "https://cdn.example/out-min.webp",
        ])
        #expect(item.thumbnailURL == URL(string: "https://cdn.example/out-min.webp"))
    }

    @Test func ignoresALinkThatIsNotHTTPS() throws {
        let item = try generation(results: [
            "rawUrl": "https://cdn.example/out.mp4", "thumbnailUrl": "http://cdn.example/out-thumb.webp",
        ])
        #expect(item.thumbnailURL == nil)
    }

    @Test func theRecordedPageHasOnlyTheRawResult() throws {
        let page = try #require(GenerationPage(RecordedGenerations.value()))
        #expect(page.items.first?.thumbnailURL == nil)
        #expect(page.items.first?.outputURL != nil)
    }
}
