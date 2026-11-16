import JutsuCore
import Presentation
import SwiftUI

/// Settings: the account on top, then a page per topic. A sidebar beside the page on a wide window (iPad, the open
/// iPhone Duo), a list that pushes the page on a narrow one. Search narrows the list to pages whose settings match.
struct AccountView: View {
    @Environment(ConnectionStore.self) private var connection
    @State private var pane: SettingsPane?
    @State private var compactColumn = NavigationSplitViewColumn.sidebar
    @State private var query = ""

    var body: some View {
        if connection.state.isConnected || AccountFixture.state != nil {
            NavigationSplitView(preferredCompactColumn: $compactColumn) {
                SettingsSidebar(selection: $pane, query: query)
                    .navigationTitle("Settings")
                    .searchable(text: $query, placement: .sidebar)
                    .closeButton()
            } detail: {
                (pane ?? .account).page
            }
        } else {
            NavigationStack {
                ConnectView()
                    .navigationTitle("Account")
                    .navigationBarTitleDisplayMode(.inline)
                    .closeButton()
            }
        }
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsPane?
    let query: String

    var body: some View {
        List(selection: $selection) {
            if query.isEmpty {
                Section {
                    NavigationLink(value: SettingsPane.account) { AccountRow() }
                }
            }
            Section {
                ForEach(panes) { pane in
                    NavigationLink(value: pane) {
                        Label {
                            Text(pane.title)
                        } icon: {
                            Image(systemName: pane.systemImage)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { OfflineBanner() }
        .overlay {
            if panes.isEmpty { ContentUnavailableView.search(text: query) }
        }
    }

    /// Every page but the account while not searching, which has its own row on top.
    private var panes: [SettingsPane] {
        SettingsPane.allCases.filter { query.isEmpty ? $0 != .account : $0.matches(query) }
    }
}

/// The account in the sidebar: who is signed in and the balance, as Settings shows the Apple Account.
private struct AccountRow: View {
    @Environment(ConnectionStore.self) private var connection
    @AppStorage(AppSettings.lowCreditThresholdKey) private var lowCreditThreshold = AppSettings
        .defaultLowCreditThreshold

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch AccountFixture.state ?? connection.state {
            case .account(let info):
                Text(info.email ?? info.name ?? String(localized: "Higgsfield account")).font(.headline)
                if let credits = info.credits {
                    Text("\(credits) cr").foregroundStyle(Theme.muted).monospacedDigit()
                }
            case .apiKey:
                Text("API key").font(.headline)
            case .none:
                EmptyView()
            }
            if let warning = LowCreditWarning.text(for: connection.state, threshold: lowCreditThreshold) {
                Label(warning, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.warning)
            } else if connection.needsAttention {
                Label("Sign in again", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(Theme.warning)
            }
        }
        .padding(.vertical, 4)
    }
}
