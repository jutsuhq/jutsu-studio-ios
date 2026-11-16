import Foundation
import JutsuCore
import Testing

@testable import Presentation

private let presetIDs = (0..<13).map { _ in UUID() }

/// Restyle on a 13 s clip, so every job bills 13 s.
private func restyleBatch(styles: Int) -> CreateForm {
    var form = CreateForm(mode: .restyle, resolution: .p720)
    form.setSource(CreateFixture.video(duration: 13))
    form.isBatch = true
    for id in presetIDs.prefix(styles) { form.batch.presetIDs.append(id) }
    return form
}

@Suite struct TemplateBatchTests {
    /// A template applied over a batch of styles is one take: the template's style is the one queued.
    @Test func applyingATemplateTurnsTheBatchOff() {
        let applied = presetIDs[0]
        var form = restyleBatch(styles: 3)
        let template = JobTemplate(name: "Neon", mode: .restyle, presetID: applied, resolution: .p720)

        form.apply(template)

        #expect(!form.isBatch)
        #expect(form.makeSpecs(isDraft: false).map(\.presetID) == [applied])
    }
}

@Suite struct BatchPriceTests {
    @Test func overTheCapAsksOnceForTheWholeBatch() {
        CostText.$locale.withValue(.enUS) {
            let form = restyleBatch(styles: 7)
            var context = CreateFixture.apiKey
            context.cap = .usd(20)
            guard case .confirm(let specs, let confirmation) = form.submitDecision(isDraft: true, in: context) else {
                Issue.record("expected a confirmation")
                return
            }
            #expect(specs.count == 7)
            #expect(
                confirmation.message == "These 7 jobs add $28.94, bringing today to $28.94 against your $20.00 cap.")
            context.cap = .usd(30)
            #expect(form.submitDecision(isDraft: true, in: context) == .start(form.makeSpecs(isDraft: true)))
            #expect(form.costLine(in: context)?.isWarning == false)
        }
    }
}
