import AuthenticationServices
import Foundation
import HiggsfieldAPI
import HiggsfieldMCP
import HiggsfieldProviders
import JutsuCore
import Presentation
import Secrets
import os

nonisolated private let logger = Logger.jutsu("Connection")

nonisolated enum Higgsfield {
    // swiftlint:disable:next force_unwrapping
    static let mcpEndpoint = URL(string: "https://mcp.higgsfield.ai/mcp")!
    // swiftlint:disable:next force_unwrapping
    static let consoleURL = URL(string: "https://console.higgsfield.ai")!

    /// Serves our OAuth client metadata document and apple-app-site-association (`AUTH_DOMAIN` in project.yml).
    static var authDomain: String {
        Bundle.main.object(forInfoDictionaryKey: "JutsuAuthDomain") as? String ?? "jutsustudio.com"
    }

    /// Our Client ID Metadata Document: the sign-in's `client_id`. Lists `redirectURI` as its only redirect.
    static var clientMetadataDocument: URL {
        // swiftlint:disable:next force_unwrapping
        URL(string: "https://\(authDomain)/ios/oauth-client.json")!
    }

    static let callbackPath = "/ios/oauth/callback/"
    static var redirectURI: String { "https://\(authDomain)\(callbackPath)" }
}

/// The Keychain item of the active connection as the `CredentialVault` the connection store writes to.
nonisolated struct KeychainVault: CredentialVault {
    let store: KeychainStore

    func saveData(_ data: Data) throws { try store.saveData(data) }
    func loadData() throws -> Data? { try store.loadData() }
    func delete() throws { try store.delete() }
}

/// The network side of connecting: key validation over REST, account sign-in over OAuth in a web sheet.
nonisolated struct HiggsfieldConnectionServices: ConnectionServices {
    func validateAPIKey(id: String, secret: String) async throws -> Bool {
        try await HiggsfieldAPIClient(keyID: id, secret: secret).validateKey()
    }

    func signInWithBrowser(
        reusing previous: OAuthTokens?, show: @escaping @concurrent @Sendable (URL) async -> Void
    ) async throws -> OAuthTokens {
        do {
            let client = try await AccountAuthorization.client(reusing: previous)
            let presenter = WebAuthenticationPresenter(
                redirectURI: Higgsfield.redirectURI, host: Higgsfield.authDomain, path: Higgsfield.callbackPath,
                show: show)
            return OAuthTokens(try await PKCEAuthorizer(client: client, presenter: presenter).authorize())
        } catch {
            throw AccountSignIn.error(for: error)
        }
    }

    func revoke(_ tokens: OAuthTokens) async {
        do {
            try await AccountAuthorization.revoke(tokens.tokenSet)
        } catch {
            logger.info("Can't revoke the signed-out tokens: \(String(describing: error), privacy: .private)")
        }
    }
}

nonisolated enum AccountAuthorization {
    /// The OAuth client at the first server offering the authorization code flow; endpoints are discovered on every
    /// sign-in and refresh. `previous` lets registration reuse the client ID stored with earlier tokens.
    static func client(reusing previous: OAuthTokens? = nil) async throws -> OAuthClient {
        let discovered = try await OAuthDiscovery().discover(mcpURL: Higgsfield.mcpEndpoint)
        guard let server = discovered.authorizationCodeServer else { throw OAuthError.unsupportedFlow }
        let registration = ClientRegistration(
            metadataDocumentURL: Higgsfield.clientMetadataDocument, redirectURIs: [Higgsfield.redirectURI])
        let id = try await registration.clientID(at: server, reusing: previous?.tokenSet)
        return OAuthClient(server: server, clientID: id, resource: discovered.resource.resource)
    }

    static func refresh(_ tokens: TokenSet) async throws -> TokenSet {
        let discovered = try await OAuthDiscovery().discover(mcpURL: Higgsfield.mcpEndpoint)
        return try await discovered.client(issuing: tokens).refresh(tokens)
    }

    static func revoke(_ tokens: TokenSet) async throws {
        let discovered = try await OAuthDiscovery().discover(mcpURL: Higgsfield.mcpEndpoint)
        try await discovered.client(issuing: tokens).revoke(tokens)
    }
}

nonisolated enum ProviderFactory {
    /// The provider for `credential`. Refreshed account tokens go to `persist`.
    static func provider(
        for credential: Credential, persist: @escaping @Sendable (OAuthTokens) async -> Void,
        unlimitedOptIn: @escaping @Sendable () async -> Bool,
        constraints: @escaping @Sendable () async -> ModelConstraintTable
    ) -> any GenerationProvider {
        switch credential {
        case .apiKey(let id, let secret):
            return HiggsfieldAPIProvider(client: HiggsfieldAPIClient(keyID: id, secret: secret))
        case .oauth(let tokens):
            let tokenProvider = TokenProvider(
                tokens: tokens.tokenSet,
                refresh: { try await AccountAuthorization.refresh($0) },
                persist: { await persist(OAuthTokens($0)) })
            let client = MCPClient(endpoint: Higgsfield.mcpEndpoint, tokens: tokenProvider)
            return HiggsfieldMCPProvider(
                account: HiggsfieldAccount(client: client), owner: tokens.owner, unlimitedOptIn: unlimitedOptIn,
                constraints: constraints)
        }
    }
}
