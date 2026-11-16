import Foundation
import HiggsfieldMCP
import HiggsfieldTestSupport
import JutsuCore
import Testing

@testable import HiggsfieldProviders

extension Network {
    /// Seedance 2.5's native draft on the account: Draft at 480p sends `draft: true`, and a finalize
    /// sends only `model`, `draft_job_id`, `resolution` and `use_unlim`, as quoted live on 2026-10-15.
    @Suite struct NativeDraft {
        /// The paid run's draft: 15 s from reference images, 9:16.
        static func draft(resolution: Resolution = .p480) -> JobSpec {
            JobSpec(
                mode: .motionTransfer, model: .seedance25, source: nil,
                references: [Provider.image, Provider.image], prompt: "a fox in the snow", resolution: resolution,
                isDraft: true, length: 15, aspectRatio: .portrait)
        }

        static var finalize: JobSpec {
            var spec = draft()
            spec.isDraft = false
            spec.resolution = .p1080
            spec.draftJobID = "draft-job"
            return spec
        }

        static func params(_ stub: StubServer) -> [JSONValue] {
            Provider.calls(stub).filter { $0["name"] == "generate_video" }.compactMap { $0["arguments"]?["params"] }
        }

        /// Finalize is quoted live before anything runs; a failed quote shows a third of the 1080p rate, as an
        /// estimate (2026-10-15: 80 credits for a 15 s draft, against 240 for a fresh 1080p render).
        @Test func aFinalizeIsQuotedAndFallsBackToAThirdOfTheFreshRate() async throws {
            let (quoted, stub) = Provider.provider(tools: Provider.fullSet) { _, _ in ["cost": ["credits": 80]] }
            #expect(try await quoted.estimate(Self.finalize) == .credits(80, isEstimate: false))
            var quote = Self.params(stub).first?.objectValue ?? [:]
            quote.removeValue(forKey: "get_cost")
            #expect(Set(quote.keys) == ["model", "draft_job_id", "resolution", "use_unlim"])

            let (failing, _) = Provider.provider(tools: Provider.fullSet) { _, _ in [:] }
            #expect(try await failing.estimate(Self.finalize) == .credits(80, isEstimate: true))
            var fresh = Self.finalize
            fresh.draftJobID = nil
            #expect(AccountModel.estimatedCredits(for: fresh) == 240)
        }

        /// Two drafts of the same length don't share a finalize quote.
        @Test func eachDraftsFinalizeIsQuotedOnItsOwn() async throws {
            let (provider, stub) = Provider.provider(tools: Provider.fullSet) { _, _ in ["cost": ["credits": 80]] }
            var other = Self.finalize
            other.draftJobID = "other-draft"
            _ = try await provider.estimate(Self.finalize)
            _ = try await provider.estimate(other)
            #expect(Self.params(stub).map { $0["draft_job_id"] } == ["draft-job", "other-draft"])
        }
    }
}
