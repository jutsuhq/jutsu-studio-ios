import Foundation
import HiggsfieldCore
import Testing

@testable import HiggsfieldMCP

/// `assets_picker_list` items as the 2026-10-28 output schema allows them.
@Suite struct AccountAssetTests {
    private func page(_ json: String) throws -> AccountAssetPage? {
        AccountAssetPage(try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))
    }

    @Test func readsAnISOCreationTime() throws {
        let page = try #require(
            try page(
                #"{"items":[{"id":"a","kind":"image","url":"https://u.test/a.webp","createdAt":"2026-10-28T09:15:00.5Z"}],"next_cursor":null}"#
            ))
        let asset = try #require(page.items.first)
        #expect(asset.createdAt == Date(timeIntervalSince1970: 1_793_178_900.5))
        #expect(page.nextCursor == nil)
    }

    @Test func readsUnixSeconds() throws {
        let page = try #require(
            try page(#"{"items":[{"id":"a","kind":"image","url":"https://u.test/a.png","createdAt":1700000000.25}]}"#))
        #expect(page.items.first?.createdAt == Date(timeIntervalSince1970: 1_700_000_000.25))
    }

    @Test func keepsTheOriginalAndThePreview() throws {
        let page = try #require(
            try page(
                #"{"items":[{"id":"a","kind":"image","url":"https://u.test/small.webp","originalUrl":"https://u.test/full.png","thumbnailUrl":"https://u.test/thumb.webp"}],"next_cursor":"next"}"#
            ))
        let asset = try #require(page.items.first)
        #expect(asset.url.absoluteString == "https://u.test/small.webp")
        #expect(asset.originalURL?.absoluteString == "https://u.test/full.png")
        #expect(asset.thumbnailURL?.absoluteString == "https://u.test/thumb.webp")
        #expect(page.nextCursor == .string("next"))
    }

    @Test func leavesOutItemsWithoutAnHTTPSLink() throws {
        let page = try #require(
            try page(
                #"{"items":[{"id":"a","kind":"image","url":"http://u.test/a.png"},{"id":"b","kind":"image","url":"https://u.test/b.png"}]}"#
            ))
        #expect(page.items.map(\.id) == ["b"])
    }
}
