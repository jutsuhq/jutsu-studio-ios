import Foundation
import HiggsfieldMCP
import HiggsfieldTestSupport
import JutsuCore
import Testing

@testable import HiggsfieldProviders

extension Network {
    /// The account models added from the catalog snapshot of 2026-10-28 (`docs/mcp-parity.md`): each request keeps to
    /// its model's `models_explore get` and sends exactly the fields the shape maps.
    @Suite struct MoreAccountModels {
        static func spec(_ id: String, mode: Mode = .motionTransfer, images: Int = 1) throws -> JobSpec {
            JobSpec(
                mode: mode, model: try #require(VideoModel(rawValue: id)),
                source: SourceClip(
                    fileURL: URL(fileURLWithPath: "/tmp/in.mp4"), duration: 30,
                    pixelSize: PixelSize(width: 1280, height: 720), range: 0...10),
                references: Array(repeating: LocalImage(fileURL: URL(fileURLWithPath: "/tmp/a.jpg")), count: images),
                prompt: "make it rain", resolution: .p720, audio: .generated, bitrate: .high)
        }

        static func sentParams(_ spec: JobSpec) async throws -> JSONValue {
            let (provider, stub) = Provider.provider(tools: Provider.fullSet) { _, _ in
                ["results": [["id": "job-1", "status": "queued"]]]
            }
            let inputs = RemoteInputs(
                video: Provider.inputs.video, images: spec.references.isEmpty ? [] : Provider.inputs.images)
            _ = try await provider.submit(spec, inputs: inputs, idempotencyKey: UUID())
            return try #require(Provider.calls(stub).first?["arguments"]?["params"])
        }

        static let references: JSONValue = [
            ["role": "video_references", "value": "video-1"], ["role": "image_references", "value": "image-1"],
        ]

        @Test(arguments: [
            ("seedance20Reference", "seedance_2_0", "720p"),
            ("seedance20MiniReference", "seedance_2_0_mini", "720p"),
        ])
        func seedance20SendsReferencesWithoutAMode(id: String, model: String, resolution: String) async throws {
            let params = try await Self.sentParams(try Self.spec(id))
            #expect(try CatalogSnapshot.violations(ofParams: params).isEmpty)
            #expect(
                params == [
                    "model": .string(model), "medias": Self.references, "prompt": "make it rain",
                    "resolution": .string(resolution), "duration": 10, "generate_audio": true,
                    "bitrate_mode": "high", "use_unlim": false,
                ])
        }

        @Test func cinemaStudio35SendsTheLengthAndTheSoundtrack() async throws {
            let params = try await Self.sentParams(try Self.spec("cinemaStudio35"))
            #expect(try CatalogSnapshot.violations(ofParams: params).isEmpty)
            #expect(
                params == [
                    "model": "cinematic_studio_video_3_5", "medias": Self.references, "prompt": "make it rain",
                    "resolution": "720p", "duration": 10, "generate_audio": true, "use_unlim": false,
                ])
        }

        /// The schema takes nothing but the clip: no length, resolution or images. Billed by the clip, 1 a second.
        @Test func flux3EditSendsOnlyTheClipAndThePrompt() async throws {
            let spec = try Self.spec("flux3VideoEdit", mode: .edit, images: 0)
            let params = try await Self.sentParams(spec)
            #expect(try CatalogSnapshot.violations(ofParams: params).isEmpty)
            #expect(
                params == [
                    "model": "flux_3_video_edit", "medias": [["role": "video_references", "value": "video-1"]],
                    "prompt": "make it rain", "use_unlim": false,
                ])
            #expect(AccountModel.quotesAfterUpload(spec) && AccountModel.estimatedCredits(for: spec) == 10)
            #expect(!Validation.check(try Self.spec("flux3VideoEdit", mode: .edit, images: 1)).isEmpty)
        }

        /// Every image model with frames is offered, the curated families first; a duplicate name only once.
        @Test func everyImageModelIsOffered() {
            let listed = [
                "seedream_v5_pro", "soul_2", "flux_3_image", "soul_v2", "nano_banana_pro", "soul_cinematic",
                "gpt_image_2", "grok_image", "kling_omni_image", "soul_location",
            ].map { AccountImageModel(id: $0, name: $0 == "soul_v2" ? "soul_2" : $0, aspectRatios: ["1:1"]) }
            let offered = AccountImages.models(listed + [AccountImageModel(id: "autosprite", name: "autosprite")])
            #expect(
                offered.map(\.id) == [
                    "soul_2", "nano_banana_pro", "soul_cinematic", "gpt_image_2", "grok_image", "soul_location",
                    "seedream_v5_pro", "flux_3_image", "kling_omni_image",
                ])
        }
    }
}
