import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.jutsustudio", category: "Persistence")

/// The store's models. A change that isn't lightweight freezes these as nested types of this schema, adds a
/// `SchemaV2` with the new ones and a `MigrationStage` to `StoreMigrationPlan`.
public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [JobRecord.self, MaterialRecord.self, AssetRecord.self, TemplateRecord.self, StarredPromptRecord.self]
    }
}

public enum StoreMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

public enum StoreContainer {
    public static var schema: Schema { Schema(versionedSchema: SchemaV1.self) }

    /// The app's container: `default.store` under `layout.root`, or memory only for tests and previews. Stored file
    /// paths into an earlier location of `home`, the app's container folder, are moved onto it first.
    public static func make(
        inMemory: Bool, layout: FileLayout = FileLayout(), home: URL = .homeDirectory
    ) throws -> ModelContainer {
        let schema = Self.schema
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            try layout.prepareDirectories()
            configuration = ModelConfiguration(schema: schema, url: layout.storeURL, cloudKitDatabase: .none)
        }
        let container = try ModelContainer(
            for: schema, migrationPlan: StoreMigrationPlan.self, configurations: [configuration])
        guard !inMemory else { return container }
        do {
            try ContainerRelocation(layout: layout, home: home).run(in: container)
        } catch {
            // Not noted as done, so the next launch tries again; the library opens either way.
            logger.error(
                "Can't move stored paths to the new container: \(String(describing: error), privacy: .private)")
        }
        return container
    }
}
