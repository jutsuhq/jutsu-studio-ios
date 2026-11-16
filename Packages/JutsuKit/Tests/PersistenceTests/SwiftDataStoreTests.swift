import Foundation
import JutsuCore
import Persistence
import SwiftData
import Testing

func makeJob(
    id: UUID = UUID(), mode: Mode = .motionTransfer, createdAt: Date = Date(), state: JobState = .preparing
) -> Job {
    let source = SourceClip(
        fileURL: URL(fileURLWithPath: "/tmp/source.mov"), duration: 60, pixelSize: PixelSize(width: 1280, height: 720),
        range: 0...10)
    let spec = JobSpec(
        mode: mode, source: source, references: [LocalImage(fileURL: URL(fileURLWithPath: "/tmp/ref.jpg"))],
        prompt: "a cat", resolution: .p720)
    var job = Job(id: id, spec: spec, providerKind: .apiKey, cost: .credits(12, isEstimate: true), createdAt: createdAt)
    job.state = state
    return job
}

@Suite struct SwiftDataStoreTests {
    let container: ModelContainer
    let store: SwiftDataStore

    init() throws {
        container = try StoreContainer.make(inMemory: true)
        store = SwiftDataStore(modelContainer: container)
    }

    @Test func savesAndFetchesJob() async throws {
        var job = makeJob()
        job.remote = RemoteJob(requestID: "r1", correlationID: "c1")
        try await store.save(job)

        #expect(try await store.job(id: job.id) == job)
        #expect(try await store.job(id: UUID()) == nil)
    }

    @Test func saveUpsertsById() async throws {
        var job = makeJob()
        try await store.save(job)
        job.state = .done
        job.progress = 1
        job.finishedAt = Date(timeIntervalSince1970: 1_000)
        job.outputFile = URL(fileURLWithPath: "/tmp/out.mp4")
        try await store.save(job)

        #expect(try await store.job(id: job.id) == job)
        let context = ModelContext(container)
        let records = try context.fetch(FetchDescriptor<JobRecord>())
        #expect(records.count == 1)
        #expect(records.first?.stateKind == "done")
        #expect(records.first?.isTerminal == true)
        #expect(records.first?.outputPath == "/tmp/out.mp4")
        #expect(records.first?.finishedAt == Date(timeIntervalSince1970: 1_000))
    }

    @Test func activeJobsAreNonTerminalOldestFirst() async throws {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let newer = makeJob(createdAt: base.addingTimeInterval(60), state: .queued)
        let older = makeJob(createdAt: base, state: .paused(.insufficientFunds))
        let done = makeJob(createdAt: base.addingTimeInterval(-60), state: .done)
        let canceled = makeJob(createdAt: base.addingTimeInterval(-30), state: .canceled)
        for job in [newer, done, older, canceled] {
            try await store.save(job)
        }

        #expect(try await store.activeJobs().map(\.id) == [older.id, newer.id])
    }

    @Test func activeJobsSkipUndecodableRecordsAndKeepThem() async throws {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let older = makeJob(createdAt: base, state: .queued)
        let unreadable = makeJob(createdAt: base.addingTimeInterval(30), state: .processing)
        let newer = makeJob(createdAt: base.addingTimeInterval(60), state: .processing)
        for job in [older, unreadable, newer] {
            try await store.save(job)
        }
        try writeUnknownMode(into: unreadable.id)

        #expect(try await store.activeJobs().map(\.id) == [older.id, newer.id])
        #expect(try await store.activeJobIDs() == [older.id, unreadable.id, newer.id])
        let kept = try ModelContext(container).fetch(FetchDescriptor<JobRecord>())
        #expect(Set(kept.map(\.id)) == [older.id, unreadable.id, newer.id])
    }

    @Test func spendingRejectsAnIncompleteHistoryWhileTheHistoryStillListsReadableJobs() async throws {
        let startOfDay = Date(timeIntervalSince1970: 1_000_000)
        var done = makeJob(createdAt: startOfDay, state: .done)
        done.finishedAt = startOfDay.addingTimeInterval(60)
        var unreadable = makeJob(createdAt: startOfDay.addingTimeInterval(30), state: .done)
        unreadable.finishedAt = startOfDay.addingTimeInterval(90)
        for job in [done, unreadable] {
            try await store.save(job)
        }
        try writeUnknownMode(into: unreadable.id)

        await #expect(throws: (any Error).self) {
            try await store.committedSpend(on: startOfDay, in: .credits)
        }
        #expect(try await store.doneJobs(limit: 5).map(\.id) == [done.id])
    }

    /// Rewrites a stored job as a newer build might: with a mode this build doesn't know.
    private func writeUnknownMode(into id: UUID) throws {
        let context = ModelContext(container)
        let record = try #require(
            try context.fetch(FetchDescriptor<JobRecord>(predicate: #Predicate { $0.id == id })).first)
        let json = try #require(String(data: record.jobData, encoding: .utf8))
        #expect(json.contains("\"motionTransfer\""))
        let rewritten = json.replacingOccurrences(of: "\"motionTransfer\"", with: "\"fromTheFuture\"")
        record.setValue(forKey: \.jobData, to: Data(rewritten.utf8))
        try context.save()
        #expect(throws: (any Error).self) { try record.job() }
    }

    @Test func committedSpendCountsTodayAndTheQueueInOneUnit() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let now = Date(timeIntervalSince1970: 86_400 * 100 + 3600)
        let running = makeJob(state: .processing)
        let other = makeJob(state: .queued)
        var today = makeJob(state: .done)
        today.finishedAt = now.addingTimeInterval(-60)
        var yesterday = makeJob(state: .done)
        yesterday.finishedAt = now.addingTimeInterval(-86_400)
        for job in [running, other, today, yesterday] {
            try await store.save(job)
        }

        let all = try await store.committedSpend(on: now, in: .credits, calendar: calendar)
        let withoutOther = try await store.committedSpend(
            on: now, in: .credits, excluding: other.id, calendar: calendar)
        let usd = try await store.committedSpend(on: now, in: .usd, calendar: calendar)
        #expect(all == 36)
        #expect(withoutOther == 24)
        #expect(usd == 0)
    }

    @Test func deletesJob() async throws {
        let job = makeJob()
        try await store.save(job)
        try await store.delete(id: job.id)
        try await store.delete(id: job.id)

        #expect(try await store.job(id: job.id) == nil)
        #expect(try await store.activeJobs().isEmpty)
    }

    @Test func inputFilesOfJobsNotDoneLeaveOutDoneJobs() async throws {
        func job(_ state: JobState, source: String) -> Job {
            var job = makeJob(state: state)
            job.spec.source?.fileURL = URL(fileURLWithPath: "/tmp/\(source).mov")
            job.spec.references = [LocalImage(fileURL: URL(fileURLWithPath: "/tmp/\(source).png"))]
            return job
        }
        try await store.save(job(.done, source: "done"))
        try await store.save(job(.failed(reason: .generationFailed), source: "failed"))
        try await store.save(job(.queued, source: "queued"))

        let files = try await store.inputFilesOfJobsNotDone()

        #expect(Set(files.map(\.lastPathComponent)) == ["failed.mov", "failed.png", "queued.mov", "queued.png"])
    }
}
