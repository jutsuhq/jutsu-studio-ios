import Foundation
import JutsuCore
import Persistence
import SwiftData
import Testing
import os

@Suite struct MaterialCatalogTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "Catalog-\(UUID())")
    private var layout: FileLayout { FileLayout(root: folder, defaultOutputFolder: folder.appending(path: "Media")) }

    private func image(_ name: String = "image") -> SavedImage {
        SavedImage(
            fileURL: folder.appending(path: "\(name).png"), prompt: "known prompt", model: "soul",
            aspectRatio: "16:9", createdAt: Date(timeIntervalSince1970: 1_000))
    }

    private func store() throws -> SwiftDataStore {
        try SwiftDataStore(modelContainer: StoreContainer.make(inMemory: true))
    }

    @Test func imageAndVideoSurviveReopeningWithMetadataStarsAndVersions() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try SwiftDataStore(modelContainer: StoreContainer.make(inMemory: false, layout: layout))
        let saved = image()
        let remote = MaterialRemote(provider: .account, owner: "alice", id: "remote-image")
        var material = try await first.saveImage(
            saved, remote: remote,
            generation: MaterialGeneration(prompt: saved.prompt, model: saved.model, parameters: Data("{}".utf8)),
            inputs: [], variantGroupID: UUID())
        let original = material.reference
        try material.addVersion(
            MaterialVersion(
                fileURL: folder.appending(path: "edit.png"),
                inputs: [MaterialInput(source: original, role: .parent)]))
        material = try await first.saveMaterial(material)
        try await first.setMaterialStarred(true, ids: [material.id])
        var job = makeJob(state: .done)
        job.outputFile = folder.appending(path: "video.mp4")
        try await first.save(job)

        let reopened = try SwiftDataStore(modelContainer: StoreContainer.make(inMemory: false, layout: layout))
        let restored = try #require(try await reopened.material(remote: remote))
        #expect(restored.id == material.id)
        #expect(restored.reference == material.reference)
        #expect(restored.isStarred)
        #expect(restored.versions.count == 2)
        #expect(restored.previousVersions.first?.generation?.parameters == Data("{}".utf8))
        #expect(try await reopened.madeFrom(restored.reference).map(\.source) == [original])
        #expect(try await reopened.material(id: job.id)?.current.video == job)
    }

    @Test func corruptCatalogEntryThrowsWithoutReplacingIt() async throws {
        let catalog = try store()
        let saved = try await catalog.saveImage(image(), remote: nil, generation: nil, inputs: [], variantGroupID: nil)
        let context = ModelContext(catalog.modelContainer)
        let record = try #require(try context.fetch(FetchDescriptor<MaterialRecord>()).first)
        let broken = Data("broken catalog entry".utf8)
        record.setValue(forKey: \.materialData, to: broken)
        try context.save()
        await #expect(throws: (any Error).self) { try await catalog.materials() }
        await #expect(throws: (any Error).self) { try await catalog.saveMaterial(saved) }
        #expect(
            try ModelContext(catalog.modelContainer).fetch(FetchDescriptor<MaterialRecord>()).first?.materialData
                == broken)
    }
}
