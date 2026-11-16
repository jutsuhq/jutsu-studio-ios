import Foundation
import JutsuCore

enum AppTab: String, Hashable {
    case create, queue, library
}

/// Where a window goes: the selected tab, and the one request a tab takes in when it shows. Every route is set here
/// and consumed once by the screen it is for, so no two views race to clear it. One per window; the app's own
/// (`AppEnvironment.navigation`) only holds what a notification asks for, until a window takes it.
@Observable
final class NavigationModel {
    enum CreateRequest: Hashable {
        /// Edit Inputs from the Queue or Library: Create opens on the job's spec.
        case editInputs(Job)
        /// Use as Reference from Library › Images.
        case useReference(LocalImage)
    }

    var tab = AppTab.create
    private(set) var createRequest: CreateRequest?
    /// A take a notification asked to show.
    private(set) var openedTake: UUID?

    func editInputs(_ job: Job) {
        createRequest = .editInputs(job)
        tab = .create
    }

    func useReference(_ image: LocalImage) {
        createRequest = .useReference(image)
        tab = .create
    }

    func openTake(_ id: UUID) {
        openedTake = id
        tab = .library
    }

    func show(_ screen: JutsuScreen) {
        switch screen {
        case .create: tab = .create
        case .queue: tab = .queue
        case .library: tab = .library
        }
    }

    func takeCreateRequest() -> CreateRequest? {
        defer { createRequest = nil }
        return createRequest
    }

    func takeOpenedTake() -> UUID? {
        defer { openedTake = nil }
        return openedTake
    }
}
