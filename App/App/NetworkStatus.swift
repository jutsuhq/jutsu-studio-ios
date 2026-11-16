import Foundation
import JutsuCore
import Presentation

/// Whether the device has a network, for the offline banner and for what is asked again once it is back.
@Observable
final class NetworkStatus {
    /// Assumed until the first path arrives, so the banner doesn't flash at launch.
    private(set) var isOnline = true
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Follows `connectivity` for the app's lifetime; `reconnected` runs each time the network comes back.
    func follow(_ connectivity: some Connectivity, reconnected: @escaping @MainActor () -> Void) {
        guard task == nil else { return }
        task = Task { [weak self] in
            for await online in connectivity.updates() {
                guard let self else { return }
                let cameBack = online && !isOnline
                if isOnline && !online { VoiceOver.announce(String(localized: "You're offline")) }
                isOnline = online
                if cameBack { reconnected() }
            }
        }
    }
}

extension AppEnvironment {
    /// What Generate answers without a network.
    static var offlineMessage: UserMessage {
        UserMessage(
            title: String(localized: "You're offline"),
            message: String(localized: "Connect to Wi-Fi or cellular data, then try again."))
    }

    /// Loads that failed for want of a network, asked again: the balance, what the connection can run, the image
    /// models and the history page. Create's prices and thumbnails follow `isOnline` on their own.
    func retryAfterReconnect() {
        Task {
            guard let provider else { return }
            await connection.refreshBalance(from: provider)
            if capabilities == nil { await loadCapabilities() }
            if imageGenerator.models.isEmpty { await loadImageModels() }
            if case .failed = history.phase { await loadHistory(refresh: !history.hasLoaded) }
        }
    }
}
