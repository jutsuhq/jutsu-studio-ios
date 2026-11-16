import Foundation
import HiggsfieldCore
import HiggsfieldTestSupport
import Testing

@testable import HiggsfieldAPI

@Test func returnedURLsElsewhereNeverGetTheKey() async throws {
    let server = StubServer()
    let elsewhere = StubServer()
    server.on("GET", "/requests/req-9/status", StubResponse(body: Fixture.status("queued")))
    server.on("POST", "/requests/req-9/cancel", StubResponse(status: 202))
    let statusURL = elsewhere.baseURL.appendingPathComponent("requests/req-9/status")
    let cancelURL = elsewhere.baseURL.appendingPathComponent("requests/req-9/cancel")
    let client = server.makeClient()

    #expect(try await client.status(requestID: "req-9", statusURL: statusURL) == .queued)
    try await client.cancel(requestID: "req-9", cancelURL: cancelURL)

    #expect(elsewhere.requests.isEmpty)
    #expect(server.requests.map(\.path) == ["/requests/req-9/status", "/requests/req-9/cancel"])
}
