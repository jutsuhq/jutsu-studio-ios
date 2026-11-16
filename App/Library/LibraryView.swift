import JutsuCore
import Presentation
import SwiftUI
import TipKit

/// What was made, in a Photos-style grid: on this iPhone, or everything the Higgsfield account made anywhere. Videos
/// and images share the grid; a tap opens the viewer, which swipes through what the grid shows. Search, a button by the
/// account, opens a field that narrows the grid to the takes whose prompt or model has every word typed ("the one with
/// the rooftop"); it is rarely needed, so it takes no room until then.
struct LibraryView: View {
    @Binding var showsAccount: Bool
    @Environment(AppEnvironment.self) private var environment
    @Environment(NavigationModel.self) private var navigation
    @SceneStorage("library.source") private var source = LibrarySource.device
    @State private var kind = LibraryKind.all
    @State private var filter = LibraryFilter()
    /// Only takes not kept or rejected yet; on this iPhone only.
    @State private var onlyUnreviewed = false
    @State private var query = ""
    @State private var showsSearch = false
    @FocusState private var searchFocused: Bool
    @State private var images: [SavedImage] = []
    @State private var viewing: ViewerRequest?
    @State private var actions = LibraryActions()
    @State private var showsCull = false
    @State private var compareFirst: Job?
    @State private var comparing: TakePair?
    @State private var scoring: ScoreRequest?

    var body: some View {
        // Each is a pass over the whole library: worked out once per redraw.
        let all = source == .device ? environment.deviceRows(images: images) : environment.historyRows()
        let shown = visible(all)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    DisplayTitle(text: "Library")
                    if showsSearch {
                        LibrarySearchBar(query: $query, focused: $searchFocused, rows: all, cancel: closeSearch)
                    }
                    AdaptivePicker(title: "Source", selection: $source) {
                        ForEach(LibrarySource.allCases) { Text($0.title).tag($0) }
                    }
                    KindChips(
                        kind: $kind, counts: filter.counts(all), showsClear: filter.isActive || onlyUnreviewed,
                        clear: clearFilters)
                    if source == .device {
                        let unreviewed = environment.library.unreviewed.count
                        if unreviewed > 0 { ReviewBanner(count: unreviewed) { showsCull = true } }
                        if !shown.isEmpty { TipView(TakeMenuTip()) }
                    }
                    if let compareFirst {
                        Label(
                            "Pick the take to compare with \(LibraryItemModel(job: compareFirst).title)",
                            systemImage: "rectangle.split.2x1"
                        )
                        .font(.footnote)
                        .foregroundStyle(Theme.accent)
                    }
                }
                .padding(.horizontal, 16)
                content(all: all, shown: shown)
            }
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { filterMenu(LibraryFilterOptions(all)) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Search", systemImage: "magnifyingglass") { openSearch() }
                        .keyboardShortcut("f")
                }
                if #available(iOS 26, *) {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                AccountToolbar(showsAccount: $showsAccount)
            }
            .refreshable {
                if source == .device {
                    await environment.library.load()
                    images = await AppEnvironment.savedImages(in: environment.imagesFolder)
                } else {
                    await environment.loadHistory(refresh: true)
                }
            }
            .fullScreenCover(item: $viewing) { MediaViewer(request: $0) }
            .fullScreenCover(isPresented: $showsCull) { CullDeck(takes: environment.library.unreviewed) }
            .sheet(item: $comparing) { CompareView(first: $0.first, second: $0.second) }
            .sheet(item: $scoring) { ScoreVariantsSheet(plan: $0.plan) }
            .libraryActionAlerts(actions, environment: environment)
            .onChange(of: environment.marks.likeFailure) { _, failure in
                if let failure { actions.message = failure }
            }
            .sensoryFeedback(.selection, trigger: source)
            .sensoryFeedback(.selection, trigger: kind)
            .task(id: actions.imagesRevision) {
                images = await AppEnvironment.savedImages(in: environment.imagesFolder)
            }
            .onChange(of: viewing == nil) { _, closed in
                guard closed else { return }
                Task { images = await AppEnvironment.savedImages(in: environment.imagesFolder) }
            }
            #if DEBUG
                .task {
                    if let debugSource = DebugLaunch.source { source = debugSource }
                    if let debugQuery = DebugLaunch.query {
                        query = debugQuery
                        showsSearch = true
                    }
                    guard DebugLaunch.opensFirst else { return }
                    try? await Task.sleep(for: .seconds(1.5))
                    let rows = visible(
                        source == .device ? environment.deviceRows(images: images) : environment.historyRows())
                    if let first = rows.first { open(first, in: rows) }
                }
            #endif
            .task(id: source) {
                if source == .higgsfield, !environment.history.hasLoaded {
                    await environment.loadHistory(refresh: true)
                }
            }
            .onChange(of: source) {
                onlyUnreviewed = false
                filter = filter.cleared
            }
            .onChange(of: navigation.openedTake, initial: true) {
                guard let id = navigation.takeOpenedTake(), let job = environment.library.job(id) else { return }
                source = .device
                let row = LibraryMediaItem.video(LibraryItemModel(job: job))
                viewing = ViewerRequest(rows: [row], first: row.id)
            }
        }
    }

    // MARK: Grid

    @ViewBuilder
    private func content(all: [LibraryMediaItem], shown: [LibraryMediaItem]) -> some View {
        if source == .higgsfield,
            let placeholder = HistoryPlaceholder(
                availability: environment.historyAvailability, history: environment.history,
                isEmpty: all.isEmpty)
        {
            HistoryPlaceholderView(placeholder: placeholder, showsAccount: $showsAccount)
        } else if all.isEmpty {
            ContentUnavailableView(
                "Nothing here yet", systemImage: "square.grid.2x2",
                description: Text(
                    "Videos and images you make land here and in the Files app. To see what your Higgsfield account made elsewhere, switch to Higgsfield."
                )
            )
            .padding(.top, 40)
        } else {
            if shown.isEmpty, isSearching {
                ContentUnavailableView.search(text: query).padding(.top, 24)
            } else if shown.isEmpty {
                ContentUnavailableView {
                    Label("No matches", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Nothing here fits these filters.")
                } actions: {
                    Button("Clear Filters", action: clearFilters)
                }
                .padding(.top, 24)
            } else {
                LibraryGrid(
                    rows: shown, actions: actions, open: { open($0, in: shown) },
                    reachedEnd: { await loadMoreHistory() }
                ) { row in
                    LibraryItemMenu(row: row, actions: actions)
                    localMenu(row)
                }
            }
            if source == .higgsfield { HistoryFooter(shown: shown.count) }
        }
    }

    private var isSearching: Bool { showsSearch && !query.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: Search

    private func openSearch() {
        withAnimation(.snappy) { showsSearch = true }
        searchFocused = true
    }

    private func closeSearch() {
        searchFocused = false
        withAnimation(.snappy) {
            showsSearch = false
            query = ""
        }
    }

    /// The rows the grid shows: the kind, every filter and the search, newest first.
    private func visible(_ all: [LibraryMediaItem]) -> [LibraryMediaItem] {
        let filtered = filter.apply(all, kind: kind)
        let rows = isSearching ? LibraryBrowse.search(query, in: filtered) : filtered
        guard onlyUnreviewed, source == .device else { return rows }
        return rows.filter { row in
            guard case .video(let item) = row else { return false }
            return environment.marks.verdict(of: item.id) == .unreviewed
        }
    }

    private func open(_ row: LibraryMediaItem, in shown: [LibraryMediaItem]) {
        if case .video(let item) = row, !item.needsImport, let first = compareFirst {
            if first.id != item.id { comparing = TakePair(first: first, second: item.job) }
            compareFirst = nil
            return
        }
        viewing = ViewerRequest(rows: pages(of: shown), first: row.id)
    }

    /// The viewer swipes through every take: a card's other variants follow it.
    private func pages(of rows: [LibraryMediaItem]) -> [LibraryMediaItem] {
        rows.flatMap { row -> [LibraryMediaItem] in
            guard case .video(let item) = row, !item.needsImport else { return [row] }
            return environment.library.variants(of: item.job).map { job in
                .video(LibraryItemModel(job: job, isStarred: environment.marks.starred.contains(job.id)))
            }
        }
    }

    private func loadMoreHistory() async {
        let history = environment.history
        guard source == .higgsfield, history.hasMore, !history.isLoading, !history.isWaitingToLoadMore else { return }
        await environment.loadHistory(refresh: false)
    }

    /// Compare and Score Variants, for takes on this iPhone.
    @ViewBuilder
    private func localMenu(_ row: LibraryMediaItem) -> some View {
        if case .video(let item) = row, !item.needsImport {
            Button("Compare With…", systemImage: "rectangle.split.2x1") { compareFirst = item.job }
            let variants = environment.library.variants(of: item.job)
            if variants.count > 1, environment.viralityAvailability != .hidden {
                Button("Score Variants", systemImage: "chart.line.uptrend.xyaxis") {
                    scoring = ScoreRequest(
                        plan: ViralityPlan(
                            variants.map { LibraryItemModel(job: $0) }, owner: environment.provider?.owner))
                }
                .disabled(environment.variantScorer.isRunning)
            }
        }
    }
}

extension LibraryView {
    // MARK: Filters

    private func filterMenu(_ options: LibraryFilterOptions) -> some View {
        let isActive = filter.isActive || onlyUnreviewed
        return Menu {
            Toggle("Starred", systemImage: "star", isOn: $filter.isStarredOnly)
            if source == .device {
                Toggle("Not Reviewed", systemImage: "rectangle.stack", isOn: $onlyUnreviewed)
            }
            if options.shows(.model, in: filter) {
                Picker("Video Model", systemImage: "film", selection: $filter.model) {
                    Text("Any").tag(VideoModel?.none)
                    ForEach(options.models, id: \.self) { Text($0.title).tag(Optional($0)) }
                }
                .pickerStyle(.menu)
            }
            if options.shows(.mode, in: filter) {
                Picker("Mode", systemImage: "wand.and.stars", selection: $filter.mode) {
                    Text("Any").tag(Mode?.none)
                    ForEach(options.modes, id: \.self) { Text($0.title).tag(Optional($0)) }
                }
                .pickerStyle(.menu)
            }
            if options.shows(.imageModel, in: filter) {
                Picker("Image Model", systemImage: "photo", selection: $filter.imageModel) {
                    Text("Any").tag(String?.none)
                    ForEach(options.imageModels, id: \.self) {
                        Text(LibraryBrowse.readableModel($0)).tag(Optional($0))
                    }
                }
                .pickerStyle(.menu)
            }
            if isActive {
                Divider()
                Button("Clear Filters", systemImage: "xmark.circle", action: clearFilters)
            }
        } label: {
            Image(systemName: isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filter")
        .accessibilityValue(isActive ? String(localized: "On") : "")
    }

    private func clearFilters() {
        filter = filter.cleared
        onlyUnreviewed = false
    }
}

/// Videos, images or both, with how many each holds under the current filters; Clear while a filter is on.
private struct KindChips: View {
    @Binding var kind: LibraryKind
    let counts: LibraryKindCounts
    let showsClear: Bool
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(LibraryKind.allCases) { option in
                let isSelected = kind == option
                Button {
                    kind = option
                } label: {
                    HStack(spacing: 5) {
                        Text(option.title)
                        Text("\(counts.count(for: option))").monospacedDigit().foregroundStyle(
                            isSelected ? Theme.ink.opacity(0.6) : Theme.faint)
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.card), in: .capsule)
                    .foregroundStyle(isSelected ? Theme.ink : Theme.text)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Spacer(minLength: 0)
            if showsClear {
                Button("Clear", action: clear).font(.subheadline)
            }
        }
    }
}

/// Takes not kept or rejected yet, and the button that opens the review deck.
private struct ReviewBanner: View {
    let count: Int
    let open: () -> Void

    var body: some View {
        Button {
            open()
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    summary
                    Spacer()
                    capsule
                }
                VStack(alignment: .leading, spacing: 10) {
                    summary
                    capsule
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                LinearGradient(
                    colors: [Theme.signatureViolet.opacity(0.26), Theme.signaturePink.opacity(0.12)],
                    startPoint: .leading, endPoint: .trailing),
                in: .rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }

    private var summary: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.stack").font(.title2).foregroundStyle(Theme.signatureFuchsia)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count) new takes").font(.headline)
                Text("Swipe to keep or reject").font(.subheadline).foregroundStyle(Theme.muted)
            }
        }
    }

    private var capsule: some View {
        Text("Review")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Theme.accent, in: .capsule)
            .foregroundStyle(Theme.ink)
    }
}

struct TakePair: Identifiable {
    let first: Job
    let second: Job
    var id: String { "\(first.id)-\(second.id)" }
}

private struct ScoreRequest: Identifiable {
    let id = UUID()
    let plan: ViralityPlan
}
