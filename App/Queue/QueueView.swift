import JutsuCore
import Presentation
import SwiftUI

/// Every job the engine runs, by what it needs from the person; a batch's jobs under one header.
struct QueueView: View {
    @Binding var showsAccount: Bool
    @Environment(AppEnvironment.self) private var environment
    @Environment(LiveJobs.self) private var liveJobs
    @Environment(NavigationModel.self) private var navigation
    @State private var message: UserMessage?
    @State private var details: Job?
    /// A job whose Retry may be charged again, while the question is up.
    @State private var chargeAgain: Job?
    @State private var sections = QueueSections()

    var body: some View {
        let entries = sections.entries(of: liveJobs)
        NavigationStack {
            List {
                section("Needs you", entries: entries.needsYou)
                section("Running", entries: entries.running)
                section("Today", entries: entries.today)
            }
            .overlay {
                if liveJobs.all.isEmpty {
                    ContentUnavailableView(
                        "Nothing queued yet", systemImage: "square.stack.3d.up",
                        description: Text("Jobs you generate show up here and keep going in the background."))
                }
            }
            .navigationTitle("Queue")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if liveJobs.canResumeAll {
                        Button("Resume All", systemImage: "play") { Task { await environment.engine.resumeAll() } }
                    } else {
                        Button("Pause All", systemImage: "pause") { Task { await environment.engine.pauseAll() } }
                            .disabled(!liveJobs.canPauseAll)
                    }
                }
                AccountToolbar(showsAccount: $showsAccount)
            }
            .refreshable { await environment.willEnterForeground() }
            .sheet(item: $details) { JobDetails(job: $0) }
            .alert($message)
            .confirmationDialog(
                "Retry and pay again?", isPresented: Binding(isPresent: $chargeAgain), titleVisibility: .visible,
                presenting: chargeAgain
            ) { job in
                Button("Retry at \(JobRowModel(job, now: .now).cost)") { run(.retryChargingAgain, on: job) }
            } message: { _ in
                Text(
                    """
                    Higgsfield may have started this job and charged for it. Retrying sends a new request, \
                    charged again.
                    """)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, entries: [QueueEntry]) -> some View {
        if !entries.isEmpty {
            Section {
                ForEach(entries) { entry in
                    switch entry {
                    case .job(let job):
                        row(job)
                    case .batch(let batch):
                        DisclosureGroup {
                            ForEach(batch.jobs, id: \.id) { row($0) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(batch.title).font(.headline)
                                Text(batch.progressText).font(.subheadline).foregroundStyle(Theme.muted)
                                if batch.isActive {
                                    ProgressView(value: batch.progress).tint(Theme.signatureFuchsia)
                                }
                                if let cost = batch.totalCostText {
                                    Text(cost).font(.system(.footnote, design: .monospaced))
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    }
                }
            } header: {
                Eyebrow(text: title)
            }
        }
    }

    private func row(_ job: Job) -> some View {
        JobRow(row: JobRowModel(job, now: .now)) { run(.resume, on: job) }
            .contentShape(.rect)
            .onTapGesture { details = job }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { details = job }
            .swipeActions(edge: .trailing) { actions(for: job) }
            .contextMenu {
                Button("Details", systemImage: "info.circle") { details = job }
                Button("Duplicate", systemImage: "plus.square.on.square") {
                    Task { message = await environment.enqueue([job.spec]) }
                }
                Button("Edit Inputs", systemImage: "slider.horizontal.3") { navigation.editInputs(job) }
            }
    }

    @ViewBuilder
    private func actions(for job: Job) -> some View {
        let row = JobRowModel(job, now: .now)
        ForEach(Array(row.actions.enumerated()), id: \.offset) { _, action in
            switch action {
            case .cancel(let isEnabled, _) where isEnabled:
                Button("Cancel", systemImage: "xmark", role: .destructive) { run(.cancel, on: job) }
            case .retry, .retryDownload:
                Button("Retry", systemImage: "arrow.clockwise") { run(.retry, on: job) }.tint(Theme.accent)
            case .retryChargingAgain:
                Button("Retry", systemImage: "arrow.clockwise") { chargeAgain = job }.tint(Theme.accent)
            case .runNext:
                Button("Run Next", systemImage: "arrow.up") { run(.runNext, on: job) }.tint(Theme.accent)
            case .resume:
                Button("Resume", systemImage: "play") { run(.resume, on: job) }.tint(Theme.accent)
            case .confirmPrice:
                Button("Send at \(row.cost)", systemImage: "checkmark") { run(.resume, on: job) }
                    .tint(Theme.accent)
            case .checkAgain:
                Button("Check Again", systemImage: "arrow.triangle.2.circlepath") { run(.checkAgain, on: job) }
            default:
                EmptyView()
            }
        }
    }

    private func run(_ command: JobCommand, on job: Job) {
        Task { message = await environment.perform(command, on: job.id) }
    }
}

/// Which jobs each section shows, in order. Sorting every job waits for a state change; a progress event only looks
/// the shown ones up again.
@MainActor
private final class QueueSections {
    struct Sections<Item> {
        var needsYou: [Item] = []
        var running: [Item] = []
        var today: [Item] = []
    }

    private var revision: Int?
    private var ids = Sections<UUID>()

    func entries(of liveJobs: LiveJobs) -> Sections<QueueEntry> {
        if revision != liveJobs.stateRevision {
            revision = liveJobs.stateRevision
            ids = Sections(
                needsYou: liveJobs.active.filter(Self.isPaused).map(\.id),
                running: liveJobs.activeEntries.filter { $0.jobs.contains { !Self.isPaused($0) } }
                    .flatMap(\.jobs).map(\.id),
                today: liveJobs.recentFinished(limit: 30).map(\.id))
        }
        func fresh(_ ids: [UUID]) -> [QueueEntry] { QueueEntry.group(ids.compactMap(liveJobs.job)) }
        return Sections(needsYou: fresh(ids.needsYou), running: fresh(ids.running), today: fresh(ids.today))
    }

    private static func isPaused(_ job: Job) -> Bool {
        if case .paused = job.state { true } else { false }
    }
}

private struct JobRow: View {
    let row: JobRowModel
    let confirmPrice: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility sizes the price goes under the title instead of squeezing it to a few letters.
        let header =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        VStack(alignment: .leading, spacing: 4) {
            header {
                Text(row.title).font(.headline).lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(row.cost)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .strikethrough(!row.isCharged && row.statusRole == .danger)
            }
            Text(row.meta).font(.subheadline).foregroundStyle(Theme.muted)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            Text(row.statusLabel).font(.subheadline.weight(.medium)).foregroundStyle(row.statusRole.color)
            if let progress = row.progress {
                ProgressView(value: progress).tint(row.stage == .generate ? Theme.signatureFuchsia : Theme.info)
            } else if row.isWorking {
                ProgressView().progressViewStyle(.linear).tint(Theme.signatureFuchsia)
            }
            if let note = row.note {
                Text(note.text).font(.footnote).foregroundStyle(note.role.color)
            }
            if row.actions.contains(.confirmPrice) {
                Button("Send at \(row.cost)", action: confirmPrice)
                    .buttonStyle(.prominent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        // One stop per job; Send at… stays reachable as the row's swipe action.
        .accessibilityElement(children: .combine)
        .accessibilityValue(row.progressText ?? "")
    }
}

/// Everything about a job: its state, inputs, price and timing, and the IDs Higgsfield support asks for.
private struct JobDetails: View {
    let job: Job

    var body: some View {
        let row = JobRowModel(job, now: .now)
        let item = LibraryItemModel(job: job)
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Status") { Text(row.statusLabel).foregroundStyle(row.statusRole.color) }
                    if let hint = row.statusHint { Text(hint).font(.footnote).foregroundStyle(Theme.muted) }
                    LabeledContent("Price", value: row.cost)
                    LabeledContent("Billing", value: item.billingSummary)
                    if let timing = item.timingSummary { LabeledContent("Timing", value: timing) }
                }
                Section("Inputs") {
                    ForEach(item.facts, id: \.self) { Text($0) }
                    if !job.spec.prompt.isEmpty { Text(job.spec.prompt).font(.callout) }
                }
                if let ids = SupportIDs.line(for: job) {
                    Section {
                        Text(ids).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        Button("Copy IDs for Support", systemImage: "doc.on.doc") { UIPasteboard.general.string = ids }
                    } footer: {
                        Text("Higgsfield's support asks for these when a job failed or was rejected.")
                    }
                }
            }
            .navigationTitle(row.title)
            .navigationBarTitleDisplayMode(.inline)
            .closeButton()
        }
        .presentationDetents([.medium, .large])
    }
}
