import Foundation
import JutsuCore

/// What the library grid shows: videos, images, or both, interleaved by date. The tab row carrying it sits
/// between the origin switch and the filter bar, stronger than the filters and weaker than the origin.
public enum LibraryKind: String, Sendable, Hashable, CaseIterable, Identifiable {
    case all
    case video
    case image

    public var id: Self { self }

    public var title: String {
        switch self {
        case .all: String(localized: "All", bundle: .module)
        case .video: String(localized: "Videos", bundle: .module)
        case .image: String(localized: "Images", bundle: .module)
        }
    }
}

/// One row of the unified library grid: a video result, an image made on this device, or an image still only on
/// the Higgsfield account. Videos and images share the grid, the search and the sort; each kind keeps its own
/// filters, and a filter that doesn't apply to the current kind is hidden rather than left without effect.
public enum LibraryMediaItem: Sendable, Hashable, Identifiable {
    case video(LibraryItemModel)
    /// An image Generate… made, saved in the output folder.
    case localImage(SavedImage)
    /// A finished image generation from the account's history; its file downloads on demand.
    case remoteImage(HistoryImageItem)

    public var id: UUID {
        switch self {
        case .video(let item): item.id
        case .localImage(let image): image.id
        case .remoteImage(let image): image.jobID
        }
    }

    public var isVideo: Bool {
        switch self {
        case .video: true
        case .localImage, .remoteImage: false
        }
    }

    /// Newest first in the grid: when a video finished for videos, when an image was made for images.
    public var createdAt: Date {
        switch self {
        case .video(let item): item.finishedAt
        case .localImage(let image): image.createdAt
        case .remoteImage(let image): image.createdAt
        }
    }

    /// Starred here, or liked on Higgsfield: the star and the like are one.
    public var isStarred: Bool {
        switch self {
        case .video(let item): item.isStarred
        case .localImage(let image): image.isStarred
        case .remoteImage(let image): image.isLiked
        }
    }

    /// What the search looks through: the prompt and the model for images, the video's own text for videos.
    public var searchText: String {
        switch self {
        case .video(let item): "\(item.spec.prompt) \(item.title)"
        case .localImage(let image): "\(image.prompt) \(image.model)"
        case .remoteImage(let image): "\(image.prompt) \(image.model)"
        }
    }

    /// The model menu value: the video model for videos, the image model's name for images.
    public var imageModel: String? {
        switch self {
        case .video: nil
        case .localImage(let image): image.model
        case .remoteImage(let image): image.model
        }
    }

    /// "16:9" for images; `nil` for videos and when unknown.
    public var aspectRatio: String? {
        switch self {
        case .video: nil
        // Saved before labels were rounded, a stored ratio can still be "73:55".
        case .localImage(let image): image.aspectRatio.map(PixelSize.aspectLabel(of:))
        case .remoteImage(let image): image.aspectRatio
        }
    }
}

/// How many rows each kind tab holds, after every filter but the kind itself: the tabs always match the grid.
public struct LibraryKindCounts: Sendable, Hashable {
    public var videos: Int
    public var images: Int

    public init(videos: Int, images: Int) {
        self.videos = videos
        self.images = images
    }

    public var all: Int { videos + images }

    public func count(for kind: LibraryKind) -> Int {
        switch kind {
        case .all: all
        case .video: videos
        case .image: images
        }
    }
}
