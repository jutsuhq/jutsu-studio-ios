import Foundation
import HiggsfieldCore

/// Hands out a valid access token: refreshes ahead of expiry, runs one refresh at a time for all callers,
/// waits `retryDelay` after a failed refresh before trying again, and asks for a new sign-in only when the refresh
/// itself is refused.
public actor TokenProvider {
    public typealias Refresh = @Sendable (TokenSet) async throws -> TokenSet
    /// Saves refreshed tokens (the app writes them to Keychain); failures there are the caller's to log.
    /// It may drop the write: a refresh can finish after the user signed out or switched accounts.
    public typealias Persist = @Sendable (TokenSet) async -> Void

    private var tokens: TokenSet
    private var refreshing: Task<TokenSet, any Error>?
    /// Until `retryDelay` after it, callers get this error instead of starting another refresh.
    private var lastFailure: (error: any Error, at: Date)?
    private let refresh: Refresh
    private let persist: Persist
    private let now: @Sendable () -> Date
    /// Seconds before `expiresAt` at which a token already counts as expired.
    private let margin: TimeInterval
    /// Seconds after a failed refresh during which no new one starts.
    private let retryDelay: TimeInterval = 5

    public init(
        tokens: TokenSet, margin: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = Date.init, refresh: @escaping Refresh, persist: @escaping Persist
    ) {
        self.tokens = tokens
        self.margin = margin
        self.now = now
        self.refresh = refresh
        self.persist = persist
    }

    public func accessToken() async throws -> String {
        if refreshing == nil, now() < tokens.expiresAt.addingTimeInterval(-margin) {
            return tokens.accessToken
        }
        return try await refreshed().accessToken
    }

    /// After a `401` for `rejected`: refreshes, unless another caller already replaced that token.
    public func accessToken(replacing rejected: String) async throws -> String {
        if refreshing == nil, tokens.accessToken != rejected { return tokens.accessToken }
        return try await refreshed().accessToken
    }

    /// The task runs only the network call; the caller that started it stores and persists the result
    /// here on the actor, and keeps `refreshing` set until then so later callers join instead of refreshing again.
    private func refreshed() async throws -> TokenSet {
        if let refreshing { return try await refreshing.value }
        guard tokens.refreshToken != nil else { throw OAuthError.reauthenticationRequired }
        if let lastFailure, now() < lastFailure.at.addingTimeInterval(retryDelay) { throw lastFailure.error }
        let task = Task { [refresh, tokens] in try await Self.run(refresh, from: tokens) }
        refreshing = task
        defer { if refreshing == task { refreshing = nil } }
        let new: TokenSet
        do {
            new = try await task.value
        } catch {
            if refreshing == task, !(error is CancellationError) { lastFailure = (error, now()) }
            throw error
        }
        if refreshing == task {
            tokens = new
            lastFailure = nil
            await persist(new)
        }
        return new
    }

    /// Only a refusal of the refresh token asks for a new sign-in. Anything else (no answer, a 5xx, an unreadable
    /// reply, metadata that can't be read) keeps the tokens to refresh again after the delay, and is thrown as
    /// `HiggsfieldError`: as it is, or as `.network` when it isn't one.
    private static func run(_ refresh: Refresh, from tokens: TokenSet) async throws -> TokenSet {
        do {
            return try await refresh(tokens)
        } catch let error as HiggsfieldError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as OAuthError where error.refusesRefresh {
            throw OAuthError.reauthenticationRequired
        } catch {
            throw HiggsfieldError.network
        }
    }
}
