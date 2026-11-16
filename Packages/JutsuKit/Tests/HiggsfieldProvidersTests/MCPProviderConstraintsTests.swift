import Foundation
import HiggsfieldMCP
import HiggsfieldTestSupport
import JutsuCore
import Testing

@testable import HiggsfieldProviders

extension Network {
    @Suite struct ProviderConstraints {
        static let explore = tool("models_explore", "Explore models", ["action", "type", "model_id", "cursor"])

        static let seedance45 = ModelConstraintTable(entries: [
            .init(model: .seedance25, mode: .motionTransfer, constraints: ModelConstraints(maxDuration: 45))
        ])

        /// Seedance on a 40 s selection.
        static let spec: JobSpec = {
            let source = SourceClip(
                fileURL: URL(fileURLWithPath: "/tmp/in.mov"), duration: 60,
                pixelSize: PixelSize(width: 1280, height: 720),
                range: 0...40)
            return JobSpec(mode: .motionTransfer, model: .seedance25, source: source, resolution: .p720)
        }()

        static func provider(
            tools: [JSONValue], constraints: ModelConstraintTable = .builtIn,
            call: @escaping @Sendable (String, JSONValue) -> JSONValue = { _, _ in [:] }
        ) -> (HiggsfieldMCPProvider, StubServer) {
            let stub = mcpServer(tools: tools, call: call)
            let tokens = TokenProvider(
                tokens: TokenSet(
                    accessToken: "access-1", refreshToken: nil, expiresAt: .distantFuture, scope: "openid",
                    clientID: "client-1"),
                refresh: { $0 }, persist: { _ in })
            let session = stub.session()
            let client = MCPClient(
                endpoint: URL(string: "https://mcp.higgsfield.ai/mcp")!, tokens: tokens, session: session)
            let provider = HiggsfieldMCPProvider(
                account: HiggsfieldAccount(client: client, session: session), owner: "user_1",
                constraints: { constraints })
            return (provider, stub)
        }

        /// The fallback estimate and the quote before upload both bill the length the table allows.
        @Test func theEstimateBillsTheLengthTheTableAllows() async throws {
            let (builtIn, _) = Self.provider(tools: Provider.fullSet)
            let (cached, _) = Self.provider(
                tools: Provider.fullSet, constraints: Self.seedance45)
            #expect(try await builtIn.estimate(Self.spec) == .credits(210, isEstimate: true))
            #expect(try await cached.estimate(Self.spec) == .credits(280, isEstimate: true))

            let (quoted, stub) = Self.provider(
                tools: Provider.fullSet, constraints: Self.seedance45
            ) { _, arguments in
                ["cost": ["credits": .number((arguments["params"]?["duration"]?.numberValue ?? 0) * 7)]]
            }
            #expect(try await quoted.estimate(Self.spec) == .credits(280, isEstimate: false))
            #expect(Provider.calls(stub).map { $0["arguments"]?["params"]?["duration"] } == [40])
        }
    }
}
