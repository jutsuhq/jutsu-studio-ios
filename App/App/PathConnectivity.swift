import Foundation
import JutsuCore
import Network

/// `Connectivity` on `NWPathMonitor`. Each stream owns its monitor, which reports the current path right after `start`.
nonisolated struct PathConnectivity: Connectivity {
    func updates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "ai.jutsustudio.ios.connectivity"))
        }
    }
}
