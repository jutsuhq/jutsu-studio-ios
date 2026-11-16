import Foundation
import HiggsfieldCore
import HiggsfieldMCP
import HiggsfieldTestSupport
import JutsuCore
import Testing

@testable import HiggsfieldProviders

extension Network {
    /// The operations on a result on the account, with the tool definitions of the catalog snapshot of
    /// 2026-10-15; every call is checked against its `inputSchema`.
    @Suite struct PostOperations {
        static let tools =
            Provider.fullSet
            + ["upscale_video", "remove_background", "reframe", "dubbing", "voice_change", "list_voices"].map {
                (try? CatalogSnapshot.tool($0)) ?? [:]
            }

        static func spec(
            _ action: PostAction, jobID: String? = "3f1c8a52-6b0e-4d7a-9a51-2f4b8c9d0e17", seconds: TimeInterval = 10
        ) -> JobSpec {
            var spec = Provider.spec(.motionTransfer)
            spec.source?.range = 0...seconds
            spec.operation = PostOperation(action: action, sourceJobID: jobID)
            return spec
        }

        static let upscale = PostAction.upscale(UpscaleOptions(target: .k4, frameRate: .fps60, engine: .standard))
        static let noInputs = RemoteInputs(video: nil, images: [])

        static func provider(
            call: @escaping @Sendable (String, JSONValue) -> JSONValue = { _, _ in [:] }
        ) -> (HiggsfieldMCPProvider, StubServer) {
            Provider.provider(tools: tools, call: call)
        }

        static func params(_ stub: StubServer) -> [JSONValue?] {
            Provider.calls(stub).map { $0["arguments"]?["params"] }
        }

        /// Quoted through `generate_video` by the result's length, resolution and frame rate.
        @Test func upscaleNamesTheResultByItsJobIDAndIsQuotedByItsLength() async throws {
            let (provider, stub) = Self.provider { name, _ in
                name == "upscale_video"
                    ? ["results": [["id": "job-2"]], "request_id": "req-2"] : ["cost": ["credits": 15]]
            }
            let spec = Self.spec(Self.upscale)

            #expect(try await provider.estimate(spec) == .credits(15, isEstimate: true))
            #expect(try await provider.serverEstimate(spec, inputs: Self.noInputs) == .credits(15, isEstimate: false))
            #expect(try await provider.submitIsIdempotent(spec) == false)
            let remote = try await provider.submit(spec, inputs: Self.noInputs, idempotencyKey: UUID())

            #expect(remote.requestID == "job-2")
            #expect(remote.correlationID == "req-2")
            #expect(Provider.calls(stub).map { $0["name"] } == ["generate_video", "generate_video", "upscale_video"])
            let quote: JSONValue = [
                "model": "bytedance_video_upscale", "get_cost": true, "duration": 10, "resolution": "4k", "fps": 60,
            ]
            #expect(
                Self.params(stub) == [
                    quote, quote,
                    [
                        "video_id": "3f1c8a52-6b0e-4d7a-9a51-2f4b8c9d0e17", "provider": "bytedance", "resolution": "4k",
                        "fps": 60, "width": 1280,
                        "height": 720,
                    ],
                ])
        }

        /// The allowance pays for the Motion Transfer itself, never for an operation on its result.
        @Test func anOperationIsNeverPaidFromTheUnlimitedAllowance() async throws {
            let (provider, _) = ProviderUnlimited.provider()
            _ = try await provider.capabilities()
            #expect(await provider.paysUnlimited(ProviderUnlimited.spec(.motionTransfer)))
            #expect(await provider.paysUnlimited(Self.spec(Self.upscale)) == false)
        }

        @Test func aLostAnswerMayHaveStartedTheOperation() async throws {
            let (provider, _) = Self.provider { _, _ in ["ok": true] }
            await #expect(throws: ProviderError.outcomeUnknown) {
                try await provider.submit(Self.spec(Self.upscale), inputs: Self.noInputs, idempotencyKey: UUID())
            }
        }
    }
}
