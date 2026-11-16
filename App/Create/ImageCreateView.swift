import JobEngine
import JutsuCore
import MediaKit
import PhotosUI
import Presentation
import SwiftUI

/// The Image side of Create: the prompt with the image to edit, then the model, the frame, the model's own
/// resolution or quality, how many images, and the price on Generate. Every choice is one tap on a visible option,
/// never a menu, except the model. Requests keep running while you switch side or tab; finished images land in
/// Documents/Images.
struct ImageCreateView: View {
    @Bindable var generator: ReferenceGenerator
    let useAsReference: (LocalImage) -> Void
    @Environment(AppEnvironment.self) private var environment
    @State private var inputItem: PhotosPickerItem?
    /// The pick being read, so a newer one can cancel it before it lands.
    @State private var pickTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // The blocker on the Generate bar says it too.
            if let reason = generator.unavailableReason, reason != generator.blocker {
                Text(reason).foregroundStyle(Theme.muted)
            }
            promptCard
            if let model = generator.model {
                modelMenu(model)
                if !model.aspectRatios.isEmpty {
                    group("Aspect ratio") {
                        AspectRatioPicker(
                            ratios: model.aspectRatios,
                            selection: Binding(
                                get: { generator.aspectRatio(source: nil, mode: .motionTransfer) ?? "" },
                                set: { generator.chosenAspectRatio = $0 }))
                    }
                }
                ForEach(model.settings, id: \.name) { setting in
                    group(LocalizedStringKey(setting.title)) {
                        OptionBar(
                            options: setting.options, title: setting.optionTitle,
                            selection: Binding(
                                get: { generator.settingValue(setting) },
                                set: { generator.chosenSettings[setting.name] = $0 }))
                    }
                }
                if model.variantCounts.count > 1 {
                    group("Images") {
                        OptionBar(
                            options: model.variantCounts, title: { "\($0)" }, selection: $generator.count)
                    }
                }
            }
            runs
            results
        }
        .animation(.snappy, value: generator.modelID)
        .sensoryFeedback(.selection, trigger: choices)
        .task(id: "\(priceKey)|\(environment.network.isOnline)") { await refreshPrice() }
        .onChange(of: inputItem) { _, item in
            // A slower earlier pick must not land over the one chosen after it.
            pickTask?.cancel()
            guard let item else { return }
            pickTask = Task {
                let image = await item.localImage()
                guard !Task.isCancelled else { return }
                if let image { generator.inputImage = image }
                inputItem = nil
            }
        }
    }

    /// The prompt, with the image to edit under it for a model that takes one.
    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Describe the image", text: $generator.prompt, axis: .vertical)
                .lineLimit(3...8)
                .keyboardDoneButton()
            if let model = generator.model, model.input != .none {
                HStack(spacing: 10) {
                    if let image = generator.inputImage {
                        InputThumbnail(url: image.fileURL) { generator.inputImage = nil }
                    }
                    let title: LocalizedStringResource =
                        generator.inputImage != nil
                        ? "Replace Image" : model.input == .required ? "Add the image to edit" : "Add an image to edit"
                    PhotosPicker(selection: $inputItem, matching: .images) {
                        InputPickLabel(title: title)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(model.input == .required && generator.inputImage == nil ? Theme.accent : .white)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.stroke) }
    }

    /// The picker's own label: a photo symbol with the action the current choice calls for.
    private struct InputPickLabel: View {
        let title: LocalizedStringResource

        var body: some View {
            Label(title, systemImage: "photo.badge.plus")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(Color.white.opacity(0.07), in: .capsule)
        }
    }

    /// The model as a card: its name and what it can do, a menu of the connection's models.
    private func modelMenu(_ model: ImageModel) -> some View {
        Menu {
            ForEach(generator.models) { option in
                Button {
                    generator.selectModel(option.id)
                } label: {
                    if option.id == model.id {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                    if let summary = option.summary { Text(summary) }
                }
            }
        } label: {
            HStack(spacing: 12) {
                SymbolTile(systemName: "jutsu.model", isAccent: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.title).font(.headline).foregroundStyle(.white)
                    if let summary = model.summary {
                        Text(summary).font(.footnote).foregroundStyle(Theme.muted)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.faint)
            }
            .padding(12)
            .background(Theme.card, in: .rect(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.stroke) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Model")
        .accessibilityValue(model.title)
    }

    private func group(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: title)
            content()
        }
    }

    /// What the option bars set, so each tap on one is felt.
    private var choices: [String] {
        [generator.modelID ?? "", generator.chosenAspectRatio ?? "", String(generator.count)]
            + generator.chosenSettings.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
    }

    private var priceKey: String { generator.priceKey(source: nil, mode: .motionTransfer) }

    @ViewBuilder private var runs: some View {
        ForEach(generator.runs) { run in
            HStack {
                Text(run.title).font(.subheadline)
                Spacer()
                if run.state == .running {
                    ProgressView()
                    if environment.imageProvider?.canCancel == true {
                        Button("Cancel") { generator.cancel(run.id) }.font(.footnote)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder private var results: some View {
        if !generator.images.isEmpty {
            HStack {
                Eyebrow(text: "Results")
                Spacer()
                Button("Clear", action: generator.clearResults).font(.footnote).disabled(generator.isRunning)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(generator.images) { image in
                    RemoteThumb(url: image.fileURL ?? image.url)
                        .aspectRatio(image.aspectRatio.flatMap(ImageModel.widthOverHeight) ?? 1, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 16))
                        .contextMenu {
                            if let file = image.fileURL {
                                Button("Use as Reference", systemImage: "person.crop.square") {
                                    useAsReference(
                                        LocalImage(fileURL: file, remoteOrigin: image.url, prompt: image.prompt))
                                }
                                ShareLink(item: file)
                            }
                        }
                }
            }
        }
    }

    private func refreshPrice() async {
        guard let provider = environment.imageProvider else { return }
        await generator.refreshPrice(
            provider: provider, source: nil, mode: .motionTransfer, upload: environment.imageUploader(provider))
    }

}

extension AppEnvironment {
    /// Prepares an image like a job's reference, then uploads it.
    func imageUploader(_ provider: any ImageProvider) -> @Sendable (LocalImage) async throws -> RemoteAsset {
        let preparer = MediaPreparer(workingDirectory: layout.sourcesFolder)
        return { image in try await provider.upload(try await preparer.prepareImage(image)) }
    }

    /// Hands the connection's image models to the Image side.
    func loadImageModels() async {
        if let sample = AccountFixture.imageModels {
            imageGenerator.useModels(sample)
            return
        }
        guard let provider = imageProvider else {
            imageGenerator.useModels([])
            return
        }
        do {
            imageGenerator.useModels(try await provider.imageModels())
        } catch {
            imageGenerator.useModels([], unavailableReason: UserMessage(error)?.message)
        }
    }
}

/// Generate with the price, over the tab bar on the Image side, so it is in reach wherever the form is scrolled.
struct ImageGenerateBar: View {
    let generator: ReferenceGenerator
    @Environment(AppEnvironment.self) private var environment
    @State private var message: UserMessage?
    @State private var confirmation: CapConfirmation?

    var body: some View {
        VStack(spacing: 6) {
            // An empty prompt says so in its own field; any other reason shows over the button.
            if let blocker = generator.blocker, !generator.prompt.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(blocker).font(.footnote).foregroundStyle(Theme.muted).lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .glass(.regular, in: .capsule)
            }
            Button {
                Task { await generate(overCapApproved: false) }
            } label: {
                Label(generateTitle, systemImage: "sparkles")
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.prominent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(generator.blocker != nil || generator.isSubmitting)
        }
        .frame(maxWidth: 640)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .alert($message)
        .capConfirmation($confirmation) { Task { await generate(overCapApproved: true) } }
    }

    private var generateTitle: String {
        let price = (generator.price ?? generator.listPrice).map(CostText.text)
        return price.map { String(localized: "Generate · \($0)") } ?? String(localized: "Generate")
    }

    private func generate(overCapApproved: Bool) async {
        guard let provider = environment.imageProvider else {
            message = UserMessage(title: String(localized: "Connect Higgsfield first"), message: "")
            return
        }
        guard environment.network.isOnline else {
            message = AppEnvironment.offlineMessage
            return
        }
        let result = await generator.generate(
            provider: provider, source: nil, mode: .motionTransfer, price: generator.price ?? generator.listPrice,
            overCapApproved: overCapApproved, upload: environment.imageUploader(provider))
        if case .needsConfirmation(let question) = result { confirmation = question }
    }
}

/// One tap per option, equal widths: the count, the resolution, the quality.
private struct OptionBar<Value: Hashable>: View {
    let options: [Value]
    let title: (Value) -> String
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(isSelected ? Theme.ink : .white)
                        .background(isSelected ? Theme.accent : Color.white.opacity(0.07), in: .rect(cornerRadius: 12))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// The frames as tiles drawn in their own shape, scrolling sideways when there are many.
private struct AspectRatioPicker: View {
    let ratios: [String]
    @Binding var selection: String
    @ScaledMetric(relativeTo: .caption) private var tile: CGFloat = 60
    @ScaledMetric(relativeTo: .caption) private var glyph: CGFloat = 24

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(ratios, id: \.self) { ratio in
                        let isSelected = ratio == selection
                        Button {
                            selection = ratio
                        } label: {
                            VStack(spacing: 6) {
                                shape(ratio)
                                    .frame(width: glyph, height: glyph)
                                Text(ratio == "auto" ? String(localized: "Auto") : ratio)
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .lineLimit(1)
                            }
                            .frame(width: tile, height: tile)
                            .foregroundStyle(isSelected ? Theme.accent : Theme.muted)
                            .background(
                                isSelected ? Theme.accent.opacity(0.12) : Color.white.opacity(0.05),
                                in: .rect(cornerRadius: 14)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 1.5)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .id(ratio)
                        .accessibilityLabel(ratio == "auto" ? String(localized: "Auto") : ratio)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
        }
    }

    /// A rounded frame of the ratio's shape, fitted in the glyph's square; a sparkle for "auto".
    @ViewBuilder private func shape(_ ratio: String) -> some View {
        if let ratio = ImageModel.widthOverHeight(ratio) {
            let width = ratio >= 1 ? glyph : glyph * ratio
            let height = ratio >= 1 ? glyph / ratio : glyph
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(lineWidth: 1.6)
                .frame(width: max(width, 6), height: max(height, 6))
        } else {
            Image(systemName: "sparkles").font(.system(size: glyph * 0.7))
        }
    }
}

/// The image to edit, with a button that takes it off.
private struct InputThumbnail: View {
    let url: URL
    let remove: () -> Void

    var body: some View {
        RemoteThumb(url: url, width: 56, height: 56, cornerRadius: 12)
            .overlay(alignment: .topTrailing) {
                Button(action: remove) {
                    Image(systemName: "xmark").font(.caption2.weight(.bold)).padding(5)
                }
                .glass(.clear, in: .circle)
                .offset(x: 6, y: -6)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Image to edit")
            .accessibilityAddTraits(.isImage)
            .accessibilityAction(named: "Remove", remove)
    }
}
