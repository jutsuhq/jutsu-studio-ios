import Foundation
import JutsuTestSupport
import Testing

@testable import JobEngine
@testable import JutsuCore

/// One submit of several variants (`JobSpec.variants`) becomes one job per variant, grouped as a batch.
@Suite(.timeLimit(.minutes(1)), .stopsEngines)
struct VariantsTests {
    func makeVariantSpec(_ variants: Int) -> JobSpec {
        var spec = makeSpec()
        spec.variants = variants
        return spec
    }

    /// Every job the answer names is saved and polling before the job that sent it takes its own answer, so a
    /// crash in between can't lose a paid variant.
    @Test func variantsAreSavedBeforeTheSendersAnswer() async throws {
        let harness = Harness()
        let gates = await harness.repository.holdSave {
            $0.state == .queued && $0.spec.variants == 1 && $0.remote?.requestID == "r1"
        }
        let engine = try await harness.makeEngine()

        let job = try await engine.enqueue(makeVariantSpec(3))
        try await gates.reached.wait()

        let variants = await harness.repository.snapshotJobs().filter { $0.batchID == job.batchID && $0.id != job.id }
        #expect(variants.count == 2)
        #expect(variants.allSatisfy { $0.remote != nil && $0.submittedAt != nil })
        await gates.release.open(.success(()))
        await harness.repository.wait { snapshot in
            snapshot.jobs.values.filter { $0.batchID == job.batchID && $0.state == .done }.count == 3
        }
    }

    /// A quit after the sender's request was saved: the job follows it instead of sending it again or failing.
    @Test func aSavedRequestIsFollowedNotSentAgain() async throws {
        let harness = Harness()
        await harness.provider.setIdempotent(false)
        var stored = Job(
            spec: makeVariantSpec(3), providerKind: .apiKey, owner: "key-a", cost: .usd(3.9, isEstimate: false))
        stored.state = .waitingForSlot
        stored.submitAttempt = SubmitAttempt(isIdempotent: false)
        stored.remote = RemoteJob(requestID: "r1", correlationID: "c1")
        await harness.repository.save(stored)

        _ = try await harness.makeEngine()
        let done = try #require(await harness.repository.wait(for: stored.id, .done))

        #expect(harness.log.count("submit") == 0)
        #expect(done.remote?.requestID == "r1")
        #expect(done.submitAttempt == nil)
    }

    /// A submit of variants is sent once, like any other: an unknown outcome fails it without sending it again.
    @Test func anUnknownOutcomeIsNotSentAgain() async throws {
        let harness = Harness()
        await harness.provider.setIdempotent(false)
        await harness.provider.script(submit: [.fail(.outcomeUnknown)])
        let engine = try await harness.makeEngine()

        let job = try await engine.enqueue(makeVariantSpec(4))
        await harness.repository.wait(for: job.id, .failed(reason: .outcomeUnknown))
        await eventually { await engine.isIdle }

        #expect(harness.log.count("submit") == 1)
        #expect(await harness.repository.snapshotJobs().count == 1)
    }
}
