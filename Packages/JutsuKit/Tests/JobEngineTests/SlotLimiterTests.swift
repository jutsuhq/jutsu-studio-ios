import Foundation
import JutsuCore
import JutsuTestSupport
import Testing

@testable import JobEngine

@Suite(.timeLimit(.minutes(1)), .stopsEngines)
struct SlotLimiterTests {
    actor Order {
        var values: [Int] = []
        func append(_ value: Int) { values.append(value) }
    }

    @Test func waitersAreServedInArrivalOrder() async throws {
        let limiter = SlotLimiter(limit: 1)
        let order = Order()
        try await limiter.acquire(UUID(), order: SlotOrder(queuedAt: .distantPast))

        let first = Task {
            try await limiter.acquire(UUID(), order: SlotOrder(queuedAt: .distantPast))
            await order.append(1)
        }
        await eventually { await limiter.waiterCount == 1 }
        let second = Task {
            try await limiter.acquire(UUID(), order: SlotOrder(queuedAt: .distantPast))
            await order.append(2)
        }
        await eventually { await limiter.waiterCount == 2 }

        await limiter.release()
        try await first.value
        #expect(await order.values == [1])
        await limiter.release()
        try await second.value
        #expect(await order.values == [1, 2])
    }

    @Test func canceledWaiterLeavesTheQueue() async throws {
        let limiter = SlotLimiter(limit: 1)
        try await limiter.acquire(UUID(), order: SlotOrder(queuedAt: .distantPast))
        let waiter = Task { try await limiter.acquire(UUID(), order: SlotOrder(queuedAt: .distantPast)) }
        await eventually { await limiter.waiterCount == 1 }

        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        #expect(await limiter.waiterCount == 0)
        await limiter.release()
        #expect(await limiter.inUse == 0)
    }
}
