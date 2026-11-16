import AVFoundation
import Foundation
import JutsuCore
import Testing

@testable import MediaKit

@Suite struct EditingExporterTests {
    private func source(_ url: URL) -> SourceClip {
        SourceClip(fileURL: url, duration: 2, pixelSize: PixelSize(width: 720, height: 480), range: 0...2)
    }

    @Test func neverReplacesAnExistingFile() async throws {
        let directory = try Fixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try await Fixtures.makeVideo(in: directory, seconds: 1)
        let output = directory.appendingPathComponent("take_v1.mov")
        try Data("keep me".utf8).write(to: output)

        await #expect(throws: (any Error).self) {
            try await EditingExporter.export(result, source: nil, preset: .premiere, to: output) { _ in }
        }
        #expect(try Data(contentsOf: output) == Data("keep me".utf8))
    }
}
