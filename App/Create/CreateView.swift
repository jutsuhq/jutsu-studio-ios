import JutsuCore
import PhotosUI
import Presentation
import SwiftUI

/// The Create form: source, mode, references and the Higgsfield-style prompt dock with the price on Generate. What it
/// does lives in `CreateScreenModel`; this is how it looks.
struct CreateView: View {
    @Binding var showsAccount: Bool
    @Environment(AppEnvironment.self) private var environment
    @Environment(NavigationModel.self) private var navigation
    @Environment(\.scenePhase) private var scenePhase
    /// Two columns once the window is wide enough: iPad, the inner screen of iPhone Duo.
    @State private var isWide = false
    @State private var pickedVideo: PhotosPickerItem?
    @State private var pickedImages: [PhotosPickerItem] = []
    @State private var showsTrim = false
    @State private var motionLibrary: MotionLibraryModel?
    @State private var showsPromptHistory = false
    @State private var showsTemplates = false
    @State private var asksClear = false

    var body: some View {
        @Bindable var model = environment.create
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center) {
                        DisplayTitle(text: "Create")
                        if model.canClear {
                            Button("Clear", systemImage: "xmark") { asksClear = true }
                                .labelStyle(.iconOnly)
                                .font(.body.weight(.semibold))
                                .buttonStyle(.liquidGlass)
                                .buttonBorderShape(.circle)
                                .confirmationDialog(
                                    model.isImageSide ? "Clear the image form?" : "Clear this take?",
                                    isPresented: $asksClear, titleVisibility: .visible
                                ) {
                                    Button("Clear", role: .destructive) { withAnimation { model.clear() } }
                                } message: {
                                    Text(
                                        model.isImageSide
                                            ? "The prompt, the image to edit and the results go. The model and its settings stay."
                                            : "The video, references and prompt go. The mode, model and settings stay.")
                                }
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.snappy, value: model.canClear)
                    Picker("Side", selection: $model.isImageSide) {
                        Text("Video").tag(false)
                        Text("Image").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if model.isImageSide {
                        ImageCreateView(generator: environment.imageGenerator) { model.addReferences([$0]) }
                    } else {
                        videoForm(model)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .readableWidth(isWide && !model.isImageSide ? 1080 : 640)
            }
            .measuresWide($isWide)
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .safeAreaInset(edge: .bottom) {
                if model.isImageSide {
                    ImageGenerateBar(generator: environment.imageGenerator)
                } else {
                    promptDock(model)
                }
            }
            .toolbar {
                if !model.isImageSide {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu("Reuse", systemImage: "clock.arrow.circlepath") {
                            Button("Prompt History", systemImage: "text.quote") { showsPromptHistory = true }
                            Button("Templates", systemImage: "square.on.square.dashed") { showsTemplates = true }
                        }
                    }
                }
                AccountToolbar(showsAccount: $showsAccount)
            }
            .sheet(isPresented: $showsPromptHistory) {
                PromptHistorySheet { model.form.prompt = $0 }
            }
            .sheet(isPresented: $showsTemplates) {
                TemplatesSheet(
                    current: model.form.makeTemplate(
                        name: TemplateNaming.suggestedName(mode: model.form.tab, prompt: model.form.prompt))
                ) { template in
                    model.message = model.form.apply(template, offered: Set(model.form.modelOptions(in: model.context)))
                }
            }
            .task(id: model.priceRequest) { await model.refreshEstimates() }
            .task(id: environment.providerGeneration) {
                await environment.loadCapabilities()
                await model.refreshSpend()
            }
            .task(id: model.form) {
                try? await Task.sleep(for: .seconds(1))
                model.saveDraft()
            }
            .onAppear(perform: model.restoreDraft)
            .onChange(of: model.isImageSide) { model.saveDraft() }
            .task(id: scenePhase) {
                if scenePhase == .active { await model.importShared() }
            }
            .onChange(of: pickedVideo) { _, item in
                guard let item else { return }
                Task { await model.loadVideo { try await item.loadTransferable(type: PickedMovie.self) } }
            }
            .onChange(of: pickedImages) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    _ = model.form.addReferences(await items.localImages())
                    pickedImages = []
                }
            }
            .onChange(of: navigation.createRequest, initial: true) { model.takeRequest(from: navigation) }
            .sheet(item: $motionLibrary) { library in
                MotionLibrarySheet(library: library) { preset in
                    await model.load { model.form.setSource(try await environment.downloadMotionClip(preset)) }
                }
            }
            .sheet(isPresented: $showsTrim) {
                TrimView(form: $model.form, context: model.context)
                    .presentationBackground(.black)
            }
            .alert($model.message)
            .sensoryFeedback(.error, trigger: model.message) { _, new in new != nil }
            .capConfirmation($model.confirmation) { model.submitOverCap() }
        }
    }

    /// The mode, then the one input the take follows (the source, with a style or frames where the mode takes them),
    /// then the references and the closed settings; model, length and resolution are on the dock. One column, or two
    /// side by side on a wide window. A video dropped on the source replaces it; images dropped on the references are
    /// added.
    private func videoForm(_ model: CreateScreenModel) -> some View {
        @Bindable var model = model
        let layout = Adaptive.columns(isWide, spacing: 18)
        return layout {
            VStack(alignment: .leading, spacing: 18) {
                AdaptivePicker(
                    title: "Mode", selection: Binding(get: { model.form.tab }, set: { model.form.pickTask($0) })
                ) {
                    ForEach(model.form.modeChoices, id: \.self) { Text($0.title).tag($0) }
                }
                let tasks = model.form.taskChoices(in: model.context)
                if tasks.count > 1 {
                    AdaptivePicker(
                        title: "Task", selection: Binding(get: { model.form.mode }, set: { model.form.pickTask($0) })
                    ) {
                        ForEach(tasks, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                SourceSection(
                    form: $model.form, pickedVideo: $pickedVideo, showsTrim: $showsTrim,
                    motionLibrary: $motionLibrary, isLoadingSource: model.isLoadingSource
                )
                .dropDestination(for: PickedMovie.self) { movies, _ in
                    guard let movie = movies.first else { return false }
                    Task { await model.loadVideo { movie } }
                    return true
                }
                if model.form.mode == .restyle || model.form.showsFrames {
                    CreateOptions(form: $model.form, presets: environment.presets)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            // Side by side, VoiceOver would otherwise read the two columns interleaved, row by row.
            .accessibilityElement(children: .contain)
            VStack(alignment: .leading, spacing: 18) {
                ReferencesSection(form: $model.form, pickedImages: $pickedImages)
                    .dropDestination(for: PickedImage.self) { images, _ in
                        model.form.addReferences(images.map { LocalImage(fileURL: $0.url) }) > 0
                    }
                CreateSettingsRow(form: $model.form, context: model.context)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .contain)
        }
    }

    private func promptDock(_ model: CreateScreenModel) -> some View {
        @Bindable var model = model
        let context = model.context
        return PromptDock(
            form: $model.form, models: model.form.modelOptions(in: context),
            generatePrice: model.form.priceText(isDraft: false, in: context),
            draftPrice: model.form.draftDiffers ? model.form.priceText(isDraft: true, in: context) : nil,
            isBusy: model.isSubmitting, trim: { showsTrim = true },
            generate: { model.submit(isDraft: false) }, draft: { model.submit(isDraft: true) })
    }
}
