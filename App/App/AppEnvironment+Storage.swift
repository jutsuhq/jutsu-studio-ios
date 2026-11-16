import Foundation
import Persistence
import Presentation
import os

nonisolated private let logger = Logger.jutsu("Storage")

/// Disk use by kind, for Settings › Downloads and Storage.
nonisolated struct StorageBreakdown: Sendable {
    /// Takes, images and exports in Documents, which the Files app shows.
    var results: Int64
    var sources: Int64
    /// Motion Library clips, account uploads, pasted and generated images.
    var inputs: Int64
    var cache: Int64

    var clearable: Int64 { sources + inputs + cache }
}

extension AppEnvironment {
    /// What Clear Inputs and Cache empties. Results in Documents are never touched.
    var cacheFolders: [URL] {
        [layout.sourcesFolder, layout.cacheFolder, Inbox.folder] + layout.downloadedInputFolders
    }

    func measureStorage() async -> StorageBreakdown {
        let layout = layout
        async let results = CacheSize.bytes(in: [layout.defaultOutputFolder])
        async let sources = CacheSize.bytes(in: [layout.sourcesFolder])
        async let inputs = CacheSize.bytes(in: layout.downloadedInputFolders)
        async let cache = CacheSize.bytes(in: [layout.cacheFolder, Inbox.folder])
        return await StorageBreakdown(results: results, sources: sources, inputs: inputs, cache: cache)
    }

    /// Inputs are prepared again from the job's source if needed. Files the Create draft or a job that isn't done
    /// points at are kept: the draft and a retry still read them.
    func clearCache() async throws {
        let kept = try await cacheFilesInUse()
        for folder in cacheFolders {
            try FileLayout.clear(folder, keeping: kept)
        }
    }

    /// Removes cached files not changed for the age set in Settings, keeping the ones still in use. Runs at launch.
    func removeExpiredCache() async {
        guard let age = AppSettings.cacheMaxAge(in: defaults) else { return }
        do {
            let kept = try await cacheFilesInUse()
            await Self.removeFiles(in: cacheFolders, changedBefore: .now - age, keeping: kept)
        } catch {
            logger.error("Can't read which cached files are in use: \(String(describing: error), privacy: .private)")
        }
    }

    private func cacheFilesInUse() async throws -> Set<URL> {
        let drafts = drafts.load()
        return try await store.inputFilesOfJobsNotDone()
            .union(drafts?.video?.localFiles ?? []).union(drafts?.image?.localFiles ?? [])
    }

    @concurrent
    private static func removeFiles(in folders: [URL], changedBefore cutoff: Date, keeping kept: Set<URL>) async {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        let keptPaths = Set(kept.map { $0.resolvingSymlinksInPath().path(percentEncoded: false) })
        for folder in folders {
            let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys))
            while let file = files?.nextObject() as? URL {
                guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true,
                    let changed = values.contentModificationDate, changed < cutoff,
                    !keptPaths.contains(file.resolvingSymlinksInPath().path(percentEncoded: false))
                else { continue }
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
