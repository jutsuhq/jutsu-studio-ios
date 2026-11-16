import JutsuCore
import Presentation
import SwiftUI

/// How results download and are named, and the space the app uses.
struct StoragePane: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(LiveJobs.self) private var liveJobs
    @AppStorage(AppSettings.cellularDownloadsKey) private var cellularDownloads = AppSettings.defaultCellularDownloads
    @AppStorage(AppSettings.outputNamePatternKey) private var namePattern = OutputNamePattern.defaultPattern
    @AppStorage(EditingExportContent.writesSidecarKey) private var writesSidecar = EditingExportContent
        .defaultWritesSidecar
    @AppStorage(AppSettings.cacheMaxAgeDaysKey) private var cacheMaxAgeDays = AppSettings.defaultCacheMaxAgeDays
    @State private var usage: StorageBreakdown?
    @State private var message: UserMessage?

    var body: some View {
        Form {
            Section {
                Toggle("Download over cellular", isOn: $cellularDownloads)
            } footer: {
                Text("Off: finished takes wait for Wi-Fi to download.")
            }
            filesSection
            storageSection
            ResetSection(reset: reset)
        }
        .settingsPage(.storage)
        .task { usage = await environment.measureStorage() }
        .onChange(of: namePattern) {
            let pattern = OutputNamePattern(namePattern)
            Task { await environment.engine.setOutputNamePattern(pattern) }
        }
        .alert($message)
    }

    private var filesSection: some View {
        Section {
            Picker("File names", selection: $namePattern) {
                ForEach(AppSettings.outputNameTemplates) { Text($0.title).tag($0.pattern) }
                if !AppSettings.outputNameTemplates.contains(where: { $0.pattern == namePattern }) {
                    Text(namePattern).tag(namePattern)
                }
            }
            Toggle("Include JSON Sidecar", isOn: $writesSidecar)
        } header: {
            Text("Files")
        } footer: {
            let example = AppSettings.outputNameExample(namePattern)
            VStack(alignment: .leading, spacing: 4) {
                Text("For example, \(example). Takes already saved keep their names.")
                Text("Export for Editing also writes a JSON file with how the take was made.")
            }
        }
    }

    private var storageSection: some View {
        Section {
            LabeledContent("Results in Files", value: size(\.results))
            LabeledContent("Prepared sources", value: size(\.sources))
            LabeledContent("Downloaded inputs", value: size(\.inputs))
            LabeledContent("Cache", value: size(\.cache))
            Picker("Remove old cache", selection: $cacheMaxAgeDays) {
                ForEach(AppSettings.cacheMaxAgeOptions, id: \.self) { Text(Self.ageTitle($0)).tag($0) }
            }
            Button("Clear Inputs and Cache") { Task { await clearCache() } }
                .disabled(liveJobs.activeCount > 0 || usage?.clearable == 0)
        } header: {
            Text("Storage")
        } footer: {
            Text("Results are never removed. Inputs of unfinished jobs and of the Create draft are kept.")
        }
    }

    private func size(_ part: KeyPath<StorageBreakdown, Int64>) -> String {
        usage.map { ByteCountFormatter.string(fromByteCount: $0[keyPath: part], countStyle: .file) } ?? "…"
    }

    private static func ageTitle(_ days: Int) -> LocalizedStringKey {
        switch days {
        case 0: "Never"
        case 1: "After a day"
        case 7: "After a week"
        case 30: "After a month"
        default: "After \(days) days"
        }
    }

    private func clearCache() async {
        do {
            try await environment.clearCache()
        } catch {
            message = UserMessage(error)
        }
        usage = await environment.measureStorage()
    }

    private func reset() {
        cellularDownloads = AppSettings.defaultCellularDownloads
        namePattern = OutputNamePattern.defaultPattern
        writesSidecar = EditingExportContent.defaultWritesSidecar
        cacheMaxAgeDays = AppSettings.defaultCacheMaxAgeDays
    }
}
