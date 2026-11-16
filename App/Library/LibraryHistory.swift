import Foundation
import JutsuCore
import Persistence
import Presentation
import SwiftData
import SwiftUI
import os

nonisolated private let logger = Logger.jutsu("History")

extension AppEnvironment {
    /// Loads the first page of the account's history again, or the next one. Pages with nothing to show are skipped.
    func loadHistory(refresh: Bool) async {
        #if DEBUG
            if SampleHistory.isOn {
                if let request = history.beginLoad(refresh: refresh) {
                    history.receive(SampleHistory.page(in: .documentsDirectory), for: request)
                }
                return
            }
        #endif
        guard let source = generationHistory, var request = history.beginLoad(refresh: refresh) else { return }
        let owner = provider?.owner
        let generation = providerGeneration
        while true {
            do {
                let response = try await source.history(after: request.cursor)
                guard generation == providerGeneration else { return }
                let page = try await store.cacheHistory(response, owner: owner)
                guard history.receive(page, for: request), let next = history.beginLoad(refresh: false) else { return }
                request = next
            } catch {
                if error as? ProviderError == .unauthorized { connection.markNeedsAttention() }
                logger.error("Can't load the history: \(String(describing: error), privacy: .private)")
                history.fail(error, for: request)
                return
            }
        }
    }

    /// Downloads a history item's result and adds it to the library as a finished job; once only.
    func importHistory(_ item: HistoryItem) async throws -> Job {
        let job = Job(importing: item, owner: provider?.owner, importedAt: .now)
        let imported = try await engine.importFinished(job, from: item.outputURL)
        liveJobs.seed([imported])
        await library.add(imported)
        return imported
    }

    /// Whether this connection can list the account's history.
    var historyAvailability: HistoryAvailability {
        #if DEBUG
            if SampleHistory.isOn { return .available }
        #endif
        return HistoryAvailability(connection.state)
    }

    /// Takes and images on this iPhone as cards, newest first: one card per generation, rejected takes left out.
    func deviceRows(images: [SavedImage]) -> [LibraryMediaItem] {
        let videos = library.faces.map { job in
            LibraryMediaItem.video(LibraryItemModel(job: job, isStarred: marks.starred.contains(job.id)))
        }
        return (videos + images.map(LibraryMediaItem.localImage)).sorted { $0.createdAt > $1.createdAt }
    }

    /// The account's history as cards; a video already downloaded shows as the take on this iPhone.
    func historyRows() -> [LibraryMediaItem] {
        LibraryBrowse.historyRows(history).map { row in
            guard case .video(let item) = row, let job = library.job(item.id) else { return row }
            return .video(LibraryItemModel(job: job, isStarred: marks.starred.contains(job.id)))
        }
    }

    /// The images in Documents/Images, newest first; read off the main actor, as the folder grows with every image.
    @concurrent
    static func savedImages(in folder: URL) async -> [SavedImage] {
        let found = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
        var images: [SavedImage] = []
        while let file = found?.nextObject() as? URL {
            guard ServerFileName.imageExtensions.contains(file.pathExtension.lowercased()) else { continue }
            let date =
                (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
            images.append(LibraryBrowse.savedImage(at: file, modified: date))
        }
        return images.sorted { $0.createdAt > $1.createdAt }
    }

    var imagesFolder: URL { OutputSubfolder.images.url(in: layout.defaultOutputFolder) }

    /// Removes takes from the library: their files go, their records go.
    func delete(_ jobs: [Job]) -> UserMessage? {
        let result = LibraryDeletion.delete(
            jobs.map { LibraryItemModel(job: $0) }, files: FileRemover(),
            records: RecordRemover(context: modelContainer.mainContext))
        library.marks.hide(result.deleted)
        return result.message
    }
}

private struct FileRemover: LibraryFiles {
    func fileExists(at url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }
    func remove(_ url: URL) throws { try FileManager.default.removeItem(at: url) }

    /// Into a temporary folder on the file's own volume, so the move is a rename and the system clears what's left.
    func setAside(_ url: URL) throws -> URL {
        let folder = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
        let moved = folder.appending(path: url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: moved)
        return moved
    }

    func putBack(_ setAside: URL, at url: URL) throws { try FileManager.default.moveItem(at: setAside, to: url) }
}

private struct RecordRemover: LibraryRecords {
    let context: ModelContext

    func delete(_ id: UUID) {
        let jobs = FetchDescriptor<JobRecord>(predicate: #Predicate { $0.id == id })
        let materials = FetchDescriptor<MaterialRecord>(predicate: #Predicate { $0.id == id })
        do {
            for record in try context.fetch(jobs) { context.delete(record) }
            for record in try context.fetch(materials) { context.delete(record) }
        } catch {
            logger.error("Can't find the records of a deleted take: \(String(describing: error), privacy: .private)")
        }
    }

    func save() throws { try context.save() }

    /// Puts back the records `delete` marked when a save failed.
    func rollback() { context.rollback() }
}

/// Why the Higgsfield side shows no grid: no account, the first page failing or loading, or nothing made yet.
struct HistoryPlaceholderView: View {
    let placeholder: HistoryPlaceholder
    @Binding var showsAccount: Bool
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Group {
            switch placeholder {
            case .unavailable(let title, let detail):
                ContentUnavailableView {
                    Label(title, systemImage: "person.crop.circle.badge.questionmark")
                } description: {
                    Text(detail)
                } actions: {
                    Button("Open Settings") { showsAccount = true }.buttonStyle(.prominent)
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label(message.title, systemImage: "exclamationmark.icloud")
                } description: {
                    Text(message.message)
                } actions: {
                    Button("Try Again") { Task { await environment.loadHistory(refresh: true) } }
                }
            case .loading:
                ProgressView("Loading your Higgsfield history…").frame(maxWidth: .infinity).padding(.top, 60)
            case .empty:
                ContentUnavailableView(
                    HistoryAvailability.emptyTitle, systemImage: "icloud",
                    description: Text(HistoryAvailability.emptyDetail))
            }
        }
        .padding(.top, 24)
    }
}

/// Under the Higgsfield grid: the next page loading, a button when loading paused, or the end of the history.
struct HistoryFooter: View {
    let shown: Int
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let history = environment.history
        Group {
            if history.isLoading {
                ProgressView()
            } else if case .failed(let message) = history.phase {
                VStack(spacing: 8) {
                    Text(message.title).font(.footnote).foregroundStyle(Theme.muted)
                    Button("Try Again") { Task { await environment.loadHistory(refresh: false) } }
                }
            } else if history.hasMore {
                Button("Load More from Higgsfield") { Task { await environment.loadHistory(refresh: false) } }
                    .buttonStyle(.liquidGlass)
            } else {
                Text(HistoryAvailability.stylesNote).font(.footnote).foregroundStyle(Theme.faint)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}
