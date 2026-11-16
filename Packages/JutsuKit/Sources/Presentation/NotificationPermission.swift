/// Whether iOS lets the app post notifications, as Settings › Notifications shows it.
public enum NotificationPermission: Equatable, Sendable {
    /// iOS hasn't asked yet; the app asks after the first queued job or when a notification toggle is turned on.
    case notAsked
    case allowed
    /// Turned off in iOS Settings; only the person can turn it back on there.
    case denied

    /// Turning a notification on is the moment to ask, when iOS hasn't yet.
    public func asks(whenTurning isOn: Bool) -> Bool {
        isOn && self == .notAsked
    }
}
