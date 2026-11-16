import Foundation
import Testing

@testable import JobEngine
@testable import JutsuCore

@Suite(.timeLimit(.minutes(1)), .stopsEngines)
struct UnlimitedTests {
    @Test func theProviderDecidesNotTheCopiedSpec() async throws {
        let harness = Harness(spendStatus: SpendStatus(committedToday: 9, cap: .usd(1)))
        let engine = try await harness.makeEngine()
        var spec = makeSpec()
        spec.usesUnlimited = true

        let refused = await #expect(throws: JobEngineError.self) { try await engine.enqueue(spec) }
        guard case .overCap = refused else {
            Issue.record("not over the cap")
            return
        }

        let job = try await engine.enqueue(spec, overCapApproved: true)
        #expect(!job.spec.usesUnlimited)
    }

    @Test func creditsChargedAfterAllAreRecordedAndCounted() async throws {
        let harness = Harness()
        await harness.provider.payUnlimited(true, answer: (paid: false, charged: .credits(40, isEstimate: false)))
        let engine = try await harness.makeEngine()

        let job = try await engine.enqueue(makeSpec())
        let done = try #require(await harness.repository.wait(for: job.id, .done))

        #expect(!done.spec.usesUnlimited)
        #expect(done.serverPrice == .credits(40, isEstimate: false))
        #expect(done.remote?.charged == nil)
        #expect(done.remote?.paidWithUnlimited == false)
    }
}
