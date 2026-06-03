// AmenNotificationCard+Accessibility.swift
// AMENAPP — Notifications/Views
//
// Accessibility extension for AmenNotificationCard (Agent A's file).
// This file is Agent D's contribution — we do NOT edit AmenNotificationCard.swift.
//
// EXTENSION LIMITATIONS (read before modifying):
// =================================================
// Swift extensions cannot retroactively add stored properties or modify a
// view's body.  As a result, the accessibility modifiers defined here provide
// *helper* values and a wrapper view — they cannot be silently injected into
// the existing card's body hierarchy.
//
// TWO INTEGRATION PATHS:
//   Path A (preferred) — Agent A adds two lines to AmenNotificationCard.body:
//       .accessibilityElement(children: .combine)
//       .accessibilityLabel(a11yCardLabel(title: titleText, body: bodyLeadingText))
//       .accessibilityHint(a11yCardHint(undoWindow: undoWindow))
//   Path B (zero-touch) — Call sites wrap AmenNotificationCard in
//       AccessibleNotificationCard { AmenNotificationCard(...) }
//       defined at the bottom of this file.
//
// The announcement on `.onAppear` is self-contained and works via
// AccessibleNotificationCard without touching Agent A's code.

import SwiftUI
import UIKit

// MARK: - AmenNotificationCard Accessibility Helpers

extension AmenNotificationCard {

    // MARK: Computed accessibility strings

    /// Combined VoiceOver label: "[CardTitle]. [CardBody]. Double-tap to confirm."
    ///
    /// Parameters match the private computed vars inside AmenNotificationCard.
    /// Pass them from the card's call site or from Agent A's body via a helper.
    ///
    /// Example (Agent A adds to body):
    /// ```swift
    /// .accessibilityLabel(a11yCardLabel(title: titleText, body: bodyLeadingText))
    /// ```
    func a11yCardLabel(title: String, body: String) -> String {
        "\(title). \(body). Double-tap to confirm."
    }

    /// VoiceOver hint: "Swipe right for Undo. N seconds remaining."
    ///
    /// Example (Agent A adds to body):
    /// ```swift
    /// .accessibilityHint(a11yCardHint(undoWindow: undoWindow))
    /// ```
    func a11yCardHint(undoWindow: TimeInterval) -> String {
        "Swipe right for Undo. \(Int(undoWindow)) seconds remaining."
    }

    /// Accessibility label for the Undo button:
    /// "Undo [action]. N seconds remaining."
    ///
    /// Agent A should apply this to the Ghost Undo Button:
    /// ```swift
    /// .accessibilityLabel(a11yUndoLabel(remaining: undoRemaining))
    /// ```
    func a11yUndoLabel(remaining: TimeInterval) -> String {
        "Undo \(action.displayName). \(Int(remaining)) seconds remaining."
    }

    // MARK: NOTE FOR AGENT A
    // ──────────────────────
    // To fully satisfy the accessibility contract, add the following modifiers
    // to AmenNotificationCard's `cardContent` var:
    //
    //   .accessibilityElement(children: .combine)
    //   .accessibilityLabel(a11yCardLabel(title: titleText, body: bodyLeadingText))
    //   .accessibilityHint(a11yCardHint(undoWindow: undoWindow))
    //
    // And replace the existing Undo button's .accessibilityLabel with:
    //   .accessibilityLabel(a11yUndoLabel(remaining: undoRemaining))
    //
    // Until those two lines are added, use `AccessibleNotificationCard` (below)
    // at the call site as a zero-touch wrapper.
}

// MARK: - AccessibleNotificationCard (zero-touch wrapper)

/// Wraps `AmenNotificationCard` to supply the full accessibility contract
/// without requiring any changes to Agent A's file.
///
/// Usage at call sites (e.g. the overlay view that renders active cards):
/// ```swift
/// AccessibleNotificationCard(
///     action: ctx.action,
///     cardTitle: titleText,
///     cardBody: bodyText,
///     undoWindow: ctx.undoWindow
/// ) {
///     AmenNotificationCard(
///         action: ctx.action,
///         actorName: ctx.actorName,
///         toneColors: ctx.toneColors,
///         onLearnMore: { ... },
///         onPrimary: { ... },
///         onUndo: { ... },
///         undoWindow: ctx.undoWindow
///     )
/// }
/// ```
struct AccessibleNotificationCard<Content: View>: View {

    let action: AmenAction
    let cardTitle: String
    let cardBody: String
    let undoWindow: TimeInterval
    @ViewBuilder let content: () -> Content

    @State private var announcementFired = false

    var body: some View {
        content()
            // Group the entire card as one VoiceOver element
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(cardTitle). \(cardBody). Double-tap to confirm.")
            .accessibilityHint("Swipe right for Undo. \(Int(undoWindow)) seconds remaining.")
            .onAppear {
                guard !announcementFired else { return }
                announcementFired = true
                // Brief delay so the card entrance animation settles before
                // VoiceOver speaks — avoids the announcement being cut off.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: cardTitle
                    )
                }
            }
    }
}
