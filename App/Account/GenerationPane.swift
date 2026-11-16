import JutsuCore
import Presentation
import SwiftUI

/// What a new Create form starts from, and how many jobs run at once.
struct GenerationPane: View {
    @Environment(AppEnvironment.self) private var environment
    @AppStorage(AppSettings.defaultModeKey) private var defaultMode = AppSettings.defaultMode.rawValue
    @AppStorage(AppSettings.defaultModelKey) private var defaultModel = ""
    @AppStorage(AppSettings.defaultResolutionKey) private var resolution = AppSettings.defaultResolution.rawValue
    @AppStorage(AppSettings.draftResolutionKey) private var draftResolution = AppSettings.defaultDraftResolution
        .rawValue
    @AppStorage(AppSettings.defaultAspectRatioKey) private var aspectRatio = AppSettings.defaultAspectRatio.rawValue
    @AppStorage(AppSettings.defaultAudioKey) private var audio = AppSettings.defaultAudio.rawValue
    /// `nil` until the user picks a limit: the connection's default applies.
    @AppStorage(AppSettings.maxConcurrencyKey) private var storedConcurrency: Int?

    var body: some View {
        Form {
            createSection
            queueSection
            ResetSection(reset: reset)
        }
        .settingsPage(.generation)
        .onChange(of: storedConcurrency) {
            let limit = concurrency.wrappedValue
            Task { await environment.engine.setMaxConcurrency(limit) }
        }
    }

    private var createSection: some View {
        Section {
            Picker("Default task", selection: $defaultMode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
            }
            Picker("Model", selection: $defaultModel) {
                Text("Automatic").tag("")
                ForEach(models, id: \.self) { Text($0.title).tag($0.rawValue) }
            }
            Picker("Resolution", selection: $resolution) {
                ForEach(Resolution.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
            }
            Picker("Draft resolution", selection: $draftResolution) {
                ForEach(Resolution.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
            }
            Picker("Aspect ratio", selection: $aspectRatio) {
                ForEach(AspectRatio.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
            }
            Picker("Sound", selection: $audio) {
                ForEach(AppSettings.defaultAudioOptions, id: \.self) { Text($0.title).tag($0.rawValue) }
            }
        } header: {
            Text("Create Defaults")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("A new Create form starts from these; a saved draft keeps its own.")
                Text("Automatic runs the task's own model. Aspect ratio applies to clips made without a source video.")
            }
        }
    }

    private var queueSection: some View {
        Section {
            Stepper(value: concurrency, in: AppSettings.maxConcurrencyRange) {
                LabeledContent("Jobs at once", value: "\(concurrency.wrappedValue)")
            }
        } header: {
            Text("Queue")
        } footer: {
            Text("Jobs over the limit wait in the queue. The change applies at once.")
        }
    }

    /// The models Create's picker offers for the default task on this connection, and the stored one if it isn't.
    private var models: [VideoModel] {
        let form = CreateForm(mode: Mode(rawValue: defaultMode) ?? AppSettings.defaultMode)
        let offered = form.modelOptions(in: environment.create.context)
        guard let stored = VideoModel(rawValue: defaultModel), !offered.contains(stored) else { return offered }
        return offered + [stored]
    }

    private var concurrency: Binding<Int> {
        Binding(
            get: { AppSettings.maxConcurrency(stored: storedConcurrency, for: environment.provider?.kind) },
            set: { storedConcurrency = AppSettings.clampConcurrency($0) })
    }

    private func reset() {
        defaultMode = AppSettings.defaultMode.rawValue
        defaultModel = ""
        resolution = AppSettings.defaultResolution.rawValue
        draftResolution = AppSettings.defaultDraftResolution.rawValue
        aspectRatio = AppSettings.defaultAspectRatio.rawValue
        audio = AppSettings.defaultAudio.rawValue
        storedConcurrency = nil
    }
}
