import SwiftUI

extension EnvironmentValues {
    /// Whether the device has a network; set at the root from `NetworkStatus`.
    nonisolated var isOnline: Bool {
        get { self[IsOnlineKey.self] }
        set { self[IsOnlineKey.self] = newValue }
    }
}

nonisolated private struct IsOnlineKey: EnvironmentKey {
    static let defaultValue = true
}

/// A strip across the top while the device is offline; nothing otherwise. What failed is asked again once the
/// network is back, so it doesn't offer a retry.
struct OfflineBanner: View {
    @Environment(\.isOnline) private var isOnline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if !isOnline {
                Label("No connection. Jutsu retries when you're back online.", systemImage: "wifi.slash")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Theme.warning)
                    .transition(reduceMotion ? AnyTransition.opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: isOnline)
    }
}
