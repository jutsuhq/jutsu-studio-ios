import Foundation
import HiggsfieldMCP
import HiggsfieldTestSupport
import JutsuCore
import Testing

@testable import HiggsfieldProviders

private let soul = "higgsfield-ai/soul/v2/standard"

extension Network {
    /// Reference images with an API key: the curated models, their REST bodies, `/estimate` and the
    /// list price when it can't answer.
    @Suite struct APIImages {
        @Test func anUnreachableEstimateFallsBackToTheListPrice() async throws {
            let server = StubServer()
            server.on("POST", "/estimate/\(soul)", StubResponse(status: 500, body: "{}"))
            let request = ImageRequest(model: soul, prompt: "a knight", aspectRatio: "1:1", count: 4)

            let cost = try await server.makeAPIProvider().imageEstimate(request)

            #expect(cost == .usd(Decimal(string: "0.0128")!, isEstimate: true))
        }

        @Test func aRefusedEstimateIsNotHidden() async throws {
            let server = StubServer()
            server.on(
                "POST", "/estimate/\(soul)", StubResponse(status: 401, body: #"{"detail": "Invalid credentials"}"#))
            let request = ImageRequest(model: soul, prompt: "a knight", aspectRatio: "1:1", count: 1)
            await #expect(throws: ProviderError.unauthorized) {
                try await server.makeAPIProvider().imageEstimate(request)
            }
        }
    }
}
