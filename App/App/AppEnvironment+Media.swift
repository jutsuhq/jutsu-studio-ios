import Foundation
import JobEngine
import JutsuCore
import MediaKit
import Presentation
import os

nonisolated private let logger = Logger.jutsu("Media")

/// Files the app brings down from Higgsfield: inputs kept in Application Support for the jobs that use them, and
/// results saved to Documents/Images, where the Files app shows them.
extension AppEnvironment {
    /// Downloads `url` into Documents/Images under a fresh name.
    func saveToImages(_ url: URL) async throws -> URL {
        let folder = OutputSubfolder.images.url(in: layout.defaultOutputFolder)
        return try await MediaLinkDownloader().download(url, into: folder, expected: .image).fileURL
    }

    /// `url` kept at `path` in the account media folder; downloaded only the first time.
    private func cachedMedia(_ url: URL, at path: String, expected: MediaLink.Kind) async throws -> URL {
        let file = layout.accountMediaFolder.appending(path: path)
        try await MediaLinkDownloader().download(url, to: file, expected: expected)
        return file
    }

    private static func fileName(_ name: String, of url: URL, default fallback: String) -> String {
        "\(name).\(url.pathExtension.isEmpty ? fallback : url.pathExtension)"
    }

    /// Downloads finished images into Documents/Images. A failed download leaves the image listed with its link.
    func saveGeneratedImages(_ images: [GeneratedImage]) {
        for image in images where image.fileURL == nil {
            Task {
                do {
                    imageGenerator.setFile(try await saveToImages(image.url), for: image.id)
                } catch {
                    logger.error("Can't save a generated image: \(String(describing: error), privacy: .private)")
                }
            }
        }
    }

    /// Each finished character sheet is saved to Documents/Images, and the log remembers where.
    func saveCharacterSheets(_ records: [CharacterSheetRecord]) {
        for record in records where record.fileURL == nil {
            guard let url = record.imageURL else { continue }
            Task {
                do {
                    characterBuilder.log.setFile(try await saveToImages(url), for: record.id)
                } catch {
                    logger.error("Can't save a character sheet: \(String(describing: error), privacy: .private)")
                }
            }
        }
    }

    /// A character sheet's file, saved first when only its link is known.
    func downloadSheet(_ sheet: CharacterSheet) async throws -> LocalImage {
        if let file = sheet.fileURL, FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
            return LocalImage(fileURL: file)
        }
        let file = try await saveToImages(sheet.imageURL)
        characterBuilder.log.setFile(file, for: sheet.id)
        return LocalImage(fileURL: file)
    }

    /// An uploaded image as a reference that keeps its media, so a job of the same account names it instead of
    /// uploading it again.
    func downloadUpload(_ upload: UploadedFile) async throws -> LocalImage {
        let file = try await cachedMedia(
            upload.fileURL, at: "uploads/" + Self.fileName(upload.id, of: upload.fileURL, default: "jpg"),
            expected: .image)
        return LocalImage(
            fileURL: file, serverMedia: ServerMedia(id: upload.id, url: upload.url, owner: provider?.owner))
    }

    /// An element's images as references that keep their media.
    func downloadElement(_ element: AccountElement, from model: AccountElementsModel) async throws -> [LocalImage] {
        let full = try await model.withImages(element)
        var images: [LocalImage] = []
        for (index, image) in full.images.enumerated() {
            let file = try await cachedMedia(
                image.url, at: "elements/\(element.id)/" + Self.fileName("\(index + 1)", of: image.url, default: "jpg"),
                expected: .image)
            images.append(LocalImage(fileURL: file, serverMedia: image.media))
        }
        return images
    }

    /// A Motion Library clip as a local file, downloaded once and kept for the jobs that use it.
    func downloadMotionClip(_ preset: MotionPreset) async throws -> SourceVideo {
        let file = layout.motionLibraryFolder.appending(
            path: Self.fileName(preset.id, of: preset.videoURL, default: "mp4"))
        try await MediaLinkDownloader().download(preset.videoURL, to: file, expected: .video)
        return try await SourceVideo.probing(file, remoteOrigin: preset.videoURL)
    }
}

extension SourceVideo {
    /// A job's clip, as Edit Inputs puts it back; its codec and size aren't kept on the job.
    init(clip: SourceClip) {
        self.init(
            fileURL: clip.fileURL, duration: clip.duration, pixelSize: clip.pixelSize, codec: "", fileSize: 0,
            bookmark: clip.bookmark)
    }

    /// A clip on disk, read for its length, size and codec.
    static func probing(_ file: URL, remoteOrigin: URL? = nil) async throws -> SourceVideo {
        let info = try await MediaProbe.probe(file)
        return SourceVideo(
            fileURL: file, duration: info.duration, pixelSize: info.pixelSize, codec: info.codec,
            fileSize: info.fileSize, remoteOrigin: remoteOrigin)
    }
}
