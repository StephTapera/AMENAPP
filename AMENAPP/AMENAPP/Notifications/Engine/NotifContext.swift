// NotifContext.swift
// AMENAPP — Smart Notification Engine
//
// Defines the core domain types for the notification system:
//   - AmenAction:    the five user-facing actions that can trigger a notification
//   - NotifStyle:    card (first-time education) vs toast (repeat / low friction)
//   - NotifContext:  the payload passed to NotificationCoordinator.fire(_:)
//   - AmenNotifications: public fire point used at call sites

import SwiftUI

// MARK: - AmenAction

/// The five first-party actions that drive notifications in AMEN.
/// Raw string values are stored in SeenStore / UserDefaults.
enum AmenAction: String, CaseIterable, Codable {
    case amen
    case repost
    case save
    case join
    case give
}

// MARK: - NotifStyle

/// Determines which UI component the view layer renders.
///
/// - `card`:  Full educational card — shown the first time an action is taken.
/// - `toast`: Compact confirmation strip — shown on repeat actions.
enum NotifStyle {
    case card
    case toast
}

// MARK: - NotifContext

/// The payload that describes a single notification event.
///
/// ### Give-action semantics
/// `apply()` is called *immediately* (optimistic UX) when `fire(_:)` is
/// invoked. For a Give, this should enqueue a delayed Firestore write that
/// fires only after `undoWindow` elapses. The engine itself never touches
/// Firestore — it simply calls `apply()` at fire time and `reverse()` if
/// the user taps Undo before the timer expires.
///
/// - Parameters:
///   - action:      The `AmenAction` that triggered this notification.
///   - actorName:   Display name of the acting user (for future card personalisation).
///   - toneColors:  A (primary, accent) color pair used by the card/toast gradient.
///   - undoWindow:  Seconds before the change is committed. Give = 6.0, others = 4.2.
///   - apply:       Closure executed immediately at `fire` time — performs the action.
///   - reverse:     Closure executed on `undo()` — rolls back the action.
struct NotifContext {
    let action: AmenAction
    let actorName: String
    let toneColors: (Color, Color)
    let undoWindow: TimeInterval   // give = 6.0, all others = 4.2
    let apply: () -> Void
    let reverse: () -> Void
}

// MARK: - AmenNotifications (Public Entry Point)

/// Thin namespace used at call sites so they never import the coordinator directly.
///
/// Usage:
/// ```swift
/// AmenNotifications.fire(NotifContext(action: .amen, ...))
/// ```
enum AmenNotifications {
    @MainActor
    static func fire(_ ctx: NotifContext) {
        NotificationCoordinator.shared.fire(ctx)
    }
}
