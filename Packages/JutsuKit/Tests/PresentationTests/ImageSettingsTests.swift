import Foundation
import JutsuCore
import Testing

@testable import Presentation

private let resolution = ImageModel.Setting(name: "resolution", options: ["1k", "2k", "4k"], defaultValue: "2k")
private let banana = ImageModel(
    id: "nano_banana_pro", title: "Nano Banana Pro", variantCounts: [1, 2, 3, 4], aspectRatios: ["1:1", "16:9"],
    settings: [resolution])
private let flux = ImageModel(
    id: "flux_2", title: "FLUX.2", aspectRatios: ["1:1"],
    settings: [ImageModel.Setting(name: "resolution", options: ["1k", "2k"], defaultValue: "1k")])
private let zImage = ImageModel(id: "z_image", title: "Z Image", aspectRatios: ["1:1"])

@MainActor
@Suite struct ImageSettingsTests {
    func generator() -> ReferenceGenerator {
        let generator = ReferenceGenerator(spend: ImageSpendLog(folder: nil), jobLog: ImageJobLog(folder: nil))
        generator.useModels([banana, flux, zImage])
        generator.prompt = "a lighthouse at dusk"
        return generator
    }

    @Test func theRequestSendsThePickedResolution() async throws {
        let generator = generator()
        #expect(generator.settingValues == ["resolution": "2k"])
        generator.chosenSettings["resolution"] = "4k"

        let draft = try #require(generator.draft(source: nil, mode: .motionTransfer))
        let request = try await generator.request(draft) { _ in throw CancellationError() }
        #expect(request.settings == ["resolution": "4k"])
    }

    /// FLUX.2 stops at 2k, so a 4k pick sends its default there and comes back on Nano Banana Pro.
    @Test func aValueTheModelLacksSendsItsDefaultAndIsKeptForTheNext() {
        let generator = generator()
        generator.chosenSettings["resolution"] = "4k"

        generator.selectModel(flux.id)
        #expect(generator.settingValues == ["resolution": "1k"])
        generator.selectModel(zImage.id)
        #expect(generator.settingValues.isEmpty)
        generator.selectModel(banana.id)
        #expect(generator.settingValues == ["resolution": "4k"])
    }

    @Test func thePriceIsReadAgainForAnotherResolution() {
        let generator = generator()
        let before = generator.priceKey(source: nil, mode: .motionTransfer)
        generator.chosenSettings["resolution"] = "1k"
        #expect(generator.priceKey(source: nil, mode: .motionTransfer) != before)
    }

    @Test func thePicksComeBackWithTheDraft() throws {
        let generator = generator()
        generator.chosenSettings["resolution"] = "1k"
        let saved = try JSONDecoder().decode(ImageDraft.self, from: try JSONEncoder().encode(generator.snapshot()))

        let restored = self.generator()
        restored.restore(saved)
        #expect(restored.settingValues == ["resolution": "1k"])
    }

    @Test func aDraftSavedBeforeSettingsStillOpens() throws {
        let json = #"{"prompt": "a knight", "modelID": "nano_banana_pro", "count": 2}"#
        let draft = try JSONDecoder().decode(ImageDraft.self, from: Data(json.utf8))
        #expect(draft.prompt == "a knight" && draft.count == 2 && draft.settings.isEmpty)
    }

    @Test func sizesReadAsAResolution() {
        let soulQuality = ImageModel.Setting(name: "quality", options: ["1.5k", "2k"])
        #expect(soulQuality.isSize && soulQuality.optionTitle("1.5k") == "1.5K")
        #expect(!ImageModel.Setting(name: "quality", options: ["low", "high"]).isSize)
        #expect(banana.summary == "Up to 4K")
    }
}
