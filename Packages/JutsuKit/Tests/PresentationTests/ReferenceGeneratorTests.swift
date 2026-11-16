import Foundation
import JutsuCore
import JutsuTestSupport
import Testing

@testable import Presentation

/// An image provider whose answers the test scripts: `statuses` are handed out in order, the last one repeated.
private actor FakeImageProvider: ImageProvider {
    nonisolated let kind: ProviderKind
    nonisolated let owner: String?
    /// The account connection has no tool that cancels a generation.
    nonisolated let canCancel: Bool
    /// The media ID its uploads answer with: each account names its own media.
    let mediaID: String
    var estimate: Result<Cost, ProviderError> = .success(.usd(Decimal(string: "0.0128")!, isEstimate: false))
    var submitError: ProviderError?
    var statuses: [ImageJobStatus] = [.completed([URL(string: "https://cdn.example.com/1.png")!])]
    /// Thrown by every poll while set: the status couldn't be read.
    var pollError: ProviderError?
    var cancelError: ProviderError?
    /// Hold the submit or the upload until opened, when set.
    var submitGate: Gate<Void>?
    var uploadGate: Gate<Void>?
    private(set) var submitted: [ImageRequest] = []
    private(set) var polls = 0
    private(set) var cancels = 0
    private(set) var uploads = 0

    init(kind: ProviderKind = .apiKey, owner: String? = "key-1", mediaID: String = "media-1", canCancel: Bool = true) {
        self.kind = kind
        self.owner = owner
        self.mediaID = mediaID
        self.canCancel = canCancel
    }

    func failPolls(with error: ProviderError?, then statuses: [ImageJobStatus]? = nil) {
        pollError = error
        if let statuses { self.statuses = statuses }
    }

    func hold(submit: Gate<Void>? = nil, upload: Gate<Void>? = nil) {
        submitGate = submit
        uploadGate = upload
    }

    func set(
        estimate: Result<Cost, ProviderError>? = nil, submitError: ProviderError? = nil,
        statuses: [ImageJobStatus]? = nil, cancelError: ProviderError? = nil
    ) {
        if let estimate { self.estimate = estimate }
        self.submitError = submitError
        if let statuses { self.statuses = statuses }
        self.cancelError = cancelError
    }

    func imageModels() async throws -> [ImageModel] { [] }

    func imageEstimate(_ request: ImageRequest) async throws -> Cost {
        try estimate.get()
    }

    func upload(_ file: PreparedFile) async throws -> RemoteAsset {
        uploads += 1
        if let uploadGate { try await uploadGate.wait() }
        return RemoteAsset(url: URL(string: "https://cdn.example.com/in.png")!, id: mediaID)
    }

    func submitImages(_ request: ImageRequest, idempotencyKey: UUID) async throws -> [RemoteJob] {
        submitted.append(request)
        if let submitGate { try await submitGate.wait() }
        if let submitError { throw submitError }
        return [RemoteJob(requestID: "req-1")]
    }

    func imageStatus(_ job: RemoteJob) async throws -> ImageJobStatus {
        polls += 1
        if let pollError { throw pollError }
        return statuses.count > 1 ? statuses.removeFirst() : statuses[0]
    }

    func cancelImages(_ job: RemoteJob) async throws {
        cancels += 1
        if let cancelError { throw cancelError }
    }
}

private let soul = ImageModel(
    id: "soul", title: "Soul 2", variantCounts: [1, 4], aspectRatios: ["1:1", "3:4", "9:16", "16:9"],
    listPrice: .usd(Decimal(string: "0.0032")!, isEstimate: true))
private let qwen = ImageModel(
    id: "qwen", title: "Qwen Image 3 Edit", aspectRatios: ["1:1", "21:9"], input: .required,
    listPrice: .usd(Decimal(string: "0.04")!, isEstimate: true))
private let input = LocalImage(fileURL: URL(fileURLWithPath: "/tmp/knight.png"))

@MainActor
@Suite struct ReferenceGeneratorTests {
    let spend = ImageSpendLog(folder: nil)
    let jobLog = ImageJobLog(folder: nil)

    func generator() -> ReferenceGenerator {
        let generator = ReferenceGenerator(spend: spend, jobLog: jobLog, sleep: pollPause)
        generator.useModels([soul, qwen])
        generator.prompt = "a knight in silver armor"
        return generator
    }

    fileprivate nonisolated static func upload(
        _ provider: FakeImageProvider
    ) -> @Sendable (LocalImage) async throws -> RemoteAsset {
        { _ in
            try await provider.upload(
                PreparedFile(fileURL: input.fileURL, contentType: "image/png", byteCount: 1, contentHash: "h"))
        }
    }

    /// A refused submit and one never sent cost nothing; one left unanswered may have started, so it keeps counting.
    @Test(arguments: [
        (ProviderError.insufficientFunds, [Bool]()), (.notSent, []), (.network, [false]),
    ])
    func aFailedSubmitIsChargedOnlyIfItMayHaveStarted(error: ProviderError, pending: [Bool]) async {
        let provider = FakeImageProvider()
        await provider.set(submitError: error)
        let generator = generator()

        await generator.generate(
            provider: provider, source: nil, mode: .motionTransfer, price: soul.listPrice,
            upload: Self.upload(provider))
        await eventually { generator.runs.first?.state != .running }

        #expect(spend.charges.map(\.isPending) == pending)
    }

    @Test func aPollTurnedDownForTheSignInKeepsTheJobAndItsPriceAndFollowsItAgainAfterReconnecting() async {
        let provider = FakeImageProvider()
        await provider.failPolls(with: .unauthorized)
        let generator = generator()
        var signInRequests = 0
        generator.onSignInExpired = { signInRequests += 1 }

        await generator.generate(
            provider: provider, source: nil, mode: .motionTransfer, price: soul.listPrice,
            upload: Self.upload(provider))
        await eventually {
            if case .interrupted = generator.runs.first?.state { return true }
            return false
        }

        // Higgsfield accepted the request: it may still finish and be charged.
        #expect(signInRequests == 1)
        #expect(spend.charges.map(\.isPending) == [true])
        #expect(jobLog.pending(of: "key-1").map(\.id) == ["req-1"])

        // Reconnected: the same job is followed again, not sent again.
        await provider.failPolls(with: nil)
        generator.reset()
        generator.resume(provider: provider)
        await eventually { generator.runs.first?.state == .finished }

        #expect(await provider.submitted.count == 1)
        #expect(generator.images.map(\.prompt) == ["a knight in silver armor"])
        #expect(spend.charges.map(\.isPending) == [false])
        #expect(jobLog.records.isEmpty)
    }

    @Test func aRunTheConnectionCantCancelKeepsGoingAndDeliversItsImages() async {
        let provider = FakeImageProvider(canCancel: false)
        await provider.set(statuses: [.pending, .completed([URL(string: "https://cdn.example.com/1.png")!])])
        let generator = generator()

        await generator.generate(
            provider: provider, source: nil, mode: .motionTransfer, price: soul.listPrice,
            upload: Self.upload(provider))
        await eventually { await provider.polls > 0 }
        generator.cancel(generator.runs.first!.id)
        await eventually { generator.runs.first?.state == .finished }

        #expect(await provider.cancels == 0)
        #expect(generator.images.map(\.prompt) == ["a knight in silver armor"])
        #expect(spend.charges.map(\.isPending) == [false])
        #expect(jobLog.records.isEmpty)
    }

    @Test func anAcceptedRequestIsFollowedAgainAfterARelaunch() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let provider = FakeImageProvider()
        await provider.set(statuses: [.pending])
        let first = ReferenceGenerator(
            spend: ImageSpendLog(folder: folder), jobLog: ImageJobLog(folder: folder),
            sleep: pollPause)
        first.useModels([soul])
        first.prompt = "a knight in silver armor"
        await first.generate(
            provider: provider, source: nil, mode: .motionTransfer, price: soul.listPrice,
            upload: Self.upload(provider))
        await eventually { await provider.polls > 0 }
        // The app quits while the image is being made.
        first.reset()

        await provider.set(statuses: [.completed([URL(string: "https://cdn.example.com/1.png")!])])
        let spend = ImageSpendLog(folder: folder)
        let second = ReferenceGenerator(
            spend: spend, jobLog: ImageJobLog(folder: folder), sleep: pollPause)
        var saved: [GeneratedImage] = []
        second.onImages = { saved += $0 }
        second.resume(provider: provider)
        await eventually { second.runs.first?.state == .finished }

        #expect(saved.map(\.prompt) == ["a knight in silver armor"])
        #expect(saved.map(\.model) == ["Soul 2"])
        #expect(spend.charges.map(\.isPending) == [false])
        #expect(ImageJobLog(folder: folder).records.isEmpty)
        #expect(await provider.submitted.count == 1)
    }

    @Test func aSecondGenerateWhileTheFirstIsSentIsRefused() async {
        let provider = FakeImageProvider()
        let gate = Gate<Void>()
        await provider.hold(submit: gate)
        await provider.set(statuses: [.pending])
        let generator = generator()
        func generate() async -> PaidStart {
            await generator.generate(
                provider: provider, source: nil, mode: .motionTransfer, price: soul.listPrice,
                upload: Self.upload(provider))
        }

        #expect(await generate() == .started)
        await eventually { await gate.isWaiting }
        #expect(generator.isSubmitting)
        #expect(await generate() == .notStarted)

        await gate.open(.success(()))
        await eventually { !generator.isSubmitting }
        #expect(await provider.submitted.count == 1)
        #expect(spend.charges.count == 1)
        generator.reset()
    }

    @Test func aRequestWhosePriceCantBeWrittenIsNotSent() async throws {
        // A regular file where the data folder should be: nothing can be written under it.
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let provider = FakeImageProvider()
        let generator = ReferenceGenerator(
            spend: ImageSpendLog(folder: file), jobLog: jobLog, sleep: pollPause)
        generator.useModels([soul])
        generator.prompt = "a knight in silver armor"

        await generator.generate(
            provider: provider, source: nil, mode: .motionTransfer, price: soul.listPrice,
            upload: Self.upload(provider))
        await eventually { generator.runs.first?.state != .running }

        guard case .failed(let message) = generator.runs.first?.state else {
            Issue.record("Expected a failed run, got \(String(describing: generator.runs.first?.state))")
            return
        }
        #expect(message.hasPrefix("Nothing was sent"))
        #expect(await provider.submitted.isEmpty)
    }

    /// Generate reads today's spend itself right before sending, so a screen can't skip the cap.
    @Test func generateAsksBeforeGoingPastTheCapAndSendsOnceAgreed() async {
        let provider = FakeImageProvider()
        var committed = Decimal(0)
        let generator = ReferenceGenerator(
            spend: spend, jobLog: jobLog,
            spendStatus: { kind in kind == .apiKey ? SpendStatus(committedToday: committed, cap: .usd(1)) : nil },
            sleep: pollPause)
        generator.useModels([soul])
        generator.prompt = "a knight in silver armor"
        let price = Cost.usd(Decimal(string: "0.08")!, isEstimate: false)
        func generate(price: Cost?, approved: Bool = false) async -> PaidStart {
            await generator.generate(
                provider: provider, source: nil, mode: .motionTransfer, price: price, overCapApproved: approved,
                upload: Self.upload(provider))
        }

        // Under the cap: sent.
        #expect(await generate(price: price) == .started)
        await eventually { generator.runs.first?.state == .finished }

        // A price not known yet, under a cap: asks, sends nothing.
        guard case .needsConfirmation(let unknown) = await generate(price: nil) else {
            Issue.record("Expected a question about the unknown price")
            return
        }
        #expect(unknown.title == "Price not known yet")

        // Over the cap: asks, sends nothing.
        committed = Decimal(string: "0.95")!
        guard case .needsConfirmation(let over) = await generate(price: price) else {
            Issue.record("Expected a question about the cap")
            return
        }
        #expect(over.title == "Over today's spend cap")
        #expect(over.confirmTitle == "Generate anyway")
        #expect(await provider.submitted.count == 1)
        #expect(spend.charges.count == 1)

        // Agreed: sent without asking again.
        #expect(await generate(price: price, approved: true) == .started)
        await eventually { generator.runs.first?.state == .finished }
        #expect(await provider.submitted.count == 2)
        #expect(spend.charges.map(\.cost) == [price, price])
    }
}

@MainActor
@Suite struct ImageSpendLogTests {
    let day = Date(timeIntervalSince1970: 1_760_310_000)

    @Test func anUnreadableSpendingFileCannotBeOverwrittenOrForgottenOnRelaunch() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(ImageSpendLog.fileName)
        let damaged = Data("[{\"cost\":80}]".utf8)
        try damaged.write(to: file)
        let charge = ImageCharge(
            date: day, cost: .credits(30, isEstimate: false), providerKind: .account, model: "Soul", images: 1)
        for _ in 0..<2 {
            let log = ImageSpendLog(folder: folder, now: day)
            #expect(throws: LogWriteError.self) { try log.add(charge) }
            #expect(log.charges.isEmpty)
            #expect(try Data(contentsOf: file) == damaged)
        }
        let log = ImageSpendLog(folder: folder, now: day)
        try Data("[]".utf8).write(to: file)
        log.retrySave()
        try log.add(charge)
        #expect(ImageSpendLog(folder: folder, now: day).charges.map(\.id) == [charge.id])
    }

    @Test func chargesSurviveARelaunchAndOldOnesAreDropped() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = ImageSpendLog(folder: folder, now: day)
        let recent = ImageCharge(
            date: day, cost: .usd(Decimal(string: "0.08")!, isEstimate: false), providerKind: .apiKey,
            model: "Grok Image 2", images: 1)
        let old = ImageCharge(
            date: day - 40 * 86_400, cost: .usd(1, isEstimate: false), providerKind: .apiKey, model: "Soul 2",
            images: 4, isPending: false)
        let dropped = ImageCharge(
            date: day, cost: .usd(1, isEstimate: false), providerKind: .apiKey, model: "Soul 2", images: 1)
        try log.add(old)
        try log.add(recent)
        try log.add(dropped)
        log.settle(recent.id)
        log.remove(dropped.id)

        let reopened = ImageSpendLog(folder: folder, now: day)

        #expect(reopened.charges.map(\.id) == [recent.id])
        #expect(reopened.charges.first?.isPending == false)
        #expect(reopened.charges.first?.cost == recent.cost)
    }

    @Test func todayCountsRunningRequestsAndTodaysFinishedOnes() {
        let calendar = Calendar(identifier: .gregorian)
        let usd = { (text: String) in Cost.usd(Decimal(string: text)!, isEstimate: false) }
        let charges = [
            ImageCharge(date: day, cost: usd("0.08"), providerKind: .apiKey, model: "a", images: 1, isPending: false),
            ImageCharge(date: day - 86_400 * 2, cost: usd("0.5"), providerKind: .apiKey, model: "b", images: 1),
            ImageCharge(
                date: day - 86_400 * 2, cost: usd("3"), providerKind: .apiKey, model: "c", images: 1, isPending: false),
            ImageCharge(date: day, cost: .credits(9, isEstimate: false), providerKind: .account, model: "d", images: 1),
        ]
        #expect(DailySpend.committed([], images: charges, on: day, calendar: calendar) == Decimal(string: "0.58"))
        #expect(DailySpend.committed([], images: charges, on: day, in: .credits, calendar: calendar) == 9)
    }
}
