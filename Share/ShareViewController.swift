import UIKit
import UniformTypeIdentifiers
import os

nonisolated private let logger = Logger(subsystem: "ai.jutsustudio.ios", category: "Share")

/// "Share → Jutsu": copies the shared video or image into the app group's inbox, where Create picks it up the next
/// time the app is in front. Links nothing of the app and holds no credentials.
final class ShareViewController: UIViewController {
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.text = String(localized: "Adding to Jutsu…")
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
        ])
        Task { await importItems() }
    }

    private func importItems() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        var copied = 0
        for provider in providers {
            for type in [UTType.movie, UTType.image] where provider.hasItemConformingToTypeIdentifier(type.identifier) {
                if await copy(from: provider, type: type) { copied += 1 }
                break
            }
        }
        label.text =
            copied > 0
            ? String(localized: "Open Jutsu: it's waiting in Create.")
            : String(localized: "Jutsu takes videos and images.")
        try? await Task.sleep(for: .seconds(1.2))
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func copy(from provider: NSItemProvider, type: UTType) async -> Bool {
        guard let inbox = SharedInbox.folder else { return false }
        return await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(for: type) { url, _, _ in
                guard let url else { return continuation.resume(returning: false) }
                let manager = FileManager.default
                // Written beside the inbox, which the app only reads: a folder inside it would be taken, and removed,
                // before its file is complete. The finished folder is renamed in, so the app sees it whole or not at all.
                let staging = inbox.deletingLastPathComponent().appending(
                    path: "staging-\(UUID().uuidString)", directoryHint: .isDirectory)
                do {
                    try manager.createDirectory(at: staging, withIntermediateDirectories: true)
                    try manager.copyItem(at: url, to: staging.appending(path: url.lastPathComponent))
                    try manager.createDirectory(at: inbox, withIntermediateDirectories: true)
                    try manager.moveItem(
                        at: staging, to: inbox.appending(path: UUID().uuidString, directoryHint: .isDirectory))
                    continuation.resume(returning: true)
                } catch {
                    try? manager.removeItem(at: staging)
                    logger.error("Can't copy a shared file: \(String(describing: error), privacy: .private)")
                    continuation.resume(returning: false)
                }
            }
        }
    }
}
