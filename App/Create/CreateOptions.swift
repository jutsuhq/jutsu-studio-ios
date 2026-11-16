import JutsuCore
import MediaKit
import PhotosUI
import Presentation
import SwiftUI

/// The inputs only some modes and models take, under the source: the restyle preset, and start and end frames. The
/// length, resolution and quality are on the prompt dock; the rest of the output in Settings (`CreateSettingsRow`).
struct CreateOptions: View {
    @Binding var form: CreateForm
    let presets: PresetCatalog
    @State private var showsPresets = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if form.mode == .restyle {
                presetRow
            }
            if form.showsFrames {
                FramesRow(form: $form)
            }
        }
        .sheet(isPresented: $showsPresets) {
            PresetPicker(selection: $form.presetID, catalog: presets)
        }
    }

    private var presetRow: some View {
        Button {
            showsPresets = true
        } label: {
            HStack(spacing: 12) {
                if let preset = presets.preset(id: form.presetID) {
                    RemoteThumb(url: preset.previewURL, width: 44, height: 44, cornerRadius: 10)
                    Text(preset.name).font(.headline)
                } else {
                    SymbolTile(systemName: "wand.and.stars", isAccent: true)
                    Text("Choose a style").font(.headline)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.faint).accessibilityHidden(true)
            }
            .padding(14)
            .background(Theme.card, in: .rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }
}

/// The restyle gallery: search, a grid of previews, a checkmark on the chosen one.
struct PresetPicker: View {
    @Binding var selection: UUID?
    @Bindable var catalog: PresetCatalog
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                    ForEach(catalog.filtered) { preset in
                        Button {
                            selection = preset.id
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                RemoteThumb(url: preset.previewURL)
                                    .frame(height: 140)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(.rect(cornerRadius: 14))
                                    .overlay(alignment: .topTrailing) {
                                        if selection == preset.id {
                                            RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.accent, lineWidth: 3)
                                            Image(systemName: "checkmark.circle.fill")
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(Theme.ink, Theme.accent)
                                                .padding(6)
                                        }
                                    }
                                Text(preset.name)
                                    .font(.caption.weight(.bold))
                                    .textCase(.uppercase)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection == preset.id ? .isSelected : [])
                    }
                }
                .padding(16)
            }
            .overlay {
                if catalog.presets.isEmpty {
                    if catalog.isRefreshing {
                        ProgressView()
                    } else {
                        ContentUnavailableView(
                            "No styles yet", systemImage: "wand.and.stars",
                            description: Text("Connect Higgsfield to load the style gallery."))
                    }
                }
            }
            .searchable(text: $catalog.query, prompt: "Styles")
            .navigationTitle("Style")
            .navigationBarTitleDisplayMode(.inline)
            .closeButton()
        }
    }
}

/// Start and optional end frame for models that make a clip between two images.
private struct FramesRow: View {
    @Binding var form: CreateForm
    @State private var picks: [FrameSlot: PhotosPickerItem] = [:]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(FrameSlot.allCases, id: \.self) { slot in
                let image = form.frame(slot)
                PhotosPicker(selection: binding(for: slot), matching: .images) {
                    FrameSlotLabel(image: image, slot: slot)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func binding(for slot: FrameSlot) -> Binding<PhotosPickerItem?> {
        Binding(
            get: { picks[slot] },
            set: { item in
                picks[slot] = item
                guard let item else { return }
                Task {
                    if let image = await item.localImage() { form.setFrame(image, for: slot) }
                }
            })
    }
}

/// One frame slot: its picked image or a plus, with the slot's name under it.
private struct FrameSlotLabel: View {
    let image: LocalImage?
    let slot: FrameSlot

    var body: some View {
        VStack(spacing: 6) {
            if let image {
                RemoteThumb(url: image.fileURL)
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: 14))
            } else {
                Image(systemName: "plus")
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .background(Theme.card, in: .rect(cornerRadius: 14))
            }
            Text(slot == .start ? "Start frame" : "End frame")
                .font(.eyebrow)
                .textCase(.uppercase)
                .foregroundStyle(Theme.faint)
        }
    }
}

/// The part of the source that is uploaded and billed: a filmstrip with two handles, several ranges for a batch.
struct TrimView: View {
    @Binding var form: CreateForm
    let context: CreateContext
    @Environment(\.dismiss) private var dismiss
    @State private var frames: [CGImage] = []

    var body: some View {
        NavigationStack {
            FitOrScroll {
                VStack(spacing: 18) {
                    Spacer()
                    Text(form.rangeText)
                        .font(.system(.title2, design: .monospaced).weight(.semibold))
                    if let rate = form.rateText(in: context) {
                        Text(rate).font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    Filmstrip(form: $form, frames: frames)
                        .frame(height: 56)
                        .padding(.horizontal, 16)
                    rangeChips
                    Text("Only the selected parts are uploaded and billed.")
                        .font(.footnote)
                        .foregroundStyle(Theme.faint)
                    Spacer()
                }
                .multilineTextAlignment(.center)
                .padding(.vertical, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .navigationTitle("Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    RoleButton(.confirm) { dismiss() }
                }
            }
            .task(id: form.source?.fileURL) {
                guard let url = form.source?.fileURL else { return }
                frames = (try? await ThumbnailStrip.images(for: url, count: 12)) ?? []
            }
        }
    }

    private var rangeChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(form.ranges.indices, id: \.self) { index in
                    Button {
                        form.selectRange(at: index)
                    } label: {
                        Text(form.rangeText(at: index)).font(.system(.caption, design: .monospaced))
                            .fontWeight(index == form.selectedRangeIndex ? .bold : .regular)
                    }
                    .buttonStyle(.liquidGlass)
                    .tint(index == form.selectedRangeIndex ? Theme.accent : nil)
                    .accessibilityAddTraits(index == form.selectedRangeIndex ? .isSelected : [])
                    .contextMenu {
                        if form.ranges.count > 1 {
                            Button("Remove", systemImage: "trash", role: .destructive) { form.removeRange(at: index) }
                        }
                    }
                }
                if form.canAddRange {
                    Button("Add Range", systemImage: "plus") { form.addRange() }
                        .buttonStyle(.liquidGlass)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
    }
}

private struct Filmstrip: View {
    @Binding var form: CreateForm
    let frames: [CGImage]

    var body: some View {
        GeometryReader { proxy in
            let duration = max(form.source?.duration ?? 1, 0.1)
            let width = proxy.size.width
            let start = form.range.lowerBound / duration * width
            let end = form.range.upperBound / duration * width
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(frames.indices, id: \.self) { index in
                        Image(decorative: frames[index], scale: 1)
                            .resizable()
                            .scaledToFill()
                            .frame(width: width / CGFloat(max(frames.count, 1)), height: proxy.size.height)
                            .clipped()
                    }
                }
                .frame(width: width, alignment: .leading)
                .background(Theme.card)
                Color.black.opacity(0.6).frame(width: max(start, 0))
                Color.black.opacity(0.6).frame(width: max(width - end, 0)).offset(x: end)
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.accent, lineWidth: 3)
                    .frame(width: max(end - start, 6))
                    .offset(x: start)
                    .trimAccessibility(.selection, form: $form)
                handle(at: start, width: width, duration: duration) { form.setStart($0) }
                    .trimAccessibility(.start, form: $form)
                handle(at: end, width: width, duration: duration) { form.setEnd($0) }
                    .trimAccessibility(.end, form: $form)
            }
            .clipShape(.rect(cornerRadius: 10))
        }
    }

    private func handle(
        at x: CGFloat, width: CGFloat, duration: TimeInterval, set: @escaping (TimeInterval) -> Void
    ) -> some View {
        Capsule()
            .fill(Theme.accent)
            .frame(width: 12)
            .offset(x: x - 6)
            .gesture(
                DragGesture().onChanged { value in
                    let time = min(max(value.location.x / width, 0), 1) * duration
                    set(time)
                    UISelectionFeedbackGenerator().selectionChanged()
                })
    }
}

extension View {
    /// A trim handle, or the whole selection, as one adjustable element: VoiceOver's swipe up and down move it by a
    /// second.
    fileprivate func trimAccessibility(_ part: TrimPart, form: Binding<CreateForm>) -> some View {
        accessibilityElement()
            .accessibilityLabel(part.accessibilityLabel)
            .accessibilityValue(form.wrappedValue.accessibilityValue(of: part))
            .accessibilityAdjustableAction { direction in
                let seconds = direction == .increment ? 1 : -1
                form.wrappedValue.nudge(part, by: seconds * Int(CreateForm.trimStepsPerSecond))
            }
    }
}
