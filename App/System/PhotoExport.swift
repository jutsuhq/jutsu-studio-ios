import Foundation
import Photos

/// Save to Photos with add-only access, asked the first time someone saves (HIG, Privacy).
nonisolated enum PhotoExport {
    enum Failure: LocalizedError {
        case denied

        var errorDescription: String? {
            String(localized: "Jutsu can't add to your photo library. Allow it in Settings › Privacy › Photos.")
        }
    }

    static func saveVideo(at url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.denied }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = false
            request.addResource(with: .video, fileURL: url, options: options)
        }
    }
}
