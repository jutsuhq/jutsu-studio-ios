import Foundation
import JutsuTestSupport
import Testing

@testable import JobEngine
@testable import JutsuCore

@Suite(.timeLimit(.minutes(1)), .stopsEngines)
struct JobEngineTests {
    @Test func happyPathSavesEveryStateBeforeTheNextStep() async throws {
        let harness = Harness()
        await harness.provider.script(status: [.success(.queued), .success(.inProgress)])
        let engine = try await harness.makeEngine()

        let job = try await engine.enqueue(makeSpec())
        let done = try #require(await harness.repository.wait(for: job.id, .done))

        #expect(
            harness.log.all == [
                "estimate", "save preparing", "prepareVideo", "prepareImage", "save uploading", "upload", "upload",
                "save waitingForSlot", "save waitingForSlot", "submit", "save queued", "status", "status",
                "save processing", "status",
                // The second save records the folder the download goes to, the third the file it is placed at.
                "save downloading", "save downloading", "download", "restoreAudio", "save downloading", "save done",
            ])
        #expect(await harness.provider.submitKeys == [job.idempotencyKey])
        #expect(done.remote?.requestID == "r1")
        #expect(done.finishedAt != nil)
        let output = try #require(done.outputFile)
        #expect(output.deletingLastPathComponent().lastPathComponent == harness.outputDirectory.lastPathComponent)
        #expect(FileManager.default.fileExists(atPath: output.path))
        let name = output.lastPathComponent
        #expect(name.hasSuffix("_motionTransfer_\(job.id.uuidString.prefix(8).lowercased()).mp4"))
        #expect(name.range(of: #"^\d{4}-\d{2}-\d{2}_"#, options: .regularExpression) != nil)

        for await event in engine.events where event.id == job.id && event.state == .done { break }
    }

    @Test func neverSubmitsMoreJobsThanSlots() async throws {
        let harness = Harness(maxConcurrency: 2)
        await harness.provider.hold(.queued)
        let engine = try await harness.makeEngine()

        var ids: [UUID] = []
        for _ in 0..<3 { ids.append(try await engine.enqueue(makeSpec()).id) }
        await harness.repository.wait { $0.count(in: .queued) == 2 }
        await eventually { await harness.provider.acceptedCount == 2 }
        #expect(await harness.provider.acceptedCount == 2)
        #expect(await engine.limiter.inUse == 2)

        await harness.provider.hold(nil)
        for id in ids { await harness.repository.wait(for: id, .done) }
        #expect(await harness.provider.maxInFlight == 2)
        #expect(await harness.provider.acceptedCount == 3)
    }

    @Test func aFullQueueRequeuesWithTheSameKeyAfterTheServersWait() async throws {
        let harness = Harness(maxConcurrency: 4)
        await harness.provider.script(submit: [.fail(.concurrencyLimit(retryAfter: 42))])
        let engine = try await harness.makeEngine()
        let start = harness.clock.now

        let job = try await engine.enqueue(makeSpec())
        await harness.repository.wait(for: job.id, .done)

        let states = await harness.repository.states(of: job.id)
        // Per submit: the transition in, the attempt marker, and clearing it after the refusal; then the retry.
        #expect(states.filter { $0 == .waitingForSlot }.count == 6)
        #expect(await engine.limiter.limit == 4)
        #expect(await harness.provider.submitKeys == [job.idempotencyKey, job.idempotencyKey])
        #expect(harness.clock.now.timeIntervalSince(start) >= 42)
    }

    @Test func resumeAfterCrashPollsWithoutResubmitting() async throws {
        let harness = Harness()
        await harness.provider.hold(.queued)
        let first = try await harness.makeEngine()
        let job = try await first.enqueue(makeSpec())
        await harness.repository.wait(for: job.id, .queued)
        await first.stop()

        await harness.provider.hold(nil)
        let second = try await harness.makeEngine()
        await harness.repository.wait(for: job.id, .done)

        #expect(await harness.provider.submitKeys == [job.idempotencyKey])
        #expect(harness.log.count("prepareVideo") == 1)
        #expect(await second.limiter.inUse == 0)
    }

    @Test func insufficientFundsPausesUntilResumed() async throws {
        let harness = Harness()
        await harness.provider.script(submit: [.fail(.insufficientFunds)])
        let engine = try await harness.makeEngine()

        let job = try await engine.enqueue(makeSpec())
        await harness.repository.wait(for: job.id, .paused(.insufficientFunds))
        await eventually { await engine.limiter.inUse == 0 }
        #expect(await harness.repository.job(id: job.id)?.state == .paused(.insufficientFunds))

        try await engine.resume(job.id)
        await harness.repository.wait(for: job.id, .done)
        #expect(await harness.provider.submitKeys == [job.idempotencyKey, job.idempotencyKey])
        #expect(await harness.provider.uploads.count == 2)
    }

    @Test func unauthorizedAfterSubmitKeepsStateAndStopsPolling() async throws {
        let harness = Harness()
        await harness.provider.script(status: [.failure(.unauthorized)])
        let engine = try await harness.makeEngine()

        let asked = CallLog()
        await engine.onConnectionNeedsAttention { asked.append("sign in") }

        let job = try await engine.enqueue(makeSpec())
        await eventually { await harness.provider.statusCalls == 1 }
        await eventually { await engine.networkWaiters == 1 }
        #expect(await harness.provider.statusCalls == 1)
        #expect(await harness.repository.job(id: job.id)?.state == .queued)
        // The job shows no change, so the app is told to ask for the sign-in.
        #expect(asked.count("sign in") == 1)

        await engine.setProvider(harness.provider)
        await harness.repository.wait(for: job.id, .done)
    }

    @Test func validationErrorFailsWithTheMessage() async throws {
        let harness = Harness()
        await harness.provider.script(submit: [.fail(.validation(field: "prompt", message: "Prompt is too long"))])
        let engine = try await harness.makeEngine()

        let job = try await engine.enqueue(makeSpec())
        await harness.repository.wait(for: job.id, .failed(reason: .message("Prompt is too long")))
        await eventually { await engine.limiter.inUse == 0 }
    }

    @Test func submitWithUnknownOutcomeFailsWithoutResending() async throws {
        let harness = Harness()
        await harness.provider.script(submit: [.fail(.outcomeUnknown)])
        let engine = try await harness.makeEngine()

        let job = try await engine.enqueue(makeSpec())
        await harness.repository.wait(for: job.id, .failed(reason: .outcomeUnknown))
        #expect(harness.log.count("submit") == 1)
        await eventually { await engine.limiter.inUse == 0 }
    }

    @Test func remoteRejectionEndsAsRejected() async throws {
        let harness = Harness()
        await harness.provider.script(status: [.success(.rejected(.protectedContent))])
        let engine = try await harness.makeEngine()

        let job = try await engine.enqueue(makeSpec())
        let rejected = await harness.repository.wait(for: job.id, .rejected)
        #expect(rejected?.rejection == .protectedContent)
        #expect(await engine.limiter.inUse == 0)
    }

    @Test func cancelWhileQueuedCancelsRemotely() async throws {
        let harness = Harness()
        await harness.provider.hold(.queued)
        let engine = try await harness.makeEngine()
        let job = try await engine.enqueue(makeSpec())
        await harness.repository.wait(for: job.id, .queued)

        try await engine.cancel(job.id)

        #expect(await harness.repository.job(id: job.id)?.state == .canceled)
        #expect(await harness.provider.cancels == ["r1"])
        #expect(await engine.limiter.inUse == 0)
    }

    @Test func aResultPlacedBeforeAQuitIsNotDownloadedAgain() async throws {
        let harness = Harness()
        let placed = harness.outputDirectory.appendingPathComponent("placed.mp4")
        try FileManager.default.createDirectory(at: harness.outputDirectory, withIntermediateDirectories: true)
        try Data("result".utf8).write(to: placed)
        var stored = storedJob(owner: "key-a", state: .downloading)
        stored.remote = RemoteJob(requestID: "r1", correlationID: "c1")
        stored.chargedAt = harness.clock.now
        stored.downloadFolder = harness.outputDirectory
        stored.outputFile = placed
        await harness.repository.save(stored)

        _ = try await harness.makeEngine()
        let done = try #require(await harness.repository.wait(for: stored.id, .done))

        #expect(done.outputFile == placed)
        #expect(harness.log.count("download") == 0)
        let files = try FileManager.default.contentsOfDirectory(atPath: harness.outputDirectory.path)
        #expect(files == ["placed.mp4"])
    }

    @Test func interruptedDownloadResumesFromThePartialFile() async throws {
        let harness = Harness(download: .dropOnce)
        let engine = try await harness.makeEngine()

        let job = try await engine.enqueue(makeSpec())
        let done = try #require(await harness.repository.wait(for: job.id, .done))

        #expect(harness.downloader.starts.all == ["0", "3"])
        let output = try #require(done.outputFile)
        #expect(try Data(contentsOf: output) == Data("video".utf8))
        #expect(!FileManager.default.fileExists(atPath: await engine.partialDownload(of: job.id).path))
    }

    @Test func failedPlaceKeepsTheEarlierResult() throws {
        let folder = try makeFolder()
        let destination = folder.appendingPathComponent("out.mp4")
        try Data("old".utf8).write(to: destination)

        #expect(throws: (any Error).self) {
            try JobEngine.place(folder.appendingPathComponent(".missing.partial"), at: destination)
        }
        #expect(try Data(contentsOf: destination) == Data("old".utf8))
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "JobEngineTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func retryIsANewAttemptWithANewIdempotencyKey() async throws {
        let harness = Harness()
        await harness.provider.script(status: [.success(.failed(message: "Generation error"))])
        let engine = try await harness.makeEngine()

        let job = try await engine.enqueue(makeSpec())
        await harness.repository.wait(for: job.id, .failed(reason: .message("Generation error")))
        await #expect(throws: JobEngineError.notResumable(.failed(reason: .message("Generation error")))) {
            try await engine.resume(job.id)
        }

        harness.clock.advance(by: 600)
        let retriedAt = harness.clock.now
        try await engine.retry(job.id)
        let done = try #require(await harness.repository.wait(for: job.id, .done))
        #expect(done.idempotencyKey != job.idempotencyKey)
        #expect(done.attemptStartedAt == retriedAt)
        #expect(await harness.provider.submitKeys == [job.idempotencyKey, done.idempotencyKey])
        #expect(await harness.provider.acceptedCount == 2)
    }

    @Test func retryIsOnlyForFailedOrCanceledJobs() async throws {
        let harness = Harness()
        let engine = try await harness.makeEngine()
        let job = try await engine.enqueue(makeSpec())
        await harness.repository.wait(for: job.id, .done)

        await #expect(throws: JobEngineError.notRetryable(.done)) { try await engine.retry(job.id) }
        let unknown = UUID()
        await #expect(throws: JobEngineError.unknownJob(unknown)) { try await engine.cancel(unknown) }
    }
}
