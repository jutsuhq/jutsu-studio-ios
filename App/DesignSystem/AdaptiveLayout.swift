import SwiftUI

/// Layout decisions made from the space a window has, never from the device, its model or its orientation: an iPad
/// window in Stage Manager, Slide Over and the inner screen of iPhone Duo resize while the app runs.
enum Adaptive {
    /// Enough width for a form in two columns of about 360 pt.
    static let twoColumnWidth: CGFloat = 760

    /// A column, or a row of columns when the window is wide; one `AnyLayout`, so switching keeps every child's state.
    static func columns(_ isWide: Bool, spacing: CGFloat) -> AnyLayout {
        isWide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: spacing * 1.5))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
    }

    /// Photos-style tiles: larger on a regular-width window, so a wide grid isn't a wall of thumbnails.
    static func tileColumns(_ sizeClass: UserInterfaceSizeClass?, spacing: CGFloat = 2) -> [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .regular ? 160 : 110), spacing: spacing)]
    }
}

extension View {
    /// Sets `isWide` while the view is at least `minimum` points wide.
    func measuresWide(_ isWide: Binding<Bool>, minimum: CGFloat = Adaptive.twoColumnWidth) -> some View {
        onGeometryChange(for: Bool.self) {
            $0.size.width >= minimum
        } action: {
            isWide.wrappedValue = $0
        }
    }

    /// Never wider than `ratio` × height, centered: a portrait card or stage stays portrait in a landscape window.
    func cappedAspect(_ ratio: CGFloat) -> some View {
        AspectCap(ratio: ratio) { self }
    }
}

private struct AspectCap: Layout {
    let ratio: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = proposal.replacingUnspecifiedDimensions()
        let child = subviews.first?.sizeThatFits(childProposal(in: size)) ?? .zero
        return CGSize(width: proposal.width ?? child.width, height: proposal.height ?? child.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        for subview in subviews {
            subview.place(at: center, anchor: .center, proposal: childProposal(in: bounds.size))
        }
    }

    private func childProposal(in size: CGSize) -> ProposedViewSize {
        ProposedViewSize(width: min(size.width, size.height * ratio), height: size.height)
    }
}
