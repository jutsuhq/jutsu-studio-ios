import Foundation
import JutsuCore

extension Job {
    /// How long Higgsfield keeps a native draft finalizable: "a 480p draft that can be finalized within seven days"
    /// (`models_explore get` of `seedance_2_5`).
    static let finalizeWindow: TimeInterval = 7 * 24 * 60 * 60

    /// When this native Seedance draft of the account (`RemoteJob.isNativeDraft`) stops being finalizable: seven days
    /// after Higgsfield completed it (`chargedAt`, else when the job finished here). `nil` for any other job.
    public var finalizeDeadline: Date? {
        guard spec.isDraft, providerKind == .account, state == .done, remote?.isNativeDraft == true,
            let completed = chargedAt ?? finishedAt
        else { return nil }
        return completed.addingTimeInterval(Self.finalizeWindow)
    }

    /// Finalize in 1080p: the draft's final, made by Higgsfield from the draft itself (`JobSpec.draftJobID`) rather
    /// than from its inputs again, for a third of a fresh 1080p render. It keeps the draft's inputs for the library
    /// and uploads nothing. `nil` unless this is a native draft that the signed-in account (`owner`) made and its
    /// seven days (`finalizeDeadline`) haven't passed at `now`.
    public func finalizeSpec(owner: String?, now: Date = Date()) -> JobSpec? {
        guard let deadline = finalizeDeadline, now < deadline, let owner, self.owner == owner,
            let draftJobID = remote?.requestID
        else { return nil }
        var final = spec
        final.resolution = .p1080
        final.isDraft = false
        final.variants = 1
        final.usesUnlimited = false
        final.draftJobID = draftJobID
        return final
    }
}
