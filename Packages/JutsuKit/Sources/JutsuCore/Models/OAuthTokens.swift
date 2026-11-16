import Foundation

public struct OAuthTokens: Codable, Sendable, Hashable {
    public var accessToken: String
    /// Absent when the server didn't grant `offline_access`.
    public var refreshToken: String?
    public var expiresAt: Date
    /// Space-separated, as returned by the token endpoint.
    public var scope: String
    public var clientID: String
    /// The authorization server that issued `clientID`; a registered client ID is only valid there.
    public var issuer: URL?
    /// From the `id_token`, for display only.
    public var email: String?
    public var name: String?
    /// The `id_token`'s `sub`. Not verified: it only tells local jobs of different accounts apart.
    /// Absent when the authorization server sends no subject claim.
    public var subject: String?
    /// The redirect URI the sign-in used: a registered `clientID` only accepts the redirects it was registered with.
    /// Absent in tokens stored before it was recorded, which were registered for the loopback redirects.
    public var redirectURI: String?

    public init(
        accessToken: String, refreshToken: String?, expiresAt: Date, scope: String, clientID: String,
        issuer: URL? = nil, email: String? = nil, name: String? = nil, subject: String? = nil,
        redirectURI: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
        self.clientID = clientID
        self.issuer = issuer
        self.email = email
        self.name = name
        self.subject = subject
        self.redirectURI = redirectURI
    }

    /// `GenerationProvider.owner` for this account: its subject, or its email when the server sent none.
    public var owner: String? { subject ?? email }
}

extension OAuthTokens: CustomStringConvertible {
    public var description: String {
        let refresh = refreshToken == nil ? "nil" : "<redacted>"
        return "OAuthTokens(accessToken: <redacted>, refreshToken: \(refresh), expiresAt: \(expiresAt), "
            + "scope: \(scope), clientID: \(clientID))"
    }
}
