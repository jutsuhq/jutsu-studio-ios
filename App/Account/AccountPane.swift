import JutsuCore
import Presentation
import SwiftUI

/// Who is connected, the balance, the plan, and signing out.
struct AccountPane: View {
    @Environment(ConnectionStore.self) private var connection
    @Environment(AppEnvironment.self) private var environment
    @AppStorage(AppSettings.lowCreditThresholdKey) private var lowCreditThreshold = AppSettings
        .defaultLowCreditThreshold

    var body: some View {
        Form {
            if case .account = state { Section { balance } }
            let plans = PlanCard.cards(for: state, capabilities: capabilities)
            if !plans.isEmpty {
                Section {
                    PlanCardsView(cards: plans)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Plan")
                } footer: {
                    Text("Higgsfield reports the plan you're on, its credits and the models it has unlimited.")
                }
            }
            if connection.needsAttention {
                Section {
                    Label(
                        "Sign in again or replace the key to keep generating.", systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(Theme.warning)
                }
            }
            Section {
                ForEach(state.cardRows(capabilities: capabilities)) { row in
                    LabeledContent(row.label, value: row.value)
                        .fontDesign(row.isMonospaced ? .monospaced : nil)
                }
            }
            Section {
                Button("Sign Out", role: .destructive) {
                    Task { await connection.signOut() }
                }
            }
        }
        .settingsPage(.account)
    }

    @ViewBuilder private var balance: some View {
        if case .account(let info) = state {
            VStack(alignment: .leading, spacing: 6) {
                if let warning = LowCreditWarning.text(for: state, threshold: lowCreditThreshold) {
                    Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.warning)
                }
                if let credits = info.credits {
                    let amount = Text("\(credits)").font(.display(44, relativeTo: .title))
                    let unit = Text("cr").font(.title3).foregroundStyle(Theme.muted)
                    Text("\(amount) \(unit)")
                        .accessibilityLabel(plate?.accessibilityLabel ?? "")
                } else {
                    Text("Balance unknown").foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private var plate: AccountPlate? { AccountPlate(connection: state, lowCreditThreshold: 0) }

    private var state: ConnectionState { AccountFixture.state ?? connection.state }
    private var capabilities: Capabilities? { AccountFixture.capabilities ?? environment.capabilities }
}
