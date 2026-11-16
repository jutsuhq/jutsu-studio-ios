import Presentation
import SwiftUI

/// What the app is, what it makes and why an app, then Connect. Skippable at every page (HIG, Onboarding).
struct OnboardingFlow: View {
    let finish: () -> Void
    @State private var page = 0
    @State private var path: [Step] = Self.startPath
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Step: Hashable { case connect }

    /// `-debug.connect YES` opens on Connect, for a screenshot. Debug builds only.
    private static var startPath: [Step] {
        #if DEBUG
            UserDefaults.standard.bool(forKey: "debug.connect") ? [.connect] : []
        #else
            []
        #endif
    }

    var body: some View {
        NavigationStack(path: $path) {
            TabView(selection: $page) {
                WhatPage().tag(0)
                MakePage().tag(1)
                WhyPage().tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // The dots sit with the button in a bar, so a page that scrolls at a large text size fades out under
            // both instead of running into them.
            .edgeBar(edge: .bottom) {
                VStack(spacing: 18) {
                    PageDots(page: $page, count: 3)
                    Button {
                        if page < 2 {
                            withAnimation(reduceMotion ? nil : .default) { page += 1 }
                        } else {
                            path.append(.connect)
                        }
                    } label: {
                        Text(page < 2 ? "Continue" : "Get Started").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.prominent)
                    .controlSize(.extraLarge)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .readableWidth()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") { path.append(.connect) }
                }
            }
            .background(OnboardingGlow())
            .navigationDestination(for: Step.self) { _ in
                ConnectView(finish: finish)
            }
        }
    }
}

private struct OnboardingGlow: View {
    var body: some View {
        RadialGradient(
            colors: [Theme.signatureViolet.opacity(0.35), .clear], center: .top, startRadius: 0, endRadius: 420
        )
        .ignoresSafeArea()
        .background(Theme.background)
    }
}

/// The hero and title at the top, the page's list centred in the room left above the button; scrolls once it doesn't
/// fit.
private struct PageLayout<Hero: View, Footer: View>: View {
    let eyebrow: LocalizedStringKey
    let title: LocalizedStringKey
    @ViewBuilder var hero: Hero
    @ViewBuilder var footer: Footer

    var body: some View {
        FitOrScroll {
            VStack(alignment: .leading, spacing: 14) {
                hero
                Eyebrow(text: eyebrow).padding(.top, 8)
                Text(title)
                    .font(.display(44))
                    .textCase(.uppercase)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 24)
                footer
                Spacer(minLength: 16)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .readableWidth()
        }
    }
}

private struct WhatPage: View {
    var body: some View {
        PageLayout(eyebrow: "Unofficial Higgsfield client", title: "All of Higgsfield,\nnative on iPhone") {
            BeforeAfterDemo()
                .containerRelativeFrame(.vertical) { height, _ in min(280, height * 0.4) }
        } footer: {
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    "Every Higgsfield video and image model on your own account: motion, swaps, restyles, edits, characters, upscales and more."
                )
                .foregroundStyle(Theme.muted)
                ModelChips()
            }
        }
    }
}

/// A draggable divider between "your clip" and "new take": the onboarding teaches by doing (HIG).
private struct BeforeAfterDemo: View {
    @State private var divider = CompareDivider()

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: [Color(rgb: 0x3B3550), Color(rgb: 0xC26B8A)], startPoint: .top, endPoint: .bottom)
                LinearGradient(
                    colors: [Color(rgb: 0x4B1D8F), Color(rgb: 0xFF5FA2)], startPoint: .top, endPoint: .bottom
                )
                .mask(alignment: .trailing) {
                    Rectangle().frame(width: proxy.size.width * (1 - divider.position))
                }
                Rectangle()
                    .fill(.white)
                    .frame(width: 2)
                    .offset(x: proxy.size.width * divider.position - 1)
            }
            .overlay(alignment: .topLeading) { label("Your clip") }
            .overlay(alignment: .topTrailing) { label("New take") }
            .clipShape(.rect(cornerRadius: 30))
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    divider.drag(to: value.location.x, width: proxy.size.width)
                }
            )
            .adjustableDivider($divider, label: "Your clip and the new take, side by side")
        }
    }

    private func label(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.eyebrow)
            // Two labels share one line across the demo; past this size they would run into each other.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .textCase(.uppercase)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glass(.clear)
            .padding(12)
    }
}

private struct ModelChips: View {
    private let models = ["Genjutsu", "Seedance 2.5", "Kling 4.0", "Wan 3.0", "Cinema Studio", "MiniMax H3"]

    var body: some View {
        FlowRow(spacing: 6) {
            ForEach(models, id: \.self) { model in
                Text(model)
                    .font(.eyebrow)
                    .textCase(.uppercase)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.07), in: .rect(cornerRadius: 8))
            }
        }
    }
}

private struct MakePage: View {
    private let capabilities: [Feature] = [
        Feature("jutsu.motion", "Motion Transfer", "Genjutsu · Kling · Wan"),
        Feature("person.2.crop.square.stack", "Object Swap", "Characters, products"),
        Feature("jutsu.wand", "Restyle", "Preset gallery"),
        Feature("jutsu.prompt", "Prompt to Video", "Seedance · Kling 4.0"),
        Feature("film.stack", "Edit & Extend", "Seedance · Kling O3"),
        Feature("jutsu.photo", "Images", "Image models"),
        Feature("jutsu.person", "Characters", "Sheets, elements"),
        Feature("jutsu.upscale", "Enhance", "Upscale · Reframe · Dub"),
    ]

    /// Two columns on iPhone, more on iPad, one at accessibility sizes.
    @ScaledMetric(relativeTo: .subheadline) private var tileWidth: CGFloat = 150
    /// The app's icons are images, not symbols, so they are sized to the text here rather than by the font.
    @ScaledMetric(relativeTo: .subheadline) private var iconSize: CGFloat = 18

    var body: some View {
        PageLayout(eyebrow: "What you can make", title: "Everything\nin one studio") {
            EmptyView()
        } footer: {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: tileWidth), spacing: 8)], spacing: 8) {
                ForEach(capabilities, id: \.symbol) { feature in
                    // The icon beside the title rather than in a tile of its own leaves the title and the models the
                    // tile's full width, so they stay on one line.
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(symbol: feature.symbol)
                                .resizable()
                                .scaledToFit()
                                .frame(width: iconSize, height: iconSize)
                                .foregroundStyle(Theme.accent)
                                .accessibilityHidden(true)
                            Text(feature.title).font(.subheadline.weight(.semibold))
                        }
                        Text(feature.detail)
                            .font(.eyebrow)
                            .foregroundStyle(Theme.faint)
                            // A list of models reads wrong broken across lines; it shrinks a little instead.
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(12)
                    // Every tile in a row takes the tallest one's height, so the rows line up.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Theme.card, in: .rect(cornerRadius: 18))
                    .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.stroke) }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct WhyPage: View {
    private let reasons: [Feature] = [
        Feature("jutsu.live", "Keeps going when you leave", "Queue a batch and lock your phone."),
        Feature(
            "jutsu.download", "Every take saved on your iPhone", "Higgsfield's links expire. Your library doesn't."),
        Feature("hand.draw", "Keep the best in a swipe", "Right to keep, left to reject."),
        Feature("jutsu.shield", "Your account, nothing in between", "No Jutsu server, no telemetry."),
    ]

    var body: some View {
        PageLayout(eyebrow: "Why an app", title: "Made for\nmany takes") {
            EmptyView()
        } footer: {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(reasons, id: \.symbol) { feature in
                    HStack(alignment: .top, spacing: 14) {
                        SymbolTile(systemName: feature.symbol, isAccent: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title).font(.headline)
                            Text(feature.detail).font(.subheadline).foregroundStyle(Theme.muted)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Where the reader is in the three pages. One adjustable element for VoiceOver, since the page view's own dots are off.
private struct PageDots: View {
    @Binding var page: Int
    let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Theme.text : Theme.faint)
                    .frame(width: index == page ? 18 : 6, height: 6)
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: page)
        .accessibilityElement()
        .accessibilityLabel("Page")
        .accessibilityValue(Text("\(page + 1) of \(count)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: page = min(page + 1, count - 1)
            case .decrement: page = max(page - 1, 0)
            @unknown default: break
            }
        }
    }
}

/// A row of an onboarding list: an SF Symbol, a title and one line about it.
private struct Feature {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    init(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
    }
}
