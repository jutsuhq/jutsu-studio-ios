/// The divider of a compare surface: the first video shows left of it, the second right of it.
public struct CompareDivider: Sendable, Hashable {
    /// One arrow-key press moves the divider by this fraction of the width.
    public static let keyboardStep = 0.05

    /// Fraction of the player's width, 0...1.
    public private(set) var position: Double

    public init(position: Double = 0.5) {
        self.position = Self.clamped(position)
    }

    /// Follows a drag at `x` points across a player `width` points wide.
    public mutating func drag(to x: Double, width: Double) {
        guard width > 0 else { return }
        position = Self.clamped(x / width)
    }

    /// Moves by `steps` keyboard steps; negative is left.
    public mutating func nudge(by steps: Int) {
        position = Self.clamped(position + Double(steps) * Self.keyboardStep)
    }

    /// "50%", for the accessibility value.
    public var percentText: String {
        CostText.percent(fraction: position)
    }

    static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0.5
    }
}
