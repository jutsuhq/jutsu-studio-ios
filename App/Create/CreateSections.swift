import JutsuCore
import PhotosUI
import Presentation
import SwiftUI

/// The video the take follows: one card, with the Motion Library inside it as the other way to fill it.
struct SourceSection: View {
    @Binding var form: CreateForm
    @Binding var pickedVideo: PhotosPickerItem?
    @Binding var showsTrim: Bool
    @Binding var motionLibrary: MotionLibraryModel?
    let isLoadingSource: Bool
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: form.isWithoutSource ? "Source video · optional" : "Source video")
            Card {
                if let source = form.source {
                    picked(source)
                } else {
                    empty
                }
            }
        }
    }

    /// The clip on one line: its name and the part used, with Trim and Replace as icons beside it.
    private func picked(_ source: SourceVideo) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(source.fileURL.lastPathComponent).font(.headline).lineLimit(1)
                // The part used and its length; Trim changes it.
                Text(form.sourceSummary).font(.eyebrow).foregroundStyle(Theme.muted).lineLimit(2)
            }
            Spacer(minLength: 0)
            Button {
                showsTrim = true
            } label: {
                IconCircle(systemName: "scissors", isAccent: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Trim")
            .accessibilityValue(form.rangeText)
            PhotosPicker(selection: $pickedVideo, matching: .videos) {
                IconCircle(systemName: "arrow.triangle.2.circlepath", isAccent: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Replace")
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 12) {
            PhotosPicker(selection: $pickedVideo, matching: .videos) {
                SourceRow(
                    symbol: "photo.on.rectangle", title: "Video from Photos",
                    detail: "Pick a clip, then the part you need", isAccent: true,
                    showsProgress: isLoadingSource)
            }
            .buttonStyle(.plain)
            if let library = environment.motionLibrary {
                Divider()
                Button {
                    motionLibrary = library
                } label: {
                    SourceRow(
                        symbol: "figure.walk.motion", title: "Motion Library",
                        detail: "Ready-made moves from Higgsfield", isAccent: false, showsProgress: false)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// One way to fill the source: a symbol tile, a title and a line of detail, with a spinner while a clip loads.
private struct SourceRow: View {
    let symbol: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let isAccent: Bool
    let showsProgress: Bool

    var body: some View {
        HStack(spacing: 14) {
            SymbolTile(systemName: symbol, isAccent: isAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            if isAccent && showsProgress { ProgressView() }
        }
        .contentShape(.rect)
    }
}

/// The character and other images the take uses, in the order the prompt names them: Photos, or the account's own
/// elements and uploads.
struct ReferencesSection: View {
    @Binding var form: CreateForm
    @Binding var pickedImages: [PhotosPickerItem]
    @Environment(AppEnvironment.self) private var environment
    @State private var showsHiggsfield = false
    @State private var showsHelp = false
    @ScaledMetric(relativeTo: .caption) private var tileWidth: CGFloat = 74
    @ScaledMetric(relativeTo: .caption) private var tileHeight: CGFloat = 98

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Eyebrow(text: "Character & references")
                helpButton
                Spacer()
                Text(form.referenceCountText).font(.eyebrow).foregroundStyle(Theme.faint)
            }
            if let reason = form.referencesDisabledReason {
                Text(reason).font(.footnote).foregroundStyle(Theme.faint)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    let size = CGSize(width: tileWidth, height: tileHeight)
                    ForEach(Array(form.references.enumerated()), id: \.offset) { index, image in
                        ReferenceThumbnail(
                            url: image.fileURL, label: "@Image\(index + 1)",
                            size: size
                        ) {
                            form.removeReference(at: index)
                        }
                    }
                    if form.canAddReferences {
                        PhotosPicker(
                            selection: $pickedImages, maxSelectionCount: max(form.referenceRoom, 1), matching: .images
                        ) {
                            AddTile(symbol: "plus", title: "Photos", size: size)
                        }
                        .accessibilityLabel("Add from Photos")
                        if offersHiggsfield {
                            Button {
                                showsHiggsfield = true
                            } label: {
                                AddTile(
                                    symbol: "person.crop.square.on.square.angled", title: "Higgsfield",
                                    size: size)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add from your Higgsfield")
                            .accessibilityHint("Your elements, characters and uploads")
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $showsHiggsfield) {
            HiggsfieldReferencesSheet(room: form.referenceRoom) { _ = form.addReferences($0) }
        }
    }

    /// The account keeps elements or uploads to pick from.
    private var offersHiggsfield: Bool {
        environment.accountElements != nil || environment.accountUploads != nil
    }

    /// How the prompt names the references, on demand instead of a tip card in the way.
    private var helpButton: some View {
        Button {
            showsHelp = true
        } label: {
            Image(systemName: "questionmark.circle").font(.footnote).foregroundStyle(Theme.faint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("How to name references")
        .popover(isPresented: $showsHelp) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Name a reference in the prompt").font(.headline)
                Text("Write @Image1 for the first reference, @Image2 for the second, and so on.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(idealWidth: 280)
            .padding()
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// The closed output settings: one row with what is set, opening the sheet that changes it. The cost line stays
/// under it, in view.
struct CreateSettingsRow: View {
    @Binding var form: CreateForm
    let context: CreateContext
    @State private var showsSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showsSettings = true
            } label: {
                HStack(spacing: 14) {
                    SymbolTile(systemName: "slider.horizontal.3", isAccent: false)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Settings").font(.headline)
                        let summary = form.outputSummary(in: context)
                        if !summary.isEmpty {
                            Text(summary).font(.subheadline).foregroundStyle(Theme.muted)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(Theme.faint).accessibilityHidden(true)
                }
                .padding(14)
                .background(Theme.card, in: .rect(cornerRadius: 22))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if let line = form.costLine(in: context) {
                Text(line.text).font(.footnote).foregroundStyle(line.isWarning ? Theme.warning : Theme.faint)
            }
        }
        .sheet(isPresented: $showsSettings) {
            CreateSettingsSheet(form: $form, context: context)
                .presentationDetents([.medium, .large])
        }
    }
}

/// What the take is made with beyond the dock's model, length and resolution: variants, the frame without a source,
/// the model's own parameters and the source's sound.
private struct CreateSettingsSheet: View {
    @Binding var form: CreateForm
    let context: CreateContext

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if form.showsVariants(in: context) {
                        Stepper(value: $form.variants, in: CreateForm.variantChoices) {
                            LabeledContent("Variants", value: "\(form.variants(in: context))")
                        }
                    } else {
                        LabeledContent("Variants", value: "1")
                    }
                } footer: {
                    if let reason = form.variantsUnavailableReason(in: context) {
                        Text(reason)
                    } else {
                        Text("Each variant is a separate take of the same inputs, billed on its own.")
                    }
                }
                let ratios = form.selectedModel.descriptor.aspectRatios
                if form.isWithoutSource, !ratios.isEmpty {
                    Picker("Frame", selection: $form.aspectRatio) {
                        ForEach([AspectRatio.auto] + ratios.filter { $0 != .auto }, id: \.self) {
                            Text($0.title).tag($0)
                        }
                    }
                }
                modelSection
                if !form.generatesAudio {
                    Picker("Source audio", selection: $form.audio) {
                        ForEach(form.audioChoices, id: \.self) { Text($0.title).tag($0) }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { DoneButton() }
            }
        }
    }

    @ViewBuilder private var modelSection: some View {
        if form.showsBitrate || form.showsCharacterOrientation || form.showsVideoBackground {
            Section(form.selectedModel.title) {
                if form.showsBitrate {
                    ParameterRow(reason: context.unavailableHint(for: .seedanceBitrate)) {
                        Picker("Quality", selection: bitrate) {
                            ForEach(SeedanceBitrate.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    }
                }
                if form.showsCharacterOrientation {
                    ParameterRow(reason: context.unavailableHint(for: .klingOrientation)) {
                        Picker("Character faces", selection: $form.characterOrientation) {
                            ForEach(CharacterOrientation.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    }
                }
                if form.showsVideoBackground {
                    ParameterRow(reason: context.unavailableHint(for: .klingVideoBackground)) {
                        Toggle("Keep the video's background", isOn: $form.keepsVideoBackground)
                    }
                }
            }
        }
    }

    /// The bitrate picked, or the connection's own default until then (`CreateForm.bitrate(on:)`).
    private var bitrate: Binding<SeedanceBitrate> {
        Binding(get: { form.bitrate(on: context.connection.kind) }, set: { form.setBitrate($0) })
    }
}

private struct DoneButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        RoleButton(.confirm) { dismiss() }
    }
}

/// A model parameter's control, disabled with the reason when the connection can't send it.
private struct ParameterRow<Content: View>: View {
    let reason: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content.disabled(reason != nil)
            if let reason {
                Text(reason).font(.footnote).foregroundStyle(Theme.faint)
            }
        }
    }
}

/// A dashed tile that adds references.
private struct AddTile: View {
    let symbol: String
    let title: LocalizedStringResource
    let size: CGSize

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).accessibilityHidden(true)
            Text(title).font(.caption).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 4)
        .foregroundStyle(Theme.muted)
        .frame(width: size.width, height: size.height)
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                .foregroundStyle(Theme.stroke)
        }
        .contentShape(.rect)
    }
}

private struct ReferenceThumbnail: View {
    let url: URL
    let label: String
    let size: CGSize
    let remove: () -> Void

    var body: some View {
        RemoteThumb(url: url, width: size.width, height: size.height, cornerRadius: 14)
            .overlay(alignment: .topLeading) {
                Text(label).font(.eyebrow).lineLimit(1).minimumScaleFactor(0.7)
                    .padding(4).background(.black.opacity(0.55), in: .rect(cornerRadius: 6))
                    .padding(4)
            }
            .overlay(alignment: .bottomTrailing) {
                Button(action: remove) {
                    Image(systemName: "xmark").font(.caption2.weight(.bold)).padding(6)
                }
                .glass(.clear, in: .circle)
                .padding(4)
            }
            // One element per reference; its small Remove button is an action instead of a second stop.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isImage)
            .accessibilityAction(named: "Remove", remove)
    }
}

/// A round icon button for an action on a card: lime for the main one.
private struct IconCircle: View {
    let systemName: String
    let isAccent: Bool
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 40

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isAccent ? Theme.accent : .white)
            .frame(width: side, height: side)
            .background(isAccent ? Theme.accent.opacity(0.14) : Color.white.opacity(0.08), in: .circle)
            .contentShape(.circle)
    }
}
