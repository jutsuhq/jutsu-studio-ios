import Foundation
import JutsuCore
import Testing

@testable import Presentation

@Suite struct UnlimitedPresentationTests {
    /// An account whose allowance covers Genjutsu Motion Transfer, with a 100-credit cap nearly spent.
    static func context(optedIn: Bool = true, credits: Int? = 10) -> CreateContext {
        CreateContext(
            connection: .account(AccountInfo(credits: credits)),
            capabilities: Capabilities(
                modes: [.motionTransfer, .objectSwap], resolutions: Set(Resolution.allCases), costUnit: .credits,
                maxConcurrency: nil, unlimited: [.genjutsu: [.motionTransfer]]),
            committedToday: 95, cap: .credits(100), unlimitedOptIn: optedIn)
    }

    @Test func withoutTheOptInOrForAnotherModeItsCredits() throws {
        var form = CreateFixture.ready()
        let spec = try #require(form.makeSpecs(isDraft: false).first)
        var context = Self.context(optedIn: false)
        context.estimates[spec.priceKey] = .credits(40, isEstimate: true)
        #expect(form.priceText(isDraft: false, in: context) == "40 cr")
        #expect(form.costLine(in: context)?.isWarning == true)

        form.mode = .objectSwap
        #expect(!Self.context().paysUnlimited(form.makeSpecs(isDraft: false)))
    }
}
