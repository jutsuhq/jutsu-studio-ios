import Foundation
import JutsuCore
import MediaKit
import Persistence
import Presentation
import SwiftData
import SwiftUI
import os

nonisolated private let logger = Logger.jutsu("Templates")

extension AppEnvironment {
    /// The templates in the main context, with their images in the app container.
    var templateLibrary: TemplateLibrary {
        TemplateLibrary(
            records: TemplateRecordStore(context: modelContainer.mainContext),
            images: TemplateImageFolder(layout: layout))
    }

    /// Stars or unstars `prompt`; a starred prompt stays on top of the history and survives clearing it.
    func setStarred(_ isStarred: Bool, prompt: String) throws {
        let text = PromptHistory.key(prompt)
        guard !text.isEmpty else { return }
        let context = modelContainer.mainContext
        let existing = try context.fetch(
            FetchDescriptor<StarredPromptRecord>(predicate: #Predicate { $0.text == text }))
        if isStarred {
            guard existing.isEmpty else { return }
            context.insert(StarredPromptRecord(text: text))
        } else {
            existing.forEach(context.delete)
        }
        try context.save()
    }

    /// Removes image folders whose template is gone; skipped when the templates can't be read.
    func pruneTemplateImages() async {
        do {
            let ids = try modelContainer.mainContext.fetch(TemplateRecord.byName).map(\.id)
            try await Self.pruneTemplateImages(in: layout, keeping: Set(ids))
        } catch {
            logger.error("Can't prune template images: \(String(describing: error), privacy: .private)")
        }
    }

    @concurrent
    private static func pruneTemplateImages(in layout: FileLayout, keeping ids: Set<UUID>) async throws {
        try layout.pruneTemplateImages(keeping: ids)
    }
}

private struct TemplateRecordStore: TemplateRecords {
    let context: ModelContext

    func names(excluding id: UUID?) -> [String] {
        ((try? context.fetch(TemplateRecord.byName)) ?? []).filter { $0.id != id }.map(\.name)
    }

    /// A record whose save fails is taken out of the context again.
    func add(_ template: JobTemplate) throws {
        let record = try TemplateRecord(template: template)
        context.insert(record)
        do {
            try context.save()
        } catch {
            context.delete(record)
            throw error
        }
    }

    func rename(_ id: UUID, to name: String) throws {
        guard let record = try record(id) else { return }
        try record.rename(to: name)
        try context.save()
    }

    func delete(_ id: UUID) throws {
        guard let record = try record(id) else { return }
        context.delete(record)
        try context.save()
    }

    private func record(_ id: UUID) throws -> TemplateRecord? {
        var descriptor = FetchDescriptor<TemplateRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

private struct TemplateImageFolder: TemplateImages {
    let layout: FileLayout

    func copy(_ references: [LocalImage], templateID: UUID) throws -> [URL] {
        let accesses = references.map { SecurityScopedAccess(url: $0.fileURL, bookmark: $0.bookmark) }
        return try withExtendedLifetime(accesses) {
            try layout.copyTemplateImages(accesses.map(\.url), templateID: templateID)
        }
    }

    func remove(templateID: UUID) {
        do {
            try layout.removeTemplateImages(templateID: templateID)
        } catch {
            logger.error("Can't remove template images: \(String(describing: error), privacy: .private)")
        }
    }
}

/// Earlier prompts, starred first; tap one to put it back in the prompt.
struct PromptHistorySheet: View {
    let onPick: (String) -> Void
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.promptHistoryClearedAtKey) private var clearedAtValue = 0.0
    @Query(JobRecord.withPrompts(after: nil)) private var jobs: [JobRecord]
    @Query(StarredPromptRecord.newestFirst) private var starred: [StarredPromptRecord]
    @State private var query = ""
    @State private var message: UserMessage?

    private var items: [PromptHistoryItem] {
        let clearedAt = AppSettings.promptHistoryClearedAt(clearedAtValue)
        let uses = jobs.map { PromptUse(text: $0.prompt, date: $0.createdAt) }
        let stars = starred.map { PromptUse(text: $0.text, date: $0.starredAt) }
        return PromptHistory.search(PromptHistory.items(uses: uses, starred: stars, clearedAt: clearedAt), query: query)
    }

    var body: some View {
        NavigationStack {
            List(items) { item in
                Button {
                    onPick(item.text)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.text).lineLimit(3).foregroundStyle(Theme.text)
                        if let lastUsed = item.lastUsed {
                            Text(lastUsed.formatted(.relative(presentation: .named)))
                                .font(.caption).foregroundStyle(Theme.faint)
                        }
                    }
                }
                .swipeActions {
                    Button(item.isStarred ? "Unstar" : "Star", systemImage: item.isStarred ? "star.slash" : "star") {
                        do { try environment.setStarred(!item.isStarred, prompt: item.text) } catch {
                            logger.error("Can't star a prompt: \(String(describing: error), privacy: .private)")
                            message = UserMessage(error)
                        }
                    }
                    .tint(Theme.accent)
                }
                .overlay(alignment: .topTrailing) {
                    if item.isStarred {
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(Theme.accent)
                            .accessibilityLabel("Starred")
                    }
                }
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView(
                        query.isEmpty ? "No prompts yet" : "No prompt matches", systemImage: "clock.arrow.circlepath",
                        description: Text("Prompts of jobs you send show up here. Swipe to star one."))
                }
            }
            .searchable(text: $query, prompt: "Search prompts")
            .navigationTitle("Prompt History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Clear") { clearedAtValue = Date.now.timeIntervalSinceReferenceDate }
                        .disabled(items.allSatisfy(\.isStarred))
                }
            }
            .closeButton()
            .alert($message)
        }
        .presentationDetents([.medium, .large])
    }
}

/// Saved setups: the task, model, references, preset and prompt, applied to Create in one tap.
struct TemplatesSheet: View {
    let current: JobTemplate
    let onApply: (JobTemplate) -> Void
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Query(TemplateRecord.byName) private var records: [TemplateRecord]
    @State private var message: UserMessage?
    @State private var renaming: TemplateRecord?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Save Current Setup", systemImage: "plus") {
                        do {
                            _ = try environment.templateLibrary.save(current)
                        } catch {
                            message = UserMessage(error)
                        }
                    }
                } footer: {
                    Text("A template keeps the task, model, length, references, preset and prompt.")
                }
                Section {
                    ForEach(records) { record in
                        if let template = try? record.template() {
                            Button {
                                onApply(template)
                                dismiss()
                            } label: {
                                TemplateRow(name: record.name, template: template)
                            }
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    do { try environment.templateLibrary.delete(record.id) } catch {
                                        message = UserMessage(error)
                                    }
                                }
                                Button("Rename", systemImage: "pencil") {
                                    newName = record.name
                                    renaming = record
                                }
                            }
                        }
                    }
                }
            }
            .overlay {
                if records.isEmpty {
                    ContentUnavailableView(
                        "No templates yet", systemImage: "square.on.square.dashed",
                        description: Text("Save a setup you reuse, then start from it in one tap."))
                }
            }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .closeButton()
            .alert(
                "Rename Template", isPresented: Binding(isPresent: $renaming)
            ) {
                TextField("Name", text: $newName)
                Button("Rename") {
                    guard let record = renaming else { return }
                    do { _ = try environment.templateLibrary.rename(record.id, to: newName) } catch {
                        message = UserMessage(error)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert($message)
        }
        .presentationDetents([.medium, .large])
    }
}

private struct TemplateRow: View {
    let name: String
    let template: JobTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).foregroundStyle(Theme.text)
            Text(verbatim: "\(template.mode.title) · \(template.model.title)")
                .font(.caption).foregroundStyle(Theme.muted)
        }
    }
}
