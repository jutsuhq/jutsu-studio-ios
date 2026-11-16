import Foundation
import JutsuCore
import Testing

@testable import Presentation

@Suite struct PlanCardTests {
    private let english = Locale(identifier: "en_US")

    @Test func highlightsTheAccountsPlanWithWhatItIncludes() {
        let capabilities = Capabilities(
            modes: [.motionTransfer], resolutions: [.p720], costUnit: .credits, maxConcurrency: nil,
            unlimited: [.klingMotionControl: [.motionTransfer]])
        let connection = ConnectionState.account(AccountInfo(plan: "Creator Plus", credits: 2596))

        let cards = PlanCard.cards(for: connection, capabilities: capabilities, locale: english)

        #expect(cards.map(\.tier) == PlanTier.allCases)
        #expect(cards.filter(\.isCurrent).map(\.tier) == [.elite])
        let current = cards.first(where: \.isCurrent)
        #expect(current?.title == "Creator Plus")
        #expect(current?.credits == "2,596 credits left")
        #expect(current?.unlimited == "Kling 3.0")
    }

    @Test func otherPlansCarryOnlyTheirRank() {
        let cards = PlanCard.cards(
            for: .account(AccountInfo(plan: "Pro", credits: 10)), capabilities: nil, locale: english)

        let others = cards.filter { !$0.isCurrent }
        #expect(others.map(\.title) == ["Free", "Starter", "Premium", "Elite"])
        #expect(others.allSatisfy { $0.credits == nil && $0.unlimited == nil })
        #expect(cards.first(where: \.isCurrent)?.accessibilityLabel == "Current plan, Pro, 10 credits left")
    }

    @Test func nothingToHighlightWithoutAKnownPlan() {
        #expect(PlanCard.cards(for: .account(AccountInfo(credits: 5)), capabilities: nil).isEmpty)
        #expect(PlanCard.cards(for: .apiKey(keyID: "key"), capabilities: nil).isEmpty)
        #expect(PlanCard.cards(for: .none, capabilities: nil).isEmpty)
    }
}
