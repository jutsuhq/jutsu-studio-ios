import Foundation
import Testing

@testable import JutsuCore

@Test func fadeOutFadesTheResultsOwnAudio() {
    #expect(
        AudioPlan.make(
            option: .fadeOut, sourceRange: 0...5, sourceAudioEnd: 5, resultDuration: 4, resultHasAudio: true)
            == .fadeResult(fadeOut: 3...4))
}

@Test func aShortResultFadesFromItsStart() {
    #expect(
        AudioPlan.make(
            option: .fadeOut, sourceRange: 0...5, sourceAudioEnd: 5, resultDuration: 0.5, resultHasAudio: true)
            == .fadeResult(fadeOut: 0...0.5))
}

@Test func originalKeepsTheResultsOwnAudio() {
    #expect(
        AudioPlan.make(
            option: .original, sourceRange: 0...5, sourceAudioEnd: 5, resultDuration: 4, resultHasAudio: true)
            == .keep)
}
