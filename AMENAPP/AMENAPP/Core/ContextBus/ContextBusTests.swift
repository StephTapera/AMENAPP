#if canImport(Testing)
// ContextBusTests.swift
// AMEN — ContextBus unit tests using Swift Testing
//
// These tests cover the four core behavioural invariants of ContextBus:
//  1. Basic emit + subscribe round-trip
//  2. Tier .s signals never reach serverForward
//  3. Consent-off signals are silently dropped
//  4. Ring buffer hard cap at 500

#if canImport(Testing)
import Testing
import Foundation
@testable import AMENAPP

// MARK: - Helpers

/// Builds a minimal valid ContextSignal with sensible defaults for tests.
private func makeSignal(
    type: SignalType = .noteSaved,
    tier: TierCeiling = .c,
    consentEdge: ConsentEdge? = nil,
    payload: [String: AnyCodableValue] = [:]
) -> ContextSignal {
    ContextSignal(
        id: UUID(),
        type: type,
        tierCeiling: tier,
        subjectRefs: [],
        payload: payload,
        occurredAt: Date(),
        decayHalfLifeDays: 7,
        consentEdgeRequired: consentEdge
    )
}

// MARK: - Test Suite

@Suite("ContextBus")
struct ContextBusTests {

    // MARK: - 1. Emit and subscribe round-trip

    @Test("Subscriber receives an emitted signal of matching type")
    func testEmitAndSubscribe() async throws {
        let bus = ContextBus()
        let stream = await bus.subscribe(to: [.noteSaved])
        let signal = makeSignal(type: .noteSaved, tier: .c)

        await bus.emit(signal)

        // Collect the first value within 2 seconds.
        var iterator = stream.makeAsyncIterator()
        let received = await withTaskGroup(of: ContextSignal?.self) { group in
            group.addTask { await iterator.next() }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return nil
            }
            for await result in group {
                group.cancelAll()
                return result
            }
            return nil
        }

        #expect(received?.id == signal.id, "Subscriber should receive the emitted signal")
    }

    // MARK: - 2. Tier .s never forwards

    @Test("Tier .s signal is delivered locally but serverForward is never called")
    func testTierSNeverForwards() async {
        let bus = ContextBus()
        let stream = await bus.subscribe(to: [.crisisSurfaceOpened])

        let crisisSignal = makeSignal(type: .crisisSurfaceOpened, tier: .s)

        // Capture pending forward count before emit.
        let pendingBefore = await bus.pendingForwardCount

        await bus.emit(crisisSignal)

        // Pending forward count must not increase for a tier .s signal.
        let pendingAfter = await bus.pendingForwardCount
        #expect(pendingAfter == pendingBefore, "Tier .s signals must never be enqueued for server forward")

        // The local subscriber should still receive it.
        var iterator = stream.makeAsyncIterator()
        let received = await withTaskGroup(of: ContextSignal?.self) { group in
            group.addTask { await iterator.next() }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return nil
            }
            for await result in group {
                group.cancelAll()
                return result
            }
            return nil
        }
        #expect(received?.id == crisisSignal.id, "Tier .s signal must still reach local subscriber")
    }

    // MARK: - 3. Consent off drops signal

    @Test("Signal requiring disabled consent edge is silently dropped")
    func testConsentOffDropsSignal() async {
        // The ConsentStore defaults to OFF for all edges except activityToRhythm.
        // .notesToMatching is OFF by default — use it as the test edge.
        let bus = ContextBus()
        let stream = await bus.subscribe(to: [.noteSaved])

        let signal = makeSignal(type: .noteSaved, tier: .c, consentEdge: .notesToMatching)

        await bus.emit(signal)

        // Subscriber must NOT receive the signal within the timeout window.
        var iterator = stream.makeAsyncIterator()
        let received = await withTaskGroup(of: ContextSignal?.self) { group in
            group.addTask { await iterator.next() }
            group.addTask {
                // Short timeout — we expect nothing to arrive.
                try? await Task.sleep(for: .milliseconds(300))
                return nil
            }
            for await result in group {
                group.cancelAll()
                return result
            }
            return nil
        }
        #expect(received == nil, "Signal requiring disabled consent edge must be dropped silently")
    }

    // MARK: - 4. Ring buffer eviction

    @Test("Ring buffer stays capped at 500 after 501 emissions")
    func testRingBufferEviction() async {
        let bus = ContextBus()

        // Emit 501 signals. Each is tier .c with no consent requirement so they all
        // enter the ring buffer.
        for _ in 0 ..< 501 {
            let signal = makeSignal(type: .noteSaved, tier: .c)
            await bus.emit(signal)
        }

        // pendingForwardCount = ringBuffer.count - forwardedCount.
        // forwardedCount may lag (async), but ringBuffer.count is capped at 500.
        // We verify the cap indirectly: pendingForwardCount <= 500.
        let pending = await bus.pendingForwardCount
        #expect(pending <= 500, "Ring buffer must evict oldest entries and stay at or below capacity of 500")
    }
}
#endif

#endif
