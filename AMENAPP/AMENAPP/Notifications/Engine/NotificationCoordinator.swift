// NotificationCoordinator.swift
// AMENAPP — Smart Notification Engine
//
// @MainActor ObservableObject observed by the root view overlay.
// Drives both card (first-time education) and toast (repeat) presentation
// through a single @Published var — the view layer reads `.style` to
// decide which component to render.
//
// Notification lifecycle:
//   fire(_:) → optimistic apply → show card/toast → auto-dismiss after undoWindow
//   undo()   → cancel timer → reverse() → clear activeCard
//   dismiss()→ cancel timer → commit (keep change) → clear activeCard
//
// Give-action note:
//   ctx.apply() is called immediately (optimistic). For Give actions the
//   caller's apply closure must schedule its own delayed Firestore write
//   that fires only after undoWindow elapses — the engine never directly
//   touches the database. ctx.reverse() cancels that pending write.
//
// Agent D integration:
//   Set NotificationCoordinator.shared.prefs = <your NotifPrefsProtocol>
//   from your module's init. The coordinator will then query per-action
//   style overrides before deciding card vs toast vs off.

import SwiftUI
import Combine

// MARK: - NotifPrefsProtocol

/// Implemented by Agent D's NotifPrefs to supply per-action style overrides.
///
/// Signature (copy verbatim into your conforming type):
/// ```swift
/// func style(for action: AmenAction) -> NotifStyleOverride
/// ```
protocol NotifPrefsProtocol {
    /// Returns the user's preferred display style for the given action.
    func style(for action: AmenAction) -> NotifStyleOverride
}

// MARK: - NotifStyleOverride

/// User-configurable display mode for a given action.
enum NotifStyleOverride {
    /// Default behaviour: show the educational card the first time (per SeenStore),
    /// then fall back to a toast on all subsequent fires.
    case smart

    /// Always show the full educational card, regardless of SeenStore state.
    case alwaysCard

    /// Skip the card entirely; always show the compact toast.
    case toastOnly

    /// Suppress all notification UI for this action.
    case off
}

// MARK: - NotificationCoordinator

/// Root coordinator for the smart notification engine.
///
/// Observed by the root view overlay via `@StateObject` or `@EnvironmentObject`.
/// A single `activeCard` published var drives both card and toast presentation —
/// the view inspects `activeCard?.style` to pick the right component.
@MainActor
final class NotificationCoordinator: ObservableObject {

    // MARK: - Singleton

    static let shared = NotificationCoordinator()

    // MARK: - Published State

    /// Non-nil while a notification is visible. `style` tells the view layer
    /// which component to render (`.card` or `.toast`).
    @Published var activeCard: (ctx: NotifContext, style: NotifStyle)? = nil

    // MARK: - Injected Prefs

    /// Injected by Agent D. Defaults to smart-for-all until overridden.
    var prefs: NotifPrefsProtocol = DefaultNotifPrefs()

    // MARK: - Private

    /// Cancels itself when a new notification fires or undo/dismiss is called.
    private var dismissTimer: Task<Void, Never>?
    private var _seenStore: SeenStore = .shared

    private init() {}

    #if DEBUG
    internal convenience init(seenStore: SeenStore) {
        self.init()
        self._seenStore = seenStore
    }
    #endif

    // MARK: - Public API

    /// Fires a notification for the given context.
    ///
    /// Steps:
    /// 1. Resolve style override from `prefs`; bail out early if `.off`.
    /// 2. Determine concrete `NotifStyle` (smart uses SeenStore; others use override).
    /// 3. Cancel any in-flight notification immediately (no queue — last one wins).
    /// 4. Call `ctx.apply()` for the optimistic change.
    /// 5. Present card or toast by writing to `activeCard`.
    /// 6. Start an auto-dismiss `Task` that expires after `ctx.undoWindow`;
    ///    on expiry the change is committed (kept) and `activeCard` is cleared.
    func fire(_ ctx: NotifContext) {
        // 1. Resolve pref override
        let override = prefs.style(for: ctx.action)
        guard override != .off else { return }

        // 2. Determine concrete style
        let style: NotifStyle
        switch override {
        case .smart:
            // First time → card; subsequent → toast
            style = _seenStore.hasSeen(ctx.action) ? .toast : .card
        case .alwaysCard:
            style = .card
        case .toastOnly:
            style = .toast
        case .off:
            return  // guarded above — unreachable
        }

        // 3. Cancel any existing notification
        cancelTimer()
        // Clear previous card immediately so view resets before the new one appears
        activeCard = nil

        // 4. Optimistic apply — the caller's closure owns any async Firestore work
        ctx.apply()

        // 5. Mark seen (only meaningful for card style, but safe to call always)
        if style == .card {
            _seenStore.markSeen(ctx.action)
        }

        // Present notification
        activeCard = (ctx: ctx, style: style)

        // 6. Auto-dismiss after undoWindow: commit = keep change, clear UI
        dismissTimer = Task {
            try? await Task.sleep(nanoseconds: UInt64(ctx.undoWindow * 1_000_000_000))
            guard !Task.isCancelled else { return }
            // Change is already applied — just clear the UI
            activeCard = nil
        }
    }

    /// Cancels the pending change: stops the timer, calls `reverse()`, hides UI.
    func undo() {
        guard let current = activeCard else { return }
        cancelTimer()
        current.ctx.reverse()
        activeCard = nil
    }

    /// Explicitly commits the change: stops the timer, keeps apply(), hides UI.
    func dismiss() {
        cancelTimer()
        // Change is already applied via ctx.apply() — nothing extra to do
        activeCard = nil
    }

    /// Resets the SeenStore so educational cards will appear again.
    /// Called from the Settings screen ("Reset Notification Tips").
    func resetSeen() {
        _seenStore.reset()
    }

    // MARK: - Private Helpers

    private func cancelTimer() {
        dismissTimer?.cancel()
        dismissTimer = nil
    }
}

// MARK: - DefaultNotifPrefs

/// Fallback prefs: every action uses `.smart` until Agent D injects real prefs.
private struct DefaultNotifPrefs: NotifPrefsProtocol {
    func style(for action: AmenAction) -> NotifStyleOverride { .smart }
}
