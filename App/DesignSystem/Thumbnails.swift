import CryptoKit
import JobEngine
import JutsuCore
import MediaKit
import UIKit

/// Pictures decoded at the size they are shown, kept in memory so a cell scrolled back into view doesn't decode its
/// file again. The system empties the cache under memory pressure.
enum Thumbnails {
    private final class Entry {
        let image: UIImage
        /// The long side asked for; the image is smaller when its source was.
        let pixels: Int

        init(image: UIImage, pixels: Int) {
            self.image = image
            self.pixels = pixels
        }
    }

    private static let cache: NSCache<NSURL, Entry> = {
        let cache = NSCache<NSURL, Entry>()
        cache.totalCostLimit = 96 << 20
        return cache
    }()

    /// The picture kept for `url` when it was decoded at `pixels` or more on its long side.
    static func cached(_ url: URL, pixels: Int = 0) -> UIImage? {
        guard let entry = cache.object(forKey: url as NSURL), entry.pixels >= pixels else { return nil }
        return entry.image
    }

    static func store(_ image: UIImage, for url: URL, pixels: Int) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(Entry(image: image, pixels: pixels), forKey: url as NSURL, cost: cost)
    }

    /// The picture at most `pixels` on its long side, decoded off the main actor: a file read here, a link read with
    /// `ServerImageReader`, or a frame of a linked video (a history result without a thumbnail). `nil` when it can't
    /// be read.
    static func image(at url: URL, pixels: Int) async -> UIImage? {
        if let cached = cached(url, pixels: pixels) { return cached }
        let decoded: CGImage?
        if url.isFileURL {
            decoded = await ImageThumbnail.image(at: url, maxPixelSize: pixels)
        } else {
            guard let data = await remoteData(url) else { return nil }
            decoded = await ImageThumbnail.image(data: data, maxPixelSize: pixels)
        }
        guard let decoded else { return nil }
        let image = UIImage(cgImage: decoded)
        store(image, for: url, pixels: pixels)
        return image
    }

    /// Linked pictures as downloaded, so the next launch doesn't fetch them again. The least recently shown go
    /// once the folder passes `diskLimit`, checked once a launch; the system may empty Caches too.
    nonisolated private static let folder = URL.cachesDirectory.appending(
        path: "Thumbnails", directoryHint: .isDirectory)
    nonisolated private static let diskLimit = 64 << 20

    @concurrent
    private static func remoteData(_ url: URL) async -> Data? {
        _ = trimmed
        let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = folder.appending(path: key)
        if let data = try? Data(contentsOf: file) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            return data
        }
        let isVideo = ServerFileName.videoExtensions.contains(url.pathExtension.lowercased())
        // A video link is read as one frame through range requests, not downloaded whole; a link without a known
        // extension that turns out not to be an image gets the same second try.
        var data = isVideo ? nil : try? await ServerImageReader().data(from: url)
        if data == nil { data = await videoFrame(url) }
        guard let data else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        return data
    }

    /// A frame from the first part of a linked video as JPEG data, at most `framePixels` on its long side.
    @concurrent
    private static func videoFrame(_ url: URL) async -> Data? {
        let size = CGSize(width: framePixels, height: framePixels)
        guard let frame = try? await ThumbnailStrip.images(for: url, count: 1, maximumSize: size).first else {
            return nil
        }
        return UIImage(cgImage: frame).jpegData(compressionQuality: 0.8)
    }

    /// Large enough for a full-screen poster on a phone, small enough for the disk cache.
    nonisolated private static let framePixels = 1280

    /// Removes the least recently shown files past `diskLimit`; runs on first use, as a lazy static does.
    nonisolated private static let trimmed: Void = {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)
        else { return }
        let newestFirst = files.compactMap { file in
            (try? file.resourceValues(forKeys: Set(keys))).map { (file, $0) }
        }.sorted { ($0.1.contentModificationDate ?? .distantPast) > ($1.1.contentModificationDate ?? .distantPast) }
        var total = 0
        for (file, values) in newestFirst {
            total += values.fileSize ?? 0
            if total > diskLimit { try? FileManager.default.removeItem(at: file) }
        }
    }()
}
