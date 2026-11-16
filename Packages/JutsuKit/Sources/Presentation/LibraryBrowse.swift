import Foundation
import JutsuCore

/// Where the Library looks: what is on this iPhone, or what the Higgsfield account made anywhere.
public enum LibrarySource: String, Sendable, Hashable, CaseIterable, Identifiable {
    case device
    case higgsfield

    public var id: Self { self }

    public var title: String {
        switch self {
        case .device: String(localized: "On iPhone", bundle: .module)
        case .higgsfield: String(localized: "Higgsfield", bundle: .module)
        }
    }
}

/// The Library's and Search's rows: the account's history as cards, the search over prompts and models, and the
/// model names Search suggests.
public enum LibraryBrowse {
    /// The history's videos and images in one list, newest first.
    public static func historyRows(_ history: AccountHistory) -> [LibraryMediaItem] {
        let videos = history.items.map { LibraryMediaItem.video(LibraryItemModel(history: $0)) }
        let images = history.images.map(LibraryMediaItem.remoteImage)
        return (videos + images).sorted { $0.createdAt > $1.createdAt }
    }

    /// The rows whose prompt, model or mode holds every word of `query`, in any order and case; none for an empty
    /// query, so Search shows its suggestions instead of everything.
    public static func search(_ query: String, in rows: [LibraryMediaItem]) -> [LibraryMediaItem] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return [] }
        return rows.filter { row in
            let text = searchText(row).lowercased()
            return words.allSatisfy { text.contains($0) }
        }
    }

    /// The model names among `rows`, the most used first, that start a word with what was typed; the names a search
    /// is most often after. Empty once the query is a whole name already.
    public static func suggestions(for query: String, in rows: [LibraryMediaItem], limit: Int = 6) -> [String] {
        var counts: [String: Int] = [:]
        for row in rows { counts[modelName(row), default: 0] += 1 }
        let typed = query.trimmingCharacters(in: .whitespaces).lowercased()
        let names = counts.keys.filter { name in
            let lower = name.lowercased()
            guard !typed.isEmpty, !lower.isEmpty else { return !lower.isEmpty }
            return lower != typed
                && (lower.hasPrefix(typed) || lower.split(separator: " ").contains { $0.hasPrefix(typed) })
        }
        let ranked = names.sorted { lhs, rhs in
            let left = counts[lhs] ?? 0
            let right = counts[rhs] ?? 0
            return left != right ? left > right : lhs < rhs
        }
        return Array(ranked.prefix(limit))
    }

    /// The model as people know it: the catalog title for a video, a readable server ID for an image
    /// ("nano_banana_pro" → "Nano Banana Pro"); an image made on this iPhone keeps the name it was saved with.
    public static func modelName(_ row: LibraryMediaItem) -> String {
        switch row {
        case .video(let item): item.spec.model.title
        case .localImage(let image): readableModel(image.model)
        case .remoteImage(let image): readableModel(image.model)
        }
    }

    /// A server model ID made readable; a name with spaces already is kept.
    public static func readableModel(_ id: String) -> String {
        guard !id.isEmpty, !id.contains(" ") else { return id }
        return id.split(whereSeparator: { $0 == "_" || $0 == "-" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// An image file in Documents/Images as a card. Its name is `SavedImage.baseName`, the date then the start of
    /// the prompt, so the prompt is read back from it; the ID comes from the path, so the card keeps it across reloads.
    public static func savedImage(at file: URL, modified: Date) -> SavedImage {
        let name = file.deletingPathExtension().lastPathComponent
        let parts = name.split(separator: " ", maxSplits: 2)
        let isDated =
            parts.count >= 2 && parts[0].count == 10 && parts[1].count == 8 && parts[0].first?.isNumber == true
        let prompt = isDated ? (parts.count == 3 ? String(parts[2]) : "") : name
        return SavedImage(
            id: stableID(file.standardizedFileURL.path), fileURL: file, prompt: prompt, model: "", aspectRatio: nil,
            createdAt: modified)
    }

    /// A UUID made from `text`, the same on every call: FNV-1a over the text, twice with different seeds.
    static func stableID(_ text: String) -> UUID {
        func hash(_ seed: UInt64) -> UInt64 {
            text.utf8.reduce(seed) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
        }
        let high = hash(0xcbf2_9ce4_8422_2325)
        let low = hash(0x8422_2325_cbf2_9ce4)
        let bytes =
            (0..<8).map { UInt8(truncatingIfNeeded: high >> ($0 * 8)) }
            + (0..<8).map { UInt8(truncatingIfNeeded: low >> ($0 * 8)) }
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9],
                bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }

    static func searchText(_ row: LibraryMediaItem) -> String {
        switch row {
        case .video(let item): "\(item.spec.prompt) \(item.title) \(item.spec.model.title) \(item.spec.mode.title)"
        case .localImage(let image): "\(image.prompt) \(image.model) \(modelName(row))"
        case .remoteImage(let image): "\(image.prompt) \(image.model) \(modelName(row))"
        }
    }
}

/// What the info sheet of a Library item lists: each fact it knows, in a fixed order, and the prompt.
public struct LibraryItemDetails: Sendable, Hashable {
    public struct Fact: Sendable, Hashable, Identifiable {
        public var title: String
        public var value: String
        public var id: String { title }
    }

    public var prompt: String
    public var facts: [Fact]
    /// The model and the shape in one line, under the item in the viewer: "Seedance 2.5 · 480p · 3.7 s".
    public var summary: String

    public init(_ row: LibraryMediaItem, isOnDevice: Bool) {
        var facts: [Fact] = []
        var summary: [String] = []
        func add(_ title: String, _ value: String?, inSummary: Bool = false) {
            guard let value, !value.isEmpty else { return }
            facts.append(Fact(title: title, value: value))
            if inSummary { summary.append(value) }
        }
        let model = String(localized: "Model", bundle: .module)
        switch row {
        case .video(let item):
            prompt = item.spec.prompt
            add(model, item.spec.model.title, inSummary: true)
            add(String(localized: "Mode", bundle: .module), item.spec.operation?.action.title ?? item.spec.mode.title)
            add(String(localized: "Preset", bundle: .module), item.presetName)
            add(String(localized: "Resolution", bundle: .module), item.spec.resolutionTitle, inSummary: true)
            if item.spec.isDraft {
                add(String(localized: "Finish", bundle: .module), LibraryFilter.Finish.drafts.title)
            }
            let seconds = item.historyItem?.duration ?? (item.job.outputDuration > 0 ? item.job.outputDuration : nil)
            add(String(localized: "Length", bundle: .module), seconds.map { Self.seconds($0) }, inSummary: true)
            let size = item.job.outputMedia?.pixelSize ?? item.historyItem?.pixelSize
            add(String(localized: "Size", bundle: .module), size.map(Self.size))
            let references = item.spec.references.count
            if references > 0 {
                add(String(localized: "References", bundle: .module), String(references))
            }
            add(String(localized: "Created", bundle: .module), Self.date(item.finishedAt))
        case .localImage(let image):
            prompt = image.prompt
            add(model, LibraryBrowse.modelName(row), inSummary: true)
            add(String(localized: "Aspect ratio", bundle: .module), row.aspectRatio, inSummary: true)
            add(String(localized: "Created", bundle: .module), Self.date(image.createdAt))
        case .remoteImage(let image):
            prompt = image.prompt
            add(model, LibraryBrowse.modelName(row), inSummary: true)
            add(String(localized: "Aspect ratio", bundle: .module), image.aspectRatio, inSummary: true)
            add(String(localized: "Size", bundle: .module), image.pixelSize.map(Self.size))
            add(String(localized: "Created", bundle: .module), Self.date(image.createdAt))
        }
        add(
            String(localized: "Where", bundle: .module),
            isOnDevice
                ? String(localized: "On this iPhone", bundle: .module)
                : String(localized: "On Higgsfield, not downloaded", bundle: .module))
        self.facts = facts
        self.summary = summary.joined(separator: " · ")
    }

    /// "8 s", "3.7 s".
    static func seconds(_ value: TimeInterval) -> String {
        let rounded = (value * 10).rounded() / 10
        let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
        return String(localized: "\(text) s", bundle: .module)
    }

    /// "1080 × 1920".
    static func size(_ size: PixelSize) -> String { "\(size.width) × \(size.height)" }

    static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
