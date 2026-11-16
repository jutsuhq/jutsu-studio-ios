import JutsuCore
import Presentation
import SwiftUI

/// The items a viewer pages through and the one it opens on.
struct ViewerRequest: Identifiable {
    let id = UUID()
    let rows: [LibraryMediaItem]
    let first: UUID
}

/// Library and Search items full screen, swiped through like Photos; ← and → on a keyboard. A take on this iPhone
/// opens in its result view, an item still on Higgsfield streams from there until it is downloaded.
struct MediaViewer: View {
    @State private var rows: [LibraryMediaItem]
    @State private var selection: UUID?
    @State private var actions = LibraryActions()
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var viewerID = UUID()

    init(request: ViewerRequest) {
        _rows = State(initialValue: request.rows)
        _selection = State(initialValue: request.first)
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(rows) { row in
                page(row, isActive: selection == row.id).tag(Optional(row.id))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(.black)
        .ignoresSafeArea()
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(.leftArrow) { step(-1) }
        .onKeyPress(.rightArrow) { step(1) }
        .onAppear { isFocused = true }
        .environment(actions)
        .environment(\.viewer, ViewerActions(id: viewerID, close: { dismiss() }, replace: { replace($0) }))
        .libraryActionAlerts(actions, environment: environment)
    }

    @ViewBuilder
    private func page(_ row: LibraryMediaItem, isActive: Bool) -> some View {
        switch row {
        case .video(let item) where !item.needsImport:
            ResultView(job: item.job, isActive: isActive)
        default:
            RemotePage(row: row, isActive: isActive)
        }
    }

    /// A downloaded item takes the place of its Higgsfield one, under the same ID, so the page stays.
    private func replace(_ row: LibraryMediaItem) {
        guard let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
        rows[index] = row
    }

    private func step(_ offset: Int) -> KeyPress.Result {
        guard let index = rows.firstIndex(where: { $0.id == selection }), rows.indices.contains(index + offset) else {
            return .ignored
        }
        withAnimation(.unlessReduceMotion()) { selection = rows[index + offset].id }
        return .handled
    }
}

/// What a page can ask of the viewer it is in. Equal for the life of one viewer, so a new body of the viewer doesn't
/// invalidate every page that reads it, as closures in the environment would.
struct ViewerActions: Equatable {
    let id: UUID
    /// Closes the viewer, for an action that leaves it, such as Reuse in Create.
    let close: @MainActor () -> Void
    /// Puts the downloaded form of an item in its place in the viewer.
    let replace: @MainActor (LibraryMediaItem) -> Void

    static let none = ViewerActions(id: UUID(), close: {}, replace: { _ in })

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

extension EnvironmentValues {
    @Entry var viewer = ViewerActions.none
}

/// An image, or a video still on Higgsfield, full screen: the picture whole, the video streaming while its page
/// shows, what made it and what can be done with it.
private struct RemotePage: View {
    let row: LibraryMediaItem
    let isActive: Bool
    @Environment(AppEnvironment.self) private var environment
    @Environment(NavigationModel.self) private var navigation
    @Environment(LibraryActions.self) private var actions
    @Environment(\.viewer) private var viewer
    @State private var showsInfo = false

    var body: some View {
        ZStack {
            Color.black
            FittedPicture(url: pictureURL)
            if isActive, case .video(let item) = row, let url = item.historyItem?.outputURL {
                LoopingPlayer(url: url, isMuted: false, gravity: .resizeAspect)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.62)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            ViewerTopBar(row: row, showsInfo: $showsInfo) {
                if case .localImage(let image) = row {
                    ShareLink(item: image.fileURL) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Share")
                        .buttonStyle(.liquidGlass)
                }
            }
        }
        .overlay(alignment: .bottom) { bottomBar }
        .sheet(isPresented: $showsInfo) { LibraryInfoSheet(row: row) }
        #if DEBUG
            .task {
                if isActive, DebugLaunch.showsInfo {
                    try? await Task.sleep(for: .seconds(1))
                    showsInfo = true
                }
            }
        #endif
    }

    private var pictureURL: URL? {
        switch row {
        case .video(let item): item.thumbnailURL
        case .localImage(let image): image.fileURL
        case .remoteImage(let image): image.outputURL
        }
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewerCaption(row: row) { showsInfo = true }
            HStack(spacing: 12) {
                if LibraryActions.isRemote(row) {
                    Button {
                        Task {
                            if let local = await actions.download(row, in: environment) { viewer.replace(local) }
                        }
                    } label: {
                        if actions.isDownloading(row) {
                            ProgressView()
                        } else {
                            Label("Download", systemImage: "arrow.down.circle")
                        }
                    }
                    .buttonStyle(.liquidGlass)
                    .controlSize(.large)
                    .disabled(actions.isDownloading(row))
                    .accessibilityHint("Saves it on this iPhone for free")
                }
                Button {
                    Task {
                        await actions.reuse(row, in: environment, navigation: navigation)
                        if actions.message == nil { viewer.close() }
                    }
                } label: {
                    Label(LibraryActions.reuseTitle(row), systemImage: "arrow.uturn.backward").frame(
                        maxWidth: .infinity)
                }
                .buttonStyle(.prominent)
                .controlSize(.large)
                .disabled(actions.isDownloading(row))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

/// Close, what the item is, its details and an optional trailing button, over the picture.
struct ViewerTopBar<Trailing: View>: View {
    let row: LibraryMediaItem
    @Binding var showsInfo: Bool
    @ViewBuilder var trailing: Trailing
    @Environment(\.viewer) private var viewer

    var body: some View {
        HStack {
            Button {
                viewer.close()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.liquidGlass)
            .accessibilityLabel("Close")
            .keyboardShortcut(.cancelAction)
            Spacer()
            VStack(spacing: 2) {
                Text(LibraryBrowse.modelName(row)).font(.headline).lineLimit(1)
                Text(Self.subtitle(row)).font(.eyebrow).textCase(.uppercase).foregroundStyle(Theme.muted)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer()
            HStack(spacing: 8) {
                trailing
                Button {
                    showsInfo = true
                } label: {
                    Image(systemName: "info")
                }
                .buttonStyle(.liquidGlass)
                .accessibilityLabel("Details")
            }
        }
        .padding(.horizontal)
    }

    /// "Motion · 3 days ago", "Image · On Higgsfield".
    static func subtitle(_ row: LibraryMediaItem) -> String {
        let kind: String
        switch row {
        case .video(let item): kind = item.modeTag
        case .localImage, .remoteImage: kind = String(localized: "Image")
        }
        let date = row.createdAt.formatted(.relative(presentation: .named))
        return "\(kind) · \(date)"
    }
}

/// The settings in one line and the start of the prompt; a tap shows them all.
struct ViewerCaption: View {
    let row: LibraryMediaItem
    let showDetails: () -> Void

    var body: some View {
        Button(action: showDetails) {
            VStack(alignment: .leading, spacing: 6) {
                Text(facts)
                    .font(.eyebrow)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.75))
                let prompt = LibraryActions.prompt(of: row)
                if !prompt.isEmpty {
                    Text(prompt).font(.subheadline).lineLimit(2).multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the whole prompt and the settings")
    }

    private var facts: String {
        LibraryItemDetails(row, isOnDevice: !LibraryActions.isRemote(row)).summary
    }
}

/// Everything known about an item: the whole prompt, which can be copied, and each setting; with the action that
/// takes it back to Create.
struct LibraryInfoSheet: View {
    let row: LibraryMediaItem
    @Environment(AppEnvironment.self) private var environment
    @Environment(NavigationModel.self) private var navigation
    @Environment(LibraryActions.self) private var actions
    @Environment(\.viewer) private var viewer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let details = LibraryItemDetails(row, isOnDevice: !LibraryActions.isRemote(row))
        NavigationStack {
            List {
                if !details.prompt.isEmpty {
                    Section("Prompt") {
                        Text(details.prompt).textSelection(.enabled)
                        Button("Copy Prompt", systemImage: "doc.on.doc") { actions.copyPrompt(row) }
                    }
                }
                Section("Settings") {
                    ForEach(details.facts) { fact in
                        LabeledContent(fact.title, value: fact.value)
                    }
                }
                Section {
                    Button(LibraryActions.reuseTitle(row), systemImage: "arrow.uturn.backward") {
                        dismiss()
                        Task {
                            await actions.reuse(row, in: environment, navigation: navigation)
                            if actions.message == nil { viewer.close() }
                        }
                    }
                } footer: {
                    Text(
                        row.isVideo
                            ? "Create opens with this take's inputs, prompt and settings, ready to run again."
                            : "Create opens with this image as a reference.")
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .closeButton()
        }
        .presentationDetents([.medium, .large])
    }
}
