import Foundation
import JutsuCore
import SwiftData

extension SwiftDataStore {
    /// History refreshes use the same persistent identities as locally generated and downloaded materials.
    public func cacheHistory(_ page: HistoryPage, owner: String?) throws -> HistoryPage {
        do {
            var page = page
            for index in page.items.indices {
                var item = page.items[index]
                let remote = MaterialRemote(provider: .account, owner: owner, id: item.id)
                let key = remote.key
                let running = try modelContext.fetch(
                    FetchDescriptor<JobRecord>(predicate: #Predicate { $0.remoteKey == key })
                ).first
                item.jobID = try material(remote: remote)?.id ?? running?.id ?? item.jobID
                let job = Job(importing: item, owner: owner, importedAt: item.createdAt)
                let generation = MaterialGeneration(prompt: item.prompt, model: item.model.rawValue)
                let version = MaterialVersion(
                    id: item.jobID, createdAt: item.createdAt, remoteURL: item.outputURL,
                    generation: generation, video: job)
                let saved = try upsertMaterial(
                    Material(
                        id: item.jobID, kind: .video, origin: .higgsfield,
                        remote: remote, createdAt: item.createdAt, isStarred: item.isLiked, version: version))
                try materialRecord(id: saved.id)?.isStarred = item.isLiked
                item.jobID = saved.id
                page.items[index] = item
            }
            for index in page.images.indices {
                var item = page.images[index]
                let remote = MaterialRemote(provider: .account, owner: owner, id: item.id)
                item.jobID = try material(remote: remote)?.id ?? item.jobID
                let version = MaterialVersion(
                    id: item.jobID, createdAt: item.createdAt, remoteURL: item.outputURL,
                    generation: MaterialGeneration(prompt: item.prompt, model: item.model),
                    aspectRatio: item.aspectRatio,
                    pixelSize: item.pixelSize)
                let saved = try upsertMaterial(
                    Material(
                        id: item.jobID, kind: .image, origin: .higgsfield,
                        remote: remote, createdAt: item.createdAt, isStarred: item.isLiked, version: version))
                try materialRecord(id: saved.id)?.isStarred = item.isLiked
                item.jobID = saved.id
                page.images[index] = item
            }
            try modelContext.save()
            return page
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Register an image and its real inputs together, retaining file-only imports without generation metadata.
    @discardableResult
    public func saveImage(
        _ image: SavedImage, remote: MaterialRemote?, generation: MaterialGeneration?,
        inputs: [LocalImage], variantGroupID: UUID?
    ) throws -> Material {
        do {
            let relations = try inputs.enumerated().map { offset, input in
                MaterialInput(
                    source: try inputMaterial(
                        file: input.fileURL, kind: .image,
                        bookmark: input.bookmark, reference: input.material), role: .reference, position: offset)
            }
            let version = MaterialVersion(
                id: image.id, createdAt: image.createdAt, fileURL: image.fileURL,
                remoteURL: image.remoteURL, generation: generation, inputs: relations, aspectRatio: image.aspectRatio)
            let saved = try upsertMaterial(
                Material(
                    id: image.id, kind: .image,
                    origin: remote == nil ? .local : .higgsfield, remote: remote, createdAt: image.createdAt,
                    isStarred: image.isStarred, variantGroupID: variantGroupID, version: version))
            try modelContext.save()
            return saved
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
