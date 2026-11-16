import Foundation
import JutsuTestSupport
import Testing

@testable import JobEngine
@testable import JutsuCore

@Suite(.timeLimit(.minutes(1)), .stopsEngines)
struct RetryTests {
    @Test func aJobThatKeepsFailingBeforeSubmitPausesUntilResumed() async throws {
        let harness = Harness()
        await harness.provider.failUploads(Array(repeating: .modelUnavailable, count: 200))
        let engine = try await harness.makeEngine()

        let job = try await engine.enqueue(makeSpec())
        let paused = try #require(await harness.repository.wait(for: job.id, .paused(.keptFailing)))

        let retrying = try #require(paused.retrying)
        #expect(retrying.cause == .modelUnavailable)
        #expect(retrying.failures >= 5)
        #expect(harness.clock.now.timeIntervalSince(retrying.since) >= 15 * 60)
        #expect(await harness.provider.submitKeys.isEmpty)
        let uploads = harness.log.count("upload")
        await eventually { await !engine.isDriving(job.id) }
        #expect(harness.log.count("upload") == uploads)

        await harness.provider.stopFailingUploads()
        try await engine.resume(job.id)
        let done = try #require(await harness.repository.wait(for: job.id, .done))
        #expect(done.retrying == nil)
    }

    @Test func aSecondRetryWhileTheFirstChecksTheCapIsIgnored() async throws {
        let harness = Harness()
        await harness.provider.script(status: [.success(.failed(message: "Generation error"))])
        let reads = CallLog()
        let checked = Gate<Void>()
        let engine = try await harness.makeEngine { job in
            guard job.state == .failed(reason: .message("Generation error")) else {
                return SpendStatus(committedToday: 0, cap: .usd(10))
            }
            reads.append("retry")
            _ = try? await checked.wait()
            return SpendStatus(committedToday: 0, cap: .usd(10))
        }
        let job = try await engine.enqueue(makeSpec())
        await harness.repository.wait(for: job.id, .failed(reason: .message("Generation error")))
        await eventually { await engine.isIdle }

        let first = Task { try await engine.retry(job.id) }
        await eventually { reads.count("retry") == 1 }
        let second = Task { try await engine.retry(job.id) }
        await eventually { reads.count("retry") == 2 }
        await checked.open(.success(()))
        try await first.value
        try await second.value

        let done = try #require(await harness.repository.wait(for: job.id, .done))
        #expect(await harness.provider.submitKeys == [job.idempotencyKey, done.idempotencyKey])
        #expect(await !harness.repository.states(of: job.id).contains(.failed(reason: .internalError)))
    }

    @Test func aSubmittedJobWhosePollsKeepFailingIsNeverPausedAndFailsAtTheDeadline() async throws {
        let harness = Harness(generationDeadline: 3600)
        await harness.provider.script(status: Array(repeating: .failure(.network), count: 500))
        let engine = try await harness.makeEngine()

        let job = try await engine.enqueue(makeSpec())
        let failed = try #require(
            await harness.repository.wait(for: job.id, .failed(reason: .deadline)))

        #expect(failed.timedOutAt != nil)
        #expect(failed.mayStillFinish)
        #expect(failed.retrying == nil)
        #expect(await harness.provider.submitKeys.count == 1)
        #expect(await !harness.repository.states(of: job.id).contains(.paused(.keptFailing)))
        #expect(await engine.limiter.inUse == 0)
    }
}
