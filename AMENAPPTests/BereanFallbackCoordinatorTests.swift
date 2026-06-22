// BereanFallbackCoordinatorTests.swift
// AMENAPPTests
//
// State-machine contracts for BereanFallbackCoordinator.
// Uses the shared singleton — suite is .serialized to prevent concurrent mutation.

import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

// MARK: - BereanFallbackCoordinatorTests

@MainActor
@Suite("BereanFallbackCoordinator", .serialized)
struct BereanFallbackCoordinatorTests {

    // MARK: 1. Initial state

    @Test("Initial state is idle after clearForSignOut")
    func initialStateIsIdle() {
        BereanFallbackCoordinator.shared.clearForSignOut()

        #expect(BereanFallbackCoordinator.shared.presentationState == .idle)
        #expect(BereanFallbackCoordinator.shared.context == nil)
        #expect(BereanFallbackCoordinator.shared.isReadyToPresent == false)
    }

    // MARK: 2. enqueue transitions

    @Test("enqueue transitions idle to queued")
    func enqueueTransitionsIdleToQueued() {
        BereanFallbackCoordinator.shared.clearForSignOut()

        BereanFallbackCoordinator.shared.enqueue(triggerReason: "live_activity_disabled")

        #expect(BereanFallbackCoordinator.shared.presentationState == .queued)
        #expect(BereanFallbackCoordinator.shared.context != nil)
        #expect(BereanFallbackCoordinator.shared.isReadyToPresent == true)
    }

    @Test("enqueue sets context fields correctly")
    func enqueueSetsContextFieldsCorrectly() throws {
        BereanFallbackCoordinator.shared.clearForSignOut()

        BereanFallbackCoordinator.shared.enqueue(
            sourceSurface: "prayer_wall",
            sourcePostId: "post_abc123",
            triggerReason: "ai_suggestion"
        )

        let ctx = try #require(BereanFallbackCoordinator.shared.context)
        #expect(ctx.sourceSurface == "prayer_wall")
        #expect(ctx.sourcePostId == "post_abc123")
        #expect(ctx.triggerReason == "ai_suggestion")
    }

    @Test("enqueue is no-op when already queued")
    func enqueueIsNoOpWhenAlreadyQueued() throws {
        BereanFallbackCoordinator.shared.clearForSignOut()

        BereanFallbackCoordinator.shared.enqueue(sourceSurface: "feed", triggerReason: "first_enqueue")
        let firstReason = try #require(BereanFallbackCoordinator.shared.context).triggerReason

        BereanFallbackCoordinator.shared.enqueue(sourceSurface: "profile", triggerReason: "second_enqueue")

        #expect(BereanFallbackCoordinator.shared.presentationState == .queued)
        let currentReason = try #require(BereanFallbackCoordinator.shared.context).triggerReason
        #expect(currentReason == firstReason)
    }

    @Test("enqueue is no-op when presenting")
    func enqueueIsNoOpWhenPresenting() {
        BereanFallbackCoordinator.shared.clearForSignOut()

        BereanFallbackCoordinator.shared.enqueue(triggerReason: "initial_trigger")
        _ = BereanFallbackCoordinator.shared.claim()

        BereanFallbackCoordinator.shared.enqueue(sourceSurface: "notifications", triggerReason: "second_trigger")

        #expect(BereanFallbackCoordinator.shared.presentationState == .presenting)
    }

    // MARK: 3. claim

    @Test("claim returns true and transitions to presenting")
    func claimReturnsTrueAndTransitionsToPresenting() {
        BereanFallbackCoordinator.shared.clearForSignOut()

        BereanFallbackCoordinator.shared.enqueue(triggerReason: "live_activity_disabled")
        let result = BereanFallbackCoordinator.shared.claim()

        #expect(result == true)
        #expect(BereanFallbackCoordinator.shared.presentationState == .presenting)
    }

    @Test("claim returns false when idle")
    func claimReturnsFalseWhenIdle() {
        BereanFallbackCoordinator.shared.clearForSignOut()

        let result = BereanFallbackCoordinator.shared.claim()

        #expect(result == false)
        #expect(BereanFallbackCoordinator.shared.presentationState == .idle)
    }

    @Test("claim returns false when already presenting")
    func claimReturnsFalseWhenAlreadyPresenting() {
        BereanFallbackCoordinator.shared.clearForSignOut()

        BereanFallbackCoordinator.shared.enqueue(triggerReason: "live_activity_disabled")
        _ = BereanFallbackCoordinator.shared.claim()

        let secondResult = BereanFallbackCoordinator.shared.claim()

        #expect(secondResult == false)
        #expect(BereanFallbackCoordinator.shared.presentationState == .presenting)
    }

    // MARK: 4. markDismissed

    @Test("markDismissed clears context and sets dismissed")
    func markDismissedClearsContextAndSetsDismissed() {
        BereanFallbackCoordinator.shared.clearForSignOut()

        BereanFallbackCoordinator.shared.enqueue(triggerReason: "live_activity_disabled")
        _ = BereanFallbackCoordinator.shared.claim()
        BereanFallbackCoordinator.shared.markDismissed()

        #expect(BereanFallbackCoordinator.shared.presentationState == .dismissed)
        #expect(BereanFallbackCoordinator.shared.context == nil)
    }

    // MARK: 5. Sign-out

    @Test("clearForSignOut resets to idle regardless of state")
    func clearForSignOutResetsToIdle() {
        BereanFallbackCoordinator.shared.clearForSignOut()

        BereanFallbackCoordinator.shared.enqueue(triggerReason: "live_activity_disabled")
        #expect(BereanFallbackCoordinator.shared.presentationState == .queued)

        BereanFallbackCoordinator.shared.clearForSignOut()

        #expect(BereanFallbackCoordinator.shared.presentationState == .idle)
        #expect(BereanFallbackCoordinator.shared.context == nil)
    }

    // MARK: 6. PresentationState equatability

    @Test("PresentationState conforms to Equatable correctly")
    func presentationStateEquatability() {
        #expect(BereanFallbackCoordinator.PresentationState.idle == .idle)
        #expect(BereanFallbackCoordinator.PresentationState.queued == .queued)
        #expect(BereanFallbackCoordinator.PresentationState.presenting == .presenting)
        #expect(BereanFallbackCoordinator.PresentationState.dismissed == .dismissed)
        #expect(BereanFallbackCoordinator.PresentationState.queued != .presenting)
        #expect(BereanFallbackCoordinator.PresentationState.idle != .dismissed)
    }
}

#endif
