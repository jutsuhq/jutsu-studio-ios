import Foundation
import JutsuTestSupport
import Testing

@testable import JobEngine
@testable import JutsuCore

func storedJob(owner: String?, state: JobState = .preparing) -> Job {
    var job = Job(spec: makeSpec(), providerKind: .apiKey, owner: owner, cost: .usd(1.3, isEstimate: false))
    job.state = state
    return job
}

@Suite(.timeLimit(.minutes(1)), .stopsEngines)
struct OwnershipTests {
    @Test func anotherAccountOfTheSameKindNeverRunsUnsubmittedJobs() async throws {
        let harness = Harness(online: false)
        let engine = try await harness.makeEngine()
        let job = try await engine.enqueue(makeSpec())
        await harness.repository.wait(for: job.id, .uploading)

        let other = FakeProvider(owner: "key-b", log: CallLog())
        await engine.setProvider(other)
        #expect(await harness.repository.job(id: job.id)?.state == .paused(.connectionNeedsAttention))

        harness.connectivity.set(online: true)
        try await engine.resume(job.id)
        await harness.repository.wait {
            $0.history[job.id]?.filter { $0 == .paused(.connectionNeedsAttention) }.count == 2
        }
        #expect(await other.uploads.isEmpty)
        #expect(await other.submitKeys.isEmpty)

        await engine.setProvider(harness.provider)
        await harness.repository.wait(for: job.id, .done)
        #expect(await other.uploads.isEmpty)
    }

    @Test func submittedJobsAreNotPolledOrCanceledThroughAnotherAccount() async throws {
        let harness = Harness()
        await harness.provider.hold(.queued)
        let engine = try await harness.makeEngine()
        let job = try await engine.enqueue(makeSpec())
        await harness.repository.wait(for: job.id, .queued)

        let other = FakeProvider(owner: "key-b", log: CallLog())
        await engine.setProvider(other)
        await eventually { await engine.networkWaiters == 1 }
        await #expect(throws: JobEngineError.notConnected) { try await engine.cancel(job.id) }
        #expect(await other.statusCalls == 0)
        #expect(await other.cancels.isEmpty)
        #expect(await harness.repository.job(id: job.id)?.state == .queued)

        await harness.provider.hold(nil)
        await engine.setProvider(harness.provider)
        await harness.repository.wait(for: job.id, .done)
    }

    @Test func submittedJobsOfAnotherAccountDontHoldSlots() async throws {
        let harness = Harness(maxConcurrency: 2)
        await harness.provider.hold(.queued)
        let engine = try await harness.makeEngine()
        let first = try await engine.enqueue(makeSpec())
        let second = try await engine.enqueue(makeSpec())
        await harness.repository.wait { $0.count(in: .queued) == 2 }
        #expect(await engine.limiter.inUse == 2)

        let other = FakeProvider(owner: "key-b", log: CallLog())
        await engine.setProvider(other)
        await eventually { await engine.networkWaiters == 2 }
        #expect(await engine.limiter.inUse == 0)

        // The other account's job isn't stuck behind the two slots the old account's jobs held.
        let third = try await engine.enqueue(makeSpec())
        await harness.repository.wait(for: third.id, .done)
        #expect(await other.acceptedCount == 1)

        await harness.provider.hold(nil)
        await engine.setProvider(harness.provider)
        for id in [first.id, second.id] { await harness.repository.wait(for: id, .done) }
    }

}

@Suite(.timeLimit(.minutes(1)), .stopsEngines)
struct SubmitAttemptTests {
    /// A stop cuts off a submit that is still waiting for its answer, at once or after its grace.
    static let graces: [Duration] = [.zero, .milliseconds(50)]

    @Test(arguments: graces)
    func interruptedSubmitWithoutIdempotencyIsNotSentAgainAfterRelaunch(grace: Duration) async throws {
        let harness = Harness()
        await harness.provider.setIdempotent(false)
        await harness.provider.script(submit: [.hang])
        let first = try await harness.makeEngine()
        let job = try await first.enqueue(makeSpec())
        await eventually { await harness.provider.submitKeys.count == 1 }
        await first.stop(finishingSubmitsWithin: grace)
        let stored = try #require(await harness.repository.job(id: job.id))
        #expect(stored.state == .waitingForSlot)
        #expect(stored.submitAttempt == SubmitAttempt(isIdempotent: false))

        let second = try await harness.makeEngine()
        let failed = try #require(await harness.repository.wait(for: job.id, .failed(reason: .submitCutOff)))

        #expect(failed.submitAttempt == SubmitAttempt(isIdempotent: false))
        #expect(await harness.provider.submitKeys.count == 1)
        await eventually { await second.limiter.inUse == 0 }
    }

    /// The answer was lost, so the relaunch sends the same upload and key again and the server accepts it once.
    @Test(arguments: graces)
    func interruptedIdempotentSubmitIsSentAgainWithItsKey(grace: Duration) async throws {
        let harness = Harness()
        await harness.provider.script(submit: [.hang])
        let first = try await harness.makeEngine()
        let job = try await first.enqueue(makeSpec())
        await eventually { await harness.provider.submitKeys.count == 1 }
        await first.stop(finishingSubmitsWithin: grace)
        #expect(await first.runners.isEmpty)
        let stored = try #require(await harness.repository.job(id: job.id))
        #expect(stored.state == .waitingForSlot)
        #expect(stored.submitAttempt == SubmitAttempt(isIdempotent: true))

        _ = try await harness.makeEngine()
        let done = try #require(await harness.repository.wait(for: job.id, .done))

        #expect(await harness.provider.submitKeys == [job.idempotencyKey, job.idempotencyKey])
        #expect(await harness.provider.acceptedCount == 1)
        #expect(await harness.provider.uploads.count == 2)
        #expect(done.submitAttempt == nil)
    }

    @Test func cancelDuringASubmitWithoutIdempotencyFailsAsUnknown() async throws {
        let harness = Harness()
        await harness.provider.setIdempotent(false)
        await harness.provider.script(submit: [.hang])
        let engine = try await harness.makeEngine()
        let job = try await engine.enqueue(makeSpec())
        await eventually { await harness.provider.submitKeys.count == 1 }

        try await engine.cancel(job.id)

        #expect(await harness.repository.job(id: job.id)?.state == .failed(reason: .outcomeUnknown))
        await eventually { await engine.limiter.inUse == 0 }
        #expect(await harness.provider.submitKeys.count == 1)
    }

    @Test func cancelDuringAnIdempotentSubmitIsRefusedAndTheSubmitGoesOn() async throws {
        let harness = Harness()
        await harness.provider.script(submit: [.hang])
        let engine = try await harness.makeEngine()
        let job = try await engine.enqueue(makeSpec())
        await eventually { await harness.provider.submitKeys.count == 1 }

        await #expect(throws: JobEngineError.submitInProgress) { try await engine.cancel(job.id) }

        let stored = try #require(await harness.repository.job(id: job.id))
        #expect(stored.state == .waitingForSlot)
        #expect(stored.submitAttempt == SubmitAttempt(isIdempotent: true))
        #expect(await engine.runners[job.id] != nil)
        await engine.stop()
    }

    /// A submit with the key whose answer was lost may be running: the job keeps resending it with that key, and
    /// can't be canceled as never sent, even once it pauses for failing.
    @Test func aLostAnswerKeepsTheSubmitMarker() async throws {
        let harness = Harness()
        await harness.provider.script(submit: Array(repeating: .fail(.network), count: 100))
        let engine = try await harness.makeEngine()
        let job = try await engine.enqueue(makeSpec())

        let paused = try #require(await harness.repository.wait(for: job.id, .paused(.keptFailing)))

        #expect(paused.submitAttempt == SubmitAttempt(isIdempotent: true))
        #expect(Set(await harness.provider.submitKeys) == [job.idempotencyKey])
        await #expect(throws: JobEngineError.submitInProgress) { try await engine.cancel(job.id) }
        await engine.stop()
    }

    /// The pause cuts the submit off; the job keeps its marker, so the resend after the pause uses the same key.
    private func pauseDuringAnIdempotentSubmit(_ harness: Harness) async throws -> (JobEngine, Job) {
        await harness.provider.script(submit: [.hang])
        let engine = try await harness.makeEngine()
        let job = try await engine.enqueue(makeSpec())
        await eventually { await harness.provider.submitKeys.count == 1 }
        await engine.setProvider(FakeProvider(owner: "key-b", log: CallLog()))
        let paused = try #require(await harness.repository.job(id: job.id))
        #expect(paused.state == .paused(.connectionNeedsAttention))
        #expect(paused.submitAttempt == SubmitAttempt(isIdempotent: true))
        return (engine, job)
    }

    @Test func connectionSwitchDuringASubmitResendsItWithItsKeyOnReturn() async throws {
        let harness = Harness()
        let (engine, job) = try await pauseDuringAnIdempotentSubmit(harness)

        await engine.setProvider(harness.provider)
        let done = try #require(await harness.repository.wait(for: job.id, .done))

        #expect(await harness.provider.submitKeys == [job.idempotencyKey, job.idempotencyKey])
        #expect(await harness.provider.acceptedCount == 1)
        #expect(done.submitAttempt == nil)
    }

    @Test func retryAfterAnUnknownOutcomeWithoutIdempotencyNeedsTheChargeAgainAgreedAndKeepsItCounted() async throws {
        let harness = Harness()
        await harness.provider.setIdempotent(false)
        await harness.provider.script(submit: [.fail(.outcomeUnknown)])
        let engine = try await harness.makeEngine()
        let job = try await engine.enqueue(makeSpec())
        let failed = try #require(await harness.repository.wait(for: job.id, .failed(reason: .outcomeUnknown)))

        await #expect(throws: JobEngineError.mayChargeAgain) { try await engine.retry(job.id) }
        #expect(await harness.provider.submitKeys == [job.idempotencyKey])

        try await engine.retry(job.id, chargeAgainApproved: true)
        let done = try #require(await harness.repository.wait(for: job.id, .done))

        #expect(done.idempotencyKey == job.idempotencyKey)
        #expect(await harness.provider.submitKeys == [job.idempotencyKey, job.idempotencyKey])
        #expect(done.earlierAttempts == [EarlierAttempt(price: failed.price, endedAt: try #require(failed.finishedAt))])
        let day = try #require(failed.finishedAt)
        #expect(Budget.committed([done], on: day, in: done.price.unit) == failed.price.amount + done.price.amount)
    }
}

@Suite(.timeLimit(.minutes(1)), .stopsEngines)
struct DownloadRetryTests {
    @Test func retryAfterAFailedDownloadFetchesThePaidResultWithoutGeneratingAgain() async throws {
        let harness = Harness(download: .refuse([404]))
        let engine = try await harness.makeEngine()
        let job = try await engine.enqueue(makeSpec())
        let failed = try #require(
            await harness.repository.wait(for: job.id, .failed(reason: .outputUnavailable)))
        #expect(failed.hasPaidOutput)

        try await engine.retry(job.id)
        let done = try #require(await harness.repository.wait(for: job.id, .done))

        #expect(await harness.provider.submitKeys == [job.idempotencyKey])
        #expect(await harness.provider.acceptedCount == 1)
        #expect(done.idempotencyKey == job.idempotencyKey)
        #expect(done.remote == failed.remote)
        #expect(done.chargedAt == failed.chargedAt)
        #expect(harness.log.count("download") == 2)
        let output = try #require(done.outputFile)
        #expect(try Data(contentsOf: output) == Data("video".utf8))
    }

}

@Suite(.timeLimit(.minutes(1)), .stopsEngines)
struct StopTests {
    /// A start while stop still waits for a submit it gave its grace keeps the engine running: the runners the
    /// stop would cancel stay, and the job finishes.
    @Test func aStartWhileStopWaitsForASubmitKeepsTheJobRunning() async throws {
        let harness = Harness()
        let answer = Gate<Void>()
        await harness.provider.script(submit: [.answer(after: answer)])
        let engine = try await harness.makeEngine()
        let job = try await engine.enqueue(makeSpec())
        await eventually { await harness.provider.submitKeys.count == 1 }

        let stopping = Task { await engine.stop(finishingSubmitsWithin: .seconds(5)) }
        await eventually { await engine.submitWaiters == 1 }
        try await engine.start()

        await answer.open(.success(()))
        await stopping.value

        #expect(await engine.isStarted)
        await harness.repository.wait(for: job.id, .done)
        #expect(await harness.repository.job(id: job.id)?.state == .done)
    }
}
