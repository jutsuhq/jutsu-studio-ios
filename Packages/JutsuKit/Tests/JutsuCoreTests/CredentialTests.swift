import Foundation
import Testing

@testable import JutsuCore

private let tokens = OAuthTokens(
    accessToken: "ACCESS-SECRET", refreshToken: "REFRESH-SECRET", expiresAt: Date(timeIntervalSince1970: 0),
    scope: "openid offline_access", clientID: "https://example.com/client.json")

@Test func apiKeyDescriptionRedactsTheSecret() {
    let credential = Credential.apiKey(id: "key-id", secret: "KEY-SECRET")
    for text in [String(describing: credential), String(reflecting: credential), "\(credential)"] {
        #expect(!text.contains("KEY-SECRET"))
        #expect(text.contains("key-id"))
    }
}

@Test func oauthDescriptionRedactsBothTokens() {
    for text in [String(describing: Credential.oauth(tokens)), String(reflecting: tokens), "\(tokens)"] {
        #expect(!text.contains("ACCESS-SECRET"))
        #expect(!text.contains("REFRESH-SECRET"))
        #expect(text.contains("openid offline_access"))
    }
}
