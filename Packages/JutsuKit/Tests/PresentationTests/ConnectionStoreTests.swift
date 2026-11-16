import Foundation
import JutsuCore
import JutsuTestSupport
import Testing

@testable import Presentation

@MainActor
@Suite(.timeLimit(.minutes(1))) struct ConnectionStoreTests {
    let vault: FakeVault
    let metadata: FakeMetadataStore

    init() {
        vault = FakeVault()
        metadata = FakeMetadataStore()
    }

    func store(
        _ services: FakeServices = FakeServices(), vault: FakeVault? = nil, metadata: FakeMetadataStore? = nil
    )
        -> (ConnectionStore, Recorder)
    {
        let store = ConnectionStore(
            vault: vault ?? self.vault, metadata: metadata ?? self.metadata, services: services)
        let recorder = Recorder()
        store.onCredentialChange = { recorder.credentials.append($0) }
        return (store, recorder)
    }

    // MARK: Restore

    @Test func persistedAPIKeyIsRestoredAndReportedOnActivate() async {
        let vault = FakeVault(.apiKey(id: "kid", secret: "s"))
        let metadata = FakeMetadataStore(ConnectionMetadata(kind: .apiKey, displayName: "kid", plan: nil))
        let (store, recorder) = store(vault: vault, metadata: metadata)
        #expect(store.state == .apiKey(keyID: "kid"))
        await store.activate()
        #expect(recorder.credentials == [.apiKey(id: "kid", secret: "s")])
    }

    @Test func persistedAccountIsRestored() {
        let vault = FakeVault(.oauth(Fixture.tokens()))
        let metadata = FakeMetadataStore(ConnectionMetadata(kind: .account, displayName: "me@example.com", plan: "Pro"))
        let (store, _) = store(vault: vault, metadata: metadata)
        #expect(store.state == .account(AccountInfo(email: "me@example.com", plan: "Pro")))
    }

    // MARK: API key

    @Test func validKeyIsTrimmedSavedAndReported() async {
        let checked = Recorder()
        let services = FakeServices(validate: { id, secret in
            await MainActor.run { checked.keys.append("\(id):\(secret)") }
            return true
        })
        let (store, recorder) = store(services)
        let form = APIKeyForm(keyID: "  kid\t", secret: "\nsecret\n")
        #expect(form.isComplete)
        await store.connectAPIKey(form)
        #expect(checked.keys == ["kid:secret"])
        #expect(store.state == .apiKey(keyID: "kid"))
        #expect(store.activity == .idle)
        #expect(store.alert == nil)
        #expect(vault.credential == .apiKey(id: "kid", secret: "secret"))
        #expect(metadata.stored == ConnectionMetadata(kind: .apiKey, displayName: "kid", plan: nil))
        #expect(recorder.credentials == [.apiKey(id: "kid", secret: "secret")])
    }

    @Test func refusedKeyShowsKeyIsInvalidAndSavesNothing() async {
        let (store, recorder) = store(FakeServices(validate: { _, _ in false }))
        await store.connectAPIKey(APIKeyForm(keyID: "kid", secret: "bad"))
        #expect(store.state == .none)
        #expect(store.alert == .invalidKey)
        #expect(vault.credential == nil)
        #expect(metadata.stored == nil)
        #expect(recorder.credentials.isEmpty)
    }

    // MARK: Account

    @Test func browserSignInConnectsTheAccount() async {
        let (store, recorder) = store()
        await store.startSignIn().value
        #expect(store.state == .account(AccountInfo()))
        #expect(store.activity == .idle)
        #expect(vault.credential == .oauth(Fixture.tokens()))
        #expect(metadata.stored?.kind == .account)
        #expect(recorder.credentials == [.oauth(Fixture.tokens())])
    }

    @Test func canceledSignInIgnoresALateResult() async {
        let gate = Gate<OAuthTokens>()
        let (store, recorder) = store(FakeServices(browser: { try await gate.wait() }))
        let task = store.startSignIn()
        #expect(store.activity == .signingIn(nil))
        await eventually { await gate.isWaiting }
        store.cancelSignIn()
        #expect(store.activity == .idle)
        await gate.open(.success(Fixture.tokens()))
        await task.value
        #expect(store.state == .none)
        #expect(vault.credential == nil)
        #expect(recorder.credentials.isEmpty)
    }

    @Test func signingInAgainReplacesTheOpenSignIn() async {
        let cancelled = Box(false)
        let first = Box(true)
        let (store, _) = store(
            FakeServices(browser: {
                guard first.value else { return Fixture.tokens("second") }
                first.update { $0 = false }
                return try await waitForCancellation(cancelled)
            }))
        let browser = store.startSignIn()
        await eventually { !first.value }
        await store.startSignIn().value
        await browser.value
        #expect(cancelled.value)
        #expect(vault.credential == .oauth(Fixture.tokens("second")))
        #expect(store.alert == nil)
    }

    @Test func storedTokensAreOfferedForClientReuse() async {
        let vault = FakeVault(.oauth(Fixture.tokens("old")))
        let services = FakeServices()
        let (store, _) = store(services, vault: vault)
        await store.startSignIn().value
        await store.startSignIn().value
        #expect(services.previous.value == [Fixture.tokens("old"), Fixture.tokens()])
    }

    // MARK: Sign out

    @Test func signOutDeletesTheCredentialAndReportsNil() async {
        let vault = FakeVault(.apiKey(id: "kid", secret: "s"))
        let metadata = FakeMetadataStore(ConnectionMetadata(kind: .apiKey, displayName: "kid", plan: nil))
        let (store, recorder) = store(vault: vault, metadata: metadata)
        store.markNeedsAttention()
        await store.signOut()
        #expect(store.state == .none)
        #expect(!store.needsAttention)
        #expect(vault.credential == nil)
        #expect(metadata.stored == nil)
        #expect(recorder.credentials == [nil])
        let (restarted, _) = self.store(vault: vault, metadata: metadata)
        #expect(restarted.state == .none)
    }

    @Test func signOutRevokesTheAccountInTheBackground() async {
        let services = FakeServices()
        let (store, _) = store(services)
        await store.startSignIn().value

        await store.signOut()
        await store.revocation?.value

        #expect(services.revoked.value == [Fixture.tokens()])
    }

    // MARK: Refreshed tokens

    @Test func refreshForTheCurrentSignInIsSaved() async throws {
        let (store, _) = store()
        await store.startSignIn().value
        let refreshed = Fixture.tokens("access-2")

        let saved = try store.saveRefreshedTokens(refreshed, generation: store.credentialGeneration)
        #expect(saved)
        #expect(vault.credential == .oauth(refreshed))
    }

    @Test func refreshFinishingAfterSignOutIsDropped() async throws {
        let (store, _) = store()
        await store.startSignIn().value
        let generation = store.credentialGeneration
        await store.signOut()

        let saved = try store.saveRefreshedTokens(Fixture.tokens("access-2"), generation: generation)
        #expect(!saved)
        #expect(vault.credential == nil)
    }

    @Test func refreshOfThePreviousAccountIsDroppedAfterASwitch() async throws {
        let signIns = Box(0)
        let services = FakeServices(browser: {
            signIns.update { $0 += 1 }
            return signIns.value == 1
                ? Fixture.tokens("a", email: "a@example.com") : Fixture.tokens("b", email: "b@example.com")
        })
        let (store, _) = store(services)
        await store.startSignIn().value
        let first = store.credentialGeneration
        await store.startSignIn().value

        let saved = try store.saveRefreshedTokens(Fixture.tokens("a-2", email: "a@example.com"), generation: first)
        #expect(!saved)
        #expect(vault.credential == .oauth(Fixture.tokens("b", email: "b@example.com")))
    }

    @Test func accountTokensUnderAnotherAccountsNameAreNotRestored() {
        let vault = FakeVault(.oauth(Fixture.tokens(email: "a@example.com")))
        let metadata = FakeMetadataStore(ConnectionMetadata(kind: .account, displayName: "b@example.com", plan: nil))
        let (store, _) = store(vault: vault, metadata: metadata)
        #expect(store.state == .none)
    }

    @Test func failedDeleteKeepsTheConnection() async {
        let vault = FakeVault(.apiKey(id: "kid", secret: "s"))
        vault.failsDelete = true
        let metadata = FakeMetadataStore(ConnectionMetadata(kind: .apiKey, displayName: "kid", plan: nil))
        let (store, recorder) = store(vault: vault, metadata: metadata)
        await store.signOut()
        #expect(store.state == .apiKey(keyID: "kid"))
        #expect(store.alert != nil)
        #expect(recorder.credentials.isEmpty)
    }

    // MARK: Keychain read failures

    @Test func keychainFailingAtActivateDisconnectsWithAnAlert() async {
        let vault = FakeVault(.apiKey(id: "kid", secret: "s"))
        let metadata = FakeMetadataStore(ConnectionMetadata(kind: .apiKey, displayName: "kid", plan: nil))
        let (store, recorder) = store(vault: vault, metadata: metadata)
        vault.failsLoad = true

        await store.activate()

        #expect(store.state == .none)
        #expect(store.alert != nil)
        #expect(recorder.credentials == [nil])
        #expect(metadata.stored != nil)
    }
}

@MainActor
final class Recorder {
    var credentials: [Credential?] = []
    var keys: [String] = []
}
