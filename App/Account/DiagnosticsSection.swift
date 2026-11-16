import SwiftUI

/// The crash, hang and performance reports iOS handed the app, to send to support from the share sheet.
struct DiagnosticsSection: View {
    @State private var files: [URL] = []

    var body: some View {
        Section {
            if files.isEmpty {
                Text("No reports yet. iOS delivers them about once a day.").foregroundStyle(Theme.muted)
            } else {
                ShareLink("Share Diagnostics", items: files)
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            Text("Reports from iOS, kept on this device. Nothing is sent unless you share them.")
        }
        .task { files = await Diagnostics.savedFiles() }
    }
}
