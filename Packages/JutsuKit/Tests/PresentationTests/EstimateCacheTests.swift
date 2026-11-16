import Foundation
import JutsuCore
import JutsuTestSupport
import Testing

@testable import Presentation

/// Credit estimates on the Create screen while the form changes.
@Suite(.timeLimit(.minutes(1)))
struct EstimateCacheTests {
    private static let account = CreateContext(connection: .account(AccountInfo(credits: 5_000)))

    private static func context(_ cache: EstimateCache, cap: SpendCap? = nil) -> CreateContext {
        var context = account
        context.estimates = cache.costs
        context.lastTotals = cache.lastTotals
        context.cap = cap
        return context
    }

    private static func record(_ form: CreateForm, generate: Int, draft: Int, in cache: inout EstimateCache) {
        let specs = form.makeSpecs(isDraft: false)
        let drafts = form.makeSpecs(isDraft: true)
        var fresh: [JobSpec: Cost] = [:]
        for spec in specs { fresh[spec] = .credits(Decimal(generate), isEstimate: true) }
        for spec in drafts { fresh[spec] = .credits(Decimal(draft), isEstimate: true) }
        cache.record(fresh, generate: specs, draft: drafts)
    }

    @Test func aChangedFormShowsTheLastPriceOnlyInTheCostLine() {
        var form = CreateFixture.ready()
        var cache = EstimateCache()
        Self.record(form, generate: 120, draft: 40, in: &cache)

        form.resolution = .p1080
        let context = Self.context(cache, cap: .credits(1_000))

        #expect(!cache.missing(form.makeSpecs(isDraft: false)).isEmpty)
        #expect(form.priceText(isDraft: false, in: context) == "Updating the price")
        // The draft keeps its own resolution, so its price is still this form's.
        #expect(form.priceText(isDraft: true, in: context) == "40 cr")
        #expect(form.costLine(in: context)?.text == "15 s = 120 credits")
        #expect(
            form.costLine(in: context)?.detail
                == "Updating the price · 5000 cr left on your plan · failed runs are free")
        #expect(form.cost(isDraft: false, in: context) == nil)
        guard case .confirm(_, let confirmation) = form.submitDecision(isDraft: false, in: context) else {
            Issue.record("expected a confirmation while the price is unknown")
            return
        }
        #expect(confirmation.title == "Price not known yet")

        // Once this form's own estimates arrive, the buttons show those.
        Self.record(form, generate: 300, draft: 90, in: &cache)
        let fresh = Self.context(cache, cap: .credits(1_000))
        #expect(form.priceText(isDraft: false, in: fresh) == "300 cr")
        #expect(form.priceText(isDraft: true, in: fresh) == "90 cr")
    }
}

@Suite struct UnknownPriceDecisionTests {
    @Test func underACapAnUnknownPriceAsks() {
        let spec = CreateFixture.ready().makeSpecs(isDraft: false)[0]
        #expect(SubmitDecision.budgeted([spec], cost: nil, committedToday: 0, cap: nil) == .start([spec]))
        guard
            case .confirm(let specs, let confirmation) = SubmitDecision.budgeted(
                [spec, spec], cost: nil, committedToday: 300, cap: .credits(1_000))
        else {
            Issue.record("expected a confirmation")
            return
        }
        #expect(specs == [spec, spec])
        #expect(
            confirmation.message
                == "These 2 jobs' price isn't known, so it may take today past your 1000 credits cap. "
                + "Today is at 300 credits so far.")
        #expect(confirmation.confirmTitle == "Start anyway")
    }
}
