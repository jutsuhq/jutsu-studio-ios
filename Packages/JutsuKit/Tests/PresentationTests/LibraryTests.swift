import Foundation
import JutsuCore
import Testing

@testable import Presentation

private func dec(_ text: String) -> Decimal {
    Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? 0
}

enum LibraryFixture {
    static let now = Date(timeIntervalSince1970: 1_000_000)

    static func item(
        mode: Mode = .restyle, source: String = "rooftop.mov", range: ClosedRange<TimeInterval> = 4...10,
        resolution: Resolution = .p480, isDraft: Bool = true, prompt: String = "", references: Int = 0,
        cost: Cost = .usd(dec("1.908"), isEstimate: false), via: ProviderKind = .apiKey,
        presetName: String? = nil, minutesAgo: Double = 36, queuedMinutesAgo: Double = 60
    ) -> LibraryItemModel {
        let clip = SourceClip(
            fileURL: URL(fileURLWithPath: "/home/me/Movies/\(source)"), duration: 30,
            pixelSize: PixelSize(width: 1920, height: 1080), range: range)
        let spec = JobSpec(
            mode: mode, source: clip,
            references: (0..<references).map { LocalImage(fileURL: URL(fileURLWithPath: "/tmp/ref\($0).png")) },
            presetID: presetName == nil ? nil : UUID(), prompt: prompt, resolution: resolution, isDraft: isDraft)
        var job = Job(
            spec: spec, providerKind: via, cost: cost, createdAt: now.addingTimeInterval(-queuedMinutesAgo * 60))
        job.state = .done
        job.finishedAt = now.addingTimeInterval(-minutesAgo * 60)
        job.outputFile = URL(fileURLWithPath: "/home/me/Movies/Jutsu Studio/out.mp4")
        job.remote = RemoteJob(requestID: "req-123", correlationID: "corr-9")
        return LibraryItemModel(job: job, presetName: presetName)
    }
}
