import Foundation
import JutsuCore
import Presentation
import SwiftUI

/// References › Your Higgsfield: the account's elements (its characters, environments and props), the images it
/// uploaded, and the character sheets made in this app, as grids. A tap downloads the pick once and adds it.
struct HiggsfieldReferencesSheet: View {
    /// How many more references the form takes.
    let room: Int
    let add: ([LocalImage]) -> Void
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var source = Source.elements
    @State private var uploads: PagedFeed<UploadedFile>?
    @State private var loading: String?
    @State private var showsCreate = false
    @State private var message: UserMessage?
    @ScaledMetric(relativeTo: .caption) private var tileWidth: CGFloat = 104

    private enum Source: Hashable { case elements, uploads, sheets }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if sources.count > 1 {
                        AdaptivePicker(title: "Show", selection: $source) {
                            ForEach(sources, id: \.self) { Text(title(of: $0)).tag($0) }
                        }
                    }
                    switch source {
                    case .elements: elementsGrid
                    case .uploads: uploadsGrid
                    case .sheets: sheetsGrid
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Your Higgsfield")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if environment.characterMaker != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Create Character", systemImage: "person.badge.plus") { showsCreate = true }
                    }
                }
            }
            .closeButton()
            .sheet(isPresented: $showsCreate) { CreateCharacterSheet() }
            .alert($message)
        }
        .task(id: environment.providerGeneration) {
            uploads = environment.accountUploads.map { source in
                PagedFeed(failureTitle: String(localized: "Can't load your uploads")) { cursor in
                    let page = try await source.uploads(.image, after: cursor)
                    return (page.items, page.nextCursor)
                }
            }
            if environment.accountElements == nil, uploads != nil { source = .uploads }
        }
        // On the scroll view, not on a grid's items: an empty grid has none, and its first page would never load.
        .task(id: LoadKey(source: source, hasUploads: uploads != nil)) {
            switch source {
            case .elements: await environment.accountElements?.loadIfNeeded()
            case .uploads: await uploads?.loadIfNeeded()
            case .sheets: break
            }
        }
    }

    private struct LoadKey: Hashable {
        let source: Source
        let hasUploads: Bool
    }

    private var sources: [Source] {
        var sources: [Source] = []
        if environment.accountElements != nil { sources.append(.elements) }
        if environment.accountUploads != nil { sources.append(.uploads) }
        if !environment.madeCharacterSheets.isEmpty { sources.append(.sheets) }
        return sources
    }

    private func title(of source: Source) -> LocalizedStringKey {
        switch source {
        case .elements: "Elements"
        case .uploads: "Uploads"
        case .sheets: "Made Here"
        }
    }

    private var columns: [GridItem] { [GridItem(.adaptive(minimum: tileWidth), spacing: 10)] }

    // MARK: Elements

    @ViewBuilder private var elementsGrid: some View {
        if let elements = environment.accountElements {
            if let reason = elements.unavailableReason {
                ContentUnavailableView(reason, systemImage: "clock")
            } else {
                AdaptivePicker(title: "Category", selection: Bindable(elements).category) {
                    Text("All").tag(ElementCategory?.none)
                    ForEach(ElementCategory.allCases) { Text($0.title).tag(Optional($0)) }
                }
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(elements.current) { element in
                        tile(
                            id: element.id, thumbnail: element.thumbnailURL,
                            title: element.name.isEmpty ? String(localized: "Untitled") : element.name,
                            detail: element.category?.title
                        ) {
                            try await pick(element, from: elements)
                        }
                        .onAppear {
                            if element.id == elements.current.last?.id { Task { await elements.loadMore() } }
                        }
                    }
                }
                footer(
                    isLoading: elements.isLoading, failure: elements.failure,
                    isEmpty: elements.hasLoaded && elements.current.isEmpty,
                    empty: ContentUnavailableView(
                        "No elements yet", systemImage: "person.crop.square",
                        description: Text("Characters, environments and props saved on higgsfield.ai appear here.")),
                    retry: { await elements.loadMore() })
            }
        }
    }

    /// The element's images, as many as fit; the rest are left out.
    private func pick(_ element: AccountElement, from elements: AccountElementsModel) async throws -> [LocalImage] {
        let full = try await elements.withImages(element)
        if case .unavailable(let reason) = ElementPick.of(full, limit: room) {
            throw ProviderError.validation(field: nil, message: reason)
        }
        return Array(try await environment.downloadElement(full, from: elements).prefix(room))
    }

    // MARK: Uploads

    @ViewBuilder private var uploadsGrid: some View {
        if let uploads {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(uploads.items) { file in
                    tile(id: file.id, thumbnail: file.previewURL, title: nil, detail: nil) {
                        [try await environment.downloadUpload(file)]
                    }
                    .onAppear {
                        if file.id == uploads.items.last?.id { Task { await uploads.loadMore() } }
                    }
                }
            }
            footer(
                isLoading: uploads.isLoading, failure: uploads.failure,
                isEmpty: uploads.hasLoaded && uploads.items.isEmpty,
                empty: ContentUnavailableView(
                    "No uploads yet", systemImage: "photo.on.rectangle",
                    description: Text("Images sent from this app or higgsfield.ai appear here.")),
                retry: { await uploads.loadMore() })
        }
    }

    // MARK: Character sheets

    private var sheetsGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(environment.madeCharacterSheets) { sheet in
                tile(
                    id: sheet.id, thumbnail: sheet.thumbnailURL ?? sheet.fileURL ?? sheet.imageURL, title: nil,
                    detail: nil
                ) {
                    [try await environment.downloadSheet(sheet)]
                }
            }
        }
    }

    // MARK: Parts

    /// A spinner while a page loads, the failure with a retry, or what an empty list says.
    @ViewBuilder private func footer(
        isLoading: Bool, failure: UserMessage?, isEmpty: Bool, empty: some View, retry: @escaping () async -> Void
    ) -> some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
        } else if let failure {
            ContentUnavailableView {
                Label(failure.title, systemImage: "exclamationmark.triangle")
            } description: {
                Text(failure.message)
            } actions: {
                Button("Try Again") { Task { await retry() } }.buttonStyle(.liquidGlass)
            }
        } else if isEmpty {
            empty
        }
    }

    private func tile(
        id: String, thumbnail: URL?, title: String?, detail: String?,
        load: @escaping () async throws -> [LocalImage]
    ) -> some View {
        Button {
            loading = id
            Task {
                defer { loading = nil }
                do {
                    add(try await load())
                    dismiss()
                } catch {
                    message = UserMessage(error)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Theme.card
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { RemoteThumb(url: thumbnail) }
                    .clipShape(.rect(cornerRadius: 14))
                    .overlay { if loading == id { ProgressView() } }
                    .overlay(alignment: .bottomLeading) {
                        if let detail {
                            Text(detail).font(.eyebrow).lineLimit(1)
                                .padding(4).background(.black.opacity(0.55), in: .rect(cornerRadius: 6))
                                .padding(4)
                        }
                    }
                if let title {
                    Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(loading != nil || room <= 0)
        .accessibilityLabel(title ?? String(localized: "Image"))
        .accessibilityHint("Adds it as a reference")
    }
}
