import Foundation
import HiggsfieldCore
import HiggsfieldTestSupport
import Testing

@testable import HiggsfieldMCP

/// `execute_preset` may answer with several `job_ids` for one Style run: as `generate_video`'s `results`, the first is
/// the run's job and the rest are its variants.
extension Network {
    @Suite struct StyleRuns {
        static let executePreset = tool("execute_preset", "Run a Genjutsu Style", ["source", "preset_id", "inputs"])
        static let tools = Account.fullSet + [executePreset]

        static let run = StyleRun(
            styleID: "genjutsu-style:1", videoID: "video-1", imageIDs: ["image-1", "image-2"], prompt: "glow",
            resolution: "720p")

        @Test func everyJobOfARunIsKept() async throws {
            let (account, _) = Account.account(tools: Self.tools) { _, _ in
                ["job_ids": ["job-1", "job-2"], "request_id": "trace-1", "status": "submitted"]
            }
            let generation = try await account.run(Self.run)
            #expect(generation.id == "job-1")
            #expect(generation.variantIDs == ["job-2"])
            #expect(generation.requestID == "trace-1")
        }
    }
}
