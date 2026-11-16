import Foundation
import HiggsfieldCore
import HiggsfieldTestSupport
import Testing

@testable import HiggsfieldMCP

func tokenProvider(access: String = "access-1", refreshes: Locked<Int> = Locked(0)) -> TokenProvider {
    TokenProvider(
        tokens: Fixture.tokens(access: access, expiresAt: .distantFuture),
        refresh: { old in
            refreshes.update { $0 += 1 }
            return Fixture.tokens(access: "fresh", refresh: old.refreshToken, expiresAt: .distantFuture)
        },
        persist: { _ in })
}

extension Network {
    @Suite struct MCP {
        let tools = (1...5).map { tool("tool_\($0)", "Tool \($0)", ["x"]) }

        @Test func unauthorizedRefreshesOnceAndRetries() async throws {
            let refreshes = Locked(0)
            let stub = mcpServer(tools: tools, rejected: ["stale"])
            let client = MCPClient(
                endpoint: Fixture.mcpURL, tokens: tokenProvider(access: "stale", refreshes: refreshes),
                session: stub.session())

            #expect(try await client.listTools().count == 5)
            #expect(refreshes.value == 1)
            #expect(stub.requests.map { $0.header("Authorization") ?? "" }.first == "Bearer stale")
            #expect(stub.requests.dropFirst().allSatisfy { $0.header("Authorization") == "Bearer fresh" })
        }

        @Test func secondUnauthorizedIsReported() async throws {
            let stub = mcpServer(tools: tools, rejected: ["stale", "fresh"])
            let client = MCPClient(
                endpoint: Fixture.mcpURL, tokens: tokenProvider(access: "stale"), session: stub.session())
            await #expect(throws: HiggsfieldError.unauthorized) { try await client.listTools() }
        }

        /// `mcpServer` with a new session ID per `initialize`, answering `404` to any session in `expired`.
        private func sessionServer(expired: Locked<Set<String>>) -> StubServer {
            let answering = mcpServer(tools: tools)
            let sessions = Locked(0)
            return StubServer { request, _ in
                if request.json?["method"] == "initialize" {
                    let number = sessions.update { count -> Int in
                        count += 1
                        return count
                    }
                    var response = answering.respond(to: request)
                    response.headers["Mcp-Session-Id"] = "session-\(number)"
                    return response
                }
                if let session = request.header("Mcp-Session-Id"), expired.value.contains(session) {
                    return .notFound
                }
                return answering.respond(to: request)
            }
        }

        @Test func expiredSessionIsStartedAgainAndTheCallRetried() async throws {
            let expired = Locked<Set<String>>([])
            let stub = sessionServer(expired: expired)
            let client = MCPClient(endpoint: Fixture.mcpURL, tokens: tokenProvider(), session: stub.session())
            #expect(try await client.listTools().count == 5)

            expired.update { $0 = ["session-1"] }
            let result = try await client.callTool("tool_1", arguments: [:])

            #expect(result.text == "done")
            let methods = stub.requests.compactMap { $0.json?["method"]?.stringValue }
            #expect(
                methods == [
                    "initialize", "notifications/initialized", "tools/list", "tools/call", "initialize",
                    "notifications/initialized", "tools/call",
                ])
            #expect(stub.requests[4].header("Mcp-Session-Id") == nil)
            #expect(stub.requests[5].header("Mcp-Session-Id") == "session-2")
            #expect(stub.requests[6].header("Mcp-Session-Id") == "session-2")
        }

        @Test func aReplyThatNeverComesTimesOut() async throws {
            let answering = mcpServer(tools: tools)
            let stub = StubServer { request, _ in
                guard request.json?["method"]?.stringValue == "tools/call" else {
                    return answering.respond(to: request)
                }
                // Keep-alive comments only: data keeps coming, the reply never does.
                return StubResponse(
                    headers: ["Content-Type": "text/event-stream"], body: ": ping\n\n", keepsOpen: true)
            }
            let client = MCPClient(
                endpoint: Fixture.mcpURL, tokens: tokenProvider(), session: stub.session(), requestTimeout: 0.3)
            await #expect(throws: HiggsfieldError.network) { try await client.callTool("tool_1", arguments: [:]) }
        }

        @Test func refreshGrantKeepsTheOldRefreshTokenWhenNoneIsIssued() async throws {
            let stub = StubServer { _, _ in .json(#"{"access_token":"next","expires_in":60}"#) }
            let now = Date(timeIntervalSince1970: 500)
            let client = Fixture.client(try Fixture.server(Fixture.clerkMetadata), session: stub.session(), now: now)
            let refreshed = try await client.refresh(Fixture.tokens(expiresAt: now))
            #expect(refreshed.accessToken == "next")
            #expect(refreshed.refreshToken == "refresh-1")
            #expect(refreshed.expiresAt == now + 60)
            let form = try #require(stub.requests.first).form
            #expect(form["grant_type"] == "refresh_token")
            #expect(form["refresh_token"] == "refresh-1")
            #expect(form["client_id"] == "client-1")
            #expect(form["resource"] == "https://mcp.higgsfield.ai/mcp")
        }
    }
}
