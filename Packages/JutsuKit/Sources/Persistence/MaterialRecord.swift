import Foundation
import JutsuCore
import SwiftData

@Model
public final class MaterialRecord {
    #Index<MaterialRecord>([\.remoteKey], [\.filePath], [\.variantGroupID], [\.createdAt])

    @Attribute(.unique) public private(set) var id: UUID
    public private(set) var createdAt: Date
    public private(set) var remoteKey: String?
    public private(set) var filePath: String?
    /// Stored apart from `materialData` so a group's members can be fetched together.
    public private(set) var variantGroupID: UUID?
    public private(set) var materialData: Data
    public var isStarred: Bool

    public init(_ material: Material) throws {
        id = material.id
        createdAt = material.createdAt
        remoteKey = material.remote?.key
        filePath = material.current.fileURL?.absoluteString
        variantGroupID = material.variantGroupID
        materialData = try JSONEncoder().encode(material)
        isStarred = material.isStarred
    }

    public func material() throws -> Material {
        var material = try JSONDecoder().decode(Material.self, from: materialData)
        guard material.id == id, Set(material.versions.map(\.id)).count == material.versions.count else {
            throw MaterialError.invalidRecord
        }
        material.isStarred = isStarred
        return material
    }

    /// Moves the stored file paths onto a moved container (`ContainerRelocation`).
    func relocate(_ rebase: PathRebase) {
        let data = rebase(materialData)
        if data != materialData { materialData = data }
        filePath = filePath.map { rebase($0) }
    }

    public func update(_ material: Material, updateStar: Bool = true) throws {
        guard material.id == id else { throw MaterialError.invalidRecord }
        materialData = try JSONEncoder().encode(material)
        createdAt = material.createdAt
        remoteKey = material.remote?.key
        filePath = material.current.fileURL?.absoluteString
        variantGroupID = material.variantGroupID
        if updateStar { isStarred = material.isStarred }
    }
}
