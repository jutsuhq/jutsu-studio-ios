import Foundation
import JutsuCore

public enum SpendingPeriod: String, CaseIterable, Sendable, Identifiable {
    case today, week, month

    public var id: Self { self }

    public var title: String {
        switch self {
        case .today: String(localized: "Today", bundle: .module)
        case .week: String(localized: "7 days", bundle: .module)
        case .month: String(localized: "30 days", bundle: .module)
        }
    }

    var days: Int {
        switch self {
        case .today: 1
        case .week: 7
        case .month: 30
        }
    }

    /// Midnight in `calendar`'s time zone, `days - 1` days before `now`; today counts as the first day.
    public func start(now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
    }
}

/// USD and credits side by side: a job is paid in one of them and they never add up.
public struct SpendTotal: Sendable, Hashable {
    public var usd: Decimal = 0
    public var credits: Decimal = 0

    public init(usd: Decimal = 0, credits: Decimal = 0) {
        self.usd = usd
        self.credits = credits
    }

    mutating func add(_ cost: Cost) {
        switch cost {
        case .usd(let amount, _): usd += amount
        case .credits(let amount, _): credits += amount
        case .unknown: break
        }
    }

    mutating func add(_ total: SpendTotal) {
        usd += total.usd
        credits += total.credits
    }

    /// "96 cr" on an account, "$12.40" on an API key: always in `unit`, what the connection is billed in, and the
    /// other unit after it only when jobs of an earlier connection were paid in it ("96 cr · $12.40"). Nothing spent
    /// reads "0 cr" or "$0.00".
    public func text(in unit: Capabilities.CostUnit) -> String {
        let credits = CostText.text(.credits(credits, isEstimate: true))
        let dollars = CostText.dollars(usd)
        switch unit {
        case .credits: return usd == 0 ? credits : "\(credits) · \(dollars)"
        case .usd: return self.credits == 0 ? dollars : "\(dollars) · \(credits)"
        }
    }
}

/// One row of a breakdown: charged jobs of one mode, resolution or kind.
public struct SpendLine: Sendable, Hashable, Identifiable {
    public var title: String
    public var jobs: Int
    public var total: SpendTotal

    public var id: String { title }

    public var jobsText: String { Self.jobsText(jobs) }

    /// "1 job", "3 jobs".
    public static func jobsText(_ count: Int) -> String {
        String(localized: "\(count) jobs", bundle: .module)
    }
}

/// Finished jobs of one period. Amounts are the estimates made before submit: the API doesn't report
/// what it actually charged.
public struct SpendingSummary: Sendable, Hashable {
    public var charged = SpendTotal()
    public var chargedJobs = 0
    /// Failed, rejected and canceled before the API finished them.
    public var notCharged = SpendTotal()
    public var notChargedJobs = 0
    public var byMode: [SpendLine] = []
    public var byResolution: [SpendLine] = []
    public var byKind: [SpendLine] = []

    /// Terminal jobs that finished in `period`, counted in `calendar`'s time zone, and the finished reference image
    /// requests and virality scores sent in it, which are charged and get a line each of their own in `byMode`.
    public init(
        _ jobs: [Job], images: [ImageCharge] = [], period: SpendingPeriod, now: Date, calendar: Calendar = .current
    ) {
        let start = period.start(now: now, calendar: calendar)
        let finished = jobs.filter { job in
            guard job.state.isTerminal, let finishedAt = job.finishedAt else { return false }
            return finishedAt >= start
        }
        var charged: [Job] = []
        for job in finished {
            if job.isCharged {
                charged.append(job)
                self.charged.add(job.spentPrice)
            } else {
                notCharged.add(job.spentPrice)
            }
        }
        chargedJobs = charged.count
        notChargedJobs = finished.count - charged.count
        byMode = Self.lines(charged, keys: Mode.allCases, key: \.spec.mode, title: \.title)
        let requests = images.filter { !$0.isPending && $0.date >= start }
        for purpose in [ImageCharge.Purpose.referenceImages, .characterSheets, .viralityScore] {
            let charges = requests.filter { $0.paidFor == purpose }
            guard !charges.isEmpty else { continue }
            var total = SpendTotal()
            for charge in charges { total.add(charge.cost) }
            self.charged.add(total)
            byMode.append(SpendLine(title: SpendingTitle.title(of: purpose), jobs: charges.count, total: total))
        }
        byResolution = Self.lines(charged, keys: Resolution.allCases, key: \.spec.resolution, title: \.rawValue)
        byKind = Self.lines(charged, keys: [true, false], key: \.spec.isDraft) {
            $0 ? String(localized: "Draft", bundle: .module) : String(localized: "Final", bundle: .module)
        }
    }

    /// One line per key that has jobs, in `keys` order.
    private static func lines<Key: Hashable>(
        _ jobs: [Job], keys: [Key], key: (Job) -> Key, title: (Key) -> String
    ) -> [SpendLine] {
        let groups = Dictionary(grouping: jobs, by: key)
        return keys.compactMap { value in
            guard let group = groups[value] else { return nil }
            var total = SpendTotal()
            for job in group { total.add(job.spentPrice) }
            return SpendLine(title: title(value), jobs: group.count, total: total)
        }
    }
}

/// The Spending lines of charges that aren't jobs.
public enum SpendingTitle {
    /// A reference image request's line.
    public static let referenceImages = String(localized: "Reference images", bundle: .module)
    /// A virality score's line.
    public static let viralityScores = String(localized: "Virality scores", bundle: .module)
    /// A character sheet request's line.
    public static let characterSheets = String(localized: "Character sheets", bundle: .module)

    static func title(of purpose: ImageCharge.Purpose) -> String {
        switch purpose {
        case .referenceImages: referenceImages
        case .viralityScore: viralityScores
        case .characterSheets: characterSheets
        }
    }
}
