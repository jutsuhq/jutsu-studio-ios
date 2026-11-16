import Accessibility
import Presentation
import SwiftUI

enum VoiceOver {
    /// Spoken at high priority, so the focus change that usually follows doesn't cut it off.
    static func announce(_ text: String) {
        var announcement = AttributedString(text)
        announcement.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(announcement).post()
    }
}

extension Animation {
    /// `animation`, or none while Reduce Motion is on; for `withAnimation` in code that has no view environment.
    static func unlessReduceMotion(_ animation: Animation = .default) -> Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : animation
    }
}

extension View {
    /// A compare divider as one adjustable element: VoiceOver's swipe up and down move it, read as a percentage.
    func adjustableDivider(_ divider: Binding<CompareDivider>, label: LocalizedStringKey) -> some View {
        accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(divider.wrappedValue.percentText)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: divider.wrappedValue.nudge(by: 1)
                case .decrement: divider.wrappedValue.nudge(by: -1)
                @unknown default: break
                }
            }
    }
}
