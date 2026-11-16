import Foundation
import Testing

@testable import JobEngine
@testable import JutsuCore

@Suite(.timeLimit(.minutes(1)), .stopsEngines)
struct ServerPriceTests {
    @Test func spendingThatBecomesUnreadableAfterEnqueuePreventsSubmission() async throws {
        let harness = Harness()
        let log = harness.log
        let engine = try await harness.makeEngine { _ in
            log.append("readSpend")
            if log.count("readSpend") > 1 { throw BudgetError.spendingUnavailable }
            return SpendStatus(committedToday: 0, cap: .usd(10))
        }
        let job = try await engine.enqueue(makeSpec())
        #expect(
            await harness.repository.wait(
                for: job.id, .failed(reason: .message(BudgetError.spendingUnavailable.localizedDescription))) != nil)
        #expect(await harness.provider.submitKeys.isEmpty)
    }

    /// The cap stops counting a failed job, so its Retry is checked again: 1.3 on top of 9 goes over a cap of 10.
    @Test func aRetryOverTheCapPausesUntilThePriceIsConfirmed() async throws {
        let harness = Harness()
        await harness.provider.script(status: [.success(.failed(message: "Generation error"))])
        let engine = try await harness.makeEngine { job in
            SpendStatus(committedToday: job.finishedAt == nil ? 0 : 9, cap: .usd(10))
        }
        let job = try await engine.enqueue(makeSpec())
        await harness.repository.wait(for: job.id, .failed(reason: .message("Generation error")))

        try await engine.retry(job.id)
        let paused = try #require(await harness.repository.wait(for: job.id, .paused(.priceAboveCap)))
        #expect(paused.approvedPrice == nil)
        #expect(await harness.provider.submitKeys == [job.idempotencyKey])

        try await engine.resume(job.id)
        let done = try #require(await harness.repository.wait(for: job.id, .done))
        #expect(done.approvedPrice == .usd(1.3, isEstimate: false))
        #expect(await harness.provider.submitKeys == [job.idempotencyKey, done.idempotencyKey])
    }

    @Test func quoteOverTheCapPausesUntilTheUserAgrees() async throws {
        let harness = Harness(spendStatus: SpendStatus(committedToday: 1, cap: .usd(3)))
        await harness.provider.setQuote(.success(.usd(2.5, isEstimate: false)))
        let engine = try await harness.makeEngine()

        let job = try await engine.enqueue(makeSpec())
        let paused = try #require(await harness.repository.wait(for: job.id, .paused(.priceAboveCap)))

        #expect(paused.serverPrice == .usd(2.5, isEstimate: false))
        #expect(paused.approvedPrice == nil)
        #expect(await harness.provider.submitKeys.isEmpty)

        try await engine.resume(job.id)
        let done = try #require(await harness.repository.wait(for: job.id, .done))
        #expect(done.approvedPrice == .usd(2.5, isEstimate: false))
        #expect(await harness.provider.submitKeys == [job.idempotencyKey])
        #expect(harness.log.count("serverEstimate") == 1)
    }

    /// Agreeing to go over the cap by the estimate isn't agreeing to any price the server quotes later.
    @Test func aQuoteAboveThePriceAgreedOverTheCapIsAskedAgain() async throws {
        let harness = Harness(spendStatus: SpendStatus(committedToday: 2, cap: .usd(3)))
        await harness.provider.setQuote(.success(.usd(2.5, isEstimate: false)))
        let engine = try await harness.makeEngine()

        let job = try await engine.enqueue(makeSpec(), overCapApproved: true)

        #expect(await harness.repository.wait(for: job.id, .paused(.priceAboveCap)) != nil)
        #expect(await harness.provider.submitKeys.isEmpty)
    }

    /// A Topaz upscale is queued without a price; once it finishes, what the provider says it charged becomes its
    /// price, and the cap counts it from then on.
    @Test func anUnknownPriceIsFilledInWithTheChargeOnceTheJobFinishes() async throws {
        let harness = Harness()
        await harness.provider.setPreliminary(.unknownCredits)
        await harness.provider.setCharge(.success(.credits(40, isEstimate: false)))
        let engine = try await harness.makeEngine()

        let job = try await engine.enqueue(makeSpec())
        let done = try #require(await harness.repository.wait(for: job.id, .done))

        #expect(done.cost == .unknownCredits)
        #expect(done.serverPrice == .credits(40, isEstimate: false))
        #expect(!done.priceIsUnknown)
        #expect(harness.log.count("charge") == 1)
    }
}
