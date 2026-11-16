import Foundation
import HiggsfieldAPI
import HiggsfieldMCP
import HiggsfieldTestSupport
import JutsuCore
import Testing

@testable import HiggsfieldProviders

extension Network {
    /// Genjutsu Lite: Genjutsu's Motion Transfer and Object Swap on Wan 3.0, as `generate_video` models of
    /// their own. Its REST schema isn't published, so an API key doesn't run it.
    @Suite struct GenjutsuLite {
        static let lite = VideoModel(rawValue: "genjutsuLite") ?? .genjutsu

        static func spec(_ mode: Mode, seconds: TimeInterval = 12, resolution: Resolution = .p720) -> JobSpec {
            JobSpec(
                mode: mode, model: lite,
                source: SourceClip(
                    fileURL: URL(fileURLWithPath: "/tmp/in.mov"), duration: 30,
                    pixelSize: PixelSize(width: 1280, height: 720), range: 0...seconds),
                references: [LocalImage(fileURL: URL(fileURLWithPath: "/tmp/a.jpg"))], prompt: "make it rain",
                resolution: resolution)
        }

        /// The live catalog's answer states no length, so the catalog's 15 s stands; a longer selection is refused.
        @Test func aSelectionPast15SecondsIsRefused() async throws {
            let motion = try CatalogSnapshot.model("hf_mult_motion_control_flash")
            let swap = try CatalogSnapshot.model("hf_mult_replace_object_flash")
            let (provider, _) = ProviderConstraints.provider(tools: Provider.fullSet + [ProviderConstraints.explore]) {
                _, arguments in
                switch arguments["model_id"]?.stringValue {
                case "hf_mult_motion_control_flash": motion
                case "hf_mult_replace_object_flash": swap
                default: [:]
                }
            }
            let table = try #require(try await provider.modelConstraints())
            #expect(table[Self.lite, .motionTransfer] == ModelConstraints())
            #expect(Self.lite.limits(for: .motionTransfer, constraints: table).duration == 4...15)
            #expect(Validation.check(Self.spec(.motionTransfer, seconds: 15), constraints: table).isEmpty)
            #expect(
                Validation.check(Self.spec(.motionTransfer, seconds: 20), constraints: table) == [.durationTooLong(20)])
            #expect(Validation.check(Self.spec(.objectSwap, seconds: 20), constraints: table) == [.durationTooLong(20)])
        }
    }
}
