import Foundation
import JutsuCore
import JutsuTestSupport
import Testing

@testable import Presentation

enum Fixture {
    static func tokens(_ access: String = "access-1", email: String? = nil, name: String? = nil) -> OAuthTokens {
        OAuthTokens(
            accessToken: access, refreshToken: "refresh", expiresAt: Date(timeIntervalSince1970: 20_000),
            scope: "openid email offline_access", clientID: "client", email: email, name: name)
    }

    static let signInPage = URL(string: "https://example.com/oauth/authorize?state=1")!
}

final class FakeVault: CredentialVault, @unchecked Sendable {
    // Safe: `data` is only touched under `lock`.
    private let lock = NSLock()
    private var data: Data?
    var failsDelete = false
    /// Reads throw, like a locked Keychain.
    var failsLoad = false

    init(_ credential: Credential? = nil) {
        data = credential.flatMap { try? JSONEncoder().encode($0) }
    }

    func saveData(_ data: Data) throws {
        locked { self.data = data }
    }

    func loadData() throws -> Data? {
        if failsLoad { throw CocoaError(.fileReadNoPermission) }
        return locked { data }
    }

    func delete() throws {
        if failsDelete { throw CocoaError(.fileWriteNoPermission) }
        locked { data = nil }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var credential: Credential? { try? loadCredential() }
}

final class FakeMetadataStore: ConnectionMetadataStore {
    var stored: ConnectionMetadata?

    init(_ stored: ConnectionMetadata? = nil) {
        self.stored = stored
    }

    func load() -> ConnectionMetadata? { stored }
    func save(_ metadata: ConnectionMetadata) { stored = metadata }
    func clear() { stored = nil }
}

struct FakeServices: ConnectionServices {
    var validate: @Sendable (String, String) async throws -> Bool = { _, _ in true }
    var browser: @Sendable () async throws -> OAuthTokens = { Fixture.tokens() }
    /// The `previous` tokens of every sign-in, in order.
    let previous = Box<[OAuthTokens?]>([])
    let revoked = Box<[OAuthTokens]>([])

    func validateAPIKey(id: String, secret: String) async throws -> Bool {
        try await validate(id, secret)
    }

    func signInWithBrowser(
        reusing previous: OAuthTokens?, show: @escaping @Sendable (URL) async -> Void
    ) async throws -> OAuthTokens {
        self.previous.update { $0.append(previous) }
        await show(Fixture.signInPage)
        return try await browser()
    }

    func revoke(_ tokens: OAuthTokens) async {
        revoked.update { $0.append(tokens) }
    }
}

/// A value shared with `@Sendable` fakes.
final class Box<Value: Sendable>: @unchecked Sendable {
    // Safe: `stored` is only touched under `lock`.
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value { lock.withLock { stored } }

    func update(_ body: (inout Value) -> Void) { lock.withLock { body(&stored) } }
}

/// What image runs sleep between polls in tests: a moment, not a yield. Runs on the main actor, and a poll that
/// only yields keeps it busy for every other test while a request is held or after its test ends.
let pollPause: @Sendable (Duration) async throws -> Void = { _ in try await Task.sleep(for: .milliseconds(20)) }

/// Waits until its task is cancelled, then records that it was and throws `CancellationError`.
/// Records an issue instead after `timeout`.
func waitForCancellation(
    _ cancelled: Box<Bool>, timeout: Duration = waitLimit, sourceLocation: SourceLocation = #_sourceLocation
) async throws -> OAuthTokens {
    let deadline = ContinuousClock.now + timeout
    while !Task.isCancelled {
        guard ContinuousClock.now < deadline else {
            Issue.record("Task was not cancelled within \(timeout)", sourceLocation: sourceLocation)
            throw CancellationError()
        }
        try? await Task.sleep(for: .milliseconds(1))
    }
    cancelled.update { $0 = true }
    throw CancellationError()
}
