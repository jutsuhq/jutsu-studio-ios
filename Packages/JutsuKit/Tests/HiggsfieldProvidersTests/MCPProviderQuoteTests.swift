import Foundation
import HiggsfieldCore
import HiggsfieldMCP
import HiggsfieldTestSupport
import JutsuCore
import Testing

@testable import HiggsfieldProviders

extension Network {
    /// The price before upload: a model sent a length is quoted with `get_cost` and no media, once per
    /// what the price depends on; a model billed by its source gets the catalog's estimate until it is uploaded.
    @Suite struct ProviderQuotes {
        static let quote: @Sendable (String, JSONValue) -> JSONValue = { _, _ in
            ["cost": ["credits": 35, "credits_exact": .number(35.5)]]
        }

        /// A model `models.json` lists; its absence fails the catalog tests.
        static func model(_ id: String) -> VideoModel { VideoModel(rawValue: id) ?? .genjutsu }

        static func spec(
            _ model: VideoModel, mode: Mode = .motionTransfer, seconds: TimeInterval = 5,
            resolution: Resolution = .p720
        ) -> JobSpec {
            JobSpec(
                mode: mode, model: model,
                source: SourceClip(
                    fileURL: URL(fileURLWithPath: "/tmp/in.mov"), duration: 30,
                    pixelSize: PixelSize(width: 1280, height: 720), range: 0...seconds),
                references: [LocalImage(fileURL: URL(fileURLWithPath: "/tmp/a.jpg"))], prompt: "make it rain",
                resolution: resolution)
        }

        static func quotes(_ stub: StubServer) -> [JSONValue] {
            Provider.calls(stub).filter { $0["name"] == "generate_video" }.compactMap { $0["arguments"]?["params"] }
        }

        /// The estimates of the models billed by their source match the live quotes for a 12 s clip (2026-10-15).
        @Test(arguments: [
            (spec(.genjutsu, seconds: 12, resolution: .p480), 36),
            (spec(.genjutsu, seconds: 12, resolution: .p1080), 240),
            (spec(.seedance25, mode: .edit, seconds: 12, resolution: .p1080), 241),
        ])
        func theEstimateOfASourceBilledModelIsTheLiveRate(spec: JobSpec, credits: Int) {
            #expect(AccountModel.estimatedCredits(for: spec) == credits)
        }

        /// A quote is asked once per model, mode, resolution, length and soundtrack, even while one is out: another
        /// prompt, frame or bitrate reads the same answer, another length asks again.
        @Test func quotesAreKeptByWhatThePriceDependsOn() async throws {
            let (provider, stub) = Provider.provider(tools: Provider.fullSet, call: Self.quote)
            var base = Self.spec(.seedance25)
            base.source = nil
            base.references = []
            base.length = 6
            var otherPrompt = base
            otherPrompt.prompt = "a fox in the snow"
            var otherFrame = base
            otherFrame.aspectRatio = .portrait
            var otherBitrate = base
            otherBitrate.bitrate = .high

            let costs = try await withThrowingTaskGroup(of: Cost.self) { group in
                for spec in [base, otherPrompt, otherFrame, otherBitrate] {
                    group.addTask { try await provider.estimate(spec) }
                }
                return try await group.reduce(into: []) { $0.append($1) }
            }
            #expect(costs.count == 4)
            #expect(costs.allSatisfy { $0 == .credits(35.5, isEstimate: false) })
            #expect(Self.quotes(stub).count == 1)

            var longer = base
            longer.length = 7
            var louder = base
            louder.audio = .mute
            _ = try await provider.estimate(longer)
            _ = try await provider.estimate(louder)
            _ = try await provider.estimate(base)
            #expect(Self.quotes(stub).map { $0["duration"] } == [6, 7, 6])
            #expect(Self.quotes(stub).map { $0["generate_audio"] } == [true, true, false])
        }

        /// A failed quote shows the estimate and isn't kept: the next estimate asks again.
        @Test func aFailedQuoteFallsBackToTheEstimateAndIsAskedAgain() async throws {
            let answers = Answers([[:], ["cost": ["credits": 21]]])
            let (provider, stub) = Provider.provider(tools: Provider.fullSet) { _, _ in answers.next() }
            let spec = Self.spec(.klingMotionControl, seconds: 12)
            #expect(try await provider.estimate(spec) == .credits(21, isEstimate: true))
            #expect(try await provider.estimate(spec) == .credits(21, isEstimate: false))
            #expect(Self.quotes(stub).count == 2)
        }

        /// `count` isn't in the quote (live: 2 quoted the same as 1), so the price is one variant's times the count.
        @Test func variantsMultiplyTheQuote() async throws {
            let (provider, stub) = Provider.provider(tools: Provider.fullSet, call: Self.quote)
            var spec = Self.spec(Self.model("wan30Reference"))
            spec.variants = 3
            #expect(try await provider.estimate(spec) == .credits(106.5, isEstimate: false))
            #expect(Self.quotes(stub).first?["count"] == nil)
        }
    }
}

/// Stub answers in order, the last one repeated.
final class Answers: @unchecked Sendable {
    // @unchecked: `values` is only touched under `lock`.
    private let lock = NSLock()
    private var values: [JSONValue]

    init(_ values: [JSONValue]) {
        self.values = values
    }

    func next() -> JSONValue {
        lock.withLock { values.count > 1 ? values.removeFirst() : values.first ?? [:] }
    }
}
