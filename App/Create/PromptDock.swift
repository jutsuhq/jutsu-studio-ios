import JutsuCore
import Presentation
import SwiftUI

/// Higgsfield's prompt bar on iOS: the prompt with Paste beside it, chips for the model, length and resolution, a
/// Draft chip when a draft would cost less, and a lime Generate tile with the price. The chips are the only place these are set, so nothing on the form repeats them. It floats over
/// the content, so it is glass; the chips inside are fills, never glass on glass.
struct PromptDock: View {
    @Binding var form: CreateForm
    let models: [VideoModel]
    let generatePrice: String?
    let draftPrice: String?
    let isBusy: Bool
    let trim: () -> Void
    let generate: () -> Void
    let draft: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ScaledMetric(relativeTo: .caption) private var tileWidth: CGFloat = 70
    @ScaledMetric(relativeTo: .caption) private var tileHeight: CGFloat = 60

    var body: some View {
        // At accessibility sizes the Generate tile goes under the prompt, so the field keeps the full width.
        let layout =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        layout {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 6) {
                    TextField("Describe the take — @Image1 for a reference", text: $form.prompt, axis: .vertical)
                        .lineLimit(verticalSizeClass == .compact || typeSize.isAccessibilitySize ? 1...3 : 2...4)
                        .font(.subheadline)
                        .keyboardDoneButton()
                    // The system's Paste button: no "allow paste" prompt, as the person taps it themselves.
                    PasteButton(payloadType: String.self) { strings in
                        guard let text = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
                        else { return }
                        form.prompt = form.prompt.isEmpty ? text : form.prompt + " " + text
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                    .tint(Color.white.opacity(0.12))
                }
                if typeSize.isAccessibilitySize {
                    // One row that scrolls, so large text doesn't stack the chips over the form.
                    ScrollView(.horizontal) {
                        HStack(spacing: 4) { chips }
                    }
                    .scrollIndicators(.hidden)
                } else {
                    FlowRow(spacing: 4) { chips }
                }
            }
            Button(action: generate) {
                // A tile beside the prompt; a wide bar under it at accessibility sizes.
                let label =
                    typeSize.isAccessibilitySize
                    ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(spacing: 2))
                label {
                    Image(decorative: "jutsu.spark")
                    Text("Generate").font(.caption.weight(.bold)).textCase(.uppercase)
                    if let generatePrice {
                        Text(generatePrice).font(.system(.caption2, design: .monospaced).weight(.semibold))
                    }
                }
                .lineLimit(1)
                .frame(
                    minWidth: tileWidth, maxWidth: .infinity,
                    minHeight: typeSize.isAccessibilitySize ? nil : tileHeight
                )
                .padding(.vertical, typeSize.isAccessibilitySize ? 6 : 0)
            }
            .buttonStyle(.prominent)
            .buttonBorderShape(.roundedRectangle(radius: 18))
            .keyboardShortcut(.return, modifiers: .command)
            // As wide as the longest label ("СГЕНЕРИРОВАТЬ"), never narrower than the tile. Under the prompt, as wide
            // as the dock.
            .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
            .disabled(isBusy)
        }
        .padding(12)
        .glass(.regular, in: .rect(cornerRadius: 30))
        .frame(maxWidth: 720)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    @ViewBuilder private var chips: some View {
        modelChip
        lengthChip
        resolutionChip
        if let draftPrice {
            Button(action: draft) {
                Chip(symbol: "hare", name: "Draft", text: String(localized: "Draft \(draftPrice)"), isAccent: true)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [.command, .shift])
            .accessibilityHint("A cheaper take at a lower resolution or shorter, to check it first")
            .disabled(isBusy)
        }
    }

    private var modelChip: some View {
        Menu {
            Picker("Model", selection: $form.model) {
                ForEach(models, id: \.self) { Text($0.title).tag($0) }
            }
        } label: {
            Chip(symbol: "jutsu.model", name: "Model", text: form.selectedModel.title)
        }
        .hoverEffect(.highlight)
    }

    /// The trimmed range's length, which opens the trim; the clip's length without a source. Nothing before a
    /// source is picked for a model that needs one.
    @ViewBuilder private var lengthChip: some View {
        if form.isWithoutSource {
            Menu {
                Picker("Length", selection: wholeLength) {
                    ForEach(form.lengthChoices, id: \.self) { Text("\($0) s").tag($0) }
                }
            } label: {
                Chip(symbol: "jutsu.clock", name: "Length", text: "\(Int(form.clipLength.rounded()))s")
            }
        } else if form.source != nil {
            Button(action: trim) {
                Chip(symbol: "jutsu.clock", name: "Length", text: "\(Int(form.selectedDuration.rounded()))s")
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the range")
        }
    }

    private var wholeLength: Binding<Int> {
        Binding(get: { Int(form.clipLength.rounded()) }, set: { form.length = TimeInterval($0) })
    }

    /// Kling's Standard or Pro in place of a resolution; a menu when the model renders at more than one.
    @ViewBuilder private var resolutionChip: some View {
        if form.showsKlingQuality {
            Menu {
                Picker("Quality", selection: $form.klingQuality) {
                    ForEach(KlingQuality.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } label: {
                Chip(symbol: "jutsu.frame", name: "Quality", text: form.klingQuality.title)
            }
        } else if form.resolutionOptions.count > 1 {
            Menu {
                Picker("Resolution", selection: $form.pickedResolution) {
                    ForEach(form.resolutionOptions, id: \.self) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Chip(symbol: "jutsu.frame", name: "Resolution", text: form.pickedResolution.rawValue)
            }
        } else {
            Chip(symbol: "jutsu.frame", name: "Resolution", text: form.pickedResolution.rawValue)
        }
    }
}

private struct Chip: View {
    let symbol: String
    let name: LocalizedStringKey
    let text: String
    /// Lime outline, for the one chip that is an action rather than a setting.
    var isAccent = false
    @ScaledMetric(relativeTo: .caption) private var iconSize: CGFloat = 14
    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 30

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(symbol: symbol).resizable().scaledToFit().frame(width: iconSize, height: iconSize)
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 7)
        .frame(minHeight: height)
        .background(isAccent ? Theme.accent.opacity(0.12) : Color.white.opacity(0.08), in: .rect(cornerRadius: 10))
        .overlay { if isAccent { RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent.opacity(0.6)) } }
        .foregroundStyle(isAccent ? Theme.accent : .white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(text)
    }
}
