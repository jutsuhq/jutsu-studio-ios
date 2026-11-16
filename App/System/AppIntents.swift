import AppIntents
import Observation

/// The screens Shortcuts and Siri can open.
enum JutsuScreen: String, AppEnum {
    case create, queue, library

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Screen"
    static let caseDisplayRepresentations: [JutsuScreen: DisplayRepresentation] = [
        .create: "Create", .queue: "Queue", .library: "Library",
    ]
}

/// Opens Jutsu on a screen. The tabs show it as soon as `ScreenRequest` has it, whether Jutsu was in front or not.
struct OpenScreenIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Jutsu"
    static let openAppWhenRun = true

    @Parameter(title: "Screen") var screen: JutsuScreen

    @MainActor
    func perform() async throws -> some IntentResult {
        ScreenRequest.shared.screen = screen
        return .result()
    }
}

/// The screen Open Jutsu asked for, until the tabs show it.
@MainActor @Observable
final class ScreenRequest {
    static let shared = ScreenRequest()
    var screen: JutsuScreen?
}

struct JutsuShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenScreenIntent(), phrases: ["Open \(.applicationName)", "Show my \(.applicationName) queue"],
            shortTitle: "Open Jutsu", systemImageName: "sparkles")
    }
}
