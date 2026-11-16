import Presentation
import SwiftData
import SwiftUI
import TipKit

@main
struct JutsuApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            Group {
                if let environment = appDelegate.environment {
                    RootView()
                        .environment(environment)
                        .environment(environment.connection)
                        .environment(environment.liveJobs)
                        .environment(\.isOnline, environment.network.isOnline)
                        .modelContainer(environment.modelContainer)
                        .task { await environment.start() }
                } else {
                    LibraryFailureView()
                }
            }
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
            // After the first frame: TipKit opens its own store, and a TipView shows once it is configured.
            .task { try? Tips.configure() }
        }
        .commands { NavigationCommands() }
        .onChange(of: phase) { _, phase in
            guard let environment = appDelegate.environment else { return }
            switch phase {
            case .background: Task { await environment.didEnterBackground() }
            case .active: Task { await environment.willEnterForeground() }
            default: break
            }
        }
    }
}

/// Shown when the store can't be opened: the app can't run without it.
private struct LibraryFailureView: View {
    var body: some View {
        ContentUnavailableView(
            "Jutsu can't open its library", systemImage: "externaldrive.badge.exclamationmark",
            description: Text("Free up some space on this iPhone, then open the app again."))
    }
}
