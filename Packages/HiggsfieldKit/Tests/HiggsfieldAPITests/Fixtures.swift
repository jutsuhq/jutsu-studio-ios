import Foundation
import HiggsfieldAPI

/// Response bodies as documented at docs.higgsfield.ai.
enum Fixture {
    static let submitted = """
        {
          "status": "queued",
          "request_id": "req-123",
          "status_url": "https://api.higgsfield.ai/requests/req-123/status",
          "cancel_url": "https://api.higgsfield.ai/requests/req-123/cancel"
        }
        """

    static func status(_ status: String, extra: String = "") -> String {
        #"{"status": "\#(status)", "request_id": "req-123"\#(extra)}"#
    }

    static let videoURL = URL(string: "https://cdn.example.com/in.mp4")!
    static let imageURLs = [
        URL(string: "https://cdn.example.com/a.jpg")!, URL(string: "https://cdn.example.com/b.png")!,
    ]

    static func request(prompt: String = "", resolution: String = "480p", presetID: UUID? = nil) -> GenerationRequest {
        GenerationRequest(
            videoURL: videoURL, imageURLs: imageURLs, prompt: prompt, resolution: resolution, presetID: presetID)
    }
}
