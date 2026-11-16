import AuthenticationServices
import Foundation
import HiggsfieldMCP
import UIKit

/// The browser step of the account sign-in on iOS: `ASWebAuthenticationSession` with an HTTPS Universal Link callback,
/// sharing Safari's cookies so someone signed in to higgsfield.ai only taps Allow.
nonisolated struct WebAuthenticationPresenter: AuthorizationPresenter {
    let redirectURI: String
    let host: String
    let path: String
    let show: @concurrent @Sendable (URL) async -> Void

    func authorize(makeURL: @Sendable (_ redirectURI: String) throws -> URL) async throws -> AuthorizationRedirect {
        let url = try makeURL(redirectURI)
        guard url.scheme?.lowercased() == "https" else { throw URLError(.unsupportedURL) }
        await show(url)
        let callback = try await WebAuthenticationSheet().run(url: url, host: host, path: path)
        return AuthorizationRedirect(callback: callback, redirectURI: redirectURI)
    }
}

@MainActor
private final class WebAuthenticationSheet: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func run(url: URL, host: String, path: String) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(url: url, callback: .https(host: host, path: path)) {
                    callback, error in
                    if let callback {
                        continuation.resume(returning: callback)
                    } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(throwing: error ?? CancellationError())
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                self.session = session
                // The completion handler isn't called when the sheet can't be shown at all.
                if !session.start() {
                    continuation.resume(throwing: ASWebAuthenticationSessionError(.presentationContextInvalid))
                }
            }
        } onCancel: {
            Task { @MainActor in self.session?.cancel() }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let key = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return key }
            // Sign-in starts from a button on screen, so there is always a scene to put the sheet over.
            guard let scene = scenes.first else { preconditionFailure("Sign-in started with no window scene") }
            return ASPresentationAnchor(windowScene: scene)
        }
    }
}
