import Foundation
import JutsuCore
import JutsuTestSupport
import Testing

@testable import Presentation

/// A scoring provider whose answers the test scripts, one per call in order, the last one repeated.
private actor FakeScorer: ViralityScoring {
    var answers: [Result<ViralityOutcome, any Error>]
    private(set) var scored: [String] = []

    init(_ answers: [Result<ViralityOutcome, any Error>]) {
        self.answers = answers
    }

    func viralityEstimate(jobID: String) async throws -> Cost? { nil }

    func scoreVirality(jobID: String) async throws -> ViralityOutcome {
        scored.append(jobID)
        let answer = answers.count > 1 ? answers.removeFirst() : answers[0]
        return try answer.get()
    }
}

/// Score Variants in batch comparison: who can be scored, what is charged, and what is kept.
@MainActor
@Suite struct VariantScoringTests {
    static let owner = "user_1"
    nonisolated static let scoredAt = Date(timeIntervalSince1970: 2_000_000)
    static let disclaimer = "Predictive proxy metrics, not guaranteed performance or clinical measures."
    /// The readings of a live run on 2026-10-15.
    static let score = ViralityScore(
        score: 46, viralPotential: 45, hook: 29, engagement: 39, sustain: 100, peakSecond: 12,
        perFrame: [0.2, 0.42, 0.3], disclaimer: disclaimer,
        reportURL: URL(string: "https://cdn.example/virality/job.html"), scoredAt: scoredAt)

    /// A finished account result of `owner` with the job ID `requestID`.
    static func item(
        _ requestID: String? = "job-1", kind: ProviderKind = .account, owner: String? = owner,
        state: JobState = .done, virality: ViralityScore? = nil
    ) -> LibraryItemModel {
        var job = JobFixture.job(state, kind: kind)
        job.owner = owner
        job.remote = requestID.map { RemoteJob(requestID: $0) }
        job.outputFile = URL(fileURLWithPath: "/out/\(requestID ?? "none").mp4")
        job.virality = virality
        return LibraryItemModel(job: job)
    }

    @Test func aRefusalIsNotChargedButALostAnswerIs() async {
        let spend = ImageSpendLog(folder: nil)
        let scorer = VariantScorer(spend: spend, now: { Self.scoredAt })
        let provider = FakeScorer([
            .failure(ProviderError.validation(field: nil, message: "Too long")),
            .failure(ProviderError.outcomeUnknown),
        ])
        let plan = ViralityPlan([Self.item("job-1"), Self.item("job-2")], owner: Self.owner)

        await scorer.score(plan, provider: provider, each: .credits(4, isEstimate: false)) { _, _ in }
        await eventually { !scorer.isRunning }

        #expect(spend.charges.count == 1)
        #expect(spend.charges.first?.isPending == false)
        #expect(scorer.failures.count == 2)
        #expect(scorer.failures[plan.entries[0].itemID] == "Too long")
    }

    /// Score reads today's spend itself right before the run, so a screen can't skip the cap.
    @Test func scoringAsksBeforeGoingPastTheCapAndRunsOnceAgreed() async {
        let spend = ImageSpendLog(folder: nil)
        var committed = Decimal(0)
        let scorer = VariantScorer(
            spend: spend,
            spendStatus: { kind in
                kind == .account ? SpendStatus(committedToday: committed, cap: .credits(100)) : nil
            },
            now: { Self.scoredAt })
        let provider = FakeScorer([.success(ViralityOutcome(score: Self.score, charged: nil))])
        let plan = ViralityPlan([Self.item("job-1"), Self.item("job-2")], owner: Self.owner)
        func score(each: Cost, approved: Bool = false) async -> PaidStart {
            await scorer.score(plan, provider: provider, each: each, overCapApproved: approved, save: { _, _ in })
        }

        // Under the cap: runs.
        #expect(await score(each: .credits(4, isEstimate: false)) == .started)
        await eventually { !scorer.isRunning }

        // A price not known, under a cap: asks, scores nothing.
        guard case .needsConfirmation(let unknown) = await score(each: .unknownCredits) else {
            Issue.record("Expected a question about the unknown price")
            return
        }
        #expect(unknown.title == "Price not known yet")

        // 95 + 2 × 4 credits goes past 100: asks, scores nothing.
        committed = 95
        guard case .needsConfirmation(let over) = await score(each: .credits(4, isEstimate: false)) else {
            Issue.record("Expected a question about the cap")
            return
        }
        #expect(over.confirmTitle == "Score anyway")
        #expect(!scorer.isRunning)
        #expect(await provider.scored.count == 2)
        #expect(spend.charges.count == 2)

        // Agreed: runs without asking again.
        #expect(await score(each: .credits(4, isEstimate: false), approved: true) == .started)
        await eventually { !scorer.isRunning }
        #expect(await provider.scored.count == 4)
        #expect(spend.charges.count == 4)
    }

    @Test func chargesAndJobsStoredBeforeScoresStillDecode() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let old = Data(
            """
            [{"id":"6F2B0E5E-3C1B-4F43-9C8A-1D2E3F4A5B6C","date":"2026-10-14T10:00:00Z",
            "cost":{"credits":{"_0":2,"isEstimate":false}},"providerKind":"account","model":"Soul","images":1,
            "isPending":false}]
            """.utf8)
        let charges = try decoder.decode([ImageCharge].self, from: old)
        #expect(charges.first?.purpose == nil)
        #expect(charges.first?.paidFor == .referenceImages)

        var job = JobFixture.job(.done)
        job.virality = Self.score
        let data = try JSONEncoder().encode(job)
        #expect(try JSONDecoder().decode(Job.self, from: data).virality == Self.score)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["virality"] = nil
        let stripped = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(Job.self, from: stripped).virality == nil)
    }
}
