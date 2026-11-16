import Foundation
import JutsuTestSupport
import Testing

@testable import JobEngine
@testable import JutsuCore

/// Polling a connection that reads several statuses in one call, as the account's `jobs_wait` does.
@Suite(.timeLimit(.minutes(1)), .stopsEngines)
struct StatusBatchTests {
    private func enqueue(_ count: Int, on engine: JobEngine, harness: Harness) async throws -> [Job] {
        var jobs: [Job] = []
        for _ in 0..<count {
            jobs.append(try await engine.enqueue(makeSpec()))
            harness.clock.advance(by: 1)
        }
        return jobs
    }

    @Test func eachJobGetsItsOwnStatusFromTheSharedAnswer() async throws {
        let harness = Harness(maxConcurrency: 3, statusBatchLimit: 12)
        await harness.provider.setBatch(statuses: [
            "r2": .failed(message: "Bad input"), "r3": .rejected(.explicitContent),
        ])
        let engine = try await harness.makeEngine()
        let jobs = try await enqueue(3, on: engine, harness: harness)

        await harness.repository.wait { snapshot in
            jobs.allSatisfy { snapshot.jobs[$0.id]?.state.isActive == false }
        }
        var states: [String: JobState] = [:]
        for job in jobs {
            let stored = try #require(await harness.repository.job(id: job.id))
            states[try #require(stored.remote?.requestID)] = stored.state
        }
        #expect(states["r1"] == .done)
        #expect(states["r2"] == .failed(reason: .message("Bad input")))
        #expect(states["r3"] == .rejected)
        #expect(await harness.provider.statusCalls == 0)
    }

    @Test func aJobMissingFromTheAnswerAsksAlone() async throws {
        let harness = Harness(maxConcurrency: 2, statusBatchLimit: 12)
        await harness.provider.setBatch(omitting: ["r1"])
        await harness.provider.hold(.inProgress)
        let engine = try await harness.makeEngine()
        let jobs = try await enqueue(2, on: engine, harness: harness)
        await harness.repository.wait { $0.count(in: .processing) == 2 }
        await eventually { await harness.provider.statusCalls >= 2 }

        await harness.provider.hold(nil)
        for job in jobs { await harness.repository.wait(for: job.id, .done) }
        #expect(await harness.provider.statusAsked.allSatisfy { $0 == "r1" })
    }
}
