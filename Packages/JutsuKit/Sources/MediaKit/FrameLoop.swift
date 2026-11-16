import Foundation

/// Where the re-encode's pump runs: on a thread of its own rather than on Swift's few cooperative threads.
/// `copyNextSampleBuffer` and the writer's back-pressure block; with every cooperative thread blocked in such calls
/// the AVFoundation work they wait for stalled too, and with it every media test running at once.
enum FrameLoop {
    /// Runs `body` on `FrameLoopExecutor`.
    static func run<T>(_ body: () async throws -> T) async throws -> T {
        try await withTaskExecutorPreference(FrameLoopExecutor.shared) { try await body() }
    }
}

/// One serial queue, which has a thread of its own whatever the cooperative pool is doing. Runs take turns on it.
/// Each job runs at its task's priority, as it did on the cooperative pool, so a run started at background priority
/// stays there.
final class FrameLoopExecutor: TaskExecutor {
    static let shared = FrameLoopExecutor()
    private let queue = DispatchQueue(label: "com.jutsustudio.frame-loop")

    func enqueue(_ job: consuming ExecutorJob) {
        // TaskPriority's raw values are the QoS classes'.
        let qos = DispatchQoS.QoSClass(rawValue: qos_class_t(UInt32(job.priority.rawValue))) ?? .default
        let job = UnownedJob(job)
        let executor = asUnownedTaskExecutor()
        queue.async(qos: DispatchQoS(qosClass: qos, relativePriority: 0)) { job.runSynchronously(on: executor) }
    }
}
