import Foundation
import JutsuCore
import Presentation
import UIKit
import os

nonisolated private let logger = Logger.jutsu("Create")

/// Create's state and what it does, apart from how it looks: the video form and the side shown, prices, today's
/// spend, submitting with the cap check, the draft kept between launches, and the inputs other places hand over.
/// One for the app, so leaving the tab keeps the form as it was.
@Observable
final class CreateScreenModel {
    var form = CreateForm(settings: .standard)
    var isImageSide = false
    var message: UserMessage?
    private(set) var isLoadingSource = false
    /// Bumped on every pick, so a slower earlier one can't land over a newer one or its spinner.
    @ObservationIgnored private var sourceGeneration = 0
    /// Drops a second Draft or Generate while one is being queued.
    private let submits = SubmitController()
    private var estimates = EstimateCache()
    /// The connection `estimates` were asked of; another one starts them over.
    @ObservationIgnored private var estimatesGeneration = 0
    private var spendStatus: SpendStatus?
    /// The over-cap question last asked; kept when the dialog clears `confirmation` before its button runs.
    @ObservationIgnored private var asked: SubmitController.Pending?
    @ObservationIgnored private var restoredDraft = false
    @ObservationIgnored private unowned let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var context: CreateContext {
        CreateContext(
            connection: environment.connection.state, capabilities: environment.capabilities,
            pricing: environment.pricing, estimates: estimates.costs, lastTotals: estimates.lastTotals,
            committedToday: spendStatus?.committedToday ?? 0, cap: spendStatus?.cap,
            unlimitedOptIn: AppSettings.usesUnlimited(in: .standard))
    }

    // MARK: Draft and spend

    /// Both sides of Create come back as they were left, without files that can no longer be read. Once.
    func restoreDraft() {
        guard !restoredDraft else { return }
        restoredDraft = true
        let drafts = environment.drafts.restore { image in
            FileManager.default.fileExists(atPath: image.fileURL.path(percentEncoded: false)) ? image : nil
        }
        if let video = drafts.video { form = video }
        if let image = drafts.image { environment.imageGenerator.restore(image) }
        isImageSide = drafts.kind == .image || AccountFixture.opensImageSide
        if let video = AccountFixture.sourceVideo { Task { await loadVideo { PickedMovie(url: video) } } }
        if let reference = AccountFixture.reference { _ = form.addReferences([LocalImage(fileURL: reference)]) }
        if let prompt = AccountFixture.prompt {
            form.prompt = prompt
            environment.imageGenerator.prompt = prompt
        }
    }

    func saveDraft() {
        guard restoredDraft else { return }
        let drafts = CreateDraftStore.Drafts(
            video: form, image: environment.imageGenerator.snapshot(), kind: isImageSide ? .image : .video)
        do {
            try environment.drafts.save(drafts)
        } catch {
            logger.error("Can't save the Create draft: \(String(describing: error), privacy: .private)")
        }
    }

    func refreshSpend() async {
        do {
            spendStatus = try await environment.spending.status(for: environment.connection.state.kind)
        } catch {
            logger.error("Can't read today's spend: \(String(describing: error), privacy: .private)")
        }
    }

    // MARK: Prices

    /// What Draft's and Generate's specs are made from, and the connection; a change asks for their prices again.
    /// Compared on every render, so it holds the inputs rather than building the specs. Prices ignore the prompt.
    var priceRequest: PriceRequest {
        var form = self.form
        form.prompt = ""
        let context = self.context
        return PriceRequest(
            form: form, connection: context.connection, capabilities: context.capabilities,
            unlimitedOptIn: context.unlimitedOptIn, generation: environment.providerGeneration,
            isOnline: environment.network.isOnline)
    }

    struct PriceRequest: Equatable {
        let form: CreateForm
        let connection: ConnectionState
        let capabilities: Capabilities?
        let unlimitedOptIn: Bool
        let generation: Int
        /// Prices that failed offline are asked again once the network is back.
        let isOnline: Bool
    }

    /// After a short stop, so typing a length or dragging a trim handle doesn't ask on every step; the prices
    /// missing are asked at once.
    func refreshEstimates() async {
        let generation = environment.providerGeneration
        if generation != estimatesGeneration {
            estimates = EstimateCache()
            estimatesGeneration = generation
        }
        let draft = form.makeSpecs(isDraft: true, in: context)
        let generate = form.makeSpecs(isDraft: false, in: context)
        let environment = environment
        guard
            let fresh = await EstimateCache.estimate(
                estimates.missing(draft + generate), after: .milliseconds(300),
                with: { await environment.estimate($0) }),
            environment.providerGeneration == generation
        else { return }
        estimates.record(fresh, generate: generate, draft: draft)
    }

    // MARK: Submit

    var isSubmitting: Bool { submits.isBusy }

    var confirmation: CapConfirmation? {
        get { submits.pending?.confirmation }
        set { if newValue == nil { submits.pending = nil } }
    }

    func submit(isDraft: Bool) {
        // Before the cap check, which would ask about a price that can't be had offline.
        guard environment.network.isOnline else {
            message = AppEnvironment.offlineMessage
            return
        }
        let decision = form.submitDecision(isDraft: isDraft, in: context)
        submits.run { [self] in
            await self.submits.handle(
                decision,
                blocked: { self.message = UserMessage(title: String(localized: "Can't generate yet"), message: $0) },
                enqueue: { await self.enqueue($0, overCapApproved: $1) })
            self.asked = self.submits.pending
        }
    }

    /// The person agreed to go past today's cap.
    func submitOverCap() {
        guard let asked else { return }
        self.asked = nil
        submits.confirm(asked)
    }

    private func enqueue(_ specs: [JobSpec], overCapApproved: Bool) async {
        message = await environment.enqueue(specs, overCapApproved: overCapApproved)
        await refreshSpend()
        if message == nil { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    // MARK: Inputs

    func loadVideo(_ movie: () async throws -> PickedMovie?) async {
        sourceGeneration += 1
        let generation = sourceGeneration
        isLoadingSource = true
        do {
            guard let movie = try await movie() else {
                if generation == sourceGeneration { isLoadingSource = false }
                return
            }
            let source = try await SourceVideo.probing(movie.url)
            guard generation == sourceGeneration else { return }
            form.setSource(source)
            isLoadingSource = false
        } catch {
            guard generation == sourceGeneration else { return }
            logger.error("Can't load the picked video: \(String(describing: error), privacy: .private)")
            message =
                error.isOutOfSpace
                ? .notEnoughStorage
                : UserMessage(title: String(localized: "Can't open this video"), message: error.localizedDescription)
            isLoadingSource = false
        }
    }

    /// Something on the side shown that Clear would take out.
    var canClear: Bool { isImageSide ? environment.imageGenerator.hasInputs : form.hasInputs }

    /// Empties the side shown: its inputs and prompt, and the Image side's results; models and settings stay.
    func clear() {
        if isImageSide {
            environment.imageGenerator.clearForm()
        } else {
            form.clearInputs()
        }
    }

    func addReferences(_ images: [LocalImage]) {
        _ = form.addReferences(images)
        isImageSide = false
    }

    /// Edit Inputs or Use as Reference from another tab of the window.
    func takeRequest(from navigation: NavigationModel) {
        switch navigation.takeCreateRequest() {
        case .editInputs(let job)?:
            form.load(job.spec, source: job.spec.source.map(SourceVideo.init(clip:)), parentID: job.id)
            isImageSide = false
        case .useReference(let image)?:
            addReferences([image])
        case nil:
            break
        }
    }

    /// Files from "Share → Jutsu": a video becomes the source, images become references.
    func importShared() async {
        let shared = await SharedInboxImporter.take()
        for item in shared.items {
            switch item {
            case .video(let video): form.setSource(video)
            case .image(let image): _ = form.addReferences([image])
            }
        }
        if shared.unreadable > 0 {
            message = UserMessage(
                title: String(localized: "Can't open this video"),
                message: String(
                    localized: "Jutsu couldn't read a file you shared. Share it again from Photos or Files."))
        }
    }

    /// Runs a download for the form; a failure becomes the message.
    func load(_ work: () async throws -> Void) async {
        do {
            try await work()
        } catch {
            message = UserMessage(error)
        }
    }
}
