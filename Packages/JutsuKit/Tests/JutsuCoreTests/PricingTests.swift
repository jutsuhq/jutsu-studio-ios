import Foundation
import Testing

@testable import JutsuCore

/// Rounds up, ignoring float noise, and clamps the durations that can't be converted instead of trapping.
@Test(arguments: [
    (8.1, 9), (12.000_000_1, 12), (11.999_999_9, 12), (0, 0), (.nan, 0), (.infinity, Int.max),
])
func billedSecondsRoundUp(duration: TimeInterval, expected: Int) {
    #expect(Pricing.billedSeconds(duration) == expected)
}

@Test func bundledRatesAreExactDecimals() throws {
    let pricing = try Pricing.bundled()
    for mode in Mode.allCases where VideoModel.genjutsu.serves(mode) {
        #expect(try pricing.rate(for: makeSpec(mode: mode, resolution: .p480)) == Decimal(string: "0.318"))
        #expect(try pricing.rate(for: makeSpec(mode: mode, resolution: .p720)) == Decimal(string: "0.681"))
        #expect(try pricing.rate(for: makeSpec(mode: mode, resolution: .p1080)) == Decimal(string: "1.632"))
    }
}

/// Seedance's list price is per second of output, and a source clip is billed as input too, at 0.6 of the rate for
/// both: 1.2 times the rate. Kling's quality is its endpoint: Standard below 1080p, Pro at 1080p.
@Test(arguments: [
    (VideoModel.seedance25, true, true, Resolution.p1080, "1.36464"),
    (.klingMotionControl, true, true, .p1080, "0.168"),
])
func otherModelsArePricedByTheirEndpoint(
    model: VideoModel, hasSource: Bool, hasReferences: Bool, resolution: Resolution, rate: String
) throws {
    let pricing = try Pricing.bundled()
    #expect(
        try pricing.rate(
            model: model, mode: .motionTransfer, resolution: resolution, hasSource: hasSource,
            hasReferences: hasReferences) == Decimal(string: rate))
}

@Test func costIsBilledSecondsTimesRate() throws {
    let pricing = try Pricing.bundled()
    #expect(
        try pricing.cost(for: makeSpec(duration: 12, resolution: .p480))
            == .usd(Decimal(string: "3.816")!, isEstimate: false))
    #expect(
        try pricing.cost(for: makeSpec(duration: 8.1, resolution: .p720))
            == .usd(Decimal(string: "6.129")!, isEstimate: false))
    #expect(
        try pricing.cost(for: makeSpec(mode: .objectSwap, duration: 30, resolution: .p1080))
            == .usd(Decimal(string: "48.96")!, isEstimate: false))
}

/// open.higgsfield.ai: Edit and Extend need a video input and bill the input and generated seconds alike at 0.6 of
/// the rate. Edit's output is as long as its source, so it costs 1.2 times the rate per second of source; Extend
/// pays 0.6 times for the source selection plus the part it adds.
@Test func editIsBilledOnTheSourceAndExtendOnTheSourceAndTheAddedPart() throws {
    let pricing = try Pricing.bundled()
    var edit = makeSpec(mode: .edit, duration: 8, resolution: .p720)
    edit.model = .seedance25
    var extend = makeSpec(mode: .extend, duration: 8, resolution: .p720)
    extend.model = .seedance25
    extend.length = 5

    #expect(Pricing.billedSeconds(for: edit) == 8)
    #expect(Pricing.billedSeconds(for: extend) == 13)
    #expect(try pricing.cost(for: edit) == .usd(Decimal(string: "4.43712")!, isEstimate: true))
    #expect(try pricing.cost(for: extend) == .usd(Decimal(string: "3.60516")!, isEstimate: true))
    #expect(try pricing.rate(for: extend) == Decimal(string: "0.27732"))
}

@Test func missingRateIsRejectedAtLoad() {
    let json = #"{"models": {"higgsfield/genjutsu/motion-transfer/v1.0": {"480p": 0.318}}}"#
    #expect(throws: Pricing.LoadError.missingRate("higgsfield/genjutsu/motion-transfer/v1.0", .p720)) {
        try Pricing(data: Data(json.utf8))
    }
}

/// Each tariff is priced above $0, or listed as unpriced (`null`) where no page states its rate.
@Test func bundledPricingCoversEveryTariffAndResolution() throws {
    let pricing = try Pricing.bundled()
    for (tariff, resolution) in Pricing.tariffs {
        if pricing.unpriced.contains(Pricing.TariffKey(tariff, resolution)) { continue }
        #expect(try #require(pricing.rates[tariff]?[resolution]) > 0, "\(tariff) \(resolution)")
    }
}

/// A `null` rate loads as unpriced: the job's list price is `Cost.unknownUSD`, never $0, and the rate throws.
@Test func anUnpricedRateIsUnknownNotFree() throws {
    let pricing = try Pricing.bundled()
    let edit = try #require(VideoModel(rawValue: "klingO3VideoEdit"))
    let spec = JobSpec(
        mode: .edit, model: edit,
        source: SourceClip(
            fileURL: URL(fileURLWithPath: "/tmp/in.mp4"), duration: 30,
            pixelSize: PixelSize(width: 1280, height: 720), range: 0...5),
        prompt: "dance", resolution: .p1080)
    #expect(try pricing.cost(for: spec) == .unknownUSD)
    #expect(throws: Pricing.LoadError.unpricedRate("kling-video/o3/video-edit", .p1080)) {
        try pricing.rate(for: spec)
    }
    let json = #"{"models": {"higgsfield/genjutsu/motion-transfer/v1.0": {"480p": null}}}"#
    #expect(throws: Pricing.LoadError.missingRate("higgsfield/genjutsu/motion-transfer/v1.0", .p720)) {
        try Pricing(data: Data(json.utf8))
    }
}

/// `{"upTo": rate}` loads as that rate, marked as the top of a range: always an estimate, even on a model whose list
/// price is otherwise exact.
@Test func anUpperBoundLoadsAsAnEstimate() throws {
    let url = try #require(JutsuCoreResources.pricingURL)
    var file = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    var models = try #require(file["models"] as? [String: Any])
    models["higgsfield/genjutsu/motion-transfer/v1.0"] = ["480p": ["upTo": 0.5], "720p": 0.681, "1080p": 1.632]
    file["models"] = models
    let pricing = try Pricing(data: JSONSerialization.data(withJSONObject: file))

    let spec = makeSpec(duration: 10, resolution: .p480)
    #expect(pricing.isUpperBound(for: spec))
    #expect(try pricing.rate(for: spec) == Decimal(string: "0.5"))
    #expect(try pricing.cost(for: spec) == .usd(5, isEstimate: true))
    let exact = makeSpec(duration: 10, resolution: .p720)
    #expect(!pricing.isUpperBound(for: exact))
    #expect(try pricing.cost(for: exact) == .usd(Decimal(string: "6.81") ?? 0, isEstimate: false))
}

/// open.higgsfield.ai prices `image-to-video` like a clip without video input: images aren't billed as video.
@Test func framesArePricedAsAClipWithoutVideoInput() throws {
    let pricing = try Pricing.bundled()
    let frames = [LocalImage(fileURL: URL(fileURLWithPath: "/tmp/start.png"))]
    let spec = JobSpec(
        mode: .motionTransfer, model: .seedance25, source: nil, references: frames, resolution: .p1080, length: 8,
        referencesAreFrames: true)
    let tariff = Pricing.tariffID(
        model: .seedance25, mode: .motionTransfer, resolution: .p1080, hasSource: false, hasReferences: true,
        usesFrames: true)
    #expect(tariff == "bytedance/seedance-2.5/image-to-video")
    #expect(try pricing.rate(for: spec) == Decimal(string: "1.1372"))
    #expect(try pricing.cost(for: spec) == .usd(Decimal(string: "9.0976") ?? 0, isEstimate: true))
}
