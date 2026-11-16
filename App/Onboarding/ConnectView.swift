import Presentation
import SwiftUI

/// Account or API key, and Not Now. No sign-up or purchase link anywhere (App Review 3.1.3(f)).
struct ConnectView: View {
    var finish: (() -> Void)?
    @Environment(ConnectionStore.self) private var connection
    @State private var showsKeyForm = false
    @State private var showsSignInSteps = false
    /// What the steps sheet's buttons asked for, run once it is gone: the web sheet can't open over it.
    @State private var afterSteps: SignInSteps.Choice?
    /// Set once someone has gone on from the steps, so the next tap opens higgsfield.ai at once. A failed sign-in
    /// clears it: the steps say what to tap.
    @AppStorage("onboarding.signInStepsSeen") private var signInStepsSeen = false

    var body: some View {
        @Bindable var connection = connection
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                DisplayTitle(text: "Connect\nHiggsfield")
                Text("Generations run on Higgsfield and are billed to your own account. Choose how you pay.")
                    .foregroundStyle(Theme.muted)
                    .padding(.bottom, 8)

                Eyebrow(text: "Recommended")
                ChoiceRow(
                    symbol: "person.crop.circle", isAccent: true, title: "Connect your Higgsfield account",
                    detail: "Spend your plan's credits, unlimited generations included"
                ) {
                    if signInStepsSeen { connection.startSignIn() } else { showsSignInSteps = true }
                }
                .disabled(connection.activity.isSigningIn)

                ChoiceRow(
                    symbol: "key", title: "Use an API key", detail: "Pay as you go in USD from console.higgsfield.ai"
                ) { showsKeyForm = true }

                Text(
                    "Signing in opens higgsfield.ai, so Jutsu never sees your password. Keys and tokens stay in this iPhone's Keychain."
                )
                .font(.footnote)
                .foregroundStyle(Theme.faint)
                Button("How signing in works") { showsSignInSteps = true }
                    .font(.footnote.weight(.semibold))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .readableWidth()
        }
        .background(Theme.background)
        .edgeBar(edge: .bottom) {
            if let finish {
                VStack(spacing: 2) {
                    Button("Not Now", action: finish)
                        .font(.headline)
                    Text("Look around first and sign in when you want to generate.")
                        .font(.footnote)
                        .foregroundStyle(Theme.faint)
                }
                .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showsKeyForm) {
            APIKeyView()
        }
        .sheet(isPresented: $showsSignInSteps) {
            switch afterSteps {
            case .signIn?:
                signInStepsSeen = true
                connection.startSignIn()
            case .apiKey?:
                showsKeyForm = true
            case nil:
                break
            }
            afterSteps = nil
        } content: {
            SignInSteps { afterSteps = $0 }
        }
        .onChange(of: connection.activity.isSigningIn) { _, signingIn in
            if !signingIn, connection.alert != nil { signInStepsSeen = false }
        }
        .onChange(of: connection.state.isConnected) { _, connected in
            if connected { finish?() }
        }
        .alert($connection.alert)
    }
}

/// What happens between tapping Connect and coming back connected, so the system prompt and Higgsfield's pages
/// that follow aren't a surprise. Shown before the first sign-in and after one that failed.
struct SignInSteps: View {
    enum Choice { case signIn, apiKey }

    let choose: (Choice) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var height: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "Sign in with Higgsfield")
                    DisplayTitle(text: "What happens\nnext", size: 34)
                }
                step(
                    1, "safari", "Tap **Continue**",
                    "iOS asks if Jutsu may use higgsfield.ai to sign in.")
                step(
                    2, "person.crop.circle", "Sign in to Higgsfield",
                    "Skipped if you're signed in to higgsfield.ai in Safari. Jutsu never sees your password.")
                step(
                    3, "hand.tap", "Tap **Allow**",
                    "Higgsfield asks to let Jutsu for iPhone use your account. Don't Allow stops here.")
                step(4, "checkmark.circle", "You're back, connected", "Your credits show at the top of Create.")
                Text("Cancel at any step and nothing changes. If Higgsfield's sign-in won't work, use an API key.")
                    .font(.footnote)
                    .foregroundStyle(Theme.faint)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .readableWidth()
        }
        .scrollBounceBehavior(.basedOnSize)
        .edgeBar(edge: .bottom) {
            VStack(spacing: 4) {
                Button {
                    choose(.signIn)
                    dismiss()
                } label: {
                    Text("Continue to Higgsfield").frame(maxWidth: .infinity)
                }
                .buttonStyle(.prominent)
                .controlSize(.extraLarge)
                Button("Use an API Key Instead") {
                    choose(.apiKey)
                    dismiss()
                }
                .font(.subheadline.weight(.semibold))
                .padding(.vertical, 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .readableWidth()
        }
        // As tall as the steps and buttons, so it sits low at default sizes and fills the screen at large ones.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
        } action: { _, newHeight in
            height = newHeight
        }
        .presentationDetents(height > 0 ? [.height(height)] : [.large])
        .presentationBackground(Theme.background)
        .presentationDragIndicator(.visible)
    }

    private func step(
        _ number: Int, _ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            SymbolTile(systemName: symbol, isAccent: number == 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(Theme.muted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(number): \(Text(title))"))
        .accessibilityValue(Text(detail))
    }
}

private struct ChoiceRow: View {
    let symbol: String
    var isAccent = false
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                SymbolTile(systemName: symbol, isAccent: isAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.white)
                    Text(detail).font(.subheadline).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Theme.faint).accessibilityHidden(true)
            }
            .padding(16)
            .background(Theme.card, in: .rect(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(isAccent ? Theme.accent.opacity(0.35) : Theme.stroke)
            }
        }
        .buttonStyle(.plain)
    }
}

/// The key ID and secret from console.higgsfield.ai, checked with Higgsfield before it is saved.
struct APIKeyView: View {
    @Environment(ConnectionStore.self) private var connection
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var form = APIKeyForm()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Key ID", text: $form.keyID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .fontDesign(.monospaced)
                    SecureField("Secret", text: $form.secret)
                        .fontDesign(.monospaced)
                } footer: {
                    Text("Charges go to the key's balance in USD. The key is stored only in this iPhone's Keychain.")
                }
                Section {
                    Label("Sign in at console.higgsfield.ai and create a key", systemImage: "1.circle")
                    Label("Paste its key ID and secret above", systemImage: "2.circle")
                    Label("Top up the key's balance there when it runs low", systemImage: "3.circle")
                    Button("Get a key at console.higgsfield.ai") { openURL(Higgsfield.consoleURL) }
                } header: {
                    Text("No key yet?")
                }
            }
            .navigationTitle("API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    RoleButton(.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if connection.activity == .validatingKey {
                        ProgressView()
                    } else {
                        RoleButton(.confirm) {
                            Task {
                                await connection.connectAPIKey(form)
                                if connection.state.isConnected { dismiss() }
                            }
                        }
                        .disabled(!form.isComplete)
                    }
                }
            }
        }
    }
}
