import Foundation
import HiggsfieldAPI
import HiggsfieldMCP
import HiggsfieldTestSupport
import JutsuCore
import Testing

@testable import HiggsfieldProviders

extension Network {
    /// Kling 4.0 on both connections: REST's four endpoints from their documented schemas (open.higgsfield.ai,
    /// 2026-10-28) and `kling4_0`'s `mode`s against its `models_explore get` in the catalog snapshot.
    @Suite struct Kling4 {
        static let model = VideoModel(rawValue: "kling40")

        static func kling() throws -> VideoModel { try #require(model) }

        /// A clip from a prompt alone, or from images when there are some.
        static func clip(
            images: Int = 0, prompt: String = "a fox in the snow", seconds: TimeInterval = 12,
            resolution: Resolution = .p1080, aspectRatio: AspectRatio? = .portrait
        ) throws -> JobSpec {
            JobSpec(
                mode: .motionTransfer, model: try kling(), source: nil,
                references: Array(repeating: LocalImage(fileURL: URL(fileURLWithPath: "/tmp/ref.png")), count: images),
                prompt: prompt, resolution: resolution, length: seconds, aspectRatio: aspectRatio)
        }

        /// A clip from a start frame and, with two images, an end frame.
        static func frames(_ count: Int = 2, prompt: String = "") throws -> JobSpec {
            var spec = try clip(images: count, prompt: prompt, seconds: 5, resolution: .p720)
            spec.referencesAreFrames = true
            return spec
        }

        /// A job on a source: its references (Motion Transfer) or an Edit of it.
        static func onSource(
            mode: Mode = .motionTransfer, seconds: TimeInterval = 10, images: Int = 1, prompt: String = "make it rain"
        ) throws -> JobSpec {
            JobSpec(
                mode: mode, model: try kling(),
                source: SourceClip(
                    fileURL: URL(fileURLWithPath: "/tmp/in.mp4"), duration: 60,
                    pixelSize: PixelSize(width: 1280, height: 720), range: 0...seconds),
                references: Array(repeating: LocalImage(fileURL: URL(fileURLWithPath: "/tmp/ref.png")), count: images),
                prompt: prompt, resolution: .p720)
        }

        /// On the account: 5 credits a second at 720p and 7.5 at 1080p, Higgsfield's announced price, until a quote;
        /// with a source video (references or Edit) 1.2 times that, as REST bills the input video too.
        @Test func theAccountEstimatesFromTheAnnouncedPrice() throws {
            var spec = try Self.clip(seconds: 10)
            #expect(AccountModel.estimatedCredits(for: spec) == 75)
            spec.length = 45
            #expect(AccountModel.estimatedCredits(for: spec) == 225)
            var images = try Self.clip(images: 2, seconds: 10)
            images.resolution = .p720
            #expect(AccountModel.estimatedCredits(for: images) == 50)
            #expect(AccountModel.estimatedCredits(for: try Self.frames()) == 25)

            // Never below the announced rate times REST's ratio with an input video to without (10 s here).
            var reference = try Self.onSource()
            let at720 = try #require(AccountModel.estimatedCredits(for: reference))
            #expect(at720 == 60 && Double(at720) >= 5 * 10 * 0.188 / 0.157)
            reference.resolution = .p1080
            let at1080 = try #require(AccountModel.estimatedCredits(for: reference))
            #expect(at1080 == 90 && Double(at1080) >= (7.5 * 10 * 0.282 / 0.235).rounded())
            var edit = try Self.onSource(mode: .edit, seconds: 12)
            #expect(AccountModel.estimatedCredits(for: edit) == 72)
            edit.resolution = .p1080
            #expect(AccountModel.estimatedCredits(for: edit) == 108)
        }
    }
}
