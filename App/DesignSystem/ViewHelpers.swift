import JutsuCore
import Presentation
import SwiftUI

/// A remote or local picture, filled and clipped to a rounded rectangle; the card color until it loads. Decoded at
/// the size it is shown, not the file's (`Thumbnails`).
struct RemoteThumb: View {
    let url: URL?
    var width: CGFloat?
    var height: CGFloat?
    var cornerRadius: CGFloat = 0
    @Environment(\.displayScale) private var displayScale
    @Environment(\.isOnline) private var isOnline
    @State private var side: CGFloat = 0
    @State private var image: UIImage?

    var body: some View {
        Theme.card
            .overlay {
                if let shown = image ?? url.flatMap({ Thumbnails.cached($0) }) {
                    Image(uiImage: shown).resizable().scaledToFill()
                }
            }
            .frame(width: width, height: height)
            .clipShape(.rect(cornerRadius: cornerRadius))
            .onGeometryChange(for: CGFloat.self) {
                max($0.size.width, $0.size.height)
            } action: {
                side = $0
            }
            // A link that failed offline is read again once the network is back.
            .task(id: ThumbRequest(url: url, pixels: pixels, isOnline: isOnline)) {
                guard let url, pixels > 0 else { return }
                if let loaded = await Thumbnails.image(at: url, pixels: pixels), !Task.isCancelled { image = loaded }
            }
            .onChange(of: url) { image = nil }
    }

    /// Rounded up to a step, so small changes of the layout don't decode the picture again.
    private var pixels: Int {
        let step: CGFloat = 128
        return Int((side * displayScale / step).rounded(.up) * step)
    }
}

private struct ThumbRequest: Equatable {
    let url: URL?
    let pixels: Int
    let isOnline: Bool
}

extension Binding where Value == Bool {
    /// True while `optional` holds a value; setting false clears it. For alerts and dialogs presented by an item.
    init<Wrapped>(isPresent optional: Binding<Wrapped?>) {
        self.init(get: { optional.wrappedValue != nil }, set: { if !$0 { optional.wrappedValue = nil } })
    }
}

extension View {
    /// Drags the file out to another app (Files, Mail, an editor in Split View); nothing without one.
    @ViewBuilder
    func draggableFile(_ url: URL?) -> some View {
        if let url { draggable(url) } else { self }
    }

    /// A Done button over the keyboard, for multi-line fields whose Return key starts a new line.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }

    /// Caps a column of text and controls at a readable width, centered, for iPad and landscape.
    func readableWidth(_ maxWidth: CGFloat = 640) -> some View {
        frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
    }

    /// The sheet's close button, leading, as iOS 26 places it.
    func closeButton() -> some View {
        modifier(CloseButton())
    }

    /// Shows `message` as an alert: OK, and the message's next step when it has one.
    func alert(_ message: Binding<UserMessage?>) -> some View {
        modifier(MessageAlert(message: message))
    }

    /// Asks before going past today's spend cap; `approve` runs the request again with the cap approved.
    func capConfirmation(_ confirmation: Binding<CapConfirmation?>, approve: @escaping () -> Void) -> some View {
        confirmationDialog(
            confirmation.wrappedValue?.title ?? "", isPresented: Binding(isPresent: confirmation),
            titleVisibility: .visible, presenting: confirmation.wrappedValue
        ) { question in
            Button(question.confirmTitle, action: approve)
        } message: { question in
            Text(question.message)
        }
    }
}

extension EnvironmentValues {
    /// Opens the Account sheet, where the connection is signed in or its key changed; set by each window's tabs.
    nonisolated var showAccount: @MainActor @Sendable () -> Void {
        get { self[ShowAccountKey.self] }
        set { self[ShowAccountKey.self] = newValue }
    }
}

nonisolated private struct ShowAccountKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable () -> Void = {}
}

private struct MessageAlert: ViewModifier {
    @Binding var message: UserMessage?
    @Environment(\.showAccount) private var showAccount
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content.alert(message?.title ?? "", isPresented: Binding(isPresent: $message), presenting: message) { shown in
            switch shown.action {
            case .openSettings?: Button("Open Settings") { showAccount() }
            case .openConsole?: Button("Open Console") { openURL(Higgsfield.consoleURL) }
            case nil: EmptyView()
            }
            Button("OK", role: .cancel) {}
        } message: { shown in
            Text(shown.message)
        }
    }
}

private struct CloseButton: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .cancellationAction) { RoleButton(.close) { dismiss() } }
        }
    }
}

/// The content at the full height it is given while it fits (its spacers stretch), scrolling when it doesn't: a small
/// iPhone, landscape, accessibility text sizes.
struct FitOrScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
                .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// Segmented while every choice fits on one line; a labeled menu once a long translation or a large text size would
/// truncate the segments.
struct AdaptivePicker<Selection: Hashable, Content: View>: View {
    let title: LocalizedStringKey
    @Binding var selection: Selection
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Picker(title, selection: $selection) { content }
                .pickerStyle(.segmented)
            LabeledContent(title) {
                Picker(title, selection: $selection) { content }
                    .pickerStyle(.menu)
            }
        }
    }
}
