import Foundation
import JobEngine
import JutsuCore
import MediaKit
import Persistence
import Presentation
import Secrets
import SwiftData
import os

nonisolated private let logger = Logger.jutsu("App")

/// The composition root: built once at launch, holds every long-lived object and hands the provider of the active
/// connection to the engine. Views read it with `@Environment(AppEnvironment.self)`.
@Observable
final class AppEnvironment {
    let layout: FileLayout
    let modelContainer: ModelContainer
    let engine: JobEngine
    let connection: ConnectionStore
    /// Every job as of the engine's last event.
    let liveJobs = LiveJobs()
    let notifications = Notifications()
    let network = NetworkStatus()
    /// Every finished take, and its keep, reject and star.
    let library: LibraryModel
    var marks: LibraryMarks { library.marks }
    let liveActivity = LiveActivityController()
    /// The Image side of Create: its form, runs and this session's images.
    let imageGenerator: ReferenceGenerator
    /// Virality Predictor runs; each score is paid for once and kept on the take.
    let variantScorer: VariantScorer
    /// Create Character: its form, and the sheets being made on the account.
    let characterBuilder: CharacterBuilder
    /// The restyle gallery of the active connection, cached on disk.
    let presets: PresetCatalog
    /// Set by the app delegate once both exist.
    @ObservationIgnored weak var background: BackgroundWork?
    /// The bundled list prices, which API key connections are estimated from.
    let pricing: Pricing?
    /// The provider of the active connection; `nil` while disconnected.
    private(set) var provider: (any GenerationProvider)?
    /// Goes up whenever `provider` is replaced, so loads for a previous connection can tell.
    private(set) var providerGeneration = 0
    private(set) var capabilities: Capabilities?
    /// The connection's Motion Library and elements, made once per connection so their pages survive reopening.
    private(set) var motionLibrary: MotionLibraryModel?
    private(set) var accountElements: AccountElementsModel?
    /// The selected tab and the requests one tab hands another.
    let navigation = NavigationModel()
    /// Create's form and what it does, kept while the person is on another tab.
    @ObservationIgnored private(set) lazy var create = CreateScreenModel(environment: self)
    /// The account's history as Library pages through it; emptied when the connection changes.
    var history = AccountHistory()
    /// Today's spend and the cap, read by Create and the engine.
    @ObservationIgnored let spending: SpendReader
    /// Both Create drafts, saved between launches.
    @ObservationIgnored let drafts: CreateDraftStore

    @ObservationIgnored let store: SwiftDataStore
    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored private var startup: Task<Void, Never>?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?

    init(layout: FileLayout, defaults: UserDefaults = .standard) throws {
        AppSettings.migrate(defaults)
        let container = try StoreContainer.make(inMemory: false, layout: layout)
        let store = SwiftDataStore(modelContainer: container)
        let settings = EngineSettings(
            outputDirectory: OutputSubfolder.videos.url(in: layout.defaultOutputFolder),
            outputNamePattern: AppSettings.outputNamePattern(in: defaults),
            maxConcurrency: AppSettings.maxConcurrency(in: defaults, for: nil))
        self.layout = layout
        self.defaults = defaults
        self.store = store
        modelContainer = container
        library = LibraryModel(store: store)
        presets = PresetCatalog(cacheFolder: layout.presetCacheFolder)
        let imageSpend = ImageSpendLog(folder: layout.root)
        let spending = SpendReader(store: store, images: imageSpend)
        self.spending = spending
        imageGenerator = ReferenceGenerator(
            spend: imageSpend, jobLog: ImageJobLog(folder: layout.root),
            spendStatus: { try await spending.status(for: $0) })
        drafts = CreateDraftStore(fileURL: layout.createDraftURL)
        variantScorer = VariantScorer(spend: imageSpend, spendStatus: { try await spending.status(for: $0) })
        characterBuilder = CharacterBuilder(
            log: CharacterSheetLog(folder: layout.root), spend: imageSpend,
            spendStatus: { try await spending.status(for: $0) })
        pricing = try? Pricing.bundled()
        engine = JobEngine(
            provider: nil, repository: store, uploadCache: store,
            media: MediaPreparer(workingDirectory: layout.sourcesFolder), connectivity: PathConnectivity(),
            settings: settings, downloader: BackgroundDownloader.shared,
            spendStatus: { job in try await spending.status(for: job.providerKind, excluding: job.id) })
        connection = ConnectionStore(
            vault: KeychainVault(store: .activeConnection), metadata: UserDefaultsMetadataStore(defaults: defaults),
            services: HiggsfieldConnectionServices())
        connection.onCredentialChange = { [weak self] credential in await self?.use(credential) }
        imageGenerator.onImages = { [weak self] images in self?.saveGeneratedImages(images) }
        marks.job = { [weak self] id in self?.library.job(id) }
        notifications.onOpen = { [weak self] id in self?.navigation.openTake(id) }
        characterBuilder.onSheets = { [weak self] records in self?.saveCharacterSheets(records) }
        characterBuilder.onSignInExpired = { [weak self] in self?.connection.markNeedsAttention() }
    }

    /// Hands the restored connection to the engine, then resumes the jobs of the last session. Runs once; a later
    /// caller (the scene becoming active, a background check) waits for it, so none starts the engine early.
    func start() async {
        if startup == nil { startup = Task { await resumeLastSession() } }
        await startup?.value
    }

    private func resumeLastSession() async {
        // Before the engine resumes any job, so none is between preparing and uploading a file removed here.
        do {
            try await Self.removePreparedFiles(in: layout.sourcesFolder)
        } catch {
            logger.error("Can't remove old prepared inputs: \(String(describing: error), privacy: .private)")
        }
        await removeExpiredCache()
        network.follow(PathConnectivity()) { [weak self] in self?.retryAfterReconnect() }
        let events = engine.events
        eventsTask = Task { [weak self, liveJobs] in
            await liveJobs.consume(
                events,
                onFinished: { job in
                    self?.liveActivity.noteFinished(job)
                    if let self { Task { await self.library.add(job) } }
                    self?.notifications.post(for: job)
                    self?.scheduleBalanceRefresh()
                },
                onStateChange: { [weak self] in
                    guard let self else { return }
                    liveActivity.update(with: liveJobs, images: imageGenerator.runs)
                    writeWidgetSnapshot()
                })
        }
        liveJobs.seed(await Self.storedJobs(in: modelContainer, finishedLimit: LiveJobs.storedFinishedLimit))
        #if DEBUG
            liveJobs.seed(AccountFixture.sampleJobs(in: .documentsDirectory))
        #endif
        liveActivity.update(with: liveJobs, images: imageGenerator.runs)
        writeWidgetSnapshot()
        await presets.loadCache()
        await library.load()
        await engine.onConnectionNeedsAttention { [weak self] in
            await MainActor.run { self?.connection.markNeedsAttention() }
        }
        await connection.activate()
        do {
            try await engine.start()
        } catch {
            logger.error("Can't resume jobs: \(String(describing: error), privacy: .private)")
        }
        // Neither the first screen nor the engine needs it.
        await pruneTemplateImages()
    }

    /// What the active connection can run; flags the connection on 401.
    @discardableResult
    func loadCapabilities() async -> Capabilities? {
        guard let provider else {
            capabilities = nil
            return nil
        }
        let generation = providerGeneration
        do {
            let loaded = try await provider.capabilities()
            guard providerGeneration == generation else { return nil }
            capabilities = loaded
            return loaded
        } catch {
            if error as? ProviderError == .unauthorized { connection.markNeedsAttention() }
            logger.error("Can't load capabilities: \(String(describing: error), privacy: .private)")
            return nil
        }
    }

    /// The provider's estimate; `nil` while disconnected or when it can't be had.
    func estimate(_ spec: JobSpec) async -> Cost? {
        guard let provider else { return nil }
        do {
            return try await provider.estimate(spec)
        } catch {
            logger.error("Can't estimate: \(String(describing: error), privacy: .private)")
            return nil
        }
    }

    /// Queues `specs` in order and stops at the first the engine refuses; the message to show, `nil` when all queued.
    func enqueue(_ specs: [JobSpec], parentID: UUID? = nil, overCapApproved: Bool = false) async -> UserMessage? {
        guard network.isOnline else { return Self.offlineMessage }
        let batchID = specs.count > 1 ? UUID() : nil
        let failure = await BatchEnqueue.run(specs, kind: connection.state.kind) { spec in
            let job = try await engine.enqueue(
                spec, parentID: parentID, batchID: batchID, overCapApproved: overCapApproved)
            liveJobs.seed([job])
        }
        // Jobs queued before a failure still go out.
        background?.startSending(count: unsentJobCount)
        if failure == nil { await notifications.requestAuthorizationIfNeeded() }
        return failure
    }

    /// Runs `command` on a job; what to tell the person when the engine refuses it, `nil` when it ran.
    func perform(_ command: JobCommand, on id: UUID) async -> UserMessage? {
        do {
            switch command {
            case .cancel: try await engine.cancel(id)
            case .retry: try await engine.retry(id)
            case .retryChargingAgain: try await engine.retry(id, chargeAgainApproved: true)
            case .checkAgain: try await engine.checkAgain(id)
            case .resume: try await engine.resume(id)
            case .runNext: try await engine.runNext(id)
            }
            return nil
        } catch {
            return UserMessage(error, kind: connection.state.kind)
        }
    }

    private func use(_ credential: Credential?) async {
        let generation = connection.credentialGeneration
        let provider = credential.map { credential in
            ProviderFactory.provider(
                for: credential,
                persist: { [weak self] refreshed in await self?.saveRefreshed(refreshed, generation: generation) },
                unlimitedOptIn: { [weak self] in await self?.usesUnlimited() ?? false },
                constraints: { .builtIn })
        }
        self.provider = provider
        providerGeneration += 1
        capabilities = nil
        history.switchAccount(to: provider.map { "\($0.kind.rawValue)|\($0.owner ?? "")" })
        marks.useLikes(generationLikes, owner: provider?.owner)
        motionLibrary = (provider as? any MotionLibrary).map { MotionLibraryModel(library: $0) }
        accountElements = (provider as? any AccountElements).map { AccountElementsModel(source: $0, isOffered: true) }
        await engine.setMaxConcurrency(AppSettings.maxConcurrency(in: defaults, for: provider?.kind))
        await engine.setProvider(provider)
        // Image requests of the old account stop being followed; the new one's, from before a relaunch, resume.
        imageGenerator.reset()
        if let imageProvider { imageGenerator.resume(provider: imageProvider) }
        scheduleBalanceRefresh()
        await loadCapabilities()
        await loadImageModels()
        followCharacterSheets()
        if let provider { await presets.refresh { try await provider.presets() } }
    }

    private func usesUnlimited() -> Bool {
        AppSettings.usesUnlimited(in: defaults)
    }

    private func saveRefreshed(_ tokens: OAuthTokens, generation: Int) {
        do {
            _ = try connection.saveRefreshedTokens(tokens, generation: generation)
        } catch {
            logger.error("Can't save refreshed sign-in: \(String(describing: error), privacy: .private)")
        }
    }

    private func scheduleBalanceRefresh() {
        Task {
            guard let provider else { return }
            await connection.refreshBalance(from: provider)
        }
    }

    /// Active jobs and the most recently finished ones, so the Queue isn't empty before the first event.
    /// Fetched and decoded in a context of their own, off the main actor.
    @concurrent
    private static func storedJobs(in container: ModelContainer, finishedLimit: Int) async -> [Job] {
        var finished = JobRecord.finishedNewestFirst
        finished.fetchLimit = finishedLimit
        let active = FetchDescriptor<JobRecord>(predicate: #Predicate<JobRecord> { $0.isTerminal == false })
        do {
            let context = ModelContext(container)
            return try (context.fetch(active) + context.fetch(finished)).compactMap { record in
                do {
                    return try record.job()
                } catch {
                    logger.error("Can't read a stored job: \(String(describing: error), privacy: .private)")
                    return nil
                }
            }
        } catch {
            logger.error("Can't load stored jobs: \(String(describing: error), privacy: .private)")
            return []
        }
    }

    @concurrent
    private static func removePreparedFiles(in folder: URL) async throws {
        try MediaPreparer(workingDirectory: folder).removePreparedFiles()
    }
}

extension AppEnvironment {
    static func launch() -> AppEnvironment? {
        do {
            return try AppEnvironment(layout: FileLayout())
        } catch {
            logger.fault("Can't open the library: \(String(describing: error), privacy: .private)")
            return nil
        }
    }
}
