import Foundation
import HiggsfieldCore
import HiggsfieldTestSupport
import Testing

@testable import HiggsfieldMCP

@Suite(.timeLimit(.minutes(1))) struct TokenProviderTests {
    let now = Date(timeIntervalSince1970: 10_000)
    /// What the providers read as the current time; starts at `now`.
    let clock = Locked(Date(timeIntervalSince1970: 10_000))
    let refreshes = Locked(0)
    let persisted = Locked<[TokenSet]>([])

    /// `failures`: how many refreshes fail before one succeeds.
    func provider(expiresIn: TimeInterval, refreshToken: String? = "refresh-1", failures: Int = 0) -> TokenProvider {
        let now = now
        let clock = clock
        let refreshes = refreshes
        let persisted = persisted
        return TokenProvider(
            tokens: Fixture.tokens(refresh: refreshToken, expiresAt: now.addingTimeInterval(expiresIn)),
            now: { clock.value },
            refresh: { old in
                let count = refreshes.update { count -> Int in
                    count += 1
                    return count
                }
                try await Task.sleep(for: .milliseconds(50))
                if count <= failures { throw OAuthError.server(code: "invalid_grant", description: nil) }
                return Fixture.tokens(access: "access-\(count + 1)", refresh: old.refreshToken, expiresAt: now + 3600)
            },
            persist: { tokens in persisted.update { $0.append(tokens) } })
    }

    @Test func tokenInsideTheMarginIsRefreshedAndPersisted() async throws {
        #expect(try await provider(expiresIn: 59).accessToken() == "access-2")
        #expect(refreshes.value == 1)
        #expect(persisted.value.map(\.accessToken) == ["access-2"])
    }

    @Test func concurrentCallersShareOneRefresh() async throws {
        let provider = provider(expiresIn: -10)
        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<10 { group.addTask { try await provider.accessToken() } }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(refreshes.value == 1)
        #expect(Set(tokens) == ["access-2"])
    }

    @Test func refusedRefreshRequiresSignIn() async {
        await #expect(throws: OAuthError.reauthenticationRequired) {
            try await provider(expiresIn: 0, failures: 1).accessToken()
        }
        await #expect(throws: OAuthError.reauthenticationRequired) {
            try await provider(expiresIn: 0, refreshToken: nil).accessToken()
        }
        #expect(refreshes.value == 1)
        #expect(persisted.value.isEmpty)
    }

    /// A provider whose refresh fails once with `error`, then succeeds.
    func provider(failingOnceWith error: any Error) -> TokenProvider {
        let refreshes = refreshes
        let clock = clock
        return TokenProvider(
            tokens: Fixture.tokens(expiresAt: now), now: { clock.value },
            refresh: { [now] old in
                let count = refreshes.update { count -> Int in
                    count += 1
                    return count
                }
                if count == 1 { throw error }
                return Fixture.tokens(access: "access-\(count + 1)", refresh: old.refreshToken, expiresAt: now + 3600)
            },
            persist: { _ in })
    }

    @Test func serverErrorKeepsTheTokensForTheNextCall() async throws {
        let provider = provider(failingOnceWith: HiggsfieldError.server(status: 503))
        await #expect(throws: HiggsfieldError.server(status: 503)) { try await provider.accessToken() }
        await #expect(throws: HiggsfieldError.server(status: 503)) { try await provider.accessToken() }
        #expect(refreshes.value == 1)
        clock.update { $0 += 5 }
        #expect(try await provider.accessToken() == "access-3")
    }
}

extension Network {
    /// `OAuthClient.refresh` against the token endpoint, as `TokenProvider` sees it.
    @Suite struct RefreshAnswers {
        func refresh(answer: StubResponse) async throws {
            let stub = StubServer { _, _ in answer }
            let client = Fixture.client(try Fixture.server(Fixture.clerkMetadata), session: stub.session())
            let provider = TokenProvider(
                tokens: Fixture.tokens(expiresAt: .distantPast), refresh: { try await client.refresh($0) },
                persist: { _ in })
            _ = try await provider.accessToken()
        }

        @Test func refusedGrantRequiresSignIn() async {
            await #expect(throws: OAuthError.reauthenticationRequired) {
                try await refresh(answer: .json(#"{"error":"invalid_grant"}"#, status: 400))
            }
            await #expect(throws: OAuthError.reauthenticationRequired) {
                try await refresh(
                    answer: .json(
                        #"{"error":"invalid_client"}"#, status: 401,
                        headers: ["WWW-Authenticate": defaultBearerChallenge]))
            }
            await #expect(throws: OAuthError.reauthenticationRequired) {
                try await refresh(answer: StubResponse(status: 400))
            }
        }
    }
}
