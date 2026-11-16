import JutsuCore
import Presentation
import SwiftUI

/// A card per rank of Higgsfield plan in a row that scrolls sideways, the account's own lit in its color with the
/// credits left and the models its unlimited generations cover. Plans are bought on Higgsfield's site, not here.
struct PlanCardsView: View {
    let cards: [PlanCard]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(cards) { PlanCardView(card: $0).id($0.id) }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                guard let current = cards.first(where: \.isCurrent) else { return }
                proxy.scrollTo(current.id, anchor: .center)
            }
        }
    }
}

private struct PlanCardView: View {
    let card: PlanCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: card.tier.symbol)
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(gradient)
                Spacer(minLength: 0)
                if card.isCurrent {
                    Text("Current")
                        .font(.eyebrow)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(card.tier.edge, in: .capsule)
                }
            }
            Text(card.title)
                .font(.headline)
                .foregroundStyle(card.isCurrent ? Theme.text : Theme.muted)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if let credits = card.credits {
                Text(credits).font(.subheadline).monospacedDigit().foregroundStyle(Theme.muted)
            }
            if let unlimited = card.unlimited {
                Label {
                    Text("Unlimited \(unlimited)")
                } icon: {
                    Image(systemName: "infinity")
                }
                .font(.footnote)
                .foregroundStyle(Theme.muted)
                .lineLimit(4)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: card.isCurrent ? 190 : 112, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background { background }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    card.isCurrent ? AnyShapeStyle(gradient) : AnyShapeStyle(Theme.stroke),
                    lineWidth: card.isCurrent ? 1.5 : 1)
        }
        .opacity(card.isCurrent ? 1 : 0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityLabel)
        .accessibilityAddTraits(card.isCurrent ? .isSelected : [])
    }

    private var gradient: LinearGradient {
        LinearGradient(colors: card.tier.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The current card is lit from its top corner in the plan's color.
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return shape.fill(Theme.card)
            .overlay {
                if card.isCurrent {
                    RadialGradient(
                        colors: [card.tier.edge.opacity(0.28), .clear], center: .topLeading, startRadius: 0,
                        endRadius: 180)
                }
            }
            .clipShape(shape)
    }
}

/// The plan colors of the plan badge.
extension PlanTier {
    var colors: [Color] {
        switch self {
        case .free: [Color.white.opacity(0.75), Color.white.opacity(0.5)]
        case .starter: [Color(rgb: 0x9CC2FF), Color(rgb: 0x5B8CFF)]
        case .pro: [Color(rgb: 0x6EF3DC), Color(rgb: 0x22C3EE)]
        case .premium: [Color(rgb: 0xFFE8A3), Color(rgb: 0xF5B83D), Color(rgb: 0xE08A1E)]
        case .elite: [Theme.signatureViolet, Theme.signatureFuchsia, Theme.signaturePink]
        }
    }

    var edge: Color {
        switch self {
        case .free: Color.white.opacity(0.6)
        case .elite: Theme.signatureFuchsia
        default: colors[colors.count / 2]
        }
    }

    var symbol: String {
        switch self {
        case .free: "circle.dashed"
        case .starter: "bolt.fill"
        case .pro: "star.fill"
        case .premium: "crown.fill"
        case .elite: "sparkles"
        }
    }
}

#Preview {
    PlanCardsView(
        cards: PlanCard.cards(
            for: .account(AccountInfo(plan: "Ultimate", credits: 2524)),
            capabilities: Capabilities(
                modes: [.motionTransfer], resolutions: [.p720], costUnit: .credits, maxConcurrency: nil,
                unlimited: [.klingMotionControl: [.motionTransfer]]))
    )
    .background(Theme.background)
}
