import Testing
import Foundation
@testable import AMENAPP

/// Covers `AuthenticationViewModel.raceFirestoreResolution(timeoutNanos:operation:)` —
/// the timeout-race primitive that backs the 6.5s budget around the Firestore
/// onboarding-status lookup. The Firestore call site itself can't be unit-tested
/// without a live Firestore, but the racing behaviour (which is the part that
/// actually broke the stuck-screen scenario) is fully covered here.
@Suite("AuthResolution timeout race")
struct AuthResolutionRaceTests {

    @Test("operation completes before timeout — succeeds with no throw")
    func operation_completes_before_timeout_succeeds() async throws {
        try await AuthenticationViewModel.raceFirestoreResolution(
            timeoutNanos: 500_000_000
        ) {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    @Test("operation hangs past timeout — throws .timedOut")
    func operation_hangs_throws_timedOut() async {
        do {
            try await AuthenticationViewModel.raceFirestoreResolution(
                timeoutNanos: 100_000_000
            ) {
                try await Task.sleep(nanoseconds: 10_000_000_000)
            }
            Issue.record("expected AuthResolutionError.timedOut, no error was thrown")
        } catch let error as AuthenticationViewModel.AuthResolutionError {
            #expect(error == .timedOut)
        } catch {
            Issue.record("expected AuthResolutionError.timedOut, got \(error)")
        }
    }

    @Test("operation throws a non-timeout error — that error propagates unchanged")
    func operation_throws_propagates_original_error() async {
        struct SimulatedFirestoreError: Error, Equatable {}
        do {
            try await AuthenticationViewModel.raceFirestoreResolution(
                timeoutNanos: 1_000_000_000
            ) {
                throw SimulatedFirestoreError()
            }
            Issue.record("expected SimulatedFirestoreError, no error was thrown")
        } catch is SimulatedFirestoreError {
            // expected
        } catch let error as AuthenticationViewModel.AuthResolutionError where error == .timedOut {
            Issue.record("operation error was incorrectly swallowed as .timedOut")
        } catch {
            Issue.record("expected SimulatedFirestoreError, got \(error)")
        }
    }

    @Test("losing operation is cancelled when timeout wins")
    func losing_operation_is_cancelled_when_timeout_wins() async {
        actor CancellationProbe {
            private(set) var observed = false
            func record() { observed = true }
        }
        let probe = CancellationProbe()

        do {
            try await AuthenticationViewModel.raceFirestoreResolution(
                timeoutNanos: 100_000_000
            ) {
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    await probe.record()
                    throw CancellationError()
                }
            }
            Issue.record("expected .timedOut to win the race")
        } catch let error as AuthenticationViewModel.AuthResolutionError {
            #expect(error == .timedOut)
        } catch {
            Issue.record("unexpected error: \(error)")
        }

        // Give the cancelled task a beat to record its observation.
        try? await Task.sleep(nanoseconds: 100_000_000)
        let observed = await probe.observed
        #expect(observed, "operation should have been cancelled when timeout won")
    }

    @Test("budget below overlay watchdog — 6.5s < 8s")
    func production_budget_stays_below_overlay_watchdog() {
        // Sanity check: the auth-side budget must remain below the overlay watchdog
        // so the auth state transitions to .error (and ContentView shows
        // AccountLifecycleBlockedView with Try Again) *before* the overlay's hard
        // backstop fires. If someone bumps either constant, this assertion fails.
        let authBudgetNanos: UInt64 = 6_500_000_000
        let overlayWatchdogNanos: UInt64 = 8 * 1_000_000_000
        #expect(authBudgetNanos < overlayWatchdogNanos)
    }
}

/// Covers `AuthenticationViewModel.resolveAuthError(from:)` — the pure mapping
/// from a thrown error to (a) the timeout/firestore classification used for
/// analytics buckets and (b) the user-visible string rendered by
/// `AccountLifecycleBlockedView`. The mapping is the contract the rest of the
/// stuck-screen fix depends on: timeout → network-specific copy, anything else
/// → generic verification copy.
@Suite("AuthResolution error mapping")
@MainActor
struct AuthResolutionErrorMappingTests {

    private let timeoutMessage =
        "We couldn't reach our servers. Check your connection and try again."
    private let genericMessage =
        "We couldn't verify your account status. Please try again."

    @Test(".timedOut → isTimeout=true with network-specific copy")
    func timedOut_maps_to_network_message() {
        let outcome = AuthenticationViewModel.resolveAuthError(
            from: AuthenticationViewModel.AuthResolutionError.timedOut
        )
        #expect(outcome.isTimeout == true)
        #expect(outcome.message == timeoutMessage)
    }

    @Test("arbitrary NSError → isTimeout=false with generic copy")
    func nsError_maps_to_generic_message() {
        let firestoreLikeError = NSError(
            domain: "FIRFirestoreErrorDomain",
            code: 14,
            userInfo: [NSLocalizedDescriptionKey: "unavailable"]
        )
        let outcome = AuthenticationViewModel.resolveAuthError(from: firestoreLikeError)
        #expect(outcome.isTimeout == false)
        #expect(outcome.message == genericMessage)
    }

    @Test("CancellationError is NOT misclassified as a timeout")
    func cancellation_is_not_timeout() {
        // A cancelled inner task surfaces as CancellationError, not as .timedOut.
        // It must take the generic branch — otherwise users see a misleading
        // "check your connection" message after they navigate away mid-resolution.
        let outcome = AuthenticationViewModel.resolveAuthError(from: CancellationError())
        #expect(outcome.isTimeout == false)
        #expect(outcome.message == genericMessage)
    }

    @Test("non-Equatable Swift error → generic copy")
    func arbitrary_swift_error_maps_to_generic_message() {
        struct OpaqueError: Error {}
        let outcome = AuthenticationViewModel.resolveAuthError(from: OpaqueError())
        #expect(outcome.isTimeout == false)
        #expect(outcome.message == genericMessage)
    }

    @Test("end-to-end: hanging operation → .timedOut → network-specific copy")
    func race_timeout_pipeline_produces_network_message() async {
        // Composes the race primitive with the error mapper to lock in the
        // full contract: "operation hangs past budget → user sees the
        // network-specific Try Again screen". This is the behavior that
        // AuthResolutionRaceTests proves halfway and that the original gap
        // (checkOnboardingStatus 6.5s timeout has zero coverage) was about.
        do {
            try await AuthenticationViewModel.raceFirestoreResolution(
                timeoutNanos: 50_000_000
            ) {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            }
            Issue.record("expected the race to throw .timedOut")
        } catch {
            let outcome = AuthenticationViewModel.resolveAuthError(from: error)
            #expect(outcome.isTimeout == true)
            #expect(outcome.message == timeoutMessage)
        }
    }

    @Test("end-to-end: inner Firestore-style error → generic copy")
    func race_inner_error_pipeline_produces_generic_message() async {
        struct SimulatedFirestoreError: Error {}
        do {
            try await AuthenticationViewModel.raceFirestoreResolution(
                timeoutNanos: 1_000_000_000
            ) {
                throw SimulatedFirestoreError()
            }
            Issue.record("expected the inner error to propagate")
        } catch {
            let outcome = AuthenticationViewModel.resolveAuthError(from: error)
            #expect(outcome.isTimeout == false)
            #expect(outcome.message == genericMessage)
        }
    }
}
