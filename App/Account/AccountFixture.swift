import JutsuCore
import Presentation
import SwiftUI

/// Sample data for Account and Spending without a Higgsfield sign-in, for screenshots: launch a Debug build with
/// `-debug.sampleAccount YES`; add `-debug.imageSide YES` to open Create on its Image side, `-debug.sourceVideo`,
/// `-debug.prompt`, `-debug.reference` or `-debug.sampleQueue YES`. Always `nil` in Release.
enum AccountFixture {
    static var state: ConnectionState? {
        guard isOn else { return nil }
        return .account(AccountInfo(email: "studio@example.com", name: "Studio", plan: "Ultimate", credits: 2524))
    }

    static var capabilities: Capabilities? {
        guard isOn else { return nil }
        return Capabilities(
            modes: Set(Mode.allCases), resolutions: [.p480, .p720], costUnit: .credits, maxConcurrency: 4,
            unlimited: [.genjutsu: [.motionTransfer], .klingMotionControl: [.motionTransfer]])
    }

    /// Three of the account's image models as the catalog of 2026-10-28 lists them.
    static var imageModels: [ImageModel]? {
        guard isOn else { return nil }
        let ratios = ["auto", "1:1", "3:2", "2:3", "4:3", "3:4", "4:5", "5:4", "9:16", "16:9", "21:9"]
        return [
            ImageModel(
                id: "nano_banana_pro", title: "Nano Banana Pro", variantCounts: [1, 2, 3, 4], aspectRatios: ratios,
                input: .optional, unstatedInputLimit: ImageModel.inputBound,
                settings: [ImageModel.Setting(name: "resolution", options: ["1k", "2k", "4k"], defaultValue: "2k")]),
            ImageModel(
                id: "soul_2", title: "Higgsfield Soul 2.0", variantCounts: [1, 2, 3, 4],
                aspectRatios: ["1:1", "16:9", "9:16", "4:3", "3:4", "3:2", "2:3"], input: .optional, maxInputs: 1,
                settings: [ImageModel.Setting(name: "quality", options: ["1.5k", "2k"], defaultValue: "2k")]),
            ImageModel(
                id: "gpt_image_2", title: "GPT Image 2", variantCounts: [1, 2, 3, 4],
                aspectRatios: ["1:1", "4:3", "3:4", "16:9", "21:9", "9:16", "3:2", "2:3"], input: .optional,
                settings: [
                    ImageModel.Setting(name: "resolution", options: ["1k", "2k", "4k"], defaultValue: "1k"),
                    ImageModel.Setting(name: "quality", options: ["low", "medium", "high"], defaultValue: "low"),
                ]),
        ]
    }

    /// A video file Create opens with as its source: `-debug.sourceVideo /path/clip.mp4`.
    static var sourceVideo: URL? {
        guard isOn, let path = UserDefaults.standard.string(forKey: "debug.sourceVideo") else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Create opens on its Image side.
    static var opensImageSide: Bool { isOn && UserDefaults.standard.bool(forKey: "debug.imageSide") }

    /// An image Create's video side opens with as its reference: `-debug.reference /path/image.jpg`.
    static var reference: URL? {
        guard isOn, let path = UserDefaults.standard.string(forKey: "debug.reference") else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// The prompt both sides of Create open with: `-debug.prompt "…"`.
    static var prompt: String? { isOn ? UserDefaults.standard.string(forKey: "debug.prompt") : nil }

    /// A Queue with takes rendering, waiting and finished: `-debug.sampleQueue YES`, with the clips in
    /// Documents/SampleHistory as their sources.
    private struct SampleJob {
        let model: VideoModel
        let mode: Mode
        let prompt: String
        let state: JobState
        let progress: Double
    }

    static func sampleJobs(in documents: URL) -> [Job] {
        guard isOn, UserDefaults.standard.bool(forKey: "debug.sampleQueue") else { return [] }
        let folder = documents.appending(path: "SampleHistory", directoryHint: .isDirectory)
        let samples = [
            SampleJob(
                model: .seedance25, mode: .motionTransfer,
                prompt: "A fairy in a smoky studio, light beam from the top left", state: .processing, progress: 0.68),
            SampleJob(
                model: .genjutsu, mode: .restyle, prompt: "Angel photoshoot, white feathers, haze", state: .processing,
                progress: 0.31),
            SampleJob(
                model: .klingMotionControl, mode: .motionTransfer, prompt: "Runway walk in an old ballroom",
                state: .queued, progress: 0),
            SampleJob(
                model: .seedance25, mode: .objectSwap, prompt: "Swap the dress for silver sequins", state: .done,
                progress: 1),
            SampleJob(
                model: .genjutsu, mode: .motionTransfer, prompt: "Night street, two friends dancing", state: .done,
                progress: 1),
        ]
        return samples.enumerated().map { index, sample in
            let (model, mode, prompt, state) = (sample.model, sample.mode, sample.prompt, sample.state)
            let file = folder.appending(path: String(format: "%02d.mp4", index + 1))
            let source = SourceClip(
                fileURL: file, duration: 6, pixelSize: PixelSize(width: 720, height: 1280), range: 0...6)
            let spec = JobSpec(
                mode: mode, model: model, source: source, prompt: prompt, resolution: .p720,
                title: ["Fairy shoot", "Angel wings", "Ballroom runway", "Silver dress", "Night dance"][index])
            let started = Date.now.addingTimeInterval(-Double(index + 1) * 140)
            var job = Job(
                spec: spec, providerKind: .account, cost: .credits(Decimal(6 + index * 2), isEstimate: false),
                createdAt: started)
            job.state = state
            job.progress = sample.progress
            job.submittedAt = started
            if state == .processing { job.processingAt = started.addingTimeInterval(20) }
            if state == .done {
                job.finishedAt = started.addingTimeInterval(110)
                job.outputFile = file
            }
            return job
        }
    }

    static func spending(for period: SpendingPeriod) -> SpendingSummary? {
        guard isOn else { return nil }
        var summary = SpendingSummary([], period: period, now: .now)
        let days = Decimal(period == .today ? 1 : period == .week ? 7 : 30)
        summary.charged = SpendTotal(credits: 184 * days)
        summary.chargedJobs = 6 * Int(truncating: days as NSDecimalNumber)
        return summary
    }

    private static var isOn: Bool {
        #if DEBUG
            UserDefaults.standard.bool(forKey: "debug.sampleAccount")
        #else
            false
        #endif
    }
}
