import Foundation
import JutsuCore
import Persistence
import Presentation

/// Today's spend and the cap, for Create's confirmation and the engine's own check before each submit.
nonisolated struct SpendReader: Sendable {
    let store: SwiftDataStore
    let images: ImageSpendLog

    /// `nil` when `kind`'s connection has no cap.
    func status(for kind: ProviderKind?, excluding excluded: UUID? = nil) async throws -> SpendStatus? {
        guard let cap = AppSettings.spendCap(in: .standard, for: kind) else { return nil }
        let committed = try await committedToday(in: cap.unit, excluding: excluded)
        return SpendStatus(committedToday: committed, cap: cap)
    }

    /// The jobs finished today plus every job in flight, and the image requests, in `unit`.
    func committedToday(in unit: Capabilities.CostUnit, excluding excluded: UUID? = nil) async throws -> Decimal {
        let now = Date()
        let jobs = try await store.jobsUnfinishedOrFinished(since: Calendar.current.startOfDay(for: now))
        let charges = await MainActor.run { images.charges }
        return DailySpend.committed(jobs.filter { $0.id != excluded }, images: charges, on: now, in: unit)
    }

    /// What Spending shows for `period`, from storage: `LiveJobs` keeps only the latest finished jobs.
    func summary(for period: SpendingPeriod) async throws -> SpendingSummary {
        let now = Date()
        let jobs = try await store.jobsUnfinishedOrFinished(since: period.start(now: now))
        let charges = await MainActor.run { images.charges }
        return SpendingSummary(jobs, images: charges, period: period, now: now)
    }
}
