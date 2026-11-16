import Presentation
import SwiftUI

/// The account's credits and avatar, which open Account.
struct AccountToolbar: ToolbarContent {
    @Binding var showsAccount: Bool
    @Environment(ConnectionStore.self) private var connection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showsAccount = true
            } label: {
                if case .account(let info) = connection.state, let credits = info.credits {
                    Text("\(credits) cr")
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .contentTransition(.numericText(value: Double(credits)))
                        .animation(reduceMotion ? nil : .snappy, value: credits)
                } else {
                    Image(systemName: "person.crop.circle")
                }
            }
            .accessibilityLabel("Account")
            .accessibilityValue(plateLabel)
            .accessibilityShowsLargeContentViewer {
                Label("Account", systemImage: "person.crop.circle")
            }
        }
    }

    /// "Creator Plus plan, 2,596 credits left", what the credits in the button stand for.
    private var plateLabel: String {
        AccountPlate(connection: connection.state, lowCreditThreshold: 0)?.accessibilityLabel ?? ""
    }
}
