import Foundation
import Testing

@testable import JutsuCore

/// An estimate of nothing is a price, not an unknown one; an unknown price stored as one before reads as unknown.
@Test func anUnknownPriceIsNotAnEstimateOfNothing() throws {
    let zero = Cost.credits(0, isEstimate: true)
    #expect(!zero.isUnknownPrice && Cost.unknownCredits.isUnknownPrice && Cost.unknownUSD.unit == .usd)
    #expect(Budget.allows(cost: zero, committedToday: 0, cap: .credits(10)) == .allowed)
    #expect(Budget.allows(cost: .unknownCredits, committedToday: 0, cap: .credits(10)) != .allowed)
    for cost in [zero, .usd(0, isEstimate: true), .unknownCredits, .unknownUSD] {
        #expect(try JSONDecoder().decode(Cost.self, from: JSONEncoder().encode(cost)) == cost)
    }
    let stored = #"{"credits":{"_0":0,"isEstimate":true}}"#
    #expect(try JSONDecoder().decode(Cost.self, from: Data(stored.utf8)) == .unknownCredits)
}

/// Edit and Extend have their own Seedance endpoints whatever the media, and Extend's length is the part it adds.
@Test func editAndExtendRunOnTheirOwnEndpoints() {
    let source = SourceClip(
        fileURL: URL(fileURLWithPath: "/tmp/in.mp4"), duration: 10, pixelSize: PixelSize(width: 1280, height: 720),
        range: 2...10)
    let edit = JobSpec(mode: .edit, model: .seedance25, source: source, prompt: "night", resolution: .p720)
    let extend = JobSpec(
        mode: .extend, model: .seedance25, source: source, prompt: "she leaves", resolution: .p720, length: 6)

    #expect(edit.endpointID == "bytedance/seedance-2.5/video-edit")
    #expect(extend.endpointID == "bytedance/seedance-2.5/video-extend")
    #expect(edit.duration == 8)
    #expect(extend.duration == 6)
    #expect(extend.limits().duration == 4...30)
}
