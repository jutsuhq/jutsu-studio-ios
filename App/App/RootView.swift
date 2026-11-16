import Presentation
import SwiftUI

/// Onboarding until the person is through it, then the tabs.
struct RootView: View {
    @AppStorage("onboarding.finished") private var onboardingFinished = false

    var body: some View {
        if onboardingFinished {
            MainTabs()
        } else {
            OnboardingFlow { onboardingFinished = true }
        }
    }
}

/// One window's tabs: a sidebar when the window is regular width, a tab bar when it is compact. The same `TabView`
/// either way, so folding iPhone Duo or resizing a window keeps every tab's state and scroll position.
struct MainTabs: View {
    @Environment(LiveJobs.self) private var liveJobs
    @Environment(AppEnvironment.self) private var environment
    @State private var navigation = NavigationModel()
    @SceneStorage("tab") private var storedTab = AppTab.create
    @State private var showsAccount = false

    var body: some View {
        TabView(selection: $navigation.tab) {
            Tab("Create", image: "jutsu.spark", value: .create) {
                CreateView(showsAccount: $showsAccount)
            }
            Tab("Queue", image: "jutsu.queue", value: .queue) {
                QueueView(showsAccount: $showsAccount)
            }
            // How many jobs and image requests are in the queue now; nothing when it is empty.
            .badge(queueCount)
            Tab("Library", image: "jutsu.library", value: .library) {
                LibraryView(showsAccount: $showsAccount)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { OfflineBanner() }
        .tabViewStyle(.sidebarAdaptable)
        .minimizesTabBarOnScroll()
        .onChange(of: environment.imageGenerator.runs) {
            environment.liveActivity.update(with: liveJobs, images: environment.imageGenerator.runs)
        }
        // The Live Activity's tap (`RenderActivity.queueURL`).
        .onOpenURL { url in
            guard url.scheme == RenderActivity.queueURL.scheme, let screen = url.host().flatMap(JutsuScreen.init)
            else { return }
            navigation.show(screen)
        }
        .onAppear {
            navigation.tab = storedTab
            #if DEBUG
                if let tab = DebugLaunch.tab { navigation.tab = tab }
                environment.liveActivity.startSample()
            #endif
            takeAppRoutes()
        }
        .onChange(of: navigation.tab) { storedTab = navigation.tab }
        .onChange(of: ScreenRequest.shared.screen) { takeAppRoutes() }
        .onChange(of: environment.navigation.openedTake) { takeAppRoutes() }
        .sheet(isPresented: $showsAccount) {
            AccountView().presentationSizing(.page)
        }
        .environment(\.showAccount) { showsAccount = true }
        .sensoryFeedback(trigger: environment.marks.lastMark) { _, mark in
            switch mark?.kind {
            case .kept?: .success
            case .rejected?: .impact(weight: .medium)
            case .starred?, .unstarred?: .selection
            case nil: nil
            }
        }
        .sensoryFeedback(.warning, trigger: attentionCount) { old, new in new > old }
        .environment(navigation)
        .focusedSceneValue(\.navigation, navigation)
    }

    /// A Shortcut's screen or a notification's take, shown by the first window that sees it.
    private func takeAppRoutes() {
        if let screen = ScreenRequest.shared.screen {
            navigation.show(screen)
            ScreenRequest.shared.screen = nil
        }
        if let take = environment.navigation.takeOpenedTake() { navigation.openTake(take) }
    }

    private var queueCount: Int { liveJobs.activeCount + environment.imageGenerator.activeCount }

    /// The jobs paused for the person, felt when one more is.
    private var attentionCount: Int {
        liveJobs.active.filter { if case .paused = $0.state { true } else { false } }.count
    }
}
