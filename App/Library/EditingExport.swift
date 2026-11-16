import Foundation
import JutsuCore
import MediaKit
import Presentation
import SwiftUI
import os

nonisolated private let logger = Logger.jutsu("Export")

/// ProRes or H.264 at a constant frame rate for an editor, with the JSON sidecar; written to Files › Jutsu › Exports.
struct EditingExportMenu: View {
    let item: LibraryItemModel
    @Environment(AppEnvironment.self) private var environment
    @AppStorage(EditingExportContent.writesSidecarKey) private var writesSidecar = EditingExportContent
        .defaultWritesSidecar
    @State private var progress: Double?
    @State private var task: Task<Void, Never>?
    @State private var exported: ExportedFile?
    @State private var message: UserMessage?

    var body: some View {
        Group {
            if let progress {
                Button {
                    task?.cancel()
                } label: {
                    ProgressView(value: progress).progressViewStyle(.circular)
                }
                .accessibilityLabel("Cancel Export")
            } else {
                Menu {
                    ForEach(ExportPreset.allCases, id: \.self) { preset in
                        Button("\(preset.title) (\(preset.formatSummary))") { export(preset) }
                    }
                    Divider()
                    Toggle(EditingExportContent.sidecarToggleTitle, isOn: $writesSidecar)
                } label: {
                    Image(systemName: "film.stack")
                }
                .accessibilityLabel("Export for Editing")
                .disabled(item.outputFile == nil)
            }
        }
        .buttonStyle(.liquidGlass)
        .sheet(item: $exported) { file in
            ShareLink(item: file.url) {
                Label("Share \(file.url.lastPathComponent)", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.prominent)
            .padding()
            .presentationDetents([.height(140)])
        }
        .alert($message)
    }

    private func export(_ preset: ExportPreset) {
        guard task == nil, let result = item.outputFile else { return }
        let folder = OutputSubfolder.exports.url(in: environment.layout.defaultOutputFolder)
        let item = item
        let writesSidecar = writesSidecar
        progress = 0
        task = Task {
            defer {
                progress = nil
                task = nil
            }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let taken = ExportFolder.existingNames(in: folder)
                let names = ExportNaming.names(for: item.spec, presetName: item.presetName, preset: preset) {
                    taken.contains($0.lowercased())
                }
                let video = folder.appendingPathComponent(names.video)
                try await EditingExporter.export(result, source: item.spec.source, preset: preset, to: video) { value in
                    Task { @MainActor in if progress != nil { progress = value } }
                }
                if writesSidecar {
                    let sidecar = ExportSidecar(
                        job: item.job, presetName: item.presetName, exportPreset: preset, exportedAt: .now)
                    try sidecar.encoded().write(
                        to: folder.appendingPathComponent(names.sidecar), options: .withoutOverwriting)
                }
                exported = ExportedFile(url: video)
            } catch is CancellationError {
                return
            } catch {
                logger.error("Editing export failed: \(String(describing: error), privacy: .private)")
                message =
                    error.isOutOfSpace
                    ? .notEnoughStorage : EditingExportContent.failure(detail: error.localizedDescription)
            }
        }
    }
}

private struct ExportedFile: Identifiable {
    let url: URL
    var id: URL { url }
}
