import Foundation
import JutsuCore

/// A command on one job. A Queue row's buttons, the Queue menu and the job's notification run the same ones.
public enum JobCommand: Sendable, Hashable {
    case cancel
    /// Sends a job that was never charged again, or downloads the paid result of one again.
    case retry
    /// Sends again a job whose last submit may have been charged, once the person agreed to pay again.
    case retryChargingAgain
    /// Polls a job past its deadline again.
    case checkAgain
    case resume
    case runNext
}
