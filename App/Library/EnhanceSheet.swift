import AVFoundation
import JutsuCore
import Presentation
import SwiftUI
import os

nonisolated private let logger = Logger.jutsu("Enhance")

/// Enhance a take on Higgsfield, with the price on each row (Upscale, Reframe, Remove Background, Dub).
/// A medium sheet floating over the video, as glass.
struct EnhanceSheet: View {
    let job: Job
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var message: UserMessage?
    @State private var overCap: CapConfirmation?
    /// The action a confirmation is for; kept when the dialog clears `overCap` before its button runs.
    @State private var askedAction: PostAction?
    @State private var reframe = ReframeAspect.portrait
    @State private var dub = DubLanguage.sorted().first
    @State private var voices: [AccountVoice] = []
    @State private var voice: AccountVoice?
    @State private var preview: AVPlayer?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    switch availability {
                    case .available:
                        higgsfieldRow(.upscale(UpscaleOptions()), symbol: "jutsu.upscale")
                        HStack {
                            higgsfieldRow(.reframe(reframe), symbol: "jutsu.reframe")
                            Picker("", selection: $reframe) {
                                ForEach(ReframeAspect.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden()
                        }
                        higgsfieldRow(.removeBackground, symbol: "jutsu.cutout")
                        if let dub {
                            HStack {
                                higgsfieldRow(.dub(dub), symbol: "jutsu.mic")
                                Picker("", selection: $dub) {
                                    ForEach(DubLanguage.sorted(), id: \.self) { Text($0.title()).tag(Optional($0)) }
                                }
                                .labelsHidden()
                            }
                        }
                        if let voice {
                            HStack {
                                higgsfieldRow(.changeVoice(voice.choice), symbol: "jutsu.mic")
                                Picker("", selection: $voice) {
                                    ForEach(voices) { Text("\($0.choice.name) · \($0.kindLabel)").tag(Optional($0)) }
                                }
                                .labelsHidden()
                                if let url = voice.previewURL {
                                    Button {
                                        preview = AVPlayer(url: url)
                                        preview?.play()
                                    } label: {
                                        Image(systemName: "play.circle")
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Listen to \(voice.choice.name)")
                                }
                            }
                        }
                    case .disabled(let reason):
                        Text(reason).foregroundStyle(Theme.muted)
                    case .hidden:
                        Text(PostOperationText.needsAccount).foregroundStyle(Theme.muted)
                    }
                } header: {
                    Text("On Higgsfield")
                }
            }
            .navigationTitle("Enhance")
            .navigationBarTitleDisplayMode(.inline)
            .closeButton()
            .alert($message)
            .capConfirmation($overCap) {
                guard let action = askedAction else { return }
                askedAction = nil
                queue(action, overCapApproved: true)
            }
        }
        .presentationDetents([.medium, .large])
        .task { await loadVoices() }
    }

    private var availability: EnhanceAvailability {
        EnhanceAvailability.of(
            LibraryItemModel(job: job), connection: environment.provider?.kind,
            offered: environment.provider?.kind == .account)
    }

    private func higgsfieldRow(_ action: PostAction, symbol: String) -> some View {
        Button {
            queue(action)
        } label: {
            HStack(spacing: 12) {
                SymbolTile(systemName: symbol)
                Text(action.title).foregroundStyle(.white)
                Spacer()
                if action.isPricedAfterRun {
                    Text(PostOperationText.priceAfterRun).font(.footnote).foregroundStyle(Theme.faint)
                }
            }
        }
    }

    /// The account's voices for Change Voice; none when the connection has no voice list.
    private func loadVoices() async {
        guard let library = environment.voiceLibrary else { return }
        do {
            voices = try await library.voices()
        } catch {
            logger.error("Can't load voices: \(String(describing: error), privacy: .private)")
            voices = []
        }
        voice = voice ?? voices.first
    }

    private func queue(_ action: PostAction, overCapApproved: Bool = false) {
        guard let spec = job.operationSpec(action, owner: environment.provider?.owner) else { return }
        Task {
            if !overCapApproved {
                // Higgsfield quotes these once they run, so under a cap the price is not known yet.
                let status = try? await environment.spending.status(for: environment.connection.state.kind)
                if case .confirm(_, let confirmation) = SubmitDecision.budgeted(
                    [spec], cost: nil, committedToday: status?.committedToday ?? 0, cap: status?.cap)
                {
                    askedAction = action
                    overCap = confirmation
                    return
                }
            }
            message = await environment.enqueue(
                [spec], parentID: job.id, overCapApproved: overCapApproved)
            if message == nil { dismiss() }
        }
    }
}
