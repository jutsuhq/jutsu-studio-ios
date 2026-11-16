// Queue, slots, polling, downloads and resume on launch.
// Portable: talks to storage, media and the network only through the ports in JutsuCore.

import Foundation
import JutsuCore

/// Runs jobs from enqueue to a downloaded file. Each active job has one task driving it through
/// `JobState`; every transition is saved to the repository before the next step starts,
/// so a crash at any point resumes from the last saved state (`start()`).
///
/// Every change of a job goes through `apply` or `save`, which take turns per job, so a change made while
/// the job's task runs (Run next) starts from the task's last change and can't undo it. User actions that
/// change the state (cancel, pause on a connection change) stop the task and wait for it first.
public actor JobEngine {
    /// Every change of every job, for the UI. One consumer.
    public nonisolated let events: AsyncStream<Job>
    let eventSink: AsyncStream<Job>.Continuation

    var provider: (any GenerationProvider)?
    let repository: any JobRepository
    let uploadCache: any UploadCache
    let media: any MediaPreparing
    let connectivity: any Connectivity
    let downloader: any Downloader
    let clock: any EngineClock
    let presetName: @Sendable (UUID) -> String?
    let spendStatus: @Sendable (Job) async throws -> SpendStatus?
    var settings: EngineSettings
    let limiter: SlotLimiter
    let log = EngineLog(category: "JobEngine")

    var jobs: [UUID: Job] = [:]
    var runners: [UUID: Runner] = [:]
    var prepared: [UUID: PreparedInputs] = [:]
    var videoURLs: [UUID: URL] = [:]
    var slotHolders: Set<UUID> = []
    var isOnline = true
    /// Set on 401: network work waits for `setProvider`.
    var connectionNeedsAttention = false
    /// Told when a 401 sets `connectionNeedsAttention`, so the app asks for the sign-in: submitted jobs wait for it
    /// without changing state, and nothing else would show why they stopped.
    var connectionAttentionHandler: (@Sendable () async -> Void)?
    var gate = NetworkGate()
    var connectivityTask: Task<Void, Never>?
    /// Jobs with a change being saved, and the writers waiting for their turn (`writing`).
    var writeTurns = WriteTurns()
    var isStarted = false
    /// Bumped by every `start` and `stop`: one that suspends meanwhile checks it again, so the last call wins.
    var lifecycle = 0
    /// Jobs `importFinished` is downloading, and the downloads, which a second import of the same job waits for;
    /// their partial files aren't leftovers.
    var importing: [UUID: Task<Job, any Error>] = [:]
    var progressCoalescer = ProgressCoalescer()
    /// Enqueues not finished yet, by request, so an equal one sent meanwhile gets the same job (`enqueue`).
    var enqueuing: [EnqueueRequest: Task<Job, any Error>] = [:]
    /// How many enqueues got the job of an equal one still running; what tests wait for instead of a delay.
    var joinedEnqueues = 0
    /// The enqueue started last; the next one waits for it.
    var lastEnqueue: Task<Void, Never>?
    /// Jobs whose submit is being sent or waits for its answer, and the `stop` waiting for them.
    var submits = SubmitTracker()
    /// Polled jobs waiting for the next shared status call, and the task that makes it (`JobEngine+StatusBatch`).
    var statusBatch = StatusBatch()

    struct Runner {
        let token: UUID
        let task: Task<Void, Never>
    }

    struct PreparedInputs {
        /// `nil` for a clip made without a source video.
        var video: PreparedFile?
        var images: [PreparedFile]
    }

    /// - Parameters:
    ///   - provider: `nil` until the user connects; jobs then wait as after `setProvider(nil)`.
    ///   - presetName: a preset's name for `{preset}` in output names, `nil` when unknown. Called on the
    ///     engine's actor while a result is placed, so it must not block.
    ///   - downloader: `nil` uses `URLSessionDownloader`, capped at `settings.maxDownloadBytes`.
    ///   - spendStatus: today's spend without the given job, and the cap of its connection; checked on enqueue
    ///     and when the provider quotes a price right before submit. `nil` skips the check. The job's own earlier
    ///     attempts that may have been charged (`Job.earlierAttempts`) are added to it here.
    public init(
        provider: (any GenerationProvider)?, repository: any JobRepository, uploadCache: any UploadCache,
        media: any MediaPreparing, connectivity: any Connectivity, settings: EngineSettings,
        downloader: (any Downloader)? = nil, clock: any EngineClock = SystemClock(),
        presetName: @escaping @Sendable (UUID) -> String? = { _ in nil },
        spendStatus: @escaping @Sendable (Job) async throws -> SpendStatus? = { _ in nil }
    ) {
        self.presetName = presetName
        self.spendStatus = { job in
            guard var status = try await spendStatus(job) else { return nil }
            if let cap = status.cap {
                status.committedToday += Budget.committed(earlierAttemptsOf: job, on: clock.now, in: cap.unit)
            }
            return status
        }
        self.provider = provider
        self.repository = repository
        self.uploadCache = uploadCache
        self.media = media
        self.connectivity = connectivity
        self.settings = settings
        self.downloader = downloader ?? URLSessionDownloader(maxBytes: settings.maxDownloadBytes)
        self.clock = clock
        limiter = SlotLimiter(limit: settings.maxConcurrency)
        (events, eventSink) = AsyncStream.makeStream()
    }

    deinit {
        connectivityTask?.cancel()
        eventSink.finish()
    }

    /// Call on launch: follows connectivity and resumes every active job from the repository.
    /// Jobs with a request ID are polled, uploaded but unsubmitted jobs are submitted with the same
    /// idempotency key, unless a submit without one may have reached the server; the rest restart their
    /// pipeline. Paused jobs stay paused. After `stop()` it resumes the same way.
    /// Before that it deletes leftovers of jobs no longer active and forgets uploads too old to reuse.
    /// If the jobs can't be loaded it throws and stays stopped, so it can be called again.
    public func start() async throws {
        // A stop still waiting for its submits hasn't stopped anything: this start takes over, and that stop
        // returns without cancelling the runners it would have (`stop`).
        guard !isStarted || submits.isStopping else { return }
        isStarted = true
        submits.isStopping = false
        lifecycle += 1
        let starting = lifecycle
        await followConnectivity()
        let activeJobs: [Job]
        let storedIDs: Set<UUID>
        do {
            activeJobs = try await repository.activeJobs()
            storedIDs = try await repository.activeJobIDs()
        } catch {
            // A stop or a newer start meanwhile owns the engine now.
            guard lifecycle == starting else { throw error }
            connectivityTask?.cancel()
            connectivityTask = nil
            isStarted = false
            throw error
        }
        await removeLeftovers(activeJobs: activeJobs, storedIDs: storedIDs)
        // A stop meanwhile cancelled the runners it saw: none may start after it.
        guard lifecycle == starting else { return }
        for stored in activeJobs {
            let job = jobs[stored.id] ?? adoptingLegacyOwner(stored)
            jobs[job.id] = job
            guard job.state.isRunnable, runners[job.id] == nil else { continue }
            await forgetRetries(of: job)
            // Accepted jobs hold their slots before anything new can take them.
            if job.state == .queued || job.state == .processing { await occupySlot(job.id) }
            startRunner(job.id)
        }
    }

    /// Before submit the job is dropped locally; while queued the API cancels it too. While downloading
    /// the generation is already finished, so only the download stops and its partial file is removed.
    /// Throws `notCancellable` while the API is processing it.
    ///
    /// A submit that may have reached Higgsfield is never dropped as canceled: the app could then no longer see,
    /// or cancel, a generation it may be charged for, and a retry would send it again under a new key. While such
    /// a submit waits for its answer (`Job.isSubmitPending`) this throws `submitInProgress`: the job resends it
    /// with the same key, after a pause once its connection is back, and can be canceled once queued. A submit
    /// sent without a key can't be resent, so cutting a running one off fails the job as `outcomeUnknown`;
    /// resuming a paused one fails it as `submitCutOff`.
    public func cancel(_ id: UUID) async throws {
        let current = try await loadJob(id)
        guard current.state.isCancellable else { throw JobEngineError.notCancellable(current.state) }
        guard !current.isSubmitPending else { throw JobEngineError.submitInProgress }
        await stopRunner(id)
        let job = try await loadJob(id)
        guard job.state.isCancellable else {
            startRunner(id)
            throw JobEngineError.notCancellable(job.state)
        }
        guard !job.isSubmitPending else {
            startRunner(id)
            throw JobEngineError.submitInProgress
        }
        if job.state == .queued, let remote = job.remote {
            do {
                try await currentProvider(for: job).cancel(remote)
            } catch {
                startRunner(id)
                throw error
            }
        }
        let mayHaveStarted = job.submitAttempt != nil
        try await apply(mayHaveStarted ? .failed(reason: .outcomeUnknown) : .cancel, to: id)
    }

    /// A failed or canceled job whose generation finished downloads that paid result again, and one that failed at
    /// the deadline is checked again (`checkAgain`): submitting it again could pay for a second generation. Any
    /// other runs again from the start as a new attempt, with a new idempotency key unless a submit of it may have
    /// reached the server. Generating a paid job again is a new job, queued with `enqueue`. A job whose submit may
    /// have been charged without an idempotency key (`Job.retryMayChargeAgain`) runs again only once the person
    /// agreed (`chargeAgainApproved`), and the cap keeps counting that attempt (`Job.earlierAttempts`).
    public func retry(_ id: UUID, chargeAgainApproved: Bool = false) async throws {
        let job = try await loadJob(id)
        switch job.state {
        case .failed, .canceled: break
        default: throw JobEngineError.notRetryable(job.state)
        }
        if job.mayStillFinish { return try await checkAgain(id) }
        let now = clock.now
        if job.hasPaidOutput {
            try await apply(.retryDownload, to: id) { $0.retriedAt = now }
        } else {
            if job.retryMayChargeAgain, !chargeAgainApproved { throw JobEngineError.mayChargeAgain }
            var attempt = job
            if job.retryMayChargeAgain {
                attempt.earlierAttempts =
                    (job.earlierAttempts ?? []) + [EarlierAttempt(price: job.price, endedAt: job.finishedAt ?? now)]
            }
            let overCap = try await retryIsOverCap(attempt)
            // A retry sent again meanwhile, or a job that went on another way, is left as it is.
            let retried = try await apply(.retry, to: id, ifStill: { $0.state == job.state }) {
                $0.earlierAttempts = attempt.earlierAttempts
                $0.retriedAt = now
                $0.inputs = nil
                $0.remote = nil
                $0.outputFile = nil
                $0.outputMedia = nil
                $0.submitAttempt = nil
                $0.serverPrice = nil
                $0.approvedPrice = nil
                $0.submittedAt = nil
                $0.processingAt = nil
                $0.promotedAt = nil
                $0.checkedAgainAt = nil
                if job.submitAttempt == nil { $0.idempotencyKey = UUID() }
            }
            guard retried != nil else { return }
            // Its Resume agrees to the price, as with a price quoted over the cap.
            if overCap {
                try await apply(.paused(.priceAboveCap), to: id)
                return
            }
        }
        startRunner(id)
    }

    /// A failed job left the queue, so the cap no longer counts it: a new attempt is checked as on enqueue,
    /// at its preliminary price.
    private func retryIsOverCap(_ job: Job) async throws -> Bool {
        guard !job.spec.usesUnlimited, let status = try await spendStatus(job), let cap = status.cap else {
            return false
        }
        return Budget.allows(cost: job.cost, committedToday: status.committedToday, cap: cap) != .allowed
    }

    /// Polls a job that failed at the deadline (`Job.mayStillFinish`) again, with a new deadline. It keeps its
    /// request, so a generation that finished meanwhile is downloaded instead of paid for twice.
    public func checkAgain(_ id: UUID) async throws {
        let job = try await loadJob(id)
        guard job.mayStillFinish else { throw JobEngineError.notRetryable(job.state) }
        let now = clock.now
        try await apply(.checkAgain, to: id) {
            $0.timedOutAt = nil
            $0.checkedAgainAt = now
        }
        startRunner(id)
    }

    /// Continues a paused job from the start of its pipeline; prepared files and uploads are cached. A job paused
    /// for `notEnoughDiskSpace` continues its download from the partial file instead.
    /// Resuming a job paused for `priceAboveCap` agrees to the price the provider quoted, so ask first. A job that
    /// went on meanwhile (a Resume sent twice) is left as it is.
    public func resume(_ id: UUID) async throws {
        let job = try await loadJob(id)
        let stillPaused = { (now: Job) in now.state == job.state }
        if job.state == .paused(.priceAboveCap) {
            try await apply(.resume, to: id, ifStill: stillPaused) { $0.approvedPrice = $0.serverPrice ?? $0.cost }
        } else if case .paused = job.state {
            try await apply(.resume, to: id, ifStill: stillPaused)
        } else if !job.state.isActive {
            throw JobEngineError.notResumable(job.state)
        }
        startRunner(id)
    }

    /// Moves a job waiting for a slot ahead of the other waiters, so it takes the next free slot. Saved with the
    /// job, so the order holds after a restart. A later Run next on another job goes ahead of this one.
    public func runNext(_ id: UUID) async throws {
        let job = try await loadJob(id)
        guard job.state == .waitingForSlot, job.submitAttempt == nil else { throw JobEngineError.notWaiting(job.state) }
        let now = clock.now
        try await save(id) { $0.promotedAt = now }
        await limiter.promote(id, at: now)
    }

    /// Switches the connection. Unsubmitted jobs of another provider or account pause with
    /// `connectionNeedsAttention`; submitted ones wait until their connection is back.
    /// `handler` runs each time the provider turns the connection down (401) while jobs depend on it.
    public func onConnectionNeedsAttention(_ handler: @escaping @Sendable () async -> Void) {
        connectionAttentionHandler = handler
    }

    /// Jobs paused for the connection resume when their connection returns.
    public func setProvider(_ newProvider: (any GenerationProvider)?) async {
        provider = newProvider
        connectionNeedsAttention = false
        for job in jobs.values where job.state.isActive {
            if newProvider?.owns(job) == true {
                guard job.state == .paused(.connectionNeedsAttention) else { continue }
                do {
                    try await resume(job.id)
                } catch {
                    log.error("Job \(job.id): can't resume", detail: String(describing: error))
                }
            } else if job.state.isBeforeSubmit {
                await stopRunner(job.id)
                guard jobs[job.id]?.state.isBeforeSubmit == true else { continue }
                do {
                    try await apply(.paused(.connectionNeedsAttention), to: job.id)
                } catch {
                    log.error("Job \(job.id): can't pause", detail: String(describing: error))
                }
            } else {
                // The jobs it leaves wait for it without a slot (`networkProvider`), so the new one's queue isn't
                // frozen behind them.
                await releaseSlot(job.id)
            }
        }
        gate.open()
    }
}

// Following the network.
extension JobEngine {
    private func followConnectivity() async {
        connectivityTask?.cancel()
        let updates = connectivity.updates()
        // The first value is the current state; wait for it so nothing starts while offline.
        for await online in updates {
            isOnline = online
            break
        }
        connectivityTask = Task { [weak self] in
            for await online in updates { await self?.setOnline(online) }
        }
    }

    private func setOnline(_ online: Bool) {
        isOnline = online
        gate.open()
    }
}

// Pause all and Resume all.
extension JobEngine {
    /// Pauses every job not yet submitted with `byUser`, so none takes a slot until `resumeAll`. Submitted
    /// jobs keep polling and downloading. An upload in progress stops; finished uploads are cached, so a
    /// resume repeats only the interrupted file. A job whose submit is already sent is left to finish it.
    public func pauseAll() async {
        let pausable = { (job: Job) in job.state.isPausableByUser && job.submitAttempt == nil }
        for job in jobs.values where pausable(job) {
            await stopRunner(job.id)
            guard let current = jobs[job.id], pausable(current) else {
                startRunner(job.id)
                continue
            }
            do {
                try await apply(.paused(.byUser), to: job.id)
            } catch {
                log.error("Job \(job.id): can't pause", detail: String(describing: error))
                startRunner(job.id)
            }
        }
    }

    /// Resumes the jobs `pauseAll` paused, oldest first. Other pauses stay: a job whose connection is
    /// still missing pauses for it again, and funds pauses wait for the user's own resume.
    public func resumeAll() async {
        await resume { $0.state == .paused(.byUser) }
    }

    private func resume(where isResumed: (Job) -> Bool) async {
        for job in jobs.values.filter(isResumed).sorted(by: { $0.createdAt < $1.createdAt }) {
            do {
                try await resume(job.id)
            } catch {
                log.error("Job \(job.id): can't resume", detail: String(describing: error))
            }
        }
    }
}

// Settings that apply from the next job on.
extension JobEngine {
    public func setMaxConcurrency(_ limit: Int) async {
        await limiter.setLimit(limit)
    }

    /// Results placed after this call use `pattern`; files already in the library keep their names.
    public func setOutputNamePattern(_ pattern: OutputNamePattern) {
        settings.outputNamePattern = pattern
    }
}
// Stopping, as on quit.
extension JobEngine {
    /// Stops all work without changing any job, as if the app quit; `start()` picks it up again.
    ///
    /// Submits already sent first get up to `grace` (wall-clock time) to be answered, so quitting doesn't cut
    /// off a request Higgsfield may already be running; no new submit is sent meanwhile. A submit still
    /// unanswered after that is resent with its idempotency key on the next start, or fails there as
    /// `FailureReason.submitCutOff` when its provider can't send one.
    public func stop(finishingSubmitsWithin grace: Duration = .zero) async {
        submits.isStopping = true
        defer { submits.isStopping = false }
        lifecycle += 1
        let stopping = lifecycle
        await waitForSubmits(upTo: grace)
        // A `start` meanwhile took over and keeps the engine running: its runners, and what it follows, stay.
        guard lifecycle == stopping else { return }
        connectivityTask?.cancel()
        connectivityTask = nil
        isStarted = false
        let running = runners
        runners = [:]
        for runner in running.values { runner.task.cancel() }
        statusBatch.ticker?.cancel()
        statusBatch.ticker = nil
        for runner in running.values { await runner.task.value }
    }

    /// Returns once no submit is out, or after `grace`.
    private func waitForSubmits(upTo grace: Duration) async {
        guard !submits.inFlight.isEmpty, grace > .zero else { return }
        let timer = Task { [weak self] in
            do { try await Task.sleep(for: grace) } catch { return }
            await self?.endSubmitGrace()
        }
        defer { timer.cancel() }
        await withCheckedContinuation { submits.wait($0) }
    }

    private func endSubmitGrace() {
        let unanswered = submits.inFlight.count
        if submits.releaseWaiters() { log.error("Stopping with \(unanswered) submit(s) unanswered") }
    }
}

// Loading jobs and their runners.
extension JobEngine {
    func loadJob(_ id: UUID) async throws -> Job {
        if let job = jobs[id] { return job }
        guard let stored = try await repository.job(id: id) else { throw JobEngineError.unknownJob(id) }
        let job = jobs[id] ?? adoptingLegacyOwner(stored)
        jobs[id] = job
        return job
    }

    /// Jobs stored before owners existed belong to the connection active when the engine first loads them,
    /// normally the one restored at launch, which queued them.
    func adoptingLegacyOwner(_ job: Job) -> Job {
        guard job.owner == nil, let provider, provider.kind == job.providerKind else { return job }
        var job = job
        job.owner = provider.owner
        return job
    }

    /// A runner counts failures from its own start: a wait from before a quit says nothing about now.
    private func forgetRetries(of job: Job) async {
        guard job.retrying != nil else { return }
        do {
            try await save(job.id) { $0.retrying = nil }
        } catch {
            log.error("Job \(job.id): can't save", detail: String(describing: error))
        }
    }

    func startRunner(_ id: UUID) {
        guard runners[id] == nil, jobs[id]?.state.isRunnable == true else { return }
        let token = UUID()
        runners[id] = Runner(token: token, task: Task { await self.drive(id, token: token) })
    }

    func stopRunner(_ id: UUID) async {
        guard let runner = runners.removeValue(forKey: id) else { return }
        runner.task.cancel()
        await runner.task.value
    }
}
