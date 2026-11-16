import Foundation
import HiggsfieldCore
import HiggsfieldTestSupport
import Testing

@testable import HiggsfieldMCP

private let header = "eyJhbGciOiJSUzI1NiJ9"
/// `{"email":"me@example.com","name":"Me"}`
private let payload = "eyJlbWFpbCI6Im1lQGV4YW1wbGUuY29tIiwibmFtZSI6Ik1lIn0"

@Test func idTokenPayloadIsDecoded() {
    let claims = IDTokenClaims(jwt: "\(header).\(payload).signature")
    #expect(claims == IDTokenClaims(email: "me@example.com", name: "Me"))
    #expect(IDTokenClaims(jwt: "\(header).\(payload)=.signature")?.email == "me@example.com")
}

@Test func garbageIsNotAnIDToken() {
    for jwt in [
        "", "garbage", "\(header).\(payload)", "\(header).\(payload).sig.extra.parts", "\(header).!!!.sig",
        "\(header)..sig", "\(header).WzFd.sig",  // `[1]`: JSON, not an object
        "\(header).bm90IGpzb24.sig",  // `not json`
        "\(header).a.sig",  // one base64 character can't decode
    ] {
        #expect(IDTokenClaims(jwt: jwt) == nil, "\(jwt)")
    }
}

extension Network {
    @Suite struct IDTokens {
        static let idToken = "\(header).\(payload).signature"

        func signIn(tokenResponse: String) async throws -> TokenSet {
            let stub = StubServer { _, _ in .json(tokenResponse) }
            let presenter = FakePresenter { "http://127.0.0.1:47613/callback?code=c&state=\($0)&\(Fixture.clerkIss)" }
            let client = Fixture.client(try Fixture.server(Fixture.clerkMetadata), session: stub.session())
            return try await PKCEAuthorizer(client: client, presenter: presenter, hasher: FakeHasher()).authorize()
        }

        @Test func tokenResponseWithIDTokenNamesTheAccount() async throws {
            let tokens = try await signIn(
                tokenResponse: #"{"access_token":"a","expires_in":60,"id_token":"\#(Self.idToken)"}"#)
            #expect(tokens.email == "me@example.com")
            #expect(tokens.name == "Me")
            #expect(tokens.issuer?.absoluteString == Fixture.clerk)
            #expect(tokens.clientID == "client-1")
        }

        @Test func refreshWithoutIDTokenKeepsTheAccount() async throws {
            let stub = StubServer { _, _ in .json(Fixture.tokenResponse) }
            let client = Fixture.client(try Fixture.server(Fixture.clerkMetadata), session: stub.session())
            var old = Fixture.tokens(expiresAt: .distantPast)
            old.email = "me@example.com"
            old.name = "Me"
            old.subject = "user_1"
            let refreshed = try await client.refresh(old)
            #expect(refreshed.accessToken == "new-access")
            #expect(refreshed.email == "me@example.com")
            #expect(refreshed.name == "Me")
            #expect(refreshed.subject == "user_1")
        }
    }
}
