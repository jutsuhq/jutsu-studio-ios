import Foundation
import HiggsfieldCore
import JobEngine
import JutsuCore
import Presentation
import os

nonisolated private let logger = Logger.jutsu("Downloads")

/// The engine's `Downloader` on a background `URLSession`: a result keeps downloading while the app is suspended or
/// even terminated, and the system relaunches the app to hand it over. A cancelled `download` stops waiting but leaves
/// the transfer running; calling again for the same file attaches to it, or returns at once when it already finished.
nonisolated final class BackgroundDownloader: NSObject, Downloader, URLSessionDownloadDelegate, @unchecked Sendable {
    static let sessionID = "ai.jutsustudio.ios.downloads"
    static let shared = BackgroundDownloader()

    // Safe: everything below is only touched under `lock`.
    private let lock = NSLock()
    private var waiters: [String: [CheckedContinuation<Void, any Error>]] = [:]
    private var finished: [String: Result<Void, any Error>] = [:]
    private var progressHandlers: [String: @Sendable (Int64, Int64?) -> Void] = [:]
    private var eventsFinished: (() -> Void)?
    private var storedSession: URLSession?

    private var session: URLSession {
        lock.withLock {
            if let storedSession { return storedSession }
            let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionID)
            configuration.sessionSendsLaunchEvents = true
            configuration.isDiscretionary = false
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            storedSession = session
            return session
        }
    }

    /// Creates the session at launch, so events for transfers that finished while the app was gone find it.
    func activate() {
        _ = session
    }

    /// The system woke the app for this session's events; `handler` is called once they are all delivered.
    func handleEvents(completion handler: @escaping () -> Void) {
        lock.withLock { eventsFinished = handler }
        activate()
    }

    func download(_ url: URL, to file: URL) async throws {
        try await download(url, to: file, progress: { _, _ in })
    }

    func download(
        _ url: URL, to file: URL, progress: @escaping @Sendable (_ written: Int64, _ total: Int64?) -> Void
    ) async throws {
        guard url.isHTTPS else { throw ProviderError.server(status: 0) }
        let key = file.path(percentEncoded: false)
        if let result = lock.withLock({ finished.removeValue(forKey: key) }) {
            try result.get()
            return
        }
        lock.withLock { progressHandlers[key] = progress }
        defer { lock.withLock { progressHandlers[key] = nil } }
        let running = await session.allTasks.contains { $0.taskDescription == key && $0.state == .running }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                lock.withLock { waiters[key, default: []].append(continuation) }
                if !running {
                    var request = URLRequest(url: url)
                    request.allowsCellularAccess = AppSettings.cellularDownloads(in: .standard)
                    let task = session.downloadTask(with: request)
                    task.taskDescription = key
                    task.resume()
                }
            }
        } onCancel: {
            // The transfer goes on in the background; only this wait ends.
            let pending = lock.withLock { waiters.removeValue(forKey: key) ?? [] }
            pending.forEach { $0.resume(throwing: CancellationError()) }
        }
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
    ) {
        guard let key = downloadTask.taskDescription else { return }
        let destination = URL(filePath: key)
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        let result: Result<Void, any Error>
        if (200..<300).contains(status) {
            do {
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: location, to: destination)
                result = .success(())
            } catch {
                result = .failure(error)
            }
        } else {
            // A 5xx may pass on a retry; a 4xx may mean the result expired, which only the engine can tell apart.
            result = .failure(
                status == 0 || status >= 500
                    ? ProviderError.server(status: status)
                    : JobEngineError.downloadFailed(status: status))
        }
        settle(key, result)
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard let key = downloadTask.taskDescription, let progress = lock.withLock({ progressHandlers[key] }) else {
            return
        }
        progress(totalBytesWritten, totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error, let key = task.taskDescription else { return }
        logger.error("Download failed: \(String(describing: error), privacy: .private)")
        settle(key, .failure(ProviderError.network))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let handler = lock.withLock { () -> (() -> Void)? in
            defer { eventsFinished = nil }
            return eventsFinished
        }
        DispatchQueue.main.async { handler?() }
    }

    /// Hands the result to whoever waits, or keeps it for the engine's next call when nobody does (a relaunch).
    private func settle(_ key: String, _ result: Result<Void, any Error>) {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, any Error>] in
            let pending = waiters.removeValue(forKey: key) ?? []
            if pending.isEmpty { finished[key] = result }
            return pending
        }
        pending.forEach { $0.resume(with: result) }
    }
}
