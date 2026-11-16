import Foundation

/// How a result is re-encoded for an editing timeline. Every preset writes a constant frame rate.
public enum ExportPreset: String, Codable, Sendable, CaseIterable {
    case premiere
    case davinciResolve
    case finalCutPro
    case editingH264

    public enum VideoCodec: String, Codable, Sendable {
        case proRes422
        /// High-bitrate H.264, for editors and machines without ProRes decoding.
        case h264
    }

    public enum AudioCodec: String, Codable, Sendable {
        case linearPCM
        case aac
    }

    public enum Container: String, Codable, Sendable {
        case quickTime
        case mpeg4

        public var fileExtension: String {
            switch self {
            case .quickTime: "mov"
            case .mpeg4: "mp4"
            }
        }
    }

    /// The three NLEs all import ProRes 422 with PCM audio natively on macOS.
    public var videoCodec: VideoCodec {
        switch self {
        case .premiere, .davinciResolve, .finalCutPro: .proRes422
        case .editingH264: .h264
        }
    }

    public var audioCodec: AudioCodec {
        switch videoCodec {
        case .proRes422: .linearPCM
        case .h264: .aac
        }
    }

    public var container: Container {
        switch videoCodec {
        case .proRes422: .quickTime
        case .h264: .mpeg4
        }
    }

    public var fileExtension: String { container.fileExtension }
}

/// One frame's duration as a rational, `value / timescale` seconds.
public struct FrameDuration: Sendable, Hashable {
    public var value: Int64
    public var timescale: Int32

    public init(value: Int64, timescale: Int32) {
        self.value = value
        self.timescale = timescale
    }

    static let fallback = FrameDuration(value: 1, timescale: 30)
    /// Bases of the NTSC rates, which run at `base * 1000 / 1001` frames per second.
    static let ntscBases: [Int32] = [24, 30, 48, 60, 120]

    /// The constant frame duration for a nominal rate as AVFoundation reports it. NTSC rates
    /// (23.976, 29.97, 59.94…) stay exact as 1001/24000 etc.; rounding them would drift a frame
    /// every ~33 s against the source in a timeline.
    public static func constant(forNominalRate rate: Double) -> FrameDuration {
        guard rate.isFinite, rate >= 1, rate <= 240 else { return fallback }
        for base in ntscBases where abs(rate - Double(base) * 1000 / 1001) < 0.01 {
            return FrameDuration(value: 1001, timescale: base * 1000)
        }
        return FrameDuration(value: 1, timescale: Int32(rate.rounded()))
    }
}
