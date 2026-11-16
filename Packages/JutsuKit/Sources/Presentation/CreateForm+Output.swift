import Foundation
import JutsuCore

// MARK: Output settings

extension CreateForm {
    /// The whole seconds the dock's Length menu offers for a clip made without a source, inside the model's limits.
    public var lengthChoices: [Int] {
        let range = limits.duration
        let lowest = Int(range.lowerBound.rounded(.up))
        let highest = Int(range.upperBound.rounded(.down))
        return lowest <= highest ? Array(lowest...highest) : [Int(clipLength.rounded())]
    }

    /// The closed Settings row of Create on a phone: what the settings sheet holds, set as it is now. "2 variants ·
    /// 16:9 · High bitrate · Audio: Original". Resolution and length are on the prompt dock's chips, so they aren't
    /// repeated.
    public func outputSummary(in context: CreateContext) -> String {
        var parts: [String] = []
        let variants = variants(in: context)
        if variants > 1 { parts.append(String(localized: "\(variants) variants", bundle: .module)) }
        if isWithoutSource, aspectRatio != .auto { parts.append(aspectRatio.title) }
        if showsBitrate { parts.append(bitrate(on: context.connection.kind).title) }
        if showsCharacterOrientation { parts.append(characterOrientation.title) }
        if showsVideoBackground, keepsVideoBackground {
            parts.append(String(localized: "Video background", bundle: .module))
        }
        if !generatesAudio { parts.append(String(localized: "Audio: \(jobAudio.title)", bundle: .module)) }
        return parts.joined(separator: " · ")
    }
}
