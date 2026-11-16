import Foundation
import JutsuCore

// Names of JutsuCore values as the UI shows them. JutsuCore has no string catalog, so their text lives here.

extension MotionShelf {
    public var title: String {
        switch self {
        case .featured: "Higgsfield"
        case .trending: String(localized: "Trending", bundle: .module)
        case .new: String(localized: "New", bundle: .module)
        case .uploads: String(localized: "Your Uploads", bundle: .module)
        }
    }
}

extension Rejection {
    /// "Rejected: …", for the queue row and notifications.
    public var title: String {
        switch self {
        case .explicitContent: String(localized: "Rejected as explicit content", bundle: .module)
        case .protectedContent:
            String(localized: "Rejected: a recognizable person or protected content", bundle: .module)
        }
    }
}

extension AspectRatio {
    public var title: String { self == .auto ? String(localized: "Auto", bundle: .module) : rawValue }
}
