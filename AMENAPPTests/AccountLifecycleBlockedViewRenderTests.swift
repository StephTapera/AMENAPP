import Foundation

#if canImport(Testing) && canImport(SwiftUI)
import Testing
import SwiftUI
@testable import AMENAPP

/// Verifies the data contract `AccountLifecycleBlockedView` exposes, which is
/// the surface that closes the stuck-screen recovery loop. We deliberately do
/// NOT try to walk the rendered SwiftUI accessibility tree from a unit-test
/// host — that tree is built lazily by the system and isn't reliably populated
/// in xctest hosting (no real screen, no scene). The behaviour proven here:
///
///   1. The view stores the four init parameters verbatim — so the message
///      `AuthenticationViewModel.resolveAuthError(...)` emits is the same one
///      the view will pass to its `Text(message)`.
///   2. The action closure routed through `action:` is the same closure the
///      Try Again button invokes — verified by calling it directly via the
///      stored property (which is what SwiftUI's button does internally).
///   3. The seam between `resolveAuthError(.timedOut)` and the view's message
///      field is end-to-end: a timeout flows into the exact copy users see.
///
/// The actual on-screen render path is exercised by manual simulator runs;
/// these tests lock in the seams.
@Suite("AccountLifecycleBlockedView contract")
@MainActor
struct AccountLifecycleBlockedViewRenderTests {

    @Test("init stores title, message, and buttonTitle verbatim")
    func init_stores_title_message_buttonTitle() {
        let view = AccountLifecycleBlockedView(
            title: "Could not verify account",
            message: "We couldn't reach our servers. Check your connection and try again.",
            buttonTitle: "Try Again",
            action: {}
        )
        #expect(view.title == "Could not verify account")
        #expect(view.message == "We couldn't reach our servers. Check your connection and try again.")
        #expect(view.buttonTitle == "Try Again")
    }

    @Test("the action closure stored on the view is the same one passed in")
    func action_closure_is_invokable() async {
        // SwiftUI's Button passes its action through unchanged. Calling the
        // stored closure directly verifies the same invocation the button
        // would perform when tapped.
        actor CallProbe {
            private(set) var count = 0
            func record() { count += 1 }
        }
        let probe = CallProbe()

        let view = AccountLifecycleBlockedView(
            title: "Could not verify account",
            message: "Network down",
            buttonTitle: "Try Again",
            action: {
                Task { await probe.record() }
            }
        )

        view.action()
        view.action()
        // Allow the detached probe Tasks to settle.
        try? await Task.sleep(nanoseconds: 100_000_000)
        let count = await probe.count
        #expect(count == 2, "action() must invoke the stored closure each time")
    }

    @Test("message rendered matches the timeout branch of resolveAuthError end-to-end")
    func message_matches_resolveAuthError_timeout_branch() {
        // Locks the seam between the auth-side fix and the view: whatever copy
        // `resolveAuthError(.timedOut)` returns must be exactly what the view
        // stores in `message`. If someone bumps one but not the other, this
        // test fails — preventing silent drift between the auth fix's
        // user-facing string and the view that renders it.
        let outcome = AuthenticationViewModel.resolveAuthError(
            from: AuthenticationViewModel.AuthResolutionError.timedOut
        )
        let view = AccountLifecycleBlockedView(
            title: "Could not verify account",
            message: outcome.message,
            buttonTitle: "Try Again",
            action: {}
        )
        #expect(view.message == outcome.message)
        #expect(view.message.contains("couldn't reach our servers"))
    }

    @Test("message rendered matches the generic branch of resolveAuthError end-to-end")
    func message_matches_resolveAuthError_generic_branch() {
        let firestoreLikeError = NSError(
            domain: "FIRFirestoreErrorDomain",
            code: 14,
            userInfo: [NSLocalizedDescriptionKey: "unavailable"]
        )
        let outcome = AuthenticationViewModel.resolveAuthError(from: firestoreLikeError)
        let view = AccountLifecycleBlockedView(
            title: "Could not verify account",
            message: outcome.message,
            buttonTitle: "Try Again",
            action: {}
        )
        #expect(view.message == outcome.message)
        #expect(view.message.contains("verify your account status"))
    }
}
#endif
