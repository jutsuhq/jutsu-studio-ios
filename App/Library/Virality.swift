import Foundation
import HiggsfieldProviders
import JutsuCore
import Persistence
import Presentation
import SwiftData
import SwiftUI
import os

nonisolated private let logger = Logger.jutsu("Virality")

extension AppEnvironment {
    var viralityAvailability: ViralityAvailability {
        ViralityAvailability.of(scorer: viralityScorer, offered: HiggsfieldMCPProvider.offersVirality)
    }

    /// The price of one score; unknown when Higgsfield gives no quote.
    func viralityEstimate(_ plan: ViralityPlan) async -> Cost {
        guard let scorer = viralityScorer, let entry = plan.entries.first else { return .unknownCredits }
        do {
            return try await scorer.viralityEstimate(jobID: entry.jobID) ?? .unknownCredits
        } catch {
            logger.error("Can't quote a virality score: \(String(describing: error), privacy: .private)")
            return .unknownCredits
        }
    }

    /// Kept on the take's current version, so it is never paid for twice.
    func saveVirality(_ score: ViralityScore, for id: UUID) {
        marks.setScore(score, for: id)
        let context = modelContainer.mainContext
        do {
            var descriptor = FetchDescriptor<MaterialRecord>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let record = try context.fetch(descriptor).first else { return }
            var material = try record.material()
            guard var job = material.current.video else { return }
            job.virality = score
            material.current.video = job
            try record.update(material)
            try context.save()
        } catch {
            logger.error("Can't save a virality score: \(String(describing: error), privacy: .private)")
        }
    }
}

/// Asks Higgsfield's Virality Predictor to score a generation's variants, with the price first.
struct ScoreVariantsSheet: View {
    let plan: ViralityPlan
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var each: Cost?
    @State private var acceptsUnknownPrice = false
    @State private var overCap: CapConfirmation?

    private var total: Cost? { each.map { plan.total(each: $0) } }

    private var canScore: Bool {
        guard let total, environment.viralityScorer != nil, plan.blocker == nil else { return false }
        return total != .unknownCredits || acceptsUnknownPrice
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if plan.isRescore { Text(ViralityPlan.rescoreNotice).foregroundStyle(Theme.warning) }
                    if let total {
                        Text(plan.priceText(total))
                        if total == .unknownCredits {
                            Toggle(PostOperationText.unknownPriceConsent, isOn: $acceptsUnknownPrice)
                        }
                    } else {
                        LabeledContent("Asking Higgsfield for the price") { ProgressView() }
                    }
                    if let blocker = plan.blocker { Text(blocker).foregroundStyle(Theme.warning) }
                } footer: {
                    Text("Scores are kept on each take. Picking the winner stays up to you.")
                }
                Section {
                    Button {
                        Task { await score() }
                    } label: {
                        Label(plan.buttonTitle, systemImage: "chart.line.uptrend.xyaxis").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.prominent)
                    .disabled(!canScore)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(VariantScorer.modelTitle)
            .navigationBarTitleDisplayMode(.inline)
            .closeButton()
            .task { each = await environment.viralityEstimate(plan) }
            .capConfirmation($overCap) { Task { await score(overCapApproved: true) } }
        }
        .presentationDetents([.medium])
    }

    private func score(overCapApproved: Bool = false) async {
        guard let scorer = environment.viralityScorer, let each else { return }
        let environment = environment
        let started = await environment.variantScorer.score(
            plan, provider: scorer, each: each, overCapApproved: overCapApproved
        ) { id, score in
            environment.saveVirality(score, for: id)
        }
        if case .needsConfirmation(let question) = started {
            overCap = question
        } else {
            dismiss()
        }
    }
}

/// The score on a take's cell: a spinner while scoring, the number once known.
struct ViralityBadge: View {
    let id: UUID
    @Environment(AppEnvironment.self) private var environment
    @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = 11

    var body: some View {
        if environment.variantScorer.scoring.contains(id) {
            ProgressView().controlSize(.mini).accessibilityLabel("Scoring")
        } else if let score = environment.marks.scores[id], let badge = score.badgeText {
            Text(badge)
                .font(.system(size: min(size, 15), weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.accent, in: .capsule)
                .accessibilityLabel(score.accessibilityLabel)
        }
    }
}
