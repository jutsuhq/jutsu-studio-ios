import Foundation
import Testing

/// How long a test waits for something before it fails. Far past what any wait takes alone: a full run starts over
/// a thousand tests at once on a few cores, and each then gets only a slice of them.
public let waitLimit: Duration = .seconds(30)

/// Lets other tasks run until `condition` holds. After `timeout` it records an issue and returns,
/// so a condition that never comes fails the test instead of hanging the run.
public func eventually(
    timeout: Duration = waitLimit, isolation: isolated (any Actor)? = #isolation,
    _ condition: () async -> Bool, sourceLocation: SourceLocation = #_sourceLocation
) async {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return }
        // A real pause, not a yield: hundreds of tests poll at once, and spinning starves the work they wait for.
        try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("Condition never became true within \(timeout)", sourceLocation: sourceLocation)
}

/// Suspends until opened, ignoring cancellation, like a browser step that never answers.
/// Stays open once opened, so a `wait` that starts after `open` returns at once. A wait that outlasts
/// `timeout` records an issue and throws: a gate nobody opens fails the test instead of hanging the run.
public actor Gate<Value: Sendable> {
    public struct TimedOut: Error {}

    public let timeout: Duration
    private var result: Result<Value, any Error>?
    private var waiters: [UUID: CheckedContinuation<Value, any Error>] = [:]

    public init(timeout: Duration = waitLimit) {
        self.timeout = timeout
    }

    public var isWaiting: Bool { !waiters.isEmpty }

    public func wait(sourceLocation: SourceLocation = #_sourceLocation) async throws -> Value {
        if let result { return try result.get() }
        let id = UUID()
        let timer = Task {
            do { try await Task.sleep(for: timeout) } catch { return }
            guard let waiter = waiters.removeValue(forKey: id) else { return }
            Issue.record("Gate was not opened within \(timeout)", sourceLocation: sourceLocation)
            waiter.resume(throwing: TimedOut())
        }
        defer { timer.cancel() }
        return try await withCheckedThrowingContinuation { waiters[id] = $0 }
    }

    public func open(_ result: Result<Value, any Error>) {
        self.result = result
        for waiter in waiters.values { waiter.resume(with: result) }
        waiters = [:]
    }
}
