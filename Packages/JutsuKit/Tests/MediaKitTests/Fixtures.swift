import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

@testable import MediaKit

/// Media fixtures are generated per test instead of committed as binaries.
enum Fixtures {
    struct WriteFailed: Error {
        let underlying: (any Error)?
    }

    static func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MediaKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Silent video of frames that fade through grey, `frameRate` fps.
    /// - Parameter shade: the grey level of each frame, by its index.
    static func makeVideo(
        in directory: URL, width: Int = 720, height: Int = 480, seconds: Int, frameRate: Int = 5,
        codec: AVVideoCodecType = .h264, fileType: AVFileType = .mp4,
        shade: (Int) -> Int32 = { Int32(30 + $0 % 200) }
    ) async throws -> URL {
        let url = directory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileType == .mov ? "mov" : "mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [AVVideoCodecKey: codec, AVVideoWidthKey: width, AVVideoHeightKey: height]
        )
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        guard writer.startWriting() else { throw WriteFailed(underlying: writer.error) }
        writer.startSession(atSourceTime: .zero)

        // Frames come from a pool of the fixture's own, not `adaptor.pixelBufferPool`: VideoToolbox can replace the
        // encoder's pool while several tests encode at once, and a frame taken from the replaced pool crashed the
        // test bundle with SIGSEGV in `CVPixelBufferPoolCreatePixelBuffer`.
        let pool = try makePool(width: width, height: height)
        for frame in 0..<(seconds * frameRate) {
            while !input.isReadyForMoreMediaData, writer.status == .writing {
                try await Task.sleep(for: .milliseconds(2))
            }
            guard writer.status == .writing else { throw WriteFailed(underlying: writer.error) }
            let buffer = try makeFrame(pool: pool, shade: shade(frame))
            let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(frameRate))
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw WriteFailed(underlying: writer.error)
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw WriteFailed(underlying: writer.error) }
        return url
    }

    private static func makePool(width: Int, height: Int) throws -> CVPixelBufferPool {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
        var pool: CVPixelBufferPool?
        guard CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool) == kCVReturnSuccess,
            let pool
        else { throw WriteFailed(underlying: nil) }
        return pool
    }

    private static func makeFrame(pool: CVPixelBufferPool, shade: Int32) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess,
            let buffer
        else { throw WriteFailed(underlying: nil) }
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), shade, CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    static func imageSize(at url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }
}
