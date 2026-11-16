import Presentation
import SwiftUI

/// Design tokens. Dark only.
///
/// Color roles: lime `accent` for what you can tap; the violet signature colors for the app doing its work
/// (brand, render progress), never on a control.
enum Theme {
    static let background = Color(rgb: 0x060607)
    static let text = Color.white
    static let muted = white(0.62, increased: 0.82)
    static let faint = white(0.46, increased: 0.7)
    static let stroke = white(0.08, increased: 0.3)
    static let card = Color.white.opacity(0.055)
    static let accent = Color("AccentColor")
    /// Text and symbols on `accent`.
    static let ink = Color(rgb: 0x0A0A0A)
    static let danger = Color(rgb: 0xFF5D5D)
    static let warning = Color(rgb: 0xFFB547)
    static let info = Color(rgb: 0x8AB4FF)

    static let signatureViolet = Color(rgb: 0x8B5CF6)
    static let signatureFuchsia = Color(rgb: 0xD946EF)
    static let signaturePink = Color(rgb: 0xF472B6)

    /// The bundled Barlow Condensed ExtraBold, for screen titles and big numbers.
    static let displayFontName = "BarlowCondensed-ExtraBold"

    /// White at `opacity`, stronger while Increase Contrast is on: secondary text keeps well above 4.5:1.
    nonisolated private static func white(_ opacity: CGFloat, increased: CGFloat) -> Color {
        Color(
            uiColor: UIColor { traits in
                UIColor(white: 1, alpha: traits.accessibilityContrast == .high ? increased : opacity)
            })
    }
}

extension Color {
    /// `0xRRGGBB` in sRGB.
    init(rgb: UInt32) {
        self.init(
            .sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255)
    }
}

extension Font {
    /// Barlow Condensed ExtraBold that follows Dynamic Type like `style`.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom(Theme.displayFontName, size: size, relativeTo: style)
    }

    /// Monospaced captions for eyebrows, prices, timecodes and specs.
    static let eyebrow = Font.system(.caption2, design: .monospaced).weight(.medium)
}

/// A screen title in the display face, upper case.
struct DisplayTitle: View {
    let text: LocalizedStringKey
    var size: CGFloat = 44

    var body: some View {
        Text(text)
            .font(.display(size))
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A monospaced, upper-case section label.
struct Eyebrow: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.eyebrow)
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(Theme.faint)
    }
}

/// A rounded card on the content layer: never glass, which belongs to controls (HIG, Materials).
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.stroke) }
    }
}

extension Image {
    /// Names starting with "jutsu." are the app's own icons (Assets › Icons), drawn for glass: a 1.6 pt line over a
    /// 22% fill. Others are SF Symbols.
    init(symbol name: String) {
        if name.hasPrefix("jutsu.") { self.init(name) } else { self.init(systemName: name) }
    }
}

/// A rounded square holding a symbol, lime for the recommended or primary choice.
struct SymbolTile: View {
    let systemName: String
    var isAccent = false

    var body: some View {
        Image(symbol: systemName)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(isAccent ? Theme.accent : .white)
            .frame(width: 36, height: 36)
            .background(isAccent ? Theme.accent.opacity(0.12) : Color.white.opacity(0.07), in: .rect(cornerRadius: 10))
            // Always beside a title that says the same.
            .accessibilityHidden(true)
    }
}

extension JobRowModel.ColorRole {
    var color: Color {
        switch self {
        case .accent: Theme.accent
        case .info: Theme.info
        case .warning: Theme.warning
        case .danger: Theme.danger
        case .faint: Theme.faint
        }
    }
}

/// Liquid Glass (bordered before iOS 26) on the lime accent, with `Theme.ink` labels: white on lime reads at about 1.2:1.
struct ProminentButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Group {
            if #available(iOS 26, *) {
                Button(configuration).buttonStyle(.glassProminent)
            } else {
                Button(configuration).buttonStyle(.borderedProminent).tint(Theme.accent)
            }
        }
        .foregroundStyle(Theme.ink)
    }
}

extension PrimitiveButtonStyle where Self == ProminentButtonStyle {
    /// The screen's main action.
    static var prominent: ProminentButtonStyle { ProminentButtonStyle() }
}
