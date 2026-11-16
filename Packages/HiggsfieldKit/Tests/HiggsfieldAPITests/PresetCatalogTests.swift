import Foundation
import HiggsfieldCore
import HiggsfieldTestSupport
import Testing

@testable import HiggsfieldAPI

@Test func aMalformedPresetIsSkippedAndTheRestLoad() async throws {
    let good = "11111111-1111-1111-1111-111111111111"
    let body = #"""
        {"items": [
            {"id": "\#(good)", "name": "Anime", "preview_url": "https://example.com/anime.jpg"},
            {"id": "not-a-uuid", "name": "Broken", "preview_url": "https://example.com/broken.jpg"},
            {"id": "22222222-2222-2222-2222-222222222222", "name": "No preview", "preview_url": ""}
        ]}
        """#
    let server = StubServer()
    server.on("GET", "/models/\(ModelEndpoint.restyle.rawValue)/presets", StubResponse(body: body))
    let presets = try await server.makeClient().presets()
    #expect(presets.map(\.id) == [UUID(uuidString: good)!])
}
