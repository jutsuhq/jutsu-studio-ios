import SwiftUI

private nonisolated struct NavigationFocusKey: FocusedValueKey {
    typealias Value = NavigationModel
}

extension FocusedValues {
    /// The navigation of the window in front, for the menu bar's commands.
    nonisolated var navigation: NavigationModel? {
        get { self[NavigationFocusKey.self] }
        set { self[NavigationFocusKey.self] = newValue }
    }
}

/// The iPad menu bar and the ⌘ overlay: the tabs of the window in front. Generate, the deck and the
/// take pager put their keys on their own buttons, which works on iPhone too.
struct NavigationCommands: Commands {
    @FocusedValue(\.navigation) private var navigation

    var body: some Commands {
        CommandGroup(before: .sidebar) {
            tabButton("Create", tab: .create, key: "1")
            tabButton("Queue", tab: .queue, key: "2")
            tabButton("Library", tab: .library, key: "3")
            Divider()
        }
    }

    private func tabButton(_ title: LocalizedStringKey, tab: AppTab, key: KeyEquivalent) -> some View {
        Button(title) { navigation?.tab = tab }
            .keyboardShortcut(key)
            .disabled(navigation == nil)
    }
}
