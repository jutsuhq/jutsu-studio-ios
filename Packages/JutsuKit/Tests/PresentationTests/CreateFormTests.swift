import Foundation
import JutsuCore
import Testing

@testable import Presentation

enum CreateFixture {
    static func video(
        duration: TimeInterval = 14.2, width: Int = 1920, height: Int = 1080, codec: String = "avc1",
        name: String = "clip.mp4"
    ) -> SourceVideo {
        SourceVideo(
            fileURL: URL(fileURLWithPath: "/tmp/\(name)"), duration: duration,
            pixelSize: PixelSize(width: width, height: height), codec: codec, fileSize: 38_000_000)
    }

    static func image(_ index: Int) -> URL { URL(fileURLWithPath: "/tmp/ref\(index).png") }

    static func references(_ urls: [URL]) -> [LocalImage] { urls.map { LocalImage(fileURL: $0) } }

    /// Genjutsu at $0.318, $0.681 and $1.632 per second.
    static let pricing = try! Pricing.bundled()

    static let apiKey = CreateContext(connection: .apiKey(keyID: "kid"), pricing: pricing)

    /// Motion transfer with a 14.2 s clip and one image: submittable.
    static func ready(_ resolution: Resolution = .p720) -> CreateForm {
        var form = CreateForm(mode: .motionTransfer, resolution: resolution)
        form.setSource(video())
        form.addReferences(CreateFixture.references([image(1)]))
        return form
    }
}

@Suite struct SubmitDecisionTests {
    @Test func asksAboveTheCap() {
        CostText.$locale.withValue(.enUS) {
            var context = CreateFixture.apiKey
            context.committedToday = 70
            context.cap = .usd(75)
            let form = CreateFixture.ready()
            guard case .confirm(let specs, let confirmation) = form.submitDecision(isDraft: false, in: context) else {
                Issue.record("expected a confirmation")
                return
            }
            #expect(specs == form.makeSpecs(isDraft: false))
            #expect(confirmation.title == "Over today's spend cap")
            #expect(
                confirmation.message == "This job adds $10.22, bringing today to $80.22 against your $75.00 cap.")
            #expect(confirmation.confirmTitle == "Start anyway")
        }
    }

    @Test func creditCapAsksForAnAccount() {
        let form = CreateFixture.ready()
        let spec = form.makeSpecs(isDraft: false)[0]
        let context = CreateContext(
            connection: .account(AccountInfo(credits: 5_000)), estimates: [spec: .credits(120, isEstimate: true)],
            committedToday: 900, cap: .credits(1_000))
        #expect(form.costLine(in: context)?.isWarning == true)
        #expect(form.costLine(in: context)?.text == "15 s = 120 credits")
        guard case .confirm(_, let confirmation) = form.submitDecision(isDraft: false, in: context) else {
            Issue.record("expected a confirmation")
            return
        }
        #expect(
            confirmation.message
                == "This job adds 120 credits, bringing today to 1020 credits against your 1000 credits cap.")
    }
}

@Suite struct DraftOfferTests {
    /// Genjutsu renders drafts at 480p: from a 480p form with the whole range, a draft is the same take.
    @Test func aDraftThatWouldMakeTheSameTakeIsNotOffered() {
        var form = CreateFixture.ready(.p480)
        form.draftResolution = .p480
        form.draftLength = .wholeRange
        #expect(form.offersDraft && !form.draftDiffers)
    }

    @Test func aLowerResolutionOrAShorterPartIsOffered() {
        var form = CreateFixture.ready(.p720)
        form.draftResolution = .p480
        form.draftLength = .wholeRange
        #expect(form.draftDiffers)

        form.resolution = .p480
        form.draftLength = .firstFiveSeconds
        #expect(form.draftDiffers)
    }
}

@Suite struct ClearInputsTests {
    @Test func clearingKeepsTheModeModelAndSettings() {
        var form = CreateFixture.ready(.p720)
        form.prompt = "she spins"
        let model = form.model
        #expect(form.hasInputs)

        form.clearInputs()

        #expect(!form.hasInputs)
        #expect(form.source == nil && form.references.isEmpty && form.prompt.isEmpty)
        #expect(form.mode == .motionTransfer && form.model == model && form.resolution == .p720)
    }
}
