import Foundation
import JutsuCore
import Persistence
import Presentation
import os

nonisolated private let logger = Logger.jutsu("Library")

/// Every finished take with a file, read from the store rather than from the engine's short list of recent jobs, with
/// a generation's variants folded into one card. The folding is worked out once per change, not on every redraw.
@Observable
final class LibraryModel {
    enum Filter: String, CaseIterable {
        case all = "All", new = "New", starred = "Starred", images = "Images", higgsfield = "Higgsfield"
    }

    let marks = LibraryMarks()
    /// Newest first.
    private(set) var takes: [Job] = []
    /// One card per generation, its newest take as the face, rejected and deleted takes left out.
    private(set) var faces: [Job] = []
    @ObservationIgnored private var variantsByGroup: [UUID: [Job]] = [:]
    @ObservationIgnored private let store: SwiftDataStore

    init(store: SwiftDataStore) {
        self.store = store
        marks.onChange = { [weak self] in self?.rebuild() }
    }

    func load() async {
        do {
            takes = try await store.doneJobs(limit: .max).filter { $0.outputFile != nil }
        } catch {
            logger.error("Can't read the library: \(String(describing: error), privacy: .private)")
        }
        await marks.load(from: store)
    }

    /// A take the engine just finished; only its own marks are read, so verdicts set meanwhile stay.
    func add(_ job: Job) async {
        guard job.state == .done, job.outputFile != nil else { return }
        takes.removeAll { $0.id == job.id }
        takes.insert(job, at: 0)
        await marks.loadMarks(of: job.id)
        rebuild()
    }

    func job(_ id: UUID) -> Job? { takes.first { $0.id == id } }

    /// The take and the other variants of its generation, newest first.
    func variants(of job: Job) -> [Job] {
        marks.groups[job.id].flatMap { variantsByGroup[$0] } ?? [job]
    }

    var unreviewed: [Job] {
        takes.filter { marks.verdict(of: $0.id) == .unreviewed && !marks.hidden.contains($0.id) }
    }

    func cards(_ filter: Filter, query: String) -> [Job] {
        var cards = faces
        switch filter {
        case .all, .images, .higgsfield: break
        case .new: cards = cards.filter { marks.verdict(of: $0.id) == .unreviewed }
        case .starred: cards = cards.filter { marks.starred.contains($0.id) }
        }
        guard !query.isEmpty else { return cards }
        return cards.filter {
            $0.spec.prompt.localizedCaseInsensitiveContains(query)
                || $0.spec.model.title.localizedCaseInsensitiveContains(query)
        }
    }

    private func rebuild() {
        let visible = takes.filter { marks.verdict(of: $0.id) != .rejected && !marks.hidden.contains($0.id) }
        var groups: [UUID: [Job]] = [:]
        var faces: [Job] = []
        for job in visible {
            guard let group = marks.groups[job.id] else {
                faces.append(job)
                continue
            }
            if groups[group] == nil { faces.append(job) }
            groups[group, default: []].append(job)
        }
        variantsByGroup = groups
        self.faces = faces
    }
}
