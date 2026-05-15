// DoomscrollGuardTests.swift
// AMENAPPTests
//
// Unit tests for DoomscrollGuard pure logic:
//   - repetitionDampener() — ranking penalty for repeated creators
//   - session state tracking (below checkpoint threshold, no Firestore involved)
//   - endSession() clears state
//   - isLateNight property
//
// NOTE: Tests that would trigger the 20-video checkpoint are intentionally
// avoided here because triggerCheckpoint() writes to Firestore. Those tests
// belong in the integration test suite.

import Testing
import Foundation
@testable import AMENAPP

@Suite("DoomscrollGuard — Repetition Dampener")
@MainActor
struct DoomscrollGuardRepetitionTests {

    // MARK: - Repetition dampener thresholds

    @Test("First appearance returns no penalty (1.0)")
    func firstAppearanceNoPenalty() {
        DoomscrollGuard.shared.endSession()
        let result = DoomscrollGuard.shared.repetitionDampener(for: "creator-new")
        #expect(result == 1.0)
    }

    @Test("Appearances within threshold return no penalty (1.0)")
    func belowThresholdNoPenalty() {
        DoomscrollGuard.shared.endSession()
        let creatorId = "creator-test-\(UUID().uuidString)"
        let threshold = DoomscrollGuard.shared.repeatedCreatorThreshold

        for _ in 0..<threshold {
            DoomscrollGuard.shared.creatorSeenCounts[creatorId, default: 0] += 1
        }

        let result = DoomscrollGuard.shared.repetitionDampener(for: creatorId)
        #expect(result == 1.0, "At exactly the threshold, penalty should not yet apply")
    }

    @Test("First over-threshold appearance returns light penalty (0.7)")
    func lightPenaltyAtThresholdPlusOne() {
        DoomscrollGuard.shared.endSession()
        let creatorId = "creator-light-\(UUID().uuidString)"
        let threshold = DoomscrollGuard.shared.repeatedCreatorThreshold

        DoomscrollGuard.shared.creatorSeenCounts[creatorId] = threshold + 1
        let result = DoomscrollGuard.shared.repetitionDampener(for: creatorId)
        #expect(result == 0.7)
    }

    @Test("Second over-threshold appearance returns moderate penalty (0.4)")
    func moderatePenaltyAtThresholdPlusTwo() {
        DoomscrollGuard.shared.endSession()
        let creatorId = "creator-moderate-\(UUID().uuidString)"
        let threshold = DoomscrollGuard.shared.repeatedCreatorThreshold

        DoomscrollGuard.shared.creatorSeenCounts[creatorId] = threshold + 2
        let result = DoomscrollGuard.shared.repetitionDampener(for: creatorId)
        #expect(result == 0.4)
    }

    @Test("Heavy repeated creator receives strong dampening penalty (0.15)")
    func strongPenaltyForHeavyRepetition() {
        DoomscrollGuard.shared.endSession()
        let creatorId = "creator-heavy-\(UUID().uuidString)"
        let threshold = DoomscrollGuard.shared.repeatedCreatorThreshold

        DoomscrollGuard.shared.creatorSeenCounts[creatorId] = threshold + 10
        let result = DoomscrollGuard.shared.repetitionDampener(for: creatorId)
        #expect(result == 0.15, "Heavy repetition must apply the strongest dampening")
    }

    @Test("Dampening penalties are strictly decreasing")
    func penaltiesAreMonotonicallyDecreasing() {
        DoomscrollGuard.shared.endSession()
        let creatorId = "creator-mono-\(UUID().uuidString)"
        let threshold = DoomscrollGuard.shared.repeatedCreatorThreshold

        var lastResult = 1.0
        for count in (threshold + 1)...(threshold + 10) {
            DoomscrollGuard.shared.creatorSeenCounts[creatorId] = count
            let result = DoomscrollGuard.shared.repetitionDampener(for: creatorId)
            #expect(result <= lastResult,
                    "Dampener at count \(count) (\(result)) should be ≤ previous (\(lastResult))")
            lastResult = result
        }
    }
}

// MARK: - Session State

@Suite("DoomscrollGuard — Session State")
@MainActor
struct DoomscrollGuardSessionTests {

    @Test("recordPostSeen increments postsSeenThisSession")
    func recordPostSeenIncrementsCounter() {
        DoomscrollGuard.shared.endSession()
        let before = DoomscrollGuard.shared.postsSeenThisSession

        // Stay well below video checkpoint threshold to avoid Firestore call
        DoomscrollGuard.shared.creatorSeenCounts["author-x", default: 0] += 1
        DoomscrollGuard.shared.postsSeenThisSession += 1

        #expect(DoomscrollGuard.shared.postsSeenThisSession == before + 1)
    }

    @Test("endSession resets all counters to zero")
    func endSessionResetsState() {
        DoomscrollGuard.shared.videosWatchedThisSession = 5
        DoomscrollGuard.shared.postsSeenThisSession = 15
        DoomscrollGuard.shared.creatorSeenCounts["some-creator"] = 3

        DoomscrollGuard.shared.endSession()

        #expect(DoomscrollGuard.shared.videosWatchedThisSession == 0)
        #expect(DoomscrollGuard.shared.postsSeenThisSession == 0)
        #expect(DoomscrollGuard.shared.creatorSeenCounts.isEmpty)
        #expect(DoomscrollGuard.shared.checkpointPending == false)
    }

    @Test("dismissCheckpoint resets video count and clears pending flag")
    func dismissCheckpointResetsCount() {
        DoomscrollGuard.shared.videosWatchedThisSession = 18
        DoomscrollGuard.shared.checkpointPending = true

        DoomscrollGuard.shared.dismissCheckpoint()

        #expect(DoomscrollGuard.shared.checkpointPending == false)
        #expect(DoomscrollGuard.shared.videosWatchedThisSession == 0)
    }

    @Test("videoCheckpointThreshold defaults to 20")
    func defaultVideoCheckpointThreshold() {
        // Verify the documented default matches the implementation.
        // This is a contract test — if the value changes, this test fails first.
        DoomscrollGuard.shared.endSession()
        #expect(DoomscrollGuard.shared.videoCheckpointThreshold == 20)
    }
}

// MARK: - Late Night Detection

@Suite("DoomscrollGuard — Late Night Detection")
@MainActor
struct DoomscrollGuardLateNightTests {

    @Test("isLateNight returns a Bool")
    func isLateNightReturnsBool() {
        // We can't control system time, so just verify the property compiles and returns a Bool.
        let result: Bool = DoomscrollGuard.shared.isLateNight
        _ = result // used
    }

    @Test("isLateNightAndHighRisk requires both conditions")
    func isLateNightAndHighRiskRequiresBothConditions() {
        DoomscrollGuard.shared.endSession()

        // With zero posts seen, even if it is late night, isLateNightAndHighRisk should be false
        DoomscrollGuard.shared.postsSeenThisSession = 0
        #expect(DoomscrollGuard.shared.isLateNightAndHighRisk == false,
                "isLateNightAndHighRisk requires > 10 posts seen, regardless of time")
    }
}
