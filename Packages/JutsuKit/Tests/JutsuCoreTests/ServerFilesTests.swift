import Foundation
import Testing

@testable import JutsuCore

struct ServerFileNameTests {
    let folder = URL(fileURLWithPath: "/tmp/jutsu/motion-library", isDirectory: true)

    func file(_ names: [String], _ url: String, allowed: [String] = ServerFileName.videoExtensions) throws -> URL? {
        ServerFileName.file(in: folder, named: names, extensionOf: try #require(URL(string: url)), allowed: allowed)
    }

    @Test func separatorsCannotClimbOut() throws {
        let placed = try #require(try file(["../../..", "..\\..\\evil", "a/../../b"], "https://cdn.example/x.mp4"))
        #expect(
            placed.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path
                == folder.path)
        #expect(placed.path.hasPrefix(folder.path + "/"))
        #expect(!placed.pathComponents.dropFirst(folder.pathComponents.count).contains(".."))
    }
}
