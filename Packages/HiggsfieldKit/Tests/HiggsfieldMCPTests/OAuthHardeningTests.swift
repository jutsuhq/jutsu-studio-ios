import Foundation
import HiggsfieldTestSupport
import Testing

@testable import HiggsfieldMCP

// Discovery validation (RFC 9728 §3.3, RFC 8414 §3.3, https only) and refresh pinned to the issuing server.

@Test func metadataForAnotherIssuerIsRejected() throws {
    let clerk = try Fixture.server(Fixture.clerkMetadata)
    let other = try #require(URL(string: "https://evil.example"))
    #expect(!clerk.isIssued(by: other))
}

@Test(arguments: [
    "https://clerk.higgsfield.ai/oauth/authorize", "https://clerk.higgsfield.ai/oauth/token",
])
func nonHTTPSEndpointIsRejected(endpoint: String) throws {
    let downgraded = Fixture.clerkMetadata.replacingOccurrences(
        of: "\"\(endpoint)\"", with: "\"file:///Applications/Calculator.app\"")
    #expect(downgraded != Fixture.clerkMetadata)
    let issuer = try #require(URL(string: Fixture.clerk))
    let server = try Fixture.server(downgraded)
    #expect(!server.isIssued(by: issuer))
}

@Test func resourceMetadataMustNameTheMCPURL() throws {
    let resource = try JSONDecoder().decode(ProtectedResourceMetadata.self, from: Data(Fixture.resourceMetadata.utf8))
    #expect(resource.describes(Fixture.mcpURL))
    let other = try #require(URL(string: "https://mcp.higgsfield.ai/other"))
    #expect(!resource.describes(other))
}

@Suite struct IssuerPinning {
    static func discovered() throws -> DiscoveredAuthorization {
        let resource = try JSONDecoder().decode(
            ProtectedResourceMetadata.self, from: Data(Fixture.resourceMetadata.utf8))
        return DiscoveredAuthorization(resource: resource, servers: [try Fixture.server(Fixture.mcpHostMetadata)])
    }

    static func tokens(issuer: String?) -> TokenSet {
        var tokens = Fixture.tokens(expiresAt: .distantPast)
        tokens.issuer = issuer.flatMap(URL.init(string:))
        return tokens
    }

    @Test func tokensOfAnUnlistedIssuerNeedANewSignIn() throws {
        // The MCP host is the only server: clerk's tokens must not go to it, even though it can refresh.
        let discovered = try Self.discovered()
        #expect(throws: OAuthError.reauthenticationRequired) {
            _ = try discovered.client(issuing: Self.tokens(issuer: Fixture.clerk))
        }
        #expect(throws: OAuthError.reauthenticationRequired) {
            _ = try discovered.client(issuing: Self.tokens(issuer: nil))
        }
    }
}
