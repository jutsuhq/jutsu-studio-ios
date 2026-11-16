import Foundation
import HiggsfieldCore
import HiggsfieldTestSupport
import Testing

@testable import HiggsfieldAPI

private let images = #"["https://cdn.example.com/a.jpg","https://cdn.example.com/b.png"]"#
private let video = #""https://cdn.example.com/in.mp4""#

@Test(arguments: [
    (
        ModelEndpoint.motionTransfer, Fixture.request(), "/higgsfield/genjutsu/motion-transfer/v1.0",
        #"{"image_urls":\#(images),"prompt":"","resolution":"480p","video_url":\#(video)}"#
    )
])
func submitSendsDocumentedRequest(
    endpoint: ModelEndpoint, generation: GenerationRequest, path: String, body: String
) async throws {
    let server = StubServer()
    server.on("POST", path, StubResponse(headers: ["X-Correlation-ID": "corr-1"], body: Fixture.submitted))
    let key = UUID()

    let job = try await server.makeClient().submit(endpoint, generation, idempotencyKey: key)

    #expect(
        job
            == SubmittedRequest(
                requestID: "req-123", correlationID: "corr-1",
                statusURL: URL(string: "https://api.higgsfield.ai/requests/req-123/status"),
                cancelURL: URL(string: "https://api.higgsfield.ai/requests/req-123/cancel"), initialStatus: .queued))
    let request = try #require(server.requests.first)
    #expect(request.method == "POST")
    #expect(request.path == path)
    #expect(request.header("Authorization") == "Key key-id:key-secret")
    #expect(request.header("Idempotency-Key") == key.uuidString.lowercased())
    #expect(request.header("Content-Type") == "application/json")
    #expect(request.bodyText == body)
}
