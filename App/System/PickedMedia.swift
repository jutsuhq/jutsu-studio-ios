import CoreTransferable
import Foundation
import JutsuCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import os

nonisolated private let logger = Logger.jutsu("Media")

/// A video from Photos, copied into the app's inbox so it outlives the picker.
nonisolated struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            PickedMovie(url: try Inbox.copy(received.file))
        }
    }
}

/// An image from Photos, copied into the app's inbox.
nonisolated struct PickedImage: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .image) { image in
            SentTransferredFile(image.url)
        } importing: { received in
            PickedImage(url: try Inbox.copy(received.file))
        }
    }
}

nonisolated enum Inbox {
    static var folder: URL {
        URL.applicationSupportDirectory.appending(path: "Jutsu/inbox", directoryHint: .isDirectory)
    }

    /// Copies a file the system handed over into a folder of its own, keeping its name.
    static func copy(_ file: URL) throws -> URL {
        let folder = folder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: file.lastPathComponent)
        try FileManager.default.copyItem(at: file, to: destination)
        return destination
    }
}

extension PhotosPickerItem {
    /// The picked image copied into the inbox; `nil` when Photos can't hand it over.
    func localImage() async -> LocalImage? {
        do {
            guard let picked = try await loadTransferable(type: PickedImage.self) else { return nil }
            return LocalImage(fileURL: picked.url)
        } catch {
            logger.error("Can't load a picked image: \(String(describing: error), privacy: .private)")
            return nil
        }
    }
}

extension [PhotosPickerItem] {
    func localImages() async -> [LocalImage] {
        var images: [LocalImage] = []
        for item in self {
            if let image = await item.localImage() { images.append(image) }
        }
        return images
    }
}
