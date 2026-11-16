import Foundation
import HiggsfieldCore
import HiggsfieldTestSupport
import Testing

@testable import HiggsfieldMCP

extension Network {
    @Suite struct Discovery {
        /// The servers as recorded: resource metadata, clerk on RFC 8414, and the device server's 404s.
        static func server(resource: String = Fixture.resourceMetadata) -> StubServer {
            StubServer { request, _ in
                switch request.url.absoluteString {
                case Fixture.resourceMetadataURL: .json(resource)
                case "\(Fixture.clerk)/.well-known/oauth-authorization-server": .json(Fixture.clerkMetadata)
                default: .json(Fixture.notFoundBody, status: 404)
                }
            }
        }

        @Test func readsRecordedMetadata() async throws {
            let stub = Self.server()
            let discovered = try await OAuthDiscovery(session: stub.session())
                .discover(mcpURL: Fixture.mcpURL, wwwAuthenticate: Fixture.wwwAuthenticate)

            #expect(stub.requests.first?.url.absoluteString == Fixture.resourceMetadataURL)
            #expect(
                discovered.resource.authorizationServers.map(\.absoluteString) == [Fixture.clerk, Fixture.deviceAuth])
            #expect(discovered.resource.scopesSupported == ["openid", "email", "offline_access"])
            #expect(discovered.servers.map(\.issuer.absoluteString) == [Fixture.clerk])

            let pkce = try #require(discovered.authorizationCodeServer)
            #expect(pkce.authorizationEndpoint?.absoluteString == "\(Fixture.clerk)/oauth/authorize")
            #expect(pkce.tokenEndpoint.absoluteString == "\(Fixture.clerk)/oauth/token")
            #expect(pkce.registrationEndpoint?.absoluteString == "\(Fixture.clerk)/oauth/register")
            #expect(pkce.clientIDMetadataDocumentSupported)
            #expect(pkce.authorizationResponseIssParameterSupported)
        }

        @Test func failsWithoutMetadata() async {
            let stub = StubServer { _, _ in .notFound }
            await #expect(throws: OAuthError.discoveryFailed) {
                try await OAuthDiscovery(session: stub.session()).discover(mcpURL: Fixture.mcpURL)
            }
        }
    }
}
