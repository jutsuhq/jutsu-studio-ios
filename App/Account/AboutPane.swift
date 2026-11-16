import Presentation
import SwiftUI

struct AboutPane: View {
    var body: some View {
        Form {
            Section {
                Text(AboutContent.versionText(info: Bundle.main.infoDictionary))
                if let repository = AboutContent.repository {
                    Link("Source Code", destination: repository)
                }
            } footer: {
                Text("Jutsu · open source · no telemetry. Unofficial, not affiliated with Higgsfield AI.")
            }
            Section("License") {
                Text(AboutContent.license)
                Text(AboutContent.fontCredit).foregroundStyle(Theme.muted)
            }
        }
        .settingsPage(.about)
    }
}
