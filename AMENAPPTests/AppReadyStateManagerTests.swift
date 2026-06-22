import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

/// Locks in the launch-overlay watchdog behaviour: the overlay must always self-dismiss
/// even when no auth/feed branch calls signalReady(). The bug this guards against is
/// the "stuck on Loading your feed..." report — see SessionTimeoutManager.swift watchdog.
@MainActor
@Suite("AppReadyStateManager watchdog")
struct AppReadyStateManagerTests {

    /// Use a short watchdog so tests stay fast. Real production timeout is 8s.
    private static let testWatchdogNanos: UInt64 = 150_000_000  // 150ms
    /// Sleep long enough to be past the watchdog firing + MainActor hop.
    private static let pastWatchdogNanos: UInt64 = 400_000_000  // 400ms

    @Test("Watchdog dismisses the overlay if signalReady is never called")
    func watchdog_fires_when_signalReady_never_arrives() async throws {
        let mgr = AppReadyStateManager(
            initialShowing: true,
            watchdogTimeoutNanos: Self.testWatchdogNanos
        )
        #expect(mgr.isShowingLoadingScreen == true)

        try await Task.sleep(nanoseconds: Self.pastWatchdogNanos)

        #expect(mgr.isShowingLoadingScreen == false)
    }

    @Test("signalReady cancels the watchdog and dismisses immediately")
    func signalReady_cancels_watchdog() async throws {
        let mgr = AppReadyStateManager(
            initialShowing: true,
            watchdogTimeoutNanos: Self.testWatchdogNanos
        )

        mgr.signalReady()
        #expect(mgr.isShowingLoadingScreen == false)

        // Sleep past the watchdog window; the cancelled task must not flip state again.
        try await Task.sleep(nanoseconds: Self.pastWatchdogNanos)
        #expect(mgr.isShowingLoadingScreen == false)
    }

    @Test("signalSignIn shows the overlay and starts a fresh watchdog")
    func signalSignIn_starts_watchdog() async throws {
        let mgr = AppReadyStateManager(
            initialShowing: false,
            watchdogTimeoutNanos: Self.testWatchdogNanos
        )
        #expect(mgr.isShowingLoadingScreen == false)

        mgr.signalSignIn()
        #expect(mgr.isShowingLoadingScreen == true)

        try await Task.sleep(nanoseconds: Self.pastWatchdogNanos)
        #expect(mgr.isShowingLoadingScreen == false)
    }

    @Test("startIfNeeded re-arms the watchdog even when overlay is already visible")
    func startIfNeeded_rearms_watchdog() async throws {
        let mgr = AppReadyStateManager(
            initialShowing: true,
            watchdogTimeoutNanos: Self.testWatchdogNanos
        )

        // Imagine ContentView re-renders shortly after init — startIfNeeded should
        // not leave the overlay stuck, even if the original watchdog were lost.
        mgr.startIfNeeded()

        try await Task.sleep(nanoseconds: Self.pastWatchdogNanos)
        #expect(mgr.isShowingLoadingScreen == false)
    }

    @Test("signalReady before watchdog fires is idempotent on subsequent calls")
    func signalReady_idempotent() async throws {
        let mgr = AppReadyStateManager(
            initialShowing: true,
            watchdogTimeoutNanos: Self.testWatchdogNanos
        )
        mgr.signalReady()
        mgr.signalReady()  // no-op, no crash
        #expect(mgr.isShowingLoadingScreen == false)
    }

    @Test("Repeated signalSignIn calls keep extending the watchdog window")
    func repeated_signalSignIn_extends_watchdog() async throws {
        let mgr = AppReadyStateManager(
            initialShowing: false,
            watchdogTimeoutNanos: Self.testWatchdogNanos
        )
        mgr.signalSignIn()
        // Re-arm before original watchdog would have fired.
        try await Task.sleep(nanoseconds: Self.testWatchdogNanos / 2)
        mgr.signalSignIn()
        try await Task.sleep(nanoseconds: Self.testWatchdogNanos / 2)
        // Original watchdog window has elapsed — but because of the re-arm the
        // overlay should still be up.
        #expect(mgr.isShowingLoadingScreen == true)

        // After the second window fully elapses, the new watchdog fires.
        try await Task.sleep(nanoseconds: Self.pastWatchdogNanos)
        #expect(mgr.isShowingLoadingScreen == false)
    }
}
#endif
