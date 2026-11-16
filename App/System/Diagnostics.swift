import Foundation
import MetricKit
import os

nonisolated private let logger = Logger.jutsu("Diagnostics")

/// MetricKit's daily metrics and its crash, hang, CPU and disk reports: a summary goes to the log and the payloads
/// stay in Caches, for the person to share from Account. Nothing is sent anywhere.
nonisolated final class Diagnostics: NSObject, MXMetricManagerSubscriber, Sendable {
    static let shared = Diagnostics()
    /// The newest payloads kept; older ones go as new ones arrive.
    private static let keptCount = 10
    private static let folder = URL.cachesDirectory.appending(path: "Diagnostics", directoryHint: .isDirectory)

    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            Self.log(payload)
            Self.save(payload.jsonRepresentation(), kind: "metrics", at: payload.timeStampEnd)
        }
        Self.trim()
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            Self.log(payload)
            Self.save(payload.jsonRepresentation(), kind: "diagnostics", at: payload.timeStampEnd)
        }
        Self.trim()
    }

    /// The saved payloads, newest first.
    @concurrent
    static func savedFiles() async -> [URL] {
        sortedFiles()
    }

    private static func log(_ payload: MXMetricPayload) {
        let launch = meanMilliseconds(payload.applicationLaunchMetrics?.histogrammedTimeToFirstDraw)
        let resume = meanMilliseconds(payload.applicationLaunchMetrics?.histogrammedApplicationResumeTime)
        let hang = meanMilliseconds(payload.applicationResponsivenessMetrics?.histogrammedApplicationHangTime)
        let cpu = payload.cpuMetrics?.cumulativeCPUTime.converted(to: .seconds).value ?? 0
        let writes = payload.diskIOMetrics?.cumulativeLogicalWrites.converted(to: .megabytes).value ?? 0
        logger.notice(
            """
            Metrics: first draw \(Int(launch), privacy: .public) ms, resume \(Int(resume), privacy: .public) ms, \
            hangs \(Int(hang), privacy: .public) ms, CPU \(Int(cpu), privacy: .public) s, \
            writes \(Int(writes), privacy: .public) MB
            """)
    }

    private static func log(_ payload: MXDiagnosticPayload) {
        let crashCount = payload.crashDiagnostics?.count ?? 0
        let hangCount = payload.hangDiagnostics?.count ?? 0
        let cpuCount = payload.cpuExceptionDiagnostics?.count ?? 0
        let diskCount = payload.diskWriteExceptionDiagnostics?.count ?? 0
        let launchCount = payload.appLaunchDiagnostics?.count ?? 0
        logger.notice(
            """
            Diagnostics: \(crashCount, privacy: .public) crashes, \(hangCount, privacy: .public) hangs, \
            \(cpuCount, privacy: .public) CPU and \(diskCount, privacy: .public) disk write exceptions, \
            \(launchCount, privacy: .public) slow launches
            """)
        for crash in payload.crashDiagnostics ?? [] {
            logger.error(
                """
                Crash: signal \(Int(truncating: crash.signal ?? 0), privacy: .public), \
                \(crash.terminationReason ?? "", privacy: .private)
                """)
        }
    }

    /// The average of a histogram of durations, each bucket counted at its middle.
    private static func meanMilliseconds(_ histogram: MXHistogram<UnitDuration>?) -> Double {
        guard let histogram else { return 0 }
        var total = 0.0
        var count = 0
        for case let bucket as MXHistogramBucket<UnitDuration> in histogram.bucketEnumerator {
            let start = bucket.bucketStart.converted(to: .milliseconds).value
            let end = bucket.bucketEnd.converted(to: .milliseconds).value
            total += (start + end) / 2 * Double(bucket.bucketCount)
            count += bucket.bucketCount
        }
        return count == 0 ? 0 : total / Double(count)
    }

    /// Named by the end of the period the payload covers, so names sort by date.
    private static func save(_ data: Data, kind: String, at date: Date) {
        let name = "\(Int(date.timeIntervalSince1970))-\(kind)-\(UUID().uuidString.prefix(8)).json"
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: folder.appending(path: name), options: .atomic)
        } catch {
            logger.error("Can't save a MetricKit payload: \(String(describing: error), privacy: .private)")
        }
    }

    private static func trim() {
        for file in sortedFiles().dropFirst(keptCount) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func sortedFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}
