import Foundation
import JutsuCore
import Persistence
import Presentation
import os

nonisolated private let logger = Logger.jutsu("Library")

/// Keep, reject and star of every take, read from and written to the library catalog. A take's material has the
/// job's ID.
@Observable
final class LibraryMarks {
    private(set) var culling: [UUID: Culling] = [:]
    private(set) var starred: Set<UUID> = []
    /// Material → its variant group, for folding a generation's variants into one card.
    private(set) var groups: [UUID: UUID] = [:]
    /// Takes deleted this session, hidden before the job list catches up.
    private(set) var hidden: Set<UUID> = []
    /// Virality Predictor scores by take.
    private(set) var scores: [UUID: ViralityScore] = [:]
    @ObservationIgnored private var store: SwiftDataStore?
    /// The star is also the take's like on Higgsfield when the connected account ran it.
    @ObservationIgnored private(set) var likes: (any GenerationLikes)?
    @ObservationIgnored private var starring = LibraryStarring(likes: nil, owner: nil)
    @ObservationIgnored var job: (UUID) -> Job? = { _ in nil }
    /// Why the last like didn't reach Higgsfield; the star was put back.
    var likeFailure: UserMessage?
    /// The last mark set here, for the haptic that answers it.
    private(set) var lastMark: LibraryMark?

    /// Called after every change that can move a take between cards.
    @ObservationIgnored var onChange: () -> Void = {}
    /// The last verdicts, newest last, so a cull can be taken back.
    @ObservationIgnored private var undoStack: [(id: UUID, previous: Culling)] = []

    func load(from store: SwiftDataStore) async {
        self.store = store
        do {
            let materials = try await store.materials()
            culling = Dictionary(materials.map { ($0.id, $0.current.culling) }, uniquingKeysWith: { first, _ in first })
            starred = Set(materials.filter(\.isStarred).map(\.id))
            scores = Dictionary(
                materials.compactMap { material in material.current.video?.virality.map { (material.id, $0) } },
                uniquingKeysWith: { first, _ in first })
            groups = Dictionary(
                materials.compactMap { material in material.variantGroupID.map { (material.id, $0) } },
                uniquingKeysWith: { first, _ in first })
            onChange()
        } catch {
            logger.error("Can't read the library: \(String(describing: error), privacy: .private)")
        }
    }

    /// One take's marks, for a take that just finished; marks already set here win over what the store has.
    func loadMarks(of id: UUID) async {
        guard let store, let material = try? await store.material(id: id) else { return }
        if culling[id] == nil { culling[id] = material.current.culling }
        if material.isStarred { starred.insert(id) }
        if let group = material.variantGroupID { groups[id] = group }
        if let score = material.current.video?.virality { scores[id] = score }
        onChange()
    }

    func verdict(of id: UUID) -> Culling { culling[id] ?? .unreviewed }

    func hide(_ ids: Set<UUID>) {
        hidden.formUnion(ids)
        onChange()
    }

    func useLikes(_ likes: (any GenerationLikes)?, owner: String?) {
        self.likes = likes
        starring = LibraryStarring(likes: likes, owner: owner)
    }

    func setScore(_ score: ViralityScore, for id: UUID) { scores[id] = score }

    /// Rejected takes are hidden, never deleted.
    func set(_ verdict: Culling, for id: UUID) async {
        let previous = self.verdict(of: id)
        culling[id] = verdict
        undoStack.append((id, previous))
        if verdict == .kept {
            lastMark = LibraryMark(kind: .kept)
        } else if verdict == .rejected {
            lastMark = LibraryMark(kind: .rejected)
        }
        onChange()
        await write(verdict, for: id)
    }

    func undo() async {
        guard let last = undoStack.popLast() else { return }
        culling[last.id] = last.previous
        onChange()
        await write(last.previous, for: last.id)
    }

    func toggleStar(_ id: UUID) async {
        let isStarred = !starred.contains(id)
        lastMark = LibraryMark(kind: isStarred ? .starred : .unstarred)
        await setStar(isStarred, id)
        guard let job = job(id) else { return }
        let item = LibraryItemModel(job: job)
        guard starring.syncsLike(item), let likeID = item.likeID, let likes else { return }
        do {
            try await likes.setLiked(likeID, isStarred)
        } catch {
            await setStar(!isStarred, id)
            likeFailure = .likeNotSaved(error)
        }
    }

    private func setStar(_ isStarred: Bool, _ id: UUID) async {
        if isStarred { starred.insert(id) } else { starred.remove(id) }
        do {
            try await store?.setMaterialStarred(isStarred, ids: [id])
        } catch {
            // Shown as it is stored, so a star that wasn't saved doesn't look kept until the next launch.
            if isStarred { starred.remove(id) } else { starred.insert(id) }
            logger.error("Can't save a star: \(String(describing: error), privacy: .private)")
        }
    }

    private func write(_ verdict: Culling, for id: UUID) async {
        guard let store else { return }
        do {
            guard let material = try await store.material(id: id) else {
                logger.error("A verdict for a take without a library record wasn't saved")
                return
            }
            try await store.setCulling([material.reference: verdict])
        } catch {
            logger.error("Can't save a verdict: \(String(describing: error), privacy: .private)")
        }
    }
}

/// A mark set in the library, for the haptic that answers it; each one is new even when the kind repeats.
struct LibraryMark: Equatable {
    enum Kind { case kept, rejected, starred, unstarred }
    let kind: Kind
    let id = UUID()
}
