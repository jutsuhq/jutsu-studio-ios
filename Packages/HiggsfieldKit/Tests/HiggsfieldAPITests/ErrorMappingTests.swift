import Foundation
import HiggsfieldCore
import HiggsfieldTestSupport
import Testing

@testable import HiggsfieldAPI

private let validationDetail = """
    {"detail": [
      {"type": "too_short", "loc": ["body", "image_urls"], "msg": "List should have at least 1 item"},
      {"type": "string_type", "loc": ["body", "prompt"], "msg": "Input should be a valid string"}
    ]}
    """

private let expiredKey = """
    {"code": "api_key_expired", "detail": "This API key has expired.", "expires_at": "2026-09-21T12:00:00Z"}
    """

private let queueFull = """
    {"detail": {"code": "account_queue_full", "message": "Too many queued generations for this account",
      "retryable": true, "limit": 40, "retry_after_seconds": 30}}
    """

private let admissionUnavailable = """
    {"detail": {"code": "admission_control_unavailable", "message": "Queue admission is unavailable", "retryable": true}}
    """

@Test(arguments: [
    (401, #"{"detail": "Invalid credentials"}"#, HiggsfieldError.unauthorized),
    (403, #"{"detail": "Not enough credits"}"#, .insufficientFunds),
    (403, "", .insufficientFunds),
    (403, expiredKey, .unauthorized),
    (
        422, validationDetail,
        .validation(
            field: "image_urls", message: "List should have at least 1 item; Input should be a valid string")
    ),
    (423, "", .modelUnavailable),
    (503, admissionUnavailable, .server(status: 503)),
    (429, queueFull, .concurrencyLimit(retryAfter: 30)),
    (500, "", .server(status: 500)),
])
func httpErrorsMapToHiggsfieldErrors(status: Int, body: String, expected: HiggsfieldError) {
    #expect(HiggsfieldAPIErrors.error(status: status, body: Data(body.utf8)) == expected)
}

/// A full queue creates nothing, so the submit sent again after the wait carries the same key and can't charge twice.
@Test func aSubmitSentAgainAfterAFullQueueKeepsItsIdempotencyKey() async throws {
    let server = StubServer { _, earlier in
        earlier == 0
            ? StubResponse.json(queueFull, status: 429, headers: ["Retry-After": "1"])
            : StubResponse.json(#"{"status": "queued", "request_id": "req-1"}"#)
    }
    let client = server.makeClient()
    let key = UUID()

    await #expect(throws: HiggsfieldError.concurrencyLimit(retryAfter: 1)) {
        try await client.submit(.motionTransfer, Fixture.request(), idempotencyKey: key)
    }
    #expect(try await client.submit(.motionTransfer, Fixture.request(), idempotencyKey: key).requestID == "req-1")
    let keys = server.requests.map { $0.header("Idempotency-Key") }
    #expect(keys == [key.uuidString.lowercased(), key.uuidString.lowercased()])
}

@Test func transportFailureIsNetworkError() async {
    let server = StubServer()
    server.on("GET", "/requests/req-123/status", fail: URLError(.notConnectedToInternet))

    await #expect(throws: HiggsfieldError.network) {
        try await server.makeClient().status(requestID: "req-123")
    }
}
