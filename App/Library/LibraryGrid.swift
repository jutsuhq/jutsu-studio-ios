import JutsuCore
import Presentation
import QuickLookThumbnailing
import SwiftUI
import UIKit

/// What a card or the viewer can do with an item, shared by Library and Search: download it from Higgsfield, take
/// it back to Create, copy its prompt, delete it from this iPhone.
@Observable
final class LibraryActions {
    var message: UserMessage?
    /// Takes waiting for the delete confirmation: a card's variants, or the one shown.
    var deleting: [Job]?
    /// Items being downloaded, so their cards show a spinner and their buttons wait.
    private(set) var downloading: Set<UUID> = []
    /// Goes up when an image lands in or leaves Documents/Images, so the screens read the folder again.
    private(set) var imagesRevision = 0

    func isDownloading(_ row: LibraryMediaItem) -> Bool { downloading.contains(row.id) }

    /// Brings an item from Higgsfield onto this iPhone, free: a video becomes a take, an image a file in
    /// Documents/Images. Returns the item as it now is; `nil` when it failed, with the reason in `message`.
    @discardableResult
    func download(_ row: LibraryMediaItem, in environment: AppEnvironment) async -> LibraryMediaItem? {
        guard !downloading.contains(row.id) else { return nil }
        downloading.insert(row.id)
        defer { downloading.remove(row.id) }
        do {
            switch row {
            case .video(let item):
                guard let history = item.historyItem else { return row }
                let job = try await environment.importHistory(history)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                return .video(LibraryItemModel(job: job, isStarred: item.isStarred))
            case .remoteImage(let image):
                let file = try await environment.saveToImages(image.outputURL)
                imagesRevision += 1
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                return .localImage(LibraryBrowse.savedImage(at: file, modified: .now))
            case .localImage:
                return row
            }
        } catch {
            message = error.isOutOfSpace ? .notEnoughStorage : UserMessage(error)
            return nil
        }
    }

    /// Opens Create on the item: a video's inputs, prompt and settings; an image as a reference, downloaded first
    /// when it is only on Higgsfield.
    func reuse(_ row: LibraryMediaItem, in environment: AppEnvironment, navigation: NavigationModel) async {
        switch row {
        case .video(let item):
            if let history = item.historyItem {
                navigation.editInputs(
                    Job(importing: history, owner: environment.provider?.owner, importedAt: .now))
            } else {
                navigation.editInputs(item.job)
            }
        case .localImage(let image):
            navigation.useReference(LocalImage(fileURL: image.fileURL))
        case .remoteImage:
            guard case .localImage(let image)? = await download(row, in: environment) else { return }
            navigation.useReference(LocalImage(fileURL: image.fileURL))
        }
    }

    func copyPrompt(_ row: LibraryMediaItem) {
        UIPasteboard.general.string = Self.prompt(of: row)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func deleteImage(_ image: SavedImage) {
        do {
            try FileManager.default.removeItem(at: image.fileURL)
            imagesRevision += 1
        } catch {
            message = UserMessage(error)
        }
    }

    static func prompt(of row: LibraryMediaItem) -> String {
        switch row {
        case .video(let item): item.spec.prompt
        case .localImage(let image): image.prompt
        case .remoteImage(let image): image.prompt
        }
    }

    /// The title of the button that takes an item back to Create.
    static func reuseTitle(_ row: LibraryMediaItem) -> LocalizedStringKey {
        row.isVideo ? "Reuse in Create" : "Use as Reference"
    }

    /// Only on Higgsfield so far, so Download is offered.
    static func isRemote(_ row: LibraryMediaItem) -> Bool {
        switch row {
        case .video(let item): item.needsImport
        case .localImage: false
        case .remoteImage: true
        }
    }
}

extension View {
    /// The alert and the delete confirmation of `actions`.
    func libraryActionAlerts(_ actions: LibraryActions, environment: AppEnvironment) -> some View {
        @Bindable var actions = actions
        return
            self
            .alert($actions.message)
            .confirmationDialog(
                Self.deleteTitle(actions.deleting?.count ?? 1), isPresented: Binding(isPresent: $actions.deleting),
                titleVisibility: .visible, presenting: actions.deleting
            ) { jobs in
                Button("Delete", role: .destructive) { actions.message = environment.delete(jobs) }
            } message: { _ in
                Text("The file is removed from this iPhone and the Files app. Higgsfield keeps its own copy.")
            }
    }

    private static func deleteTitle(_ count: Int) -> String {
        count > 1 ? String(localized: "Delete \(count) variants?") : String(localized: "Delete this take?")
    }
}

/// Library and Search cards, three across on a phone. Each opens on a tap and shows its menu and a preview on a
/// long press; `reachedEnd` runs when the last card shows, to load the next page of the history.
struct LibraryGrid<Menu: View>: View {
    let rows: [LibraryMediaItem]
    let actions: LibraryActions
    let open: (LibraryMediaItem) -> Void
    var reachedEnd: () async -> Void = {}
    @ViewBuilder let menu: (LibraryMediaItem) -> Menu
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        LazyVGrid(columns: Adaptive.tileColumns(sizeClass), spacing: 2) {
            ForEach(rows) { row in
                Button {
                    open(row)
                } label: {
                    LibraryCell(
                        row: row, variants: variants(of: row), isStarred: isStarred(row),
                        isDownloading: actions.isDownloading(row))
                }
                .buttonStyle(.plain)
                .hoverEffect(.lift)
                .contextMenu {
                    menu(row)
                } preview: {
                    LibraryPreview(row: row)
                }
                .draggableFile(file(of: row))
                .task {
                    if row.id == rows.last?.id { await reachedEnd() }
                }
            }
        }
    }

    private func variants(of row: LibraryMediaItem) -> Int {
        guard case .video(let item) = row, !item.needsImport else { return 1 }
        return environment.library.variants(of: item.job).count
    }

    private func isStarred(_ row: LibraryMediaItem) -> Bool {
        guard case .video(let item) = row, !item.needsImport else { return row.isStarred }
        return environment.marks.starred.contains(item.id)
    }

    private func file(of row: LibraryMediaItem) -> URL? {
        switch row {
        case .video(let item): item.outputFile
        case .localImage(let image): image.fileURL
        case .remoteImage: nil
        }
    }
}

/// The menu every card has: download what is only on Higgsfield, reuse, copy the prompt, share, delete.
struct LibraryItemMenu: View {
    let row: LibraryMediaItem
    let actions: LibraryActions
    @Environment(AppEnvironment.self) private var environment
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        if LibraryActions.isRemote(row) {
            Button("Download to iPhone", systemImage: "arrow.down.circle") {
                Task { await actions.download(row, in: environment) }
            }
        }
        Button(LibraryActions.reuseTitle(row), systemImage: row.isVideo ? "slider.horizontal.3" : "person.crop.square")
        {
            Task { await actions.reuse(row, in: environment, navigation: navigation) }
        }
        if !LibraryActions.prompt(of: row).isEmpty {
            Button("Copy Prompt", systemImage: "doc.on.doc") { actions.copyPrompt(row) }
        }
        switch row {
        case .video(let item) where !item.needsImport:
            let marks = environment.marks
            Button(marks.starred.contains(item.id) ? "Unstar" : "Star", systemImage: "star") {
                Task { await marks.toggleStar(item.id) }
            }
            if let url = item.outputFile { ShareLink(item: url) }
            Button("Delete", systemImage: "trash", role: .destructive) {
                actions.deleting = environment.library.variants(of: item.job)
            }
        case .localImage(let image):
            ShareLink(item: image.fileURL)
            Button("Delete", systemImage: "trash", role: .destructive) { actions.deleteImage(image) }
        default:
            EmptyView()
        }
    }
}

/// One card: the picture, what it is, and whether it is starred, has variants or is only on Higgsfield.
struct LibraryCell: View {
    let row: LibraryMediaItem
    var variants = 1
    var isStarred = false
    var isDownloading = false
    @State private var frame: UIImage?
    /// Badges grow with the text size, but only so far: they sit on a thumbnail about 110 pt wide.
    @ScaledMetric(relativeTo: .caption2) private var badgeSize: CGFloat = 9.5

    var body: some View {
        Color.white.opacity(0.06)
            .aspectRatio(9 / 16, contentMode: .fit)
            .overlay { picture }
            .clipped()
            .overlay(alignment: .topLeading) { tag }
            .overlay(alignment: .topTrailing) { corner }
            .overlay(alignment: .bottomLeading) {
                if isStarred {
                    Image(systemName: "star.fill").font(.caption).foregroundStyle(Theme.accent).padding(6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if case .video(let item) = row, !item.needsImport { ViralityBadge(id: item.id).padding(6) }
            }
            .overlay {
                if isDownloading {
                    ProgressView().padding(10).background(.black.opacity(0.55), in: .circle)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder private var picture: some View {
        switch row {
        case .video(let item) where item.outputFile != nil:
            if let shown = frame ?? item.outputFile.flatMap({ Thumbnails.cached($0) }) {
                Image(uiImage: shown).resizable().scaledToFill()
            }
            Color.clear.task(id: item.outputFile) { frame = await Self.frame(of: item.outputFile) }
        case .video(let item):
            RemoteThumb(url: item.thumbnailURL)
        case .localImage(let image):
            RemoteThumb(url: image.fileURL)
        case .remoteImage(let image):
            RemoteThumb(url: image.posterURL)
        }
    }

    private var tag: some View {
        let text: String
        var isDraft = false
        switch row {
        case .video(let item):
            isDraft = item.spec.isDraft
            text = isDraft ? String(localized: "Draft \(item.spec.resolution.rawValue)") : item.modeTag
        case .localImage, .remoteImage:
            text = String(localized: "Image")
        }
        return Text(text)
            .font(.system(size: min(badgeSize, 14), weight: .semibold, design: .monospaced))
            .textCase(.uppercase)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                isDraft ? AnyShapeStyle(.white.opacity(0.88)) : AnyShapeStyle(.black.opacity(0.55)),
                in: .rect(cornerRadius: 6)
            )
            .foregroundStyle(isDraft ? .black : .white)
            .padding(6)
    }

    @ViewBuilder private var corner: some View {
        if LibraryActions.isRemote(row) {
            Image(systemName: "icloud")
                .font(.system(size: min(badgeSize + 1.5, 15), weight: .semibold))
                .padding(5)
                .background(.black.opacity(0.55), in: .circle)
                .padding(6)
        } else if variants > 1 {
            Label("\(variants)", systemImage: "square.stack")
                .font(.system(size: min(badgeSize + 0.5, 14), weight: .semibold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(.black.opacity(0.55), in: .rect(cornerRadius: 6))
                .padding(6)
        }
    }

    private var accessibilityLabel: String {
        var parts: [String]
        switch row {
        case .video(let item):
            parts = [item.accessibilityLabel(now: .now)]
        case .localImage, .remoteImage:
            parts = [String(localized: "Image"), LibraryBrowse.modelName(row), LibraryActions.prompt(of: row)]
            if LibraryActions.isRemote(row) { parts.append(String(localized: "On Higgsfield, not downloaded yet")) }
        }
        if isDownloading { parts.append(String(localized: "Downloading")) }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private static func frame(of url: URL?) async -> UIImage? {
        guard let url else { return nil }
        if let cached = Thumbnails.cached(url) { return cached }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 240, height: 426), scale: 2, representationTypes: .thumbnail)
        guard let image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).uiImage
        else { return nil }
        Thumbnails.store(image, for: url, pixels: 426 * 2)
        return image
    }
}

/// A long press shows the item at its own shape: a video playing muted, an image whole.
struct LibraryPreview: View {
    let row: LibraryMediaItem

    var body: some View {
        switch row {
        case .video(let item):
            ZStack {
                Color.black
                FittedPicture(url: item.thumbnailURL)
                if let url = item.outputFile ?? item.historyItem?.outputURL {
                    LoopingPlayer(url: url, gravity: .resizeAspect)
                }
            }
            .frame(width: 270, height: 480)
        case .localImage(let image):
            FittedPicture(url: image.fileURL).frame(width: 320, height: 400).background(.black)
        case .remoteImage(let image):
            FittedPicture(url: image.posterURL).frame(width: 320, height: 400).background(.black)
        }
    }

}

/// A picture shown whole at the size it is given, decoded for that size; black until it loads.
struct FittedPicture: View {
    let url: URL?
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            let pixels = Int(max(proxy.size.width, proxy.size.height) * displayScale)
            ZStack {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .task(id: url) {
                guard let url, pixels > 0 else { return }
                if let cached = Thumbnails.cached(url) { image = cached }
                if let loaded = await Thumbnails.image(at: url, pixels: pixels), !Task.isCancelled { image = loaded }
            }
        }
    }
}
