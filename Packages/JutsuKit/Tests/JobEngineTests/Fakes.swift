import Foundation
import JutsuTestSupport
import Testing

@testable import JobEngine
@testable import JutsuCore

/// Ordered record of what the fakes were asked to do, shared by all of them.
final class CallLog: @unchecked Sendable {
    // Safe: `entries` is only touched under `lock`.
    private let lock = NSLock()
    private var entries: [String] = []

    func append(_ entry: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    func count(_ entry: String) -> Int { all.filter { $0 == entry }.count }
}

/// Virtual time: sleeping advances `now` and returns at once.
final class TestClock: EngineClock, @unchecked Sendable {
    // Safe: `current` is only touched under `lock`.
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_791_892_800)

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        current += seconds
    }

    /// Advances at once, then gives the thread up for a moment: with a mere yield, a job held polling spins
    /// through virtual hours and starves every test running beside it.
    func sleep(for seconds: TimeInterval) async throws {
        try Task.checkCancellation()
        advance(by: seconds)
        try await Task.sleep(for: .microseconds(100))
    }
}

actor InMemoryRepository: JobRepository {
    let log: CallLog
    private var stored: [UUID: Job] = [:]
    private var history: [UUID: [JobState]] = [:]
    private var waiters:
        [UUID: (predicate: @Sendable (Snapshot) -> Bool, continuation: CheckedContinuation<Void, Never>)] =
            [:]

    struct Snapshot: Sendable {
        var jobs: [UUID: Job]
        var history: [UUID: [JobState]]

        func reached(_ id: UUID, _ state: JobState) -> Bool { history[id]?.contains(state) == true }
        func count(in state: JobState) -> Int { jobs.values.filter { $0.state == state }.count }
    }

    private var held: HeldSave?
    func activeJobIDs() -> Set<UUID> {
        Set(stored.values.filter(\.state.isActive).map(\.id))
    }

    private struct HeldSave {
        let matches: @Sendable (Job) -> Bool
        let reached: Gate<Void>
        let release: Gate<Void>
    }

    init(log: CallLog) {
        self.log = log
    }

    func save(_ job: Job) async {
        log.append("save \(job.state)")
        stored[job.id] = job
        history[job.id, default: []].append(job.state)
        let snapshot = Snapshot(jobs: stored, history: history)
        for (id, waiter) in waiters where waiter.predicate(snapshot) {
            waiters[id] = nil
            waiter.continuation.resume()
        }
        if let held, held.matches(job) {
            self.held = nil
            await held.reached.open(.success(()))
            _ = try? await held.release.wait()
        }
    }

    /// The next save of a job that `matches` is stored, then doesn't return until `release` opens, like a slow
    /// disk; `reached` opens once that save is held.
    func holdSave(where matches: @escaping @Sendable (Job) -> Bool) -> (reached: Gate<Void>, release: Gate<Void>) {
        let gates = (reached: Gate<Void>(), release: Gate<Void>())
        held = HeldSave(matches: matches, reached: gates.reached, release: gates.release)
        return gates
    }

    func job(id: UUID) -> Job? { stored[id] }

    /// Every job saved so far, in no order.
    func snapshotJobs() -> [Job] { Array(stored.values) }

    func activeJobs() -> [Job] {
        stored.values.filter { $0.state.isActive }.sorted { $0.createdAt < $1.createdAt }
    }

    func delete(id: UUID) { stored[id] = nil }

    func states(of id: UUID) -> [JobState] { history[id] ?? [] }

    /// Returns once `predicate` holds for what has been saved so far. Records an issue and returns after
    /// `timeout`, so a state that never comes fails the test instead of hanging the run.
    /// Unlike `Gate` (a single-shot value), this re-checks an evolving snapshot on every save.
    func wait(
        timeout: Duration = waitLimit, sourceLocation: SourceLocation = #_sourceLocation,
        until predicate: @escaping @Sendable (Snapshot) -> Bool
    ) async {
        if predicate(Snapshot(jobs: stored, history: history)) { return }
        let id = UUID()
        let timer = Task {
            do { try await Task.sleep(for: timeout) } catch { return }
            guard let waiter = waiters.removeValue(forKey: id) else { return }
            Issue.record("Repository did not reach the state within \(timeout)", sourceLocation: sourceLocation)
            waiter.continuation.resume()
        }
        defer { timer.cancel() }
        await withCheckedContinuation { waiters[id] = (predicate, $0) }
    }

    /// Returns once the job has been saved in `state` at some point.
    @discardableResult
    func wait(for id: UUID, _ state: JobState, sourceLocation: SourceLocation = #_sourceLocation) async -> Job? {
        await wait(sourceLocation: sourceLocation) { $0.reached(id, state) }
        return stored[id]
    }
}

actor FakeProvider: GenerationProvider {
    enum SubmitStep {
        case fail(ProviderError)
        /// Never answers until the task is canceled: the response is lost in a crash.
        case hang
        /// Accepts the job, then answers once `gate` opens, even if the task is canceled meanwhile.
        case answer(after: Gate<Void>)
    }

    nonisolated let kind = ProviderKind.apiKey
    nonisolated let owner: String?
    let log: CallLog
    /// `false` acts like an MCP submit tool without an idempotency argument.
    var isIdempotent = true
    var submitSteps: [SubmitStep] = []
    var statusSteps: [Result<RemoteStatus, ProviderError>] = []
    var uploadErrors: [ProviderError] = []
    /// Returned by every status call while set; `nil` completes the job.
    var heldStatus: RemoteStatus?
    /// What `serverEstimate` answers; `nil` acts like a provider that can't quote.
    var quote: Result<Cost, ProviderError>?
    /// What `paysUnlimited` answers for every spec.
    var paysUnlimited = false
    /// Put into every accepted `RemoteJob`: how the submit answer says it was paid.
    var unlimitedAnswer: (paid: Bool, charged: Cost?) = (false, nil)
    let videoURL = URL(string: "https://cdn.example/out.mp4")!

    private(set) var uploads: [String] = []
    private(set) var submitKeys: [UUID] = []
    private(set) var statusCalls = 0
    /// The request ID of each `status` call.
    private(set) var statusAsked: [String] = []
    private(set) var cancels: [String] = []
    private(set) var maxInFlight = 0
    private var accepted: [UUID: RemoteJob] = [:]
    private var inFlight: Set<String> = []

    /// Above 1, the engine polls through `statuses(of:)`; 0 acts like the API key, which polls each job.
    nonisolated let statusBatchLimit: Int
    /// Request IDs every batch answer leaves out.
    var batchOmits: Set<String> = []
    /// Answers by request ID that override `heldStatus` in batch answers.
    var batchStatuses: [String: RemoteStatus] = [:]

    init(owner: String? = "key-a", log: CallLog, statusBatchLimit: Int = 0) {
        self.owner = owner
        self.log = log
        self.statusBatchLimit = statusBatchLimit
    }

    func setBatch(omitting: Set<String> = [], statuses: [String: RemoteStatus] = [:]) {
        batchOmits = omitting
        batchStatuses = statuses
    }

    /// Answers each job as `status` would, except `batchOmits`.
    func statuses(of jobs: [RemoteJob]) -> BatchStatus? {
        log.append("statuses")
        var statuses: [String: RemoteStatus] = [:]
        for job in jobs where !batchOmits.contains(job.requestID) {
            let status = batchStatuses[job.requestID] ?? heldStatus ?? .completed(videoURL: videoURL)
            switch status {
            case .queued, .inProgress: break
            default: inFlight.remove(job.requestID)
            }
            statuses[job.requestID] = status
        }
        return BatchStatus(statuses: statuses, pollAfter: nil)
    }

    func setIdempotent(_ value: Bool) { isIdempotent = value }

    func submitIsIdempotent(_ spec: JobSpec) -> Bool { isIdempotent }

    var acceptedCount: Int { accepted.count }

    func script(submit: [SubmitStep] = [], status: [Result<RemoteStatus, ProviderError>] = []) {
        submitSteps += submit
        statusSteps += status
    }

    func failUploads(_ errors: [ProviderError]) { uploadErrors += errors }

    func stopFailingUploads() { uploadErrors = [] }

    func hold(_ status: RemoteStatus?) { heldStatus = status }

    func setQuote(_ quote: Result<Cost, ProviderError>?) { self.quote = quote }

    func payUnlimited(_ value: Bool, answer: (paid: Bool, charged: Cost?) = (true, nil)) {
        paysUnlimited = value
        unlimitedAnswer = answer
    }

    func paysUnlimited(_ spec: JobSpec) -> Bool { paysUnlimited }

    func serverEstimate(_ spec: JobSpec, inputs: RemoteInputs) throws -> Cost? {
        guard let quote else { return nil }
        log.append("serverEstimate")
        return try quote.get()
    }

    func capabilities() -> Capabilities {
        Capabilities(
            modes: Set(Mode.allCases), resolutions: Set(Resolution.allCases), costUnit: .usd, maxConcurrency: nil)
    }

    func presets() -> [StylePreset] { [] }

    /// What `estimate` answers in place of $1.30 a variant, when set.
    var preliminary: Cost?
    /// What `charge(of:)` answers; `nil` acts like a provider that can't tell what it charged.
    var charge: Result<Cost, ProviderError>?

    func setPreliminary(_ cost: Cost?) { preliminary = cost }

    func setCharge(_ charge: Result<Cost, ProviderError>?) { self.charge = charge }

    func estimate(_ spec: JobSpec) -> Cost {
        log.append("estimate")
        return preliminary ?? Cost.usd(1.3, isEstimate: false).times(spec.variants)
    }

    func charge(of job: Job) throws -> Cost? {
        log.append("charge")
        return try charge?.get()
    }

    func linkedAsset(_ origin: URL, kind: MediaLink.Kind, byteCount: Int64) -> RemoteAsset? {
        log.append("linked \(kind.rawValue)")
        return nil
    }

    func serverAsset(_ media: ServerMedia) -> RemoteAsset? {
        log.append("server media")
        return nil
    }

    func upload(_ file: PreparedFile) throws -> RemoteAsset {
        log.append("upload")
        if !uploadErrors.isEmpty { throw uploadErrors.removeFirst() }
        uploads.append(file.contentHash)
        return RemoteAsset(url: URL(string: "https://upload.example/\(file.contentHash)")!)
    }

    func submit(_ spec: JobSpec, inputs: RemoteInputs, idempotencyKey: UUID) async throws -> RemoteJob {
        log.append("submit")
        submitKeys.append(idempotencyKey)
        let step = submitSteps.isEmpty ? nil : submitSteps.removeFirst()
        switch step {
        case .fail(let error): throw error
        case .hang:
            _ = accept(idempotencyKey, spec: spec)
            try await Task.sleep(nanoseconds: 3_600_000_000_000)
            throw CancellationError()
        case .answer(let gate):
            let remote = accept(idempotencyKey, spec: spec)
            try await gate.wait()
            return remote
        case nil: return accept(idempotencyKey, spec: spec)
        }
    }

    /// Same key, same job: the server's idempotency. Variants past the first are "r1-v1", "r1-v2"…
    private func accept(_ key: UUID, spec: JobSpec) -> RemoteJob {
        if let known = accepted[key] { return known }
        var remote = RemoteJob(requestID: "r\(accepted.count + 1)")
        (remote.paidWithUnlimited, remote.charged) = unlimitedAnswer
        remote.variants = (1..<max(spec.variants, 1)).map { RemoteJob(requestID: "\(remote.requestID)-v\($0)") }
        accepted[key] = remote
        inFlight.insert(remote.requestID)
        for variant in remote.variants { inFlight.insert(variant.requestID) }
        maxInFlight = max(maxInFlight, inFlight.count)
        return remote
    }

    func status(_ job: RemoteJob) throws -> RemoteStatus {
        log.append("status")
        statusCalls += 1
        statusAsked.append(job.requestID)
        let status: RemoteStatus
        if !statusSteps.isEmpty {
            status = try statusSteps.removeFirst().get()
        } else {
            status = heldStatus ?? .completed(videoURL: videoURL)
        }
        switch status {
        case .queued, .inProgress: break
        default: inFlight.remove(job.requestID)
        }
        return status
    }

    func cancel(_ job: RemoteJob) {
        log.append("cancel")
        cancels.append(job.requestID)
        inFlight.remove(job.requestID)
    }

    func balance() -> Balance? { nil }
}

struct FakeMedia: MediaPreparing {
    let log: CallLog

    func imageSize(of image: LocalImage) -> PixelSize? { nil }

    func outputMedia(of file: URL) -> OutputMedia? { nil }

    func prepareVideo(_ source: SourceClip, progress: @escaping @Sendable (Double) -> Void) -> PreparedFile {
        log.append("prepareVideo")
        for step in [0.5, 1] { progress(step) }
        return PreparedFile(fileURL: source.fileURL, contentType: "video/mp4", byteCount: 1, contentHash: "video")
    }

    func prepareImage(_ image: LocalImage) -> PreparedFile {
        log.append("prepareImage")
        return PreparedFile(
            fileURL: image.fileURL, contentType: "image/jpeg", byteCount: 1,
            contentHash: "image-\(image.fileURL.lastPathComponent)")
    }

    /// The result already has sound.
    func restoreAudio(of spec: JobSpec, result: URL, to output: URL) -> Bool {
        log.append("restoreAudio")
        return false
    }
}

actor FakeUploadCache: UploadCache {
    private var entries: [String: (asset: RemoteAsset, date: Date)] = [:]

    func asset(forContentHash contentHash: String, uploadedAfter date: Date) -> RemoteAsset? {
        guard let entry = entries[contentHash], entry.date >= date else { return nil }
        return entry.asset
    }

    func store(_ asset: RemoteAsset, contentHash: String, uploadedAt: Date) {
        entries[contentHash] = (asset, uploadedAt)
    }

    func removeAssets(uploadedBefore date: Date) {
        entries = entries.filter { $0.value.date >= date }
    }

}

/// Every subscriber gets the current state, then every change.
final class FakeConnectivity: Connectivity, @unchecked Sendable {
    // Safe: `online` and `subscribers` are only touched under `lock`.
    private let lock = NSLock()
    private var online: Bool
    private var subscribers: [AsyncStream<Bool>.Continuation] = []

    init(online: Bool) {
        self.online = online
    }

    func updates() -> AsyncStream<Bool> {
        let (stream, continuation) = AsyncStream.makeStream(of: Bool.self)
        lock.lock()
        defer { lock.unlock() }
        continuation.yield(online)
        subscribers.append(continuation)
        return stream
    }

    func set(online: Bool) {
        lock.lock()
        defer { lock.unlock() }
        self.online = online
        for subscriber in subscribers { subscriber.yield(online) }
    }
}

/// Appends what `file` is still missing of "video", like a resuming download.
struct FakeDownloader: Downloader {
    enum Mode {
        case complete
        /// The first call gets "vid", then the connection drops.
        case dropOnce
        /// Call n is refused with the n-th status, later calls complete. 404 is an expired result.
        case refuse([Int])
    }

    let log: CallLog
    var mode = Mode.complete
    /// The size of `file` at the start of every call.
    let starts = CallLog()

    func download(_ url: URL, to file: URL) throws {
        log.append("download")
        let body = Data("video".utf8)
        let existing = (try? Data(contentsOf: file)) ?? Data()
        starts.append("\(existing.count)")
        switch mode {
        case .complete:
            try (existing + body.dropFirst(existing.count)).write(to: file)
        case .dropOnce where log.count("download") == 1:
            try body.prefix(3).write(to: file)
            throw ProviderError.network
        case .dropOnce:
            try (existing + body.dropFirst(existing.count)).write(to: file)
        case .refuse(let statuses) where log.count("download") <= statuses.count:
            throw JobEngineError.downloadFailed(status: statuses[log.count("download") - 1])
        case .refuse:
            try body.write(to: file)
        }
    }
}

/// All fakes for one test; engines made from it share them, as two launches of the app would.
struct Harness {
    let log = CallLog()
    let clock = TestClock()
    let provider: FakeProvider
    let repository: InMemoryRepository
    let cache = FakeUploadCache()
    let connectivity: FakeConnectivity
    let outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "JobEngineTests-\(UUID().uuidString)")
    let maxConcurrency: Int
    let downloader: FakeDownloader
    /// What the engine's spend check sees; `nil` skips it.
    var spendStatus: SpendStatus?
    /// Unbounded by default: the virtual clock runs hours ahead while a test holds a status.
    let generationDeadline: TimeInterval

    init(
        online: Bool = true, maxConcurrency: Int = 2, download: FakeDownloader.Mode = .complete,
        spendStatus: SpendStatus? = nil,
        generationDeadline: TimeInterval = .greatestFiniteMagnitude, statusBatchLimit: Int = 0
    ) {
        self.spendStatus = spendStatus
        self.generationDeadline = generationDeadline
        provider = FakeProvider(log: log, statusBatchLimit: statusBatchLimit)
        repository = InMemoryRepository(log: log)
        connectivity = FakeConnectivity(online: online)
        self.maxConcurrency = maxConcurrency
        downloader = FakeDownloader(log: log, mode: download)
    }

    /// - Parameter readSpend: replaces the fixed `spendStatus`, e.g. to count what the repository holds.
    func makeEngine(readSpend: (@Sendable (Job) async throws -> SpendStatus?)? = nil) async throws -> JobEngine {
        let settings = EngineSettings(
            outputDirectory: outputDirectory, maxConcurrency: maxConcurrency, jitter: 0, uploadMaxAge: 3600,
            generationDeadline: generationDeadline)
        let engine = JobEngine(
            provider: provider, repository: repository, uploadCache: cache,
            media: FakeMedia(log: log),
            connectivity: connectivity, settings: settings, downloader: downloader, clock: clock,
            spendStatus: readSpend ?? { [spendStatus] _ in spendStatus })
        StopsEngines.made?.add(engine)
        try await engine.start()
        return engine
    }
}

func makeSpec(references: Int = 1) -> JobSpec {
    let source = SourceClip(
        fileURL: URL(fileURLWithPath: "/tmp/source.mov"), duration: 60,
        pixelSize: PixelSize(width: 1280, height: 720), range: 0...10)
    let images = (0..<references).map { LocalImage(fileURL: URL(fileURLWithPath: "/tmp/ref\($0).jpg")) }
    return JobSpec(mode: .motionTransfer, source: source, references: images, resolution: .p480)
}

// What tests wait on to know nothing more happens: a job no task drives changes only on a command, and a task
// parked on the network gate or a slot moves only when that opens.
extension JobEngine {
    func isDriving(_ id: UUID) -> Bool { runners[id] != nil }
    func drivesNone(of ids: [UUID]) -> Bool { ids.allSatisfy { runners[$0] == nil } }
    var isIdle: Bool { runners.isEmpty }
    var networkWaiters: Int { gate.waiterCount }
    var submitWaiters: Int { submits.waiterCount }
    var runningEnqueues: Int { enqueuing.count }
    func waitsForWriteTurn(_ id: UUID) -> Bool { writeTurns.hasWaiters(for: id) }
}

/// Stops every engine a test made once the test ends; their tasks would otherwise poll on through the tests after
/// it, as the test clock never really sleeps.
struct StopsEngines: SuiteTrait, TestTrait, TestScoping {
    @TaskLocal static var made: EngineList?

    final class EngineList: @unchecked Sendable {
        // Safe: `engines` is only touched under `lock`.
        private let lock = NSLock()
        private var engines: [JobEngine] = []

        func add(_ engine: JobEngine) { lock.withLock { engines.append(engine) } }
        var all: [JobEngine] { lock.withLock { engines } }
    }

    var isRecursive: Bool { true }

    func provideScope(
        for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
    ) async throws {
        guard !test.isSuite else { return try await function() }
        let made = EngineList()
        do {
            try await Self.$made.withValue(made) { try await function() }
        } catch {
            for engine in made.all { await engine.stop() }
            throw error
        }
        for engine in made.all { await engine.stop() }
    }
}

extension Trait where Self == StopsEngines {
    static var stopsEngines: Self { Self() }
}
