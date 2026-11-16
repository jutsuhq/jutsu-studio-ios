import SwiftUI

// Liquid Glass and the controls that came with it are iOS 26 and later; before that each falls back to the closest
// older look, so the app runs from iOS 18.

enum GlassKind {
    case regular, clear
}

extension View {
    /// A glass background in `shape`, or a material before iOS 26.
    @ViewBuilder
    func glass(_ kind: GlassKind = .regular, in shape: some Shape = Capsule()) -> some View {
        if #available(iOS 26, *) {
            glassEffect(kind == .clear ? .clear : .regular, in: shape)
        } else {
            background(kind == .clear ? .ultraThinMaterial : .regularMaterial, in: shape)
        }
    }

    /// A bar on `edge` that content scrolls under: `safeAreaBar` from iOS 26, a safe-area inset before.
    @ViewBuilder
    func edgeBar<Bar: View>(edge: VerticalEdge, @ViewBuilder content: () -> Bar) -> some View {
        if #available(iOS 26, *) {
            safeAreaBar(edge: edge, content: content)
        } else {
            safeAreaInset(edge: edge, content: content)
        }
    }

    /// The tab bar shrinks while the content scrolls down, from iOS 26.
    @ViewBuilder
    func minimizesTabBarOnScroll() -> some View {
        if #available(iOS 26, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}

/// Glass shapes near each other blend from iOS 26; before, the content as it is.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// `.glass` from iOS 26, `.bordered` before.
struct LiquidGlassButtonStyle: PrimitiveButtonStyle {
    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26, *) {
            Button(configuration).buttonStyle(.glass)
        } else {
            Button(configuration).buttonStyle(.bordered)
        }
    }
}

extension PrimitiveButtonStyle where Self == LiquidGlassButtonStyle {
    static var liquidGlass: LiquidGlassButtonStyle { LiquidGlassButtonStyle() }
}

/// A toolbar button with an iOS 26 system role (its own glyph, no title), titled the older way before.
struct RoleButton: View {
    enum Kind {
        case close, cancel, confirm
    }

    let kind: Kind
    let action: () -> Void

    init(_ kind: Kind, action: @escaping () -> Void) {
        self.kind = kind
        self.action = action
    }

    var body: some View {
        if #available(iOS 26, *) {
            Button(role: role, action: action)
        } else {
            switch kind {
            case .close: Button("Close", systemImage: "xmark", action: action)
            case .cancel: Button("Cancel", role: .cancel, action: action)
            case .confirm: Button("Done", action: action).fontWeight(.semibold)
            }
        }
    }

    @available(iOS 26, *)
    private var role: ButtonRole {
        switch kind {
        case .close: .close
        case .cancel: .cancel
        case .confirm: .confirm
        }
    }
}
