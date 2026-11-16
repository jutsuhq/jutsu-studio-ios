import Foundation
import HiggsfieldCore
import Testing

@testable import HiggsfieldMCP

@Suite struct ImageSettingsTests {
    private func model(_ json: String) throws -> AccountImageModel? {
        AccountImageModel(item: try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))
    }

    /// GPT Image 2 as `models_explore list` described it on 2026-10-28.
    @Test func resolutionAndQualityAreReadFromTheCatalog() throws {
        let gpt = try #require(
            try model(
                """
                {"id": "gpt_image_2", "name": "GPT Image 2", "aspect_ratios": ["1:1"],
                 "parameters": [
                   {"name": "resolution", "type": "string", "default": "1k", "options": ["1k", "2k", "4k"]},
                   {"name": "quality", "type": "string", "default": "low", "options": ["low", "medium", "high"]},
                   {"name": "style_id", "type": "string"}]}
                """))
        #expect(
            gpt.settings == [
                .init(name: "resolution", options: ["1k", "2k", "4k"], defaultValue: "1k"),
                .init(name: "quality", options: ["low", "medium", "high"], defaultValue: "low"),
            ])
    }

    /// Nano Banana 2 Lite renders at 1k only: nothing to choose.
    @Test func aParameterWithOneValueIsNoChoice() throws {
        let lite = try #require(
            try model(
                """
                {"id": "nano_banana_2_lite", "name": "Nano Banana 2 Lite", "aspect_ratios": ["1:1"],
                 "parameters": [{"name": "resolution", "type": "string", "default": "1k", "options": ["1k"]}]}
                """))
        #expect(lite.settings.isEmpty)
    }

    @Test func theChosenValuesGoInTheParams() {
        let request = AccountImageRequest(
            model: "nano_banana_pro", prompt: "a lighthouse", aspectRatio: "16:9", count: 2,
            settings: ["resolution": "4k", "model": "not this"])
        let params = request.arguments(getCost: true)["params"]
        #expect(params?["resolution"] == "4k")
        #expect(params?["model"] == "nano_banana_pro")
    }
}
