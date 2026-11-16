import Foundation
import JutsuCore
import Testing

@testable import Presentation

@Suite struct CreateOutputTests {
    /// An API key that makes up to four variants per job.
    static let variantsContext = CreateContext(
        connection: .apiKey(keyID: "kid"),
        capabilities: Capabilities(
            modes: [.motionTransfer, .restyle, .objectSwap], resolutions: Set(Resolution.allCases), costUnit: .usd,
            maxConcurrency: nil, maxVariants: 4),
        pricing: CreateFixture.pricing)

    @Test func summarizesTheSourceAudioOnly() {
        #expect(CreateFixture.ready().outputSummary(in: CreateFixture.apiKey) == "Audio: Original")
    }

    @Test func namesVariantsTheJobsMake() {
        var form = CreateFixture.ready()
        form.variants = 3
        form.audio = .mute
        #expect(form.outputSummary(in: Self.variantsContext) == "3 variants · Audio: Mute")
        // Unknown capabilities make one variant, whatever is picked.
        #expect(form.outputSummary(in: CreateFixture.apiKey) == "Audio: Mute")
    }

    @Test func aClipWithoutASourceHasNoSourceAudio() throws {
        var form = CreateForm(mode: .motionTransfer, resolution: .p720)
        form.model = .seedance25
        try #require(form.isWithoutSource)
        form.aspectRatio = .landscape
        #expect(!form.outputSummary(in: CreateFixture.apiKey).contains("Audio"))
        #expect(form.outputSummary(in: CreateFixture.apiKey).contains(AspectRatio.landscape.title))
    }

    @Test func lengthChoicesStayInsideTheModelsLimits() throws {
        var form = CreateForm(mode: .motionTransfer, resolution: .p720)
        form.model = .seedance25
        let choices = form.lengthChoices
        let limits = form.limits.duration
        #expect(!choices.isEmpty)
        #expect(choices.allSatisfy { limits.contains(TimeInterval($0)) })
        #expect(choices.contains(Int(form.clipLength.rounded())))
    }
}
