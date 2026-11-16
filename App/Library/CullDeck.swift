import JutsuCore
import Presentation
import SwiftUI

/// New takes as a deck: swipe right to keep, left to reject, double-tap to star; → ← S and ⌘Z with a keyboard.
struct CullDeck: View {
    let takes: [Job]
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var drag: CGSize = .zero
    @State private var kept = 0
    @AccessibilityFocusState private var focusedCard: UUID?
    @ScaledMetric(relativeTo: .title2) private var mainButton: CGFloat = 44
    @ScaledMetric(relativeTo: .title3) private var starButton: CGFloat = 34

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if index < takes.count {
                    ForEach(Array(takes.enumerated().reversed()), id: \.element.id) { offset, job in
                        if offset >= index, offset < index + 3 {
                            card(job, depth: offset - index)
                        }
                    }
                } else {
                    finished
                }
            }
            .safeAreaInset(edge: .bottom) {
                if index < takes.count { controls }
            }
            .navigationTitle(index < takes.count ? "\(index + 1) / \(takes.count)" : String(localized: "Done"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    RoleButton(.close) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Undo", systemImage: "arrow.uturn.backward") { undo() }
                        .keyboardShortcut("z")
                        .disabled(index == 0)
                }
            }
        }
    }

    private func card(_ job: Job, depth: Int) -> some View {
        let item = LibraryItemModel(job: job, isStarred: environment.marks.starred.contains(job.id))
        return ZStack(alignment: .bottomLeading) {
            if let url = item.outputFile {
                LoopingPlayer(url: url)
            } else {
                Theme.card
            }
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.title2.weight(.semibold))
                Text(item.facts.joined(separator: " · ")).font(.eyebrow).textCase(.uppercase).opacity(0.75)
            }
            .padding(20)
            if depth == 0 { stamps }
        }
        .clipShape(.rect(cornerRadius: 32))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .cappedAspect(3 / 4)
        .scaleEffect(1 - CGFloat(depth) * 0.04)
        .offset(y: CGFloat(-depth) * 10)
        .offset(depth == 0 ? drag : .zero)
        .rotationEffect(.degrees(depth == 0 ? Double(drag.width / 25) : 0))
        .gesture(swipe(job), isEnabled: depth == 0)
        .onTapGesture(count: 2) { if depth == 0 { decide(.star, job) } }
        // One element for the top card, its swipes and double-tap as actions; the cards under it stay out.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel(now: .now))
        .accessibilityAction(named: "Keep") { decide(.keep, job) }
        .accessibilityAction(named: "Reject") { decide(.reject, job) }
        .accessibilityAction(named: item.isStarred ? "Unstar" : "Star") { decide(.star, job) }
        .accessibilityFocused($focusedCard, equals: job.id)
        .accessibilityHidden(depth > 0)
    }

    @ViewBuilder private var stamps: some View {
        Text("KEEP")
            .font(.display(38))
            .foregroundStyle(Theme.accent)
            .padding(8)
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(Theme.accent, lineWidth: 4) }
            .rotationEffect(.degrees(-12))
            .opacity(Double(max(drag.width, 0) / 100))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(28)
        Text("REJECT")
            .font(.display(38))
            .foregroundStyle(Theme.danger)
            .padding(8)
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(Theme.danger, lineWidth: 4) }
            .rotationEffect(.degrees(12))
            .opacity(Double(max(-drag.width, 0) / 100))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(28)
    }

    private func swipe(_ job: Job) -> some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                if value.translation.width > 100 {
                    decide(.keep, job)
                } else if value.translation.width < -100 {
                    decide(.reject, job)
                } else {
                    withAnimation(reduceMotion ? nil : .spring) { drag = .zero }
                }
            }
    }

    private var controls: some View {
        GlassGroup(spacing: 18) {
            HStack(spacing: 18) {
                Button {
                    if let job = current { decide(.reject, job) }
                } label: {
                    Image(systemName: "xmark").font(.title2.weight(.bold)).frame(width: mainButton, height: mainButton)
                }
                .buttonStyle(.liquidGlass)
                .tint(Theme.danger)
                .keyboardShortcut(.leftArrow, modifiers: [])
                .accessibilityLabel("Reject")
                Button {
                    if let job = current { decide(.star, job) }
                } label: {
                    Image(systemName: "star").font(.title3).frame(width: starButton, height: starButton)
                }
                .buttonStyle(.liquidGlass)
                .tint(Theme.warning)
                .keyboardShortcut("s", modifiers: [])
                .accessibilityLabel("Star")
                Button {
                    if let job = current { decide(.keep, job) }
                } label: {
                    Image(systemName: "checkmark").font(.title2.weight(.bold))
                        .frame(width: mainButton, height: mainButton)
                }
                .buttonStyle(.prominent)
                .keyboardShortcut(.rightArrow, modifiers: [])
                .accessibilityLabel("Keep")
            }
        }
        .padding(.bottom, 8)
    }

    private var finished: some View {
        VStack(spacing: 12) {
            Text("All reviewed").font(.display(40)).textCase(.uppercase)
            Text("Kept \(kept), rejected \(takes.count - kept). Rejected takes are hidden, never deleted.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
            Button("Done") { dismiss() }
                .buttonStyle(.prominent)
                .controlSize(.large)
        }
        .padding(32)
    }

    private var current: Job? { index < takes.count ? takes[index] : nil }

    private enum Decision { case keep, reject, star }

    private func decide(_ decision: Decision, _ job: Job) {
        let marks = environment.marks
        switch decision {
        case .star:
            VoiceOver.announce(
                marks.starred.contains(job.id) ? String(localized: "Unstarred") : String(localized: "Starred"))
            Task { await marks.toggleStar(job.id) }
            return
        case .keep:
            kept += 1
            VoiceOver.announce(String(localized: "Kept"))
            Task { await marks.set(.kept, for: job.id) }
        case .reject:
            VoiceOver.announce(String(localized: "Rejected"))
            Task { await marks.set(.rejected, for: job.id) }
        }
        let exit = CGSize(width: decision == .keep ? 600 : -600, height: 0)
        if reduceMotion {
            advance()
        } else {
            withAnimation(.easeIn(duration: 0.25)) {
                drag = exit
            } completion: {
                advance()
            }
        }
    }

    private func advance() {
        drag = .zero
        index += 1
        focusedCard = current?.id
    }

    private func undo() {
        guard index > 0 else { return }
        index -= 1
        let job = takes[index]
        if environment.marks.verdict(of: job.id) == .kept { kept = max(kept - 1, 0) }
        focusedCard = job.id
        Task { await environment.marks.undo() }
    }
}

/// Two takes side by side, playing in sync; tap the better one to keep it and reject the other.
struct CompareView: View {
    let first: Job
    let second: Job
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var winner: UUID?

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                HStack(spacing: 4) {
                    side(first, label: "Take A")
                    side(second, label: "Take B")
                }
                Text("Tap the better take.").font(.footnote).foregroundStyle(Theme.faint)
                Button {
                    guard let winner else { return }
                    let loser = winner == first.id ? second.id : first.id
                    Task {
                        await environment.marks.set(.kept, for: winner)
                        await environment.marks.set(.rejected, for: loser)
                        dismiss()
                    }
                } label: {
                    Text(winner == nil ? "Pick a Take" : "Keep It, Reject the Other").frame(maxWidth: .infinity)
                }
                .buttonStyle(.prominent)
                .controlSize(.large)
                .disabled(winner == nil)
            }
            .padding(16)
            .background(Theme.background)
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .closeButton()
        }
    }

    private func side(_ job: Job, label: LocalizedStringKey) -> some View {
        Button {
            winner = job.id
        } label: {
            ZStack(alignment: .topLeading) {
                if let url = job.outputFile {
                    LoopingPlayer(url: url)
                } else {
                    Theme.card
                }
                Text(label).font(.eyebrow).textCase(.uppercase).padding(6)
                    .background(.black.opacity(0.55), in: .rect(cornerRadius: 6)).padding(8)
            }
            .aspectRatio(9 / 16, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18).strokeBorder(winner == job.id ? Theme.accent : .clear, lineWidth: 3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(LibraryItemModel(job: job).accessibilityLabel(now: .now))
        .accessibilityAddTraits(winner == job.id ? .isSelected : [])
    }
}
