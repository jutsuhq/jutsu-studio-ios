import Foundation
import JobEngine
import JutsuCore
import MediaKit
import PhotosUI
import Presentation
import SwiftUI

extension AppEnvironment {
    /// The finished sheets made in the app on the signed-in account, newest first.
    var madeCharacterSheets: [CharacterSheet] {
        guard let maker = characterMaker else { return [] }
        return characterBuilder.log.sheets(of: maker.owner)
    }

    func characterPresetsFeed() -> PagedFeed<CharacterPreset>? {
        characterMaker.map { maker in
            PagedFeed(failureTitle: String(localized: "Can't load the presets")) { cursor in
                let page = try await maker.characterPresets(after: cursor)
                return (page.items, page.nextCursor)
            }
        }
    }

    /// Prepares a face or style image like a job's reference, then uploads it to `maker`.
    func characterUploader(_ maker: any CharacterSheetMaker) -> @Sendable (LocalImage) async throws -> RemoteAsset {
        let preparer = MediaPreparer(workingDirectory: layout.sourcesFolder)
        return { image in try await maker.upload(try await preparer.prepareImage(image)) }
    }

    /// A new connection: the old one's sheets stop being followed, the new account's running ones are followed again.
    func followCharacterSheets() {
        characterBuilder.reset()
        if let maker = characterMaker { characterBuilder.resume(maker: maker) }
    }

}

/// Create Character: a person or an animal designed from a description, a face, style images and traits, made into
/// character sheets on the account. The sheets keep going after the sheet closes and land in Library › Images.
struct CreateCharacterSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var presets: PagedFeed<CharacterPreset>?
    @State private var pickedFace: PhotosPickerItem?
    @State private var pickedStyles: [PhotosPickerItem] = []
    @State private var confirmation: CapConfirmation?
    @State private var isStarting = false

    private var builder: CharacterBuilder { environment.characterBuilder }
    private var isBusy: Bool { isStarting || builder.isSubmitting }

    var body: some View {
        @Bindable var builder = builder
        NavigationStack {
            Form {
                Section {
                    Text(
                        "A character sheet shows one person or animal from every side. Use it as a reference to keep them the same in every video."
                    )
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                }
                presetsSection
                Section("Character") {
                    Picker("Character", selection: Binding(get: { builder.kind }, set: { builder.selectKind($0) })) {
                        ForEach(CharacterTier.Kind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if builder.kind.tiers.count > 1 {
                        Picker("Look", selection: Binding(get: { builder.tier }, set: { builder.selectTier($0) })) {
                            ForEach(builder.kind.tiers) { Text($0.title).tag($0) }
                        }
                    }
                    TextField(
                        "Who they are, how they look and dress",
                        text: $builder.brief, axis: .vertical
                    )
                    .lineLimit(3...8)
                    .keyboardDoneButton()
                }
                imagesSection
                Section {
                    Toggle("Randomize", isOn: $builder.randomize)
                    Picker("Sheets", selection: $builder.count) {
                        ForEach(Array(CharacterDesign.sheetCounts), id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Randomize fills in what the form leaves open differently each time.")
                }
                traitsSection
                runsSection
            }
            .safeAreaInset(edge: .bottom) { generateBar }
            .navigationTitle("Create Character")
            .navigationBarTitleDisplayMode(.inline)
            .closeButton()
        }
        .task(id: environment.providerGeneration) {
            presets = environment.characterPresetsFeed()
            await presets?.loadIfNeeded()
        }
        .task(id: builder.tier) {
            if let maker = environment.characterMaker { await builder.loadTraits(from: maker) }
        }
        .task(id: builder.quoteKey) { await refreshQuote() }
        .onChange(of: pickedFace) { _, item in
            guard let item else { return }
            Task {
                if let image = await item.localImage() { builder.face = image }
                pickedFace = nil
            }
        }
        .onChange(of: pickedStyles) { _, items in
            guard !items.isEmpty else { return }
            Task {
                _ = builder.addStyles(await items.localImages())
                pickedStyles = []
            }
        }
        .capConfirmation($confirmation) { generate(overCapApproved: true) }
    }

    @ViewBuilder private var presetsSection: some View {
        if let presets, !presets.items.isEmpty {
            Section {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(presets.items) { preset in
                            PresetTile(preset: preset, isPicked: builder.preset?.id == preset.id) {
                                builder.apply(preset)
                            }
                        }
                        if presets.hasMore && presets.failure == nil {
                            ProgressView().task(id: presets.items.count) { await presets.loadMore() }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                if builder.preset != nil {
                    Button("Clear Preset") { builder.clearPreset() }
                }
            } header: {
                Text("Presets")
            }
        }
    }

    private var imagesSection: some View {
        Section {
            HStack {
                Text("Face")
                Spacer()
                if let face = builder.face {
                    Thumb(url: face.fileURL) { builder.face = nil }
                } else {
                    PhotosPicker("Choose", selection: $pickedFace, matching: .images)
                }
            }
            HStack {
                Text("Style")
                Spacer()
                ForEach(Array(builder.styles.enumerated()), id: \.offset) { index, style in
                    Thumb(url: style.fileURL) { builder.removeStyle(at: index) }
                }
                if builder.styles.count < CharacterDesign.maxStyles {
                    PhotosPicker(
                        "Choose", selection: $pickedStyles,
                        maxSelectionCount: CharacterDesign.maxStyles - builder.styles.count, matching: .images)
                }
            }
        } footer: {
            Text("Both optional: a photo of the face to keep, up to 3 images of the look to follow.")
        }
    }

    @ViewBuilder private var traitsSection: some View {
        if let failure = builder.traitsFailure {
            Section("Traits") { Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.muted) }
        } else if !builder.traitGroups.isEmpty {
            Section("Traits") {
                ForEach(builder.traitGroups) { group in
                    DisclosureGroup {
                        FlowChips(group: group, builder: builder)
                    } label: {
                        LabeledContent(group.title, value: choice(in: group))
                    }
                }
            }
        }
    }

    @ViewBuilder private var runsSection: some View {
        if !builder.runs.isEmpty {
            Section {
                ForEach(builder.runs.reversed()) { run in
                    LabeledContent(String(localized: "\(run.count) character sheets")) { status(of: run) }
                }
            } header: {
                Text("Requests")
            } footer: {
                Text("Each sheet takes a few minutes. You can close this: the sheets keep going and land in Library.")
            }
        }
    }

    @ViewBuilder private func status(of run: CharacterRun) -> some View {
        switch run.state {
        case .sending: Text("Sending…").foregroundStyle(Theme.muted)
        case .running: ProgressView()
        case .finished:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent).accessibilityLabel("Done")
        case .failed(let message), .interrupted(let message):
            Text(message).font(.caption).foregroundStyle(Theme.danger).lineLimit(2)
        }
    }

    private var generateBar: some View {
        VStack(spacing: 6) {
            if environment.characterMaker == nil {
                Text("Connect your Higgsfield account to create characters.").font(.footnote)
            } else if let blocker = builder.blocker {
                Text(blocker).font(.footnote)
            } else if let failure = builder.quoteFailure {
                Text(failure).font(.footnote).lineLimit(2)
            }
            Button {
                generate()
            } label: {
                HStack {
                    if isBusy { ProgressView() }
                    Text("Generate")
                    if let quote = builder.currentQuote {
                        Text(quote.price).font(.system(.subheadline, design: .monospaced))
                    } else if builder.isQuoting && environment.characterMaker != nil {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.prominent)
            .controlSize(.large)
            .disabled(isBusy || builder.currentQuote == nil || environment.characterMaker == nil)
        }
        .foregroundStyle(Theme.muted)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func choice(in group: CharacterTraitGroup) -> String {
        let picked = (builder.traits[group.id] ?? []).compactMap { id in group.traits.first { $0.id == id }?.title }
        if !picked.isEmpty { return picked.joined(separator: ", ") }
        return builder.randomize ? String(localized: "Random") : String(localized: "Any")
    }

    /// A short stop after each change, so typing doesn't ask for a price on every key.
    private func refreshQuote() async {
        guard let maker = environment.characterMaker, builder.blocker == nil else { return }
        do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
        await builder.refreshQuote(maker: maker, upload: environment.characterUploader(maker))
    }

    private func generate(overCapApproved: Bool = false) {
        guard !isBusy, let maker = environment.characterMaker else { return }
        isStarting = true
        Task {
            defer { isStarting = false }
            let started = await builder.generate(maker: maker, overCapApproved: overCapApproved)
            if case .needsConfirmation(let question) = started { confirmation = question }
        }
    }
}

private struct PresetTile: View {
    let preset: CharacterPreset
    let isPicked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                RemoteThumb(url: preset.previewURL, width: 80, height: 80, cornerRadius: 12)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isPicked ? Theme.accent : Theme.stroke, lineWidth: isPicked ? 2 : 1)
                    }
                Text(preset.name).font(.caption2.weight(.semibold)).lineLimit(1).frame(width: 80, alignment: .leading)
                    .foregroundStyle(isPicked ? Theme.accent : Theme.muted)
            }
        }
        .buttonStyle(.plain)
        .disabled(preset.settings == nil)
        .accessibilityLabel(preset.name)
        .accessibilityAddTraits(isPicked ? [.isButton, .isSelected] : .isButton)
    }
}

private struct FlowChips: View {
    let group: CharacterTraitGroup
    let builder: CharacterBuilder

    var body: some View {
        FlowRow(spacing: 6) {
            ForEach(group.traits) { trait in
                let isPicked = builder.isPicked(trait, in: group)
                Button {
                    builder.toggle(trait, in: group)
                } label: {
                    Text(trait.title)
                        .font(.caption.weight(isPicked ? .bold : .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 28)
                        .foregroundStyle(isPicked ? Theme.ink : Theme.muted)
                        .background(isPicked ? Theme.accent : Theme.card, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isPicked ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct Thumb: View {
    let url: URL
    let remove: () -> Void

    var body: some View {
        RemoteThumb(url: url, width: 40, height: 40, cornerRadius: 8)
            .overlay(alignment: .topTrailing) {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.white)
                }
                .offset(x: 6, y: -6)
                .accessibilityLabel("Remove")
            }
    }
}
