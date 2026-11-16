import Foundation
import HiggsfieldMCP
import JutsuCore

/// The account's uploads in the app's terms.
enum AccountMapping {
    static func assetKind(_ kind: UploadKind) -> AssetKind {
        switch kind {
        case .image: .image
        case .video: .video
        }
    }

    static func file(_ asset: AccountAsset) -> UploadedFile {
        let size = asset.width.flatMap { width in asset.height.map { PixelSize(width: width, height: $0) } }
        return UploadedFile(
            id: asset.id, kind: asset.kind == .video ? .video : .image, url: asset.url, originalURL: asset.originalURL,
            thumbnailURL: asset.thumbnailURL, pixelSize: size, duration: asset.duration, createdAt: asset.createdAt)
    }

    /// An uploaded video as a clip of the Motion Library: it plays itself on hover and is named by its length.
    static func clip(_ file: UploadedFile) -> MotionPreset {
        let name =
            file.duration.flatMap { Int(exactly: $0.rounded()) }.map {
                String(localized: "Upload · \($0) s", bundle: .module)
            } ?? String(localized: "Upload", bundle: .module)
        return MotionPreset(
            id: "upload:\(file.id)", name: name, videoURL: file.fileURL, thumbnailURL: file.thumbnailURL,
            previewURL: file.url)
    }
}
