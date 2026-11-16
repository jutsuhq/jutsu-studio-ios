import Foundation
import Testing

@testable import JobEngine
@testable import JutsuCore

@Suite(.timeLimit(.minutes(1)), .stopsEngines)
struct ServerURLEngineTests {
    static let deadline = EngineSettings(outputDirectory: URL(fileURLWithPath: "/tmp")).generationDeadline

    @Test func aJobTheProviderNeverFinishesFailsAtTheDeadline() async throws {
        let harness = Harness(maxConcurrency: 1, generationDeadline: Self.deadline)
        await harness.provider.hold(.inProgress)
        let engine = try await harness.makeEngine()

        let job = try await engine.enqueue(makeSpec())
        let failed = try #require(await harness.repository.wait(for: job.id, .failed(reason: .deadline)))

        let submittedAt = try #require(failed.submittedAt)
        #expect(harness.clock.now.timeIntervalSince(submittedAt) >= Self.deadline)
        #expect(await harness.provider.submitKeys.count == 1)
        #expect(await engine.limiter.inUse == 0)

        await harness.provider.hold(nil)
        let next = try await engine.enqueue(makeSpec())
        await harness.repository.wait(for: next.id, .done)
        #expect(await harness.repository.job(id: job.id)?.state == .failed(reason: .deadline))
        #expect(await harness.provider.submitKeys.count == 2)
    }

    /// Fails `job` at the deadline while the provider keeps generating it.
    private func timeOut(_ harness: Harness) async throws -> (JobEngine, Job) {
        await harness.provider.hold(.inProgress)
        let engine = try await harness.makeEngine()
        let job = try await engine.enqueue(makeSpec())
        let failed = try #require(await harness.repository.wait(for: job.id, .failed(reason: .deadline)))
        #expect(failed.mayStillFinish)
        return (engine, failed)
    }

    @Test func checkAgainAfterTheDeadlineFetchesTheResultWithoutSubmittingAgain() async throws {
        let harness = Harness(generationDeadline: Self.deadline)
        let (engine, failed) = try await timeOut(harness)

        await harness.provider.hold(nil)
        try await engine.checkAgain(failed.id)
        let done = try #require(await harness.repository.wait(for: failed.id, .done))

        #expect(await harness.provider.submitKeys.count == 1)
        #expect(done.remote == failed.remote)
        #expect(done.timedOutAt == nil)
    }

    @Test func retryAfterTheDeadlineChecksAgainInsteadOfSubmitting() async throws {
        let harness = Harness(generationDeadline: Self.deadline)
        let (engine, failed) = try await timeOut(harness)

        await harness.provider.hold(nil)
        try await engine.retry(failed.id)
        let done = try #require(await harness.repository.wait(for: failed.id, .done))

        #expect(await harness.provider.submitKeys == [failed.idempotencyKey])
        #expect(done.idempotencyKey == failed.idempotencyKey)
    }
}
