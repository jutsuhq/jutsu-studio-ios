import Foundation
import HiggsfieldCore
import HiggsfieldTestSupport
import Testing

@testable import HiggsfieldMCP

/// The answers of the paid run on 2026-10-15 (`docs/mcp-snapshots/live-2026-10-15/`), trimmed and with
/// example URLs, replayed by a stub.
extension Network {
    @Suite struct LivePaidRun {
        /// A stub answering `tool` with `text` as an `isError` result, and everything else as usual.
        static func refusing(_ tool: String, text: String, answer: JSONValue = [:]) -> (HiggsfieldAccount, StubServer) {
            let answering = mcpServer(tools: Account.fullSet)
            let stub = StubServer { request, _ in
                guard request.json?["params"]?["name"] == .string(tool), let id = request.json?["id"] else {
                    return answering.respond(to: request)
                }
                return .json([
                    "jsonrpc": "2.0", "id": id,
                    "result": [
                        "isError": true, "content": [["type": "text", "text": .string(text)]],
                        "structuredContent": answer,
                    ],
                ])
            }
            let session = stub.session()
            let client = MCPClient(endpoint: Fixture.mcpURL, tokens: tokenProvider(), session: session)
            return (HiggsfieldAccount(client: client, session: session), stub)
        }

        /// A refused unlimited opt-in started nothing (balance and credit history unchanged), so it is a refusal with
        /// its reason, not an unknown outcome.
        @Test func aRefusedUnlimitedOptInIsARefusal() async throws {
            let live = try CatalogSnapshot.liveAnswer("generate_image_use_unlim_refused")
            let text = try #require(live.text)
            #expect(live.isError)
            let request = AccountImageRequest(model: "soul_2", prompt: "a paper boat", aspectRatio: "1:1", count: 1)

            let (images, _) = Self.refusing("generate_image", text: text, answer: live.answer)
            await #expect(throws: HiggsfieldError.validation(field: nil, message: text)) {
                try await images.generateImages(request)
            }

            let (videos, _) = Self.refusing("generate_video", text: text)
            await #expect(throws: HiggsfieldError.validation(field: nil, message: text)) {
                try await videos.generate(Account.request)
            }
        }

        /// An execution error carrying the out-of-credits recovery submitted nothing.
        @Test func aSubmitErrorWithBillingRecoveryIsInsufficientFunds() async throws {
            let (account, _) = Self.refusing(
                "generate_video", text: "Not enough credits", answer: ["recovery_tool": "show_plans_and_credits"])
            await #expect(throws: HiggsfieldError.insufficientFunds) { try await account.generate(Account.request) }
        }

        /// Any other execution error of a submit may have started a job.
        @Test func anotherSubmitErrorIsAnUnknownOutcome() async throws {
            let (account, _) = Self.refusing("generate_video", text: "Error starting generation: upstream timeout")
            await #expect(throws: HiggsfieldError.server(status: 200)) {
                try await account.generate(Account.request)
            }
        }
    }
}
