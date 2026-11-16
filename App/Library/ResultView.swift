import JutsuCore
import Presentation
import SwiftUI
import os

nonisolated private let logger = Logger.jutsu("Result")

/// A take full screen: drag the divider to compare it with its source, keep, reject or star it, render the final,
/// save or share. Controls over the video are clear glass with a dimming layer (HIG, Materials).
struct ResultView: View {
    let job: Job
    /// Its page is the one showing; only then does it play, so the pages either side stay quiet.
    var isActive = true
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.viewer) private var viewer
    @State private var divider = CompareDivider()
    @State private var message: UserMessage?
    @State private var isWorking = false
    @State private var overCap: CapConfirmation?
    /// The final a confirmation is for; kept when the dialog clears `overCap` before its button runs.
    @State private var askedFinal: Resolution?
    @State private var showsEnhance = false
    @State private var showsInfo = false

    private var item: LibraryItemModel {
        LibraryItemModel(job: job, isStarred: environment.marks.starred.contains(job.id))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // A portrait take stays portrait in a wide window instead of being cropped to a strip.
            if isActive {
                beforeAfter.cappedAspect(3 / 4).ignoresSafeArea()
            } else {
                FittedPicture(url: item.outputFile).ignoresSafeArea()
            }
            LinearGradient(colors: [.clear, .black.opacity(0.62)], startPoint: .center, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) { bottomBar }
        .sheet(isPresented: $showsEnhance) { EnhanceSheet(job: job) }
        .sheet(isPresented: $showsInfo) { LibraryInfoSheet(row: .video(item)) }
        .alert($message)
        .capConfirmation($overCap) {
            guard let resolution = askedFinal else { return }
            askedFinal = nil
            renderFinal(at: resolution, overCapApproved: true)
        }
    }

    @ViewBuilder private var beforeAfter: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                if let source = item.playback(.source) {
                    LoopingPlayer(url: source.url, range: source.range)
                }
                if let output = item.outputFile {
                    LoopingPlayer(url: output, isMuted: false)
                        .mask(alignment: .trailing) {
                            Rectangle().frame(
                                width: proxy.size.width * (item.playback(.source) == nil ? 1 : 1 - divider.position))
                        }
                }
                if item.playback(.source) != nil {
                    Rectangle().fill(.white).frame(width: 2).offset(x: proxy.size.width * divider.position - 1)
                }
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    divider.drag(to: value.location.x, width: proxy.size.width)
                }
            )
            .adjustableDivider($divider, label: "Source and take, side by side")
            .accessibilityHidden(item.playback(.source) == nil)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                viewer.close()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.liquidGlass)
            .accessibilityLabel("Close")
            .keyboardShortcut(.cancelAction)
            Spacer()
            VStack(spacing: 2) {
                Text(item.title).font(.headline).lineLimit(1)
                Text(item.modeTag).font(.eyebrow).textCase(.uppercase).foregroundStyle(Theme.muted)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer()
            HStack(spacing: 8) {
                if let url = item.outputFile {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Share")
                        .buttonStyle(.liquidGlass)
                }
                Button {
                    showsInfo = true
                } label: {
                    Image(systemName: "info")
                }
                .buttonStyle(.liquidGlass)
                .accessibilityLabel("Details")
            }
        }
        .padding(.horizontal)
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.facts.joined(separator: " · "))
                .font(.eyebrow)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.75))
            if !job.spec.prompt.isEmpty {
                Button {
                    showsInfo = true
                } label: {
                    Text(job.spec.prompt).font(.subheadline).lineLimit(2).multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the whole prompt and the settings")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    VerdictButtons(id: job.id)
                    Spacer()
                    tools
                }
                VStack(alignment: .leading, spacing: 12) {
                    VerdictButtons(id: job.id)
                    HStack(spacing: 12) { tools }
                }
            }
            if item.canRenderFinal, let resolution = item.finalResolutions.last {
                Button {
                    renderFinal(at: resolution)
                } label: {
                    Label(finalTitle(resolution), systemImage: "sparkles").frame(maxWidth: .infinity)
                }
                .buttonStyle(.prominent)
                .controlSize(.large)
                .disabled(isWorking)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder private var tools: some View {
        Button {
            showsEnhance = true
        } label: {
            Image(systemName: "wand.and.stars")
        }
        .buttonStyle(.liquidGlass)
        .accessibilityLabel("Enhance")
        EditingExportMenu(item: item)
        Button {
            save()
        } label: {
            Image(systemName: "square.and.arrow.down")
        }
        .buttonStyle(.liquidGlass)
        .accessibilityLabel("Save to Photos")
    }

    private func finalTitle(_ resolution: Resolution) -> String {
        let price = item.finalPrice(
            at: resolution, pricing: environment.pricing, connection: environment.provider?.kind
        )
        .map(CostText.text)
        return price.map { String(localized: "Render Final \(resolution.rawValue) · \($0)") }
            ?? String(localized: "Render Final \(resolution.rawValue)")
    }

    private func renderFinal(at resolution: Resolution, overCapApproved: Bool = false) {
        let spec = item.finalSpec(at: resolution, owner: environment.provider?.owner)
        isWorking = true
        Task {
            if !overCapApproved {
                let cost = item.finalPrice(
                    at: resolution, pricing: environment.pricing, connection: environment.provider?.kind)
                let status = try? await environment.spending.status(for: environment.connection.state.kind)
                if case .confirm(_, let confirmation) = SubmitDecision.budgeted(
                    [spec], cost: cost, committedToday: status?.committedToday ?? 0, cap: status?.cap)
                {
                    askedFinal = resolution
                    overCap = confirmation
                    isWorking = false
                    return
                }
            }
            message = await environment.enqueue(
                [spec], parentID: job.id, overCapApproved: overCapApproved)
            isWorking = false
            if message == nil { viewer.close() }
        }
    }

    private func save() {
        guard let url = item.outputFile else { return }
        Task {
            do {
                try await PhotoExport.saveVideo(at: url)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                logger.error("Can't save to Photos: \(String(describing: error), privacy: .private)")
                message =
                    error.isOutOfSpace
                    ? .notEnoughStorage
                    : UserMessage(title: String(localized: "Can't save to Photos"), message: error.localizedDescription)
            }
        }
    }
}

/// Reject, Star and Keep in one glass group; Keep is the one prominent action.
struct VerdictButtons: View {
    let id: UUID
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let marks = environment.marks
        let verdict = marks.verdict(of: id)
        GlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    Task { await marks.set(.rejected, for: id) }
                } label: {
                    Image(systemName: verdict == .rejected ? "xmark.circle.fill" : "xmark")
                }
                .buttonStyle(.liquidGlass)
                .tint(verdict == .rejected ? Theme.danger : nil)
                .accessibilityLabel("Reject")
                .accessibilityAddTraits(verdict == .rejected ? .isSelected : [])
                Button {
                    Task { await marks.toggleStar(id) }
                } label: {
                    Image(systemName: marks.starred.contains(id) ? "star.fill" : "star")
                }
                .buttonStyle(.liquidGlass)
                .tint(Theme.warning)
                .accessibilityLabel(marks.starred.contains(id) ? "Unstar" : "Star")
                Button {
                    Task { await marks.set(.kept, for: id) }
                } label: {
                    Image(systemName: verdict == .kept ? "checkmark.circle.fill" : "checkmark")
                }
                .buttonStyle(.prominent)
                .accessibilityLabel("Keep")
                .accessibilityAddTraits(verdict == .kept ? .isSelected : [])
            }
        }
    }
}
