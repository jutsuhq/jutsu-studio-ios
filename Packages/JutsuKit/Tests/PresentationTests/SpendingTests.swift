import Foundation
import JutsuCore
import Testing

@testable import Presentation

private func makeJob(
    _ state: JobState, cost: Cost, finishedAt: Date?, mode: Mode = .motionTransfer, resolution: Resolution = .p720,
    isDraft: Bool = false, duration: TimeInterval = 10
) -> Job {
    let source = SourceClip(
        fileURL: URL(fileURLWithPath: "/tmp/source.mov"), duration: 30,
        pixelSize: PixelSize(width: 1280, height: 720), range: 0...duration)
    let spec = JobSpec(mode: mode, source: source, resolution: resolution, isDraft: isDraft)
    var job = Job(
        spec: spec, providerKind: .apiKey, cost: cost, createdAt: finishedAt ?? Date(timeIntervalSince1970: 0))
    job.state = state
    job.finishedAt = finishedAt
    return job
}

@Suite struct SpendingSummaryTests {
    /// UTC+10, so local midnight is 14:00 UTC the day before.
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 10 * 3600)!
        return calendar
    }()
    /// 2025-10-13 09:00 local, 2025-10-12 23:00 UTC.
    let now = Date(timeIntervalSince1970: 1_760_310_000)
    var localMidnight: Date { now - 9 * 3600 }

    /// Account and the widget pass the image requests, so their total is the one the cap counts once finished.
    @Test func finishedImageRequestsOfThePeriodAddToTheCharged() {
        let jobs = [makeJob(.done, cost: .credits(30, isEstimate: true), finishedAt: localMidnight + 60)]
        let images = [
            ImageCharge(
                date: localMidnight + 120, cost: .credits(2, isEstimate: true), providerKind: .account,
                model: "Virality", images: 1, isPending: false, purpose: .viralityScore),
            ImageCharge(
                date: localMidnight + 180, cost: .credits(5, isEstimate: true), providerKind: .account, model: "Soul",
                images: 1, purpose: .referenceImages),
            ImageCharge(
                date: localMidnight - 3 * 86_400, cost: .credits(7, isEstimate: true), providerKind: .account,
                model: "Soul", images: 1, isPending: false, purpose: .referenceImages),
        ]
        let today = SpendingSummary(jobs, images: images, period: .today, now: now, calendar: calendar)
        #expect(today.charged == SpendTotal(credits: 32))
        #expect(today.byMode.map(\.title).last == SpendingTitle.viralityScores)
        let week = SpendingSummary(jobs, images: images, period: .week, now: now, calendar: calendar)
        #expect(week.charged == SpendTotal(credits: 39))
    }

    @Test func todayFollowsTheUserTimeZoneNotUTC() {
        let jobs = [
            makeJob(.done, cost: .usd(1, isEstimate: false), finishedAt: localMidnight),
            makeJob(.done, cost: .usd(10, isEstimate: false), finishedAt: localMidnight - 1),
        ]
        let today = SpendingSummary(jobs, period: .today, now: now, calendar: calendar)
        #expect(today.charged == SpendTotal(usd: 1))
        #expect(today.chargedJobs == 1)
        let week = SpendingSummary(jobs, period: .week, now: now, calendar: calendar)
        #expect(week.charged == SpendTotal(usd: 11))
    }

    @Test func failedRejectedAndCanceledAreNotCharged() {
        var downloadFailed = makeJob(
            .failed(reason: .message("download")), cost: .usd(3, isEstimate: false), finishedAt: now)
        downloadFailed.chargedAt = now
        let jobs = [
            makeJob(.done, cost: .usd(10, isEstimate: false), finishedAt: now),
            makeJob(.failed(reason: .message("x")), cost: .usd(4, isEstimate: false), finishedAt: now),
            makeJob(.rejected, cost: .credits(20, isEstimate: true), finishedAt: now),
            makeJob(.canceled, cost: .usd(1, isEstimate: false), finishedAt: now),
            downloadFailed,
        ]
        let summary = SpendingSummary(jobs, period: .today, now: now, calendar: calendar)
        #expect(summary.charged == SpendTotal(usd: 13))
        #expect(summary.chargedJobs == 2)
        #expect(summary.notCharged == SpendTotal(usd: 5, credits: 20))
        #expect(summary.notChargedJobs == 3)
    }

    @Test func chargedRuleMatchesTheDailyCap() {
        var canceled = makeJob(.canceled, cost: .usd(7, isEstimate: false), finishedAt: now)
        canceled.chargedAt = now
        let jobs = [
            canceled, makeJob(.done, cost: .usd(10, isEstimate: false), finishedAt: now),
            makeJob(.failed(reason: .message("x")), cost: .usd(50, isEstimate: false), finishedAt: now),
        ]
        let summary = SpendingSummary(jobs, period: .today, now: now, calendar: calendar)
        #expect(summary.charged.usd == 17)
        #expect(summary.charged.usd == DailySpend.committed(jobs, on: now, calendar: calendar))
    }
}

@Suite struct SpendTotalTextTests {
    private let english = Locale(identifier: "en_US")

    @Test func theConnectionsUnitLeadsAndTheOtherFollowsOnlyWhenUsed() {
        CostText.$locale.withValue(english) {
            #expect(SpendTotal().text(in: .credits) == "0 cr")
            #expect(SpendTotal().text(in: .usd) == "$0.00")
            #expect(SpendTotal(credits: 96).text(in: .credits) == "96 cr")
            #expect(SpendTotal(usd: 12.4, credits: 96).text(in: .credits) == "96 cr · $12.40")
            #expect(SpendTotal(usd: 12.4).text(in: .usd) == "$12.40")
            #expect(SpendTotal(usd: 12.4, credits: 96).text(in: .usd) == "$12.40 · 96 cr")
        }
    }
}
