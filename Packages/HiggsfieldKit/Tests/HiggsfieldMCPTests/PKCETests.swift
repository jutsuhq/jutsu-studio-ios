import Foundation
import HiggsfieldTestSupport
import Testing

@testable import HiggsfieldMCP

/// Returns fixed bytes whose base64 contains `+`, `/` and `=`, so the base64url rewrite is visible.
struct FakeHasher: PKCEHasher {
    func sha256(_ data: Data) -> Data { Data([0xfb, 0xff, 0xfe, 0xfb, 0xff]) }
}

struct FakePresenter: AuthorizationPresenter {
    static let redirectURI = "http://127.0.0.1:47613/callback"

    let opened = Locked<[URL]>([])
    let redirect: @Sendable (_ state: String) -> String

    func authorize(makeURL: @Sendable (String) throws -> URL) async throws -> AuthorizationRedirect {
        let url = try makeURL(Self.redirectURI)
        opened.update { $0.append(url) }
        let state =
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "state" }?.value ?? ""
        return AuthorizationRedirect(
            callback: try #require(URL(string: redirect(state))), redirectURI: Self.redirectURI)
    }
}

@Test func verifierUsesUnreservedCharactersAndValidLength() {
    let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    let verifiers = (0..<20).map { _ in PKCE(hasher: FakeHasher()).verifier }
    for verifier in verifiers {
        #expect((43...128).contains(verifier.count))
        #expect(verifier.allSatisfy(allowed.contains))
    }
    #expect(Set(verifiers).count == verifiers.count)
}

#if canImport(CryptoKit)
    @Test func cryptoKitHasherMatchesRFC7636Vector() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", hasher: CryptoKitHasher())
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }
#endif

@Test func callbackWithForeignStateIsRejected() throws {
    let issuer = try #require(URL(string: Fixture.clerk))
    let callback = URL(string: "http://127.0.0.1:47613/callback?code=abc&state=other&\(Fixture.clerkIss)")
    #expect(throws: OAuthError.stateMismatch) {
        try PKCEAuthorizer.code(
            from: try #require(callback), expectedState: "mine", issuer: issuer, requiresIssuer: true)
    }
    let denied = URL(string: "http://127.0.0.1:47613/callback?error=access_denied&state=mine&\(Fixture.clerkIss)")
    #expect(throws: OAuthError.accessDenied) {
        try PKCEAuthorizer.code(from: try #require(denied), expectedState: "mine", issuer: issuer, requiresIssuer: true)
    }
}

extension Network {
    @Suite struct Authorization {
        @Test func authorizationCodeFlowSendsPKCEStateAndResource() async throws {
            let stub = StubServer { request, _ in
                request.url.path == "/oauth/token" ? .json(Fixture.tokenResponse) : .notFound
            }
            let presenter = FakePresenter {
                "http://127.0.0.1:47613/callback?code=the-code&state=\($0)&\(Fixture.clerkIss)"
            }
            let client = Fixture.client(try Fixture.server(Fixture.clerkMetadata), session: stub.session())

            let tokens = try await PKCEAuthorizer(client: client, presenter: presenter, hasher: FakeHasher())
                .authorize()

            #expect(tokens.accessToken == "new-access")
            #expect(tokens.refreshToken == "new-refresh")
            let opened = try #require(presenter.opened.value.first)
            let query = Dictionary(
                uniqueKeysWithValues: (URLComponents(url: opened, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                    .map { ($0.name, $0.value ?? "") })
            #expect(opened.path == "/oauth/authorize")
            #expect(query["response_type"] == "code")
            #expect(query["client_id"] == "client-1")
            #expect(query["redirect_uri"] == "http://127.0.0.1:47613/callback")
            #expect(query["scope"] == "openid email offline_access")
            #expect(query["code_challenge"] == "-__--_8")
            #expect(query["code_challenge_method"] == "S256")
            #expect(query["resource"] == "https://mcp.higgsfield.ai/mcp")
            #expect(query["state"]?.count == 32)

            let exchange = try #require(stub.requests.first)
            #expect(exchange.method == "POST")
            #expect(exchange.header("Content-Type") == "application/x-www-form-urlencoded")
            let form = exchange.form
            #expect(form["grant_type"] == "authorization_code")
            #expect(form["code"] == "the-code")
            #expect(form["client_id"] == "client-1")
            #expect(form["redirect_uri"] == "http://127.0.0.1:47613/callback")
            #expect(form["resource"] == "https://mcp.higgsfield.ai/mcp")
            #expect(form["code_verifier"].map { (43...128).contains($0.count) } == true)
        }

        @Test func stateMismatchNeverReachesTheTokenEndpoint() async throws {
            let stub = StubServer { _, _ in .json(Fixture.tokenResponse) }
            let presenter = FakePresenter { _ in "http://127.0.0.1:47613/callback?code=the-code&state=forged" }
            let client = Fixture.client(try Fixture.server(Fixture.clerkMetadata), session: stub.session())
            await #expect(throws: OAuthError.stateMismatch) {
                try await PKCEAuthorizer(client: client, presenter: presenter, hasher: FakeHasher()).authorize()
            }
            #expect(stub.requests.isEmpty)
        }
    }
}
