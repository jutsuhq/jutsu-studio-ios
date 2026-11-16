import Foundation
import JutsuCore
import Testing

@testable import Presentation

enum JobFixture {
    static let now = Date(timeIntervalSince1970: 1_000_000)

    static func job(
        _ state: JobState, mode: Mode = .motionTransfer, kind: ProviderKind = .apiKey,
        cost: Cost = .usd(Decimal(string: "8.168")!, isEstimate: false), createdMinutesAgo: Double = 3,
        finishedMinutesAgo: Double? = nil, progress: Double = 0
    ) -> Job {
        let spec = JobSpec(
            mode: mode,
            source: SourceClip(
                fileURL: URL(fileURLWithPath: "/clips/dance.mov"), duration: 30,
                pixelSize: PixelSize(width: 1280, height: 720), range: 0...12),
            resolution: .p720)
        var job = Job(
            spec: spec, providerKind: kind, cost: cost, createdAt: now.addingTimeInterval(-createdMinutesAgo * 60))
        job.state = state
        job.progress = progress
        job.finishedAt = finishedMinutesAgo.map { now.addingTimeInterval(-$0 * 60) }
        return job
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1))) struct LiveJobsTests {
    @Test func seedNeverOverwritesANewerEvent() {
        var job = JobFixture.job(.queued)
        let live = LiveJobs()
        job.state = .processing
        live.apply(job)
        job.state = .queued
        live.seed([job])
        #expect(live.job(job.id)?.state == .processing)
    }

    @Test func consumeReportsOnlyStateChanges() async {
        var job = JobFixture.job(.processing)
        let (events, continuation) = AsyncStream.makeStream(of: Job.self)
        continuation.yield(job)
        job.progress = 0.5
        continuation.yield(job)
        job.state = .done
        job.finishedAt = JobFixture.now
        continuation.yield(job)
        continuation.finish()
        let live = LiveJobs()
        var changes = 0
        await live.consume(events, onStateChange: { changes += 1 })
        #expect(changes == 2)
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    @Test func oldFinishedKeepsTheNewestTodaysAndActiveOnes() {
        // Today in UTC started 826 minutes before `JobFixture.now`.
        let earlier = [2000.0, 3000, 4000, 5000].map {
            JobFixture.job(.done, createdMinutesAgo: 6000, finishedMinutesAgo: $0)
        }
        let today = JobFixture.job(.failed(reason: .message("Boom")), createdMinutesAgo: 900, finishedMinutesAgo: 10)
        let active = JobFixture.job(.processing, createdMinutesAgo: 9000)

        let old = LiveJobs.oldFinished(
            earlier + [today, active], keeping: 2, now: JobFixture.now, calendar: Self.utc)

        #expect(old == [earlier[1].id, earlier[2].id, earlier[3].id])
    }

    @Test func oldFinishedKeepsABatchWhole() {
        let batchID = UUID()
        var kept = JobFixture.job(.done, createdMinutesAgo: 6000, finishedMinutesAgo: 2000)
        kept.batchID = batchID
        var mate = JobFixture.job(.done, createdMinutesAgo: 6000, finishedMinutesAgo: 3000)
        mate.batchID = batchID
        let alone = JobFixture.job(.done, createdMinutesAgo: 6000, finishedMinutesAgo: 4000)

        let old = LiveJobs.oldFinished([kept, mate, alone], keeping: 1, now: JobFixture.now, calendar: Self.utc)

        #expect(old == [alone.id])
    }
}

@Suite struct JobRowModelTests {
    @Test func terminalAndPausedActions() {
        #expect(JobRowModel(JobFixture.job(.done), now: JobFixture.now).actions == [.openInLibrary])
        #expect(JobRowModel(JobFixture.job(.failed(reason: .message("x"))), now: JobFixture.now).actions == [.retry])
        #expect(JobRowModel(JobFixture.job(.canceled), now: JobFixture.now).actions == [.retry])
        var unanswered = JobFixture.job(.failed(reason: .outcomeUnknown))
        unanswered.submitAttempt = SubmitAttempt(isIdempotent: false)
        #expect(JobRowModel(unanswered, now: JobFixture.now).actions == [.retryChargingAgain])
        unanswered.submitAttempt = SubmitAttempt(isIdempotent: true)
        #expect(JobRowModel(unanswered, now: JobFixture.now).actions == [.retry])
        #expect(JobRowModel(JobFixture.job(.rejected), now: JobFixture.now).actions == [.edit])
        for state in [JobState.failed(reason: .message("Download failed")), .canceled] {
            var paid = JobFixture.job(state)
            paid.remote = RemoteJob(requestID: "r1")
            paid.chargedAt = JobFixture.now
            #expect(JobRowModel(paid, now: JobFixture.now).actions == [.retryDownload, .generateAgain])
        }
        var timedOut = JobFixture.job(.failed(reason: .deadline))
        timedOut.remote = RemoteJob(requestID: "r1")
        timedOut.timedOutAt = JobFixture.now
        #expect(JobRowModel(timedOut, now: JobFixture.now).actions == [.checkAgain])
        #expect(
            JobRowModel(JobFixture.job(.paused(.insufficientFunds)), now: JobFixture.now).actions == [
                .resume, .cancel(isEnabled: true, help: "Cancel job"),
            ])
    }

    @Test func jobPausedForItsServerPriceAsksBeforeResuming() {
        CostText.$locale.withValue(.enUS) {
            var job = JobFixture.job(.paused(.priceAboveCap))
            job.serverPrice = .usd(9.5, isEstimate: false)
            let row = JobRowModel(job, now: JobFixture.now)

            #expect(row.actions == [.confirmPrice, .cancel(isEnabled: true, help: "Cancel job")])
            #expect(row.note?.text == "Price from Higgsfield goes over today's spending cap · confirm to resume")
            #expect(row.cost == "$9.50")
            #expect(row.priceSource == "Price from Higgsfield")
            #expect(JobRowModel(JobFixture.job(.queued), now: JobFixture.now).priceSource == "Estimate")
        }
    }
}
