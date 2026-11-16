import Foundation
import HiggsfieldMCP
import JutsuCore
import Testing

@testable import HiggsfieldProviders

@Test(arguments: [
    (OAuthError.stateMismatch, SignInError.invalidResponse),
    (.accessDenied, .denied),
    (.reauthenticationRequired, .reauthenticationRequired),
    (.server(code: "invalid_client", description: nil), .server("invalid_client")),
])
func oauthFailuresBecomeSignInErrors(oauth: OAuthError, expected: SignInError) {
    #expect(AccountSignIn.error(for: oauth) as? SignInError == expected)
}

@Test func tokensKeepTheRedirectURITheyWereSignedInWith() {
    let redirectURI = "https://example.com/ios/oauth/callback/"
    let tokens = OAuthTokens(
        accessToken: "access", refreshToken: nil, expiresAt: .now, scope: "", clientID: "client",
        redirectURI: redirectURI)

    #expect(tokens.tokenSet.redirectURI == redirectURI)
    #expect(OAuthTokens(tokens.tokenSet).redirectURI == redirectURI)
}
