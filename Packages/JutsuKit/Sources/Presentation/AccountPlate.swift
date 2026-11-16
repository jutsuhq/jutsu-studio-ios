import Foundation
import JutsuCore

/// The rank of a Higgsfield plan, which decides how its badge looks. Read from the plan's name, since plans get
/// renamed and added more often than they change rank.
public enum PlanTier: Int, Sendable, CaseIterable, Comparable {
    case free
    case starter
    case pro
    case premium
    case elite

    /// "Creator Plus" → `.elite`, "Pro" → `.pro`. An unknown paid plan counts as `.pro`.
    public init(planTitle: String) {
        let words = Set(planTitle.lowercased().split { !$0.isLetter }.map(String.init))
        func has(_ any: Set<String>) -> Bool { !words.isDisjoint(with: any) }
        if has(["ultra", "business", "team", "enterprise", "studio", "unlimited"])
            || words.isSuperset(of: ["creator", "plus"])
        {
            self = .elite
        } else if has(["ultimate", "creator", "premium", "max"]) {
            self = .premium
        } else if has(["pro", "plus", "standard"]) {
            self = .pro
        } else if has(["basic", "starter", "start", "lite"]) {
            self = .starter
        } else if has(["free", "trial"]) {
            self = .free
        } else {
            self = .pro
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The rank's own name, on the card of a plan the account isn't on.
    public var title: String {
        switch self {
        case .free: String(localized: "Free", bundle: .module)
        case .starter: String(localized: "Starter", bundle: .module)
        case .pro: String(localized: "Pro", bundle: .module)
        case .premium: String(localized: "Premium", bundle: .module)
        case .elite: String(localized: "Elite", bundle: .module)
        }
    }
}

/// One card of Account's plan row: a card per rank of Higgsfield plan, the account's own highlighted with what it
/// includes. Higgsfield reports only the account's plan, its credits and its unlimited models, so the other cards
/// carry the rank alone: no prices or allowances made up here.
public struct PlanCard: Sendable, Hashable, Identifiable {
    public var tier: PlanTier
    /// The plan's own name on the current card ("Creator Plus"), the rank's on the others.
    public var title: String
    public var isCurrent: Bool
    /// "2,596 credits left" on the current card; `nil` elsewhere and while the credits are unknown.
    public var credits: String?
    /// The models its unlimited generations cover on the current card, "Genjutsu Motion Transfer · Kling 3.0".
    public var unlimited: String?

    public var id: PlanTier { tier }

    /// "Current plan, Creator Plus, 2,596 credits left, unlimited Kling 3.0"; the rank alone on the others.
    public var accessibilityLabel: String {
        guard isCurrent else { return title }
        var parts = [String(localized: "Current plan", bundle: .module), title]
        if let credits { parts.append(credits) }
        if let unlimited { parts.append(String(localized: "unlimited \(unlimited)", bundle: .module)) }
        return parts.joined(separator: ", ")
    }

    /// Every rank, cheapest first; empty for an API key and for an account whose plan isn't known yet, which have
    /// nothing to highlight.
    public static func cards(
        for connection: ConnectionState, capabilities: Capabilities?, locale: Locale = .current
    ) -> [PlanCard] {
        guard case .account(let info) = connection, let plan = info.plan else { return [] }
        let current = PlanTier(planTitle: plan)
        return PlanTier.allCases.map { tier in
            guard tier == current else { return PlanCard(tier: tier, title: tier.title, isCurrent: false) }
            let credits = info.credits.map {
                String(localized: "\(ConnectionState.grouped($0, locale: locale)) credits left", bundle: .module)
            }
            return PlanCard(
                tier: tier, title: plan, isCurrent: true, credits: credits, unlimited: capabilities?.unlimitedText)
        }
    }
}

/// The account toolbar button's text: the plan and what is left on it.
public struct AccountPlate: Sendable, Hashable {
    /// "Creator Plus", "Account" while the plan is unknown, "API key".
    public var badge: String
    /// `nil` for an API key and for an account whose plan isn't known yet: a neutral badge.
    public var tier: PlanTier?
    /// "2,596"; "—" while the credits are unknown.
    public var amount: String
    /// "credits", or what an API key is billed in.
    public var unit: String
    /// "Low credits: 42 left" below the threshold.
    public var warning: String?
    public var isAPIKey = false
    /// What `amount` shows, for the plural in `accessibilityLabel`.
    var credits: Int?
    var locale: Locale

    /// `nil` without a connection.
    public init?(connection: ConnectionState, lowCreditThreshold: Int, locale: Locale = .current) {
        self.locale = locale
        switch connection {
        case .none:
            return nil
        case .apiKey:
            badge = String(localized: "API key", bundle: .module)
            isAPIKey = true
            amount = String(localized: "Per job", bundle: .module)
            unit = String(localized: "billed in USD", bundle: .module)
        case .account(let info):
            badge = info.plan ?? String(localized: "Account", bundle: .module)
            tier = info.plan.map(PlanTier.init(planTitle:))
            credits = info.credits
            amount = info.credits.map { ConnectionState.grouped($0, locale: locale) } ?? "—"
            unit = String(localized: "credits", bundle: .module)
            warning = LowCreditWarning.text(for: connection, threshold: lowCreditThreshold, locale: locale)
        }
    }

    /// "Creator Plus plan, 2,596 credits left".
    public var accessibilityLabel: String {
        guard !isAPIKey else { return String(localized: "API key, billed in USD per job", bundle: .module) }
        switch (tier, credits) {
        case (nil, nil): return String(localized: "Higgsfield account", bundle: .module)
        case (nil, let credits?):
            return String(localized: "Higgsfield account, \(credits) credits left", bundle: .module, locale: locale)
        case (_?, nil): return String(localized: "\(badge) plan", bundle: .module)
        case (_?, let credits?):
            return String(localized: "\(badge) plan, \(credits) credits left", bundle: .module, locale: locale)
        }
    }
}
