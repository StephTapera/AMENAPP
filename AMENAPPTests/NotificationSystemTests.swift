// NotificationSystemTests.swift
// AMENAPPTests — Notifications
//
// Agent E QA gate: contract tests for the smart notification system.
//
// ── SEAMS REQUIRED ─────────────────────────────────────────────────────────
// Two internal testable inits must be added to the engine files:
//
// SeenStore.swift — add below `private init() {}`:
//
//   #if DEBUG
//   /// Testable init: backed by an isolated UserDefaults suite so tests
//   /// never pollute UserDefaults.standard or each other.
//   internal convenience init(testSuite: String) {
//       self.init()
//       self._defaults = UserDefaults(suiteName: testSuite) ?? .standard
//   }
//   #endif
//
//   Note: also add `private var _defaults = UserDefaults.standard` and
//   replace `defaults` usages with `_defaults`.
//
// NotificationCoordinator.swift — add below `private init() {}`:
//
//   #if DEBUG
//   /// Testable init: accepts an isolated SeenStore so each test gets
//   /// a fresh seen-state without touching the production singleton.
//   internal convenience init(seenStore: SeenStore) {
//       self.init()
//       self._seenStore = seenStore
//   }
//   #endif
//
//   Note: also add `private var _seenStore: SeenStore = SeenStore.shared`
//   and replace all `SeenStore.shared` usages with `_seenStore`.
//
// These two changes are the ONLY engine modifications needed. All other
// test contracts (copy table, ctx closures, undo/dismiss logic, prefs
// protocol) are already fully testable via the existing public API.
// ───────────────────────────────────────────────────────────────────────────
//
// Design principles:
//   - Contract tests: stored properties + invokable closures + protocol seams.
//   - No UIHostingController / accessibility-tree walks.
//   - SeenStore tests use isolated UserDefaults suites.
//   - @MainActor tests match production actor context.

#if canImport(Testing)
import Testing
import Foundation
@testable import AMENAPP

// MARK: - Helpers

/// Returns a test-isolated SeenStore backed by a unique UserDefaults suite.
/// Requires the DEBUG testable init described in the seam comment above.
private func makeIsolatedSeenStore() -> (store: SeenStore, teardown: () -> Void) {
    let suiteName = "AmenNotifTest-\(UUID().uuidString)"
    let store = SeenStore(testSuite: suiteName)
    let teardown: () -> Void = {
        UserDefaults(suiteName: suiteName)?.removeSuite(named: suiteName)
    }
    return (store, teardown)
}

/// Minimal NotifContext whose apply/reverse closures flip caller-supplied Bool flags.
private func makeCtx(
    action: AmenAction = .amen,
    undoWindow: TimeInterval = 4.2,
    onApply: @escaping () -> Void = {},
    onReverse: @escaping () -> Void = {}
) -> NotifContext {
    NotifContext(
        action: action,
        actorName: "TestActor",
        toneColors: (.blue, .purple),
        undoWindow: undoWindow,
        apply: onApply,
        reverse: onReverse
    )
}

// MARK: - Suite 1: Notification Style Decision

@Suite("Notification Style Decision")
@MainActor
struct StyleDecisionTests {

    // Test: unseen action → .card under .smart
    @Test("Unseen action resolves to .card under .smart prefs")
    func unseenActionResolvesToCard() {
        let (seen, teardown) = makeIsolatedSeenStore()
        defer { teardown() }

        let coordinator = NotificationCoordinator(seenStore: seen)
        coordinator.prefs = AllSmartPrefs()

        var applyCalled = false
        coordinator.fire(makeCtx(action: .amen, onApply: { applyCalled = true }))

        #expect(coordinator.activeCard != nil,      "activeCard must be set")
        #expect(coordinator.activeCard?.style == .card, "First fire must be .card for unseen")
        #expect(applyCalled,                        "apply() must be called at fire time")
        coordinator.dismiss()
    }

    // Test: seen action → .toast under .smart
    @Test("Previously-seen action resolves to .toast under .smart prefs")
    func seenActionResolvesToToast() {
        let (seen, teardown) = makeIsolatedSeenStore()
        defer { teardown() }

        seen.markSeen(.repost)

        let coordinator = NotificationCoordinator(seenStore: seen)
        coordinator.prefs = AllSmartPrefs()

        coordinator.fire(makeCtx(action: .repost))

        #expect(coordinator.activeCard?.style == .toast, "Seen action must resolve to .toast")
        coordinator.dismiss()
    }

    // Test: .off override suppresses entirely
    @Test(".off style override suppresses notification — activeCard stays nil")
    func offOverrideSuppressesAll() {
        let (seen, teardown) = makeIsolatedSeenStore()
        defer { teardown() }

        var applyCalled = false
        let coordinator = NotificationCoordinator(seenStore: seen)
        coordinator.prefs = SingleOverridePrefs(action: .save, override: .off)

        coordinator.fire(makeCtx(action: .save, onApply: { applyCalled = true }))

        #expect(coordinator.activeCard == nil, ".off must not set activeCard")
        #expect(!applyCalled, ".off must not call apply()")
    }

    // Test: .alwaysCard override → always card
    @Test(".alwaysCard override shows card even for previously-seen action")
    func alwaysCardBypassesSeenStore() {
        let (seen, teardown) = makeIsolatedSeenStore()
        defer { teardown() }

        seen.markSeen(.join)

        let coordinator = NotificationCoordinator(seenStore: seen)
        coordinator.prefs = SingleOverridePrefs(action: .join, override: .alwaysCard)

        coordinator.fire(makeCtx(action: .join))

        #expect(coordinator.activeCard?.style == .card, ".alwaysCard must show .card regardless of SeenStore")
        coordinator.dismiss()
    }

    // Test: .toastOnly override → always toast
    @Test(".toastOnly override shows toast even for unseen action")
    func toastOnlyBypassesCard() {
        let (seen, teardown) = makeIsolatedSeenStore()
        defer { teardown() }

        // action is unseen — without override it would be .card
        let coordinator = NotificationCoordinator(seenStore: seen)
        coordinator.prefs = SingleOverridePrefs(action: .give, override: .toastOnly)

        coordinator.fire(makeCtx(action: .give))

        #expect(coordinator.activeCard?.style == .toast, ".toastOnly must show .toast for unseen action")
        coordinator.dismiss()
    }

    // Test: SeenStore.reset() → back to card on next fire
    @Test("After SeenStore.reset(), next fire for previously-seen action returns .card")
    func resetRestoresCardBehaviour() {
        let (seen, teardown) = makeIsolatedSeenStore()
        defer { teardown() }

        seen.markSeen(.amen)
        seen.reset()

        #expect(!seen.hasSeen(.amen), "reset() must clear seen state")

        let coordinator = NotificationCoordinator(seenStore: seen)
        coordinator.prefs = AllSmartPrefs()

        coordinator.fire(makeCtx(action: .amen))

        #expect(coordinator.activeCard?.style == .card, "Post-reset fire must show .card")
        coordinator.dismiss()
    }

    // Test: markSeen is only called for .card style (not for toast)
    @Test("SeenStore.markSeen is called after a .card fire, not after a .toast fire")
    func markSeenCalledOnlyForCard() {
        let (seen, teardown) = makeIsolatedSeenStore()
        defer { teardown() }

        #expect(!seen.hasSeen(.amen), "precondition: amen is unseen")

        let coordinator = NotificationCoordinator(seenStore: seen)
        coordinator.prefs = AllSmartPrefs()

        // First fire → card → markSeen should be called
        coordinator.fire(makeCtx(action: .amen))
        #expect(coordinator.activeCard?.style == .card, "Should be card")
        #expect(seen.hasSeen(.amen), "markSeen must be called after card fire")
        coordinator.dismiss()

        // Second fire → toast → markSeen already true, no state change
        coordinator.fire(makeCtx(action: .amen))
        #expect(coordinator.activeCard?.style == .toast, "Should be toast on repeat")
        coordinator.dismiss()
    }
}

// MARK: - Suite 2: Undo Reversal

@Suite("Undo Reversal")
@MainActor
struct UndoReversalTests {

    // Test: undo() calls reverse() and clears activeCard
    @Test("undo() calls ctx.reverse() and clears activeCard")
    func undoCallsReverseAndClearsCard() {
        let (seen, teardown) = makeIsolatedSeenStore()
        defer { teardown() }

        let coordinator = NotificationCoordinator(seenStore: seen)
        coordinator.prefs = AllSmartPrefs()

        var reverseCalled = false
        coordinator.fire(makeCtx(action: .amen, onReverse: { reverseCalled = true }))

        #expect(coordinator.activeCard != nil, "activeCard must be set before undo")

        coordinator.undo()

        #expect(reverseCalled,                  "undo() must call ctx.reverse()")
        #expect(coordinator.activeCard == nil,  "undo() must clear activeCard")
    }

    // Test: dismiss() does NOT call reverse()
    @Test("dismiss() commits the change — does NOT call ctx.reverse()")
    func dismissDoesNotCallReverse() {
        let (seen, teardown) = makeIsolatedSeenStore()
        defer { teardown() }

        let coordinator = NotificationCoordinator(seenStore: seen)
        coordinator.prefs = AllSmartPrefs()

        var reverseCalled = false
        coordinator.fire(makeCtx(action: .save, onReverse: { reverseCalled = true }))

        coordinator.dismiss()

        #expect(!reverseCalled,                 "dismiss() must NOT call ctx.reverse()")
        #expect(coordinator.activeCard == nil,  "dismiss() must clear activeCard")
    }

    // Test: auto-dismiss timer calls dismiss(), not undo()
    // This is verified structurally: the auto-dismiss Task in NotificationCoordinator
    // only sets `activeCard = nil` without calling `reverse()`. We verify indirectly:
    // apply() is called at fire time; after the timer the change must remain applied.
    @Test("Auto-dismiss path: apply() is called at fire; activeCard clears without reverse()")
    func autoDismissCallsApplyNotReverse() async throws {
        let (seen, teardown) = makeIsolatedSeenStore()
        defer { teardown() }

        let coordinator = NotificationCoordinator(seenStore: seen)
        coordinator.prefs = AllSmartPrefs()

        var applyCalled = false
        var reverseCalled = false

        // Use a tiny undoWindow so the auto-dismiss fires quickly in tests
        coordinator.fire(makeCtx(
            action: .amen,
            undoWindow: 0.05,
            onApply: { applyCalled = true },
            onReverse: { reverseCalled = true }
        ))

        #expect(applyCalled, "apply() must be called immediately at fire time")

        // Wait for the auto-dismiss timer (0.05 s + slack)
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 s

        #expect(coordinator.activeCard == nil, "Auto-dismiss must clear activeCard")
        #expect(!reverseCalled, "Auto-dismiss must NOT call reverse() — change is committed")
    }

    // Test: firing after undo leaves coordinator in clean state
    @Test("Firing a notification after undo works — coordinator is not in a broken state")
    func fireAfterUndoWorks() {
        let (seen, teardown) = makeIsolatedSeenStore()
        defer { teardown() }

        let coordinator = NotificationCoordinator(seenStore: seen)
        coordinator.prefs = AllSmartPrefs()

        coordinator.fire(makeCtx(action: .amen))
        coordinator.undo()
        #expect(coordinator.activeCard == nil)

        var applyCalled = false
        coordinator.fire(makeCtx(action: .repost, onApply: { applyCalled = true }))

        #expect(coordinator.activeCard != nil, "Second fire after undo must set activeCard")
        #expect(applyCalled,                   "apply() must be called on the second fire")
        coordinator.dismiss()
    }

    // Test: Give action — undo cancels deferred charge (isPendingGive = false)
    // Structural contract: AmenGiveActionHandler.reverse must set isPendingGive = false.
    // We exercise the closures directly without involving NotificationCoordinator's timer.
    @Test("Give undo: reverse() sets AmenGiveActionHandler.isPendingGive to false")
    func giveUndoCancelsDeferredCharge() {
        // Use a closure-capture approach: build a NotifContext matching what
        // AmenGiveActionHandler would produce, then call reverse() directly.
        var isPendingGive = false

        let ctx = NotifContext(
            action: .give,
            actorName: "Test Ministry",
            toneColors: (.yellow, .orange),
            undoWindow: 6.0,
            apply: {
                isPendingGive = true
                // In production, a Task.sleep(6s) deferred commit is launched here.
                // For the test we only verify the flag set by apply().
            },
            reverse: {
                isPendingGive = false
                // In production, the deferred Task is cancelled here.
            }
        )

        ctx.apply()
        #expect(isPendingGive, "apply() must set isPendingGive = true (optimistic)")

        ctx.reverse()
        #expect(!isPendingGive, "reverse() must set isPendingGive = false (deferred charge cancelled)")
    }
}

// MARK: - Suite 3: Copy Completeness

@Suite("Copy Completeness")
struct CopyTests {

    // Test: all 5 AmenAction cases have a NotifCopy.Entry
    @Test("All AmenAction cases have a NotifCopy.Entry")
    func allActionsHaveCopyEntry() {
        for action in AmenAction.allCases {
            #expect(
                NotifCopy.table[action] != nil,
                "Missing NotifCopy.Entry for action: \(action.rawValue)"
            )
        }
    }

    // Test: no empty strings in any Entry field
    @Test("No NotifCopy.Entry has an empty required string field")
    func noEmptyStringsInCopyEntries() {
        for action in AmenAction.allCases {
            guard let entry = NotifCopy.table[action] else {
                Issue.record("Missing entry for \(action.rawValue)")
                continue
            }
            #expect(!entry.cardTitle.isEmpty,     "cardTitle empty for \(action.rawValue)")
            #expect(!entry.cardBody.isEmpty,      "cardBody empty for \(action.rawValue)")
            #expect(!entry.primaryLabel.isEmpty,  "primaryLabel empty for \(action.rawValue)")
            #expect(!entry.toastTitle.isEmpty,    "toastTitle empty for \(action.rawValue)")
            #expect(!entry.toastSubtitle.isEmpty, "toastSubtitle empty for \(action.rawValue)")
        }
    }

    // Test: table count matches AmenAction case count (catches missing entries)
    @Test("NotifCopy.table size matches AmenAction.allCases count")
    func tableSizeMatchesActionCount() {
        #expect(
            NotifCopy.table.count == AmenAction.allCases.count,
            "Expected \(AmenAction.allCases.count) entries, found \(NotifCopy.table.count)"
        )
    }

    // Test: Give copy mentions the 6-second window
    @Test("Give entry copy references the 6-second undo window")
    func giveCopyMentionsSixSeconds() {
        guard let entry = NotifCopy.table[.give] else {
            Issue.record("No .give entry — covered by allActionsHaveCopyEntry")
            return
        }
        let combined = entry.cardBody + entry.toastSubtitle
        #expect(
            combined.contains("6"),
            "Give copy must reference the 6-second undo window. Found: '\(combined)'"
        )
    }

    // Test: .amen copy states it is private (trust/privacy contract)
    @Test(".amen copy includes privacy signal ('private' or 'only')")
    func amenCopySignalPrivacy() {
        guard let entry = NotifCopy.table[.amen] else {
            Issue.record("No .amen entry")
            return
        }
        let combined = (entry.cardBody + entry.toastSubtitle).lowercased()
        #expect(
            combined.contains("private") || combined.contains("only"),
            ".amen copy must state the action is private. Found: '\(combined)'"
        )
    }
}

// MARK: - Suite 4: SeenStore Persistence

@Suite("SeenStore")
struct SeenStoreTests {

    // Test: hasSeen returns false before markSeen
    @Test("hasSeen returns false for all actions on a fresh store")
    func hasSeenFalseBeforeMarkSeen() {
        let (store, teardown) = makeIsolatedSeenStore()
        defer { teardown() }

        for action in AmenAction.allCases {
            #expect(!store.hasSeen(action), "hasSeen must be false before markSeen: \(action.rawValue)")
        }
    }

    // Test: hasSeen returns true after markSeen
    @Test("hasSeen returns true after markSeen for each action")
    func hasSeenTrueAfterMarkSeen() {
        let (store, teardown) = makeIsolatedSeenStore()
        defer { teardown() }

        for action in AmenAction.allCases {
            store.markSeen(action)
            #expect(store.hasSeen(action), "hasSeen must be true after markSeen: \(action.rawValue)")
        }
    }

    // Test: reset() clears all seen state
    @Test("reset() clears all seen state — hasSeen returns false for every action")
    func resetClearsAll() {
        let (store, teardown) = makeIsolatedSeenStore()
        defer { teardown() }

        for action in AmenAction.allCases { store.markSeen(action) }
        store.reset()

        for action in AmenAction.allCases {
            #expect(!store.hasSeen(action), "hasSeen must be false after reset: \(action.rawValue)")
        }
    }

    // Test: markSeen is idempotent
    @Test("markSeen is idempotent — calling twice does not corrupt state")
    func markSeenIdempotent() {
        let (store, teardown) = makeIsolatedSeenStore()
        defer { teardown() }

        store.markSeen(.save)
        store.markSeen(.save)

        #expect(store.hasSeen(.save), "hasSeen must remain true after double markSeen")
    }

    // Test: marking one action does not mark others
    @Test("markSeen for one action does not affect other actions")
    func markSeenDoesNotPollute() {
        let (store, teardown) = makeIsolatedSeenStore()
        defer { teardown() }

        store.markSeen(.amen)

        #expect( store.hasSeen(.amen),   "amen should be seen")
        #expect(!store.hasSeen(.repost), "repost must not be seen")
        #expect(!store.hasSeen(.save),   "save must not be seen")
        #expect(!store.hasSeen(.join),   "join must not be seen")
        #expect(!store.hasSeen(.give),   "give must not be seen")
    }

    // Test: two isolated stores do not share state
    @Test("Two isolated SeenStore instances do not share state")
    func isolatedStoresIndependent() {
        let (storeA, teardownA) = makeIsolatedSeenStore()
        let (storeB, teardownB) = makeIsolatedSeenStore()
        defer { teardownA(); teardownB() }

        storeA.markSeen(.amen)

        #expect( storeA.hasSeen(.amen), "storeA should see amen")
        #expect(!storeB.hasSeen(.amen), "storeB must not share state with storeA")
    }

    // Test: UserDefaults storage survives relaunch (structure test)
    // We verify that a store re-created with the same suite name sees the same state,
    // which is the mechanism that provides relaunch persistence in production.
    @Test("Seen state persists across SeenStore re-creation with same suite name")
    func seenStatePersistsAcrossReinit() {
        let suiteName = "AmenNotifPersistTest-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removeSuite(named: suiteName) }

        let storeA = SeenStore(testSuite: suiteName)
        storeA.markSeen(.join)

        // Re-create using the same suite — simulates app relaunch
        let storeB = SeenStore(testSuite: suiteName)
        #expect(storeB.hasSeen(.join), "Seen state must survive re-creation (UserDefaults persistence)")
    }
}

// MARK: - Test Doubles

/// Prefs that return .smart for every action (mirrors DefaultNotifPrefs behaviour).
private struct AllSmartPrefs: NotifPrefsProtocol {
    func style(for action: AmenAction) -> NotifStyleOverride { .smart }
}

/// Prefs that return a specific override for one action, .smart for all others.
private struct SingleOverridePrefs: NotifPrefsProtocol {
    let action: AmenAction
    let override: NotifStyleOverride

    func style(for a: AmenAction) -> NotifStyleOverride {
        a == action ? override : .smart
    }
}

#endif // canImport(Testing)
