import Foundation

/// A provider whose account likes its generations; the library's star follows the like.
public protocol GenerationLikes: Sendable {
    /// Sets the like of the generation `RemoteJob.requestID` names; setting the state it has is harmless.
    func setLiked(_ requestID: String, _ isLiked: Bool) async throws
}

/// A provider whose account keeps the files uploaded to it, to start new jobs from.
public protocol AccountUploads: Sendable {
    /// One page of `kind`, newest first; `nil` for the first page.
    func uploads(_ kind: UploadKind, after cursor: HistoryCursor?) async throws -> UploadPage
}

public enum UploadKind: String, Sendable, Hashable, CaseIterable {
    case image
    case video
}

/// A file the account uploaded, downloadable while the provider keeps it.
public struct UploadedFile: Sendable, Hashable, Identifiable {
    /// The provider's media ID.
    public var id: String
    public var kind: UploadKind
    /// The provider's preview, which may be smaller than the file (`fileURL`).
    public var url: URL
    /// The full-resolution file when `url` is a smaller preview.
    public var originalURL: URL?
    /// A smaller preview, for videos and some images.
    public var thumbnailURL: URL?
    public var pixelSize: PixelSize?
    /// Videos only, in seconds.
    public var duration: TimeInterval?
    public var createdAt: Date

    public init(
        id: String, kind: UploadKind, url: URL, originalURL: URL? = nil, thumbnailURL: URL? = nil,
        pixelSize: PixelSize? = nil, duration: TimeInterval? = nil, createdAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.url = url
        self.originalURL = originalURL
        self.thumbnailURL = thumbnailURL
        self.pixelSize = pixelSize
        self.duration = duration
        self.createdAt = createdAt
    }

    /// What to download: the full-resolution file, else the link listed.
    public var fileURL: URL { originalURL ?? url }

    /// What a grid shows: the smaller preview when there is one.
    public var previewURL: URL { thumbnailURL ?? url }
}

public struct UploadPage: Sendable, Hashable {
    public var items: [UploadedFile]
    /// `nil` on the last page.
    public var nextCursor: HistoryCursor?

    public init(items: [UploadedFile], nextCursor: HistoryCursor?) {
        self.items = items
        self.nextCursor = nextCursor
    }
}
