import AVFoundation
import Foundation
import Synchronization
import Testing

@testable import MediaKit

@Suite struct VideoReencoderTests {
    @Test func reencodesTheRangeIntoAPlayableClipAndReportsTheEnd() async throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try await Fixtures.makeVideo(in: directory, seconds: 3)
        let output = directory.appendingPathComponent("out.mp4")
        let range = CMTimeRange(
            start: CMTime(seconds: 1, preferredTimescale: 600), duration: CMTime(seconds: 2, preferredTimescale: 600))
        let last = Mutex(0.0)

        try await VideoReencoder.reencode(
            VideoRequest(sourceURL: source, timeRange: range, upscaledSize: nil, byteLimit: 1 << 20), to: output
        ) { value in last.withLock { $0 = value } }

        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.loadTracks(withMediaType: .video)
        #expect(abs(duration - 2) < 0.5)
        #expect(tracks.count == 1)
        #expect(last.withLock { $0 } == 1)
    }
}
