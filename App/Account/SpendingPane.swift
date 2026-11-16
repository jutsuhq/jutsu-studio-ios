import JutsuCore
import Presentation
import SwiftUI

/// What was charged, the daily cap, and how an account's plan is spent.
struct SpendingPane: View {
    @Environment(ConnectionStore.self) private var connection
    @Environment(AppEnvironment.self) private var environment
    @Environment(LiveJobs.self) private var liveJobs
    @AppStorage(AppSettings.spendCapEnabledKey) private var usdCapOn = AppSettings.defaultSpendCapEnabled
    @AppStorage(AppSettings.spendCapUSDKey) private var usdCap = AppSettings.defaultSpendCapUSD
    @AppStorage(AppSettings.spendCapCreditsEnabledKey) private var creditCapOn = AppSettings
        .defaultSpendCapCreditsEnabled
    @AppStorage(AppSettings.spendCapCreditsKey) private var creditCap = AppSettings.defaultSpendCapCredits
    @AppStorage(AppSettings.useUnlimitedKey) private var usesUnlimited = AppSettings.defaultUseUnlimited
    @AppStorage(AppSettings.lowCreditThresholdKey) private var lowCreditThreshold = AppSettings
        .defaultLowCreditThreshold
    @State private var period = SpendingPeriod.today
    @State private var loadedSpending: LoadedSpending?

    var body: some View {
        Form {
            spendingSection
            capSection
            if state.kind == .account { planSection }
            ResetSection(reset: reset)
        }
        .settingsPage(.spending)
    }

    private var spending: SpendReader { environment.spending }
    private var state: ConnectionState { AccountFixture.state ?? connection.state }

    /// The stored jobs once read; until then, or when they can't be read, the ones this session holds.
    private var spendingSummary: SpendingSummary {
        if let sample = AccountFixture.spending(for: period) { return sample }
        if let loadedSpending, loadedSpending.period == period { return loadedSpending.summary }
        return SpendingSummary(liveJobs.all, images: spending.images.charges, period: period, now: .now)
    }

    private var spendingSection: some View {
        Section("Spending") {
            AdaptivePicker(title: "Period", selection: $period) {
                ForEach(SpendingPeriod.allCases) { Text($0.title).tag($0) }
            }
            let summary = spendingSummary
            LabeledContent("Charged", value: summary.charged.text(in: state.costUnit))
                .font(.system(.body, design: .monospaced))
            LabeledContent("Jobs", value: "\(summary.chargedJobs)")
        }
        .task(id: SpendingInputs(period: period, jobs: liveJobs.stateRevision, images: spending.images.charges)) {
            let period = period
            guard let summary = try? await spending.summary(for: period) else { return }
            loadedSpending = LoadedSpending(period: period, summary: summary)
        }
    }

    private var capSection: some View {
        Section {
            if state.costUnit == .credits {
                Toggle("Daily cap", isOn: $creditCapOn)
                if creditCapOn {
                    Stepper(value: $creditCap, in: 10...100_000, step: 50) {
                        LabeledContent("Credits a day", value: "\(creditCap)")
                    }
                }
            } else {
                Toggle("Daily cap", isOn: $usdCapOn)
                if usdCapOn {
                    Stepper(value: $usdCap, in: 1...10_000, step: 5) {
                        LabeledContent("USD a day", value: usdCap.formatted(.currency(code: "USD")))
                    }
                }
            }
        } footer: {
            Text("Jobs over the cap ask before they start. Failed and rejected jobs are never billed.")
        }
    }

    private var planSection: some View {
        Section {
            Toggle("Use Unlimited when the plan has it", isOn: $usesUnlimited)
            Stepper(value: $lowCreditThreshold, in: 0...10_000, step: 50) {
                LabeledContent("Warn below", value: "\(lowCreditThreshold) cr")
            }
        } header: {
            Text("Plan")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let covered = (AccountFixture.capabilities ?? environment.capabilities)?.unlimitedText {
                    Text("Unlimited covers \(covered).")
                }
                Text("Below this many credits the account shows a warning; 0 turns it off.")
            }
        }
    }

    private func reset() {
        usdCapOn = AppSettings.defaultSpendCapEnabled
        usdCap = AppSettings.defaultSpendCapUSD
        creditCapOn = AppSettings.defaultSpendCapCreditsEnabled
        creditCap = AppSettings.defaultSpendCapCredits
        usesUnlimited = AppSettings.defaultUseUnlimited
        lowCreditThreshold = AppSettings.defaultLowCreditThreshold
    }
}

nonisolated private struct LoadedSpending {
    var period: SpendingPeriod
    var summary: SpendingSummary
}

/// What Spending is read again on.
nonisolated private struct SpendingInputs: Equatable {
    var period: SpendingPeriod
    var jobs: Int
    var images: [ImageCharge]
}
