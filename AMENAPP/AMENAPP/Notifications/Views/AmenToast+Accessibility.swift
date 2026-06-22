// AmenToast+Accessibility.swift
// AMENAPP — Notifications/Views
//
// Accessibility extension for AmenToast (Agent A's file).
// This file is Agent D's contribution — we do NOT edit AmenToast.swift.
//
// EXTENSION LIMITATIONS:
// =======================
// Agent A's AmenToast already applies .accessibilityElement(children: .combine)
// and a combined label on its `toastPill` var (lines 104–106 of AmenToast.swift).
// The extension below enhances that baseline with:
//   1. Richer label strings accessible to Agent A via helper methods.
//   2. An action-aware Undo label (uses AmenAction.displayName from NotifPrefs.swift).
//   3. Dynamic Type note: the pill uses .lineLimit(1) on both text lines, which
//      clips at XXL+ sizes.  Agent A should switch to .lineLimit(nil) / .fixedSize()
//      on the subtitle Text at XXL scale, or increase the pill's min-height.
//   4. A zero-touch wrapper `AccessibleToast` for call sites.
//
// NOTE FOR AGENT A on Dynamic Type:
// ----------------------------------
// At XXL accessibility text sizes the subtitle line ("Jordan will be encouraged")
// clips due to .lineLimit(1). Replace the subtitle Text's lineLimit with:
//
//   .lineLimit(sizeCategory >= .accessibilityMedium ? 2 : 1)
//
// adding @Environment(\.sizeCategory) private var sizeCategory to AmenToast.
// The pill height will grow naturally; glassSurface already clips to its bounds.

import SwiftUI
import UIKit

// MARK: - AmenToast Accessibility Helpers

extension AmenToast {

    // MARK: Computed label strings

    /// Combined VoiceOver label for the toast pill.
    /// "[title]. [subtitle]."
    ///
    /// Agent A can replace the inline string in toastPill's .accessibilityLabel with:
    /// ```swift
    /// .accessibilityLabel(a11yToastLabel(title: title, subtitle: subtitle))
    /// ```
    func a11yToastLabel(title: String, subtitle: String) -> String {
        "\(title). \(subtitle)."
    }

    /// Action-aware Undo button label.
    /// "Undo [action display name]. N seconds remaining."
    ///
    /// Replaces the generic "Undo, N seconds remaining" label on the undoButton.
    /// Agent A applies this to the undo Button:
    /// ```swift
    /// .accessibilityLabel(a11yUndoLabel(action: action, remaining: undoRemaining))
    /// ```
    func a11yUndoLabel(action: AmenAction, remaining: TimeInterval) -> String {
        "Undo \(action.displayName). \(Int(remaining)) seconds remaining."
    }
}

// MARK: - AccessibleToast (zero-touch wrapper)

/// Wraps `AmenToast` to upgrade its accessibility labels to the full contract
/// (action-aware, combined label, on-appear announcement) without touching
/// Agent A's file.
///
/// Usage at call sites (e.g. the overlay view):
/// ```swift
/// AccessibleToast(
///     action: ctx.action,
///     title: toastTitle,
///     subtitle: toastSubtitle,
///     undoWindow: ctx.undoWindow,
///     onUndo: { NotificationCoordinator.shared.undo() }
/// )
/// ```
struct AccessibleToast: View {

    let action: AmenAction
    let title: String
    let subtitle: String
    let undoWindow: TimeInterval
    let onUndo: () -> Void

    @State private var undoRemaining: TimeInterval
    @State private var announcementFired = false

    init(
        action: AmenAction,
        title: String,
        subtitle: String,
        undoWindow: TimeInterval,
        onUndo: @escaping () -> Void
    ) {
        self.action = action
        self.title = title
        self.subtitle = subtitle
        self.undoWindow = undoWindow
        self.onUndo = onUndo
        self._undoRemaining = State(initialValue: undoWindow)
    }

    var body: some View {
        AmenToast(
            action: action,
            title: title,
            subtitle: subtitle,
            undoWindow: undoWindow,
            onUndo: onUndo
        )
        // Override the baseline label with the action-aware version.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle). Undo \(action.displayName) available for \(Int(undoRemaining)) seconds.")
        .accessibilityAction(named: "Undo \(action.displayName)") { onUndo() }
        .onAppear {
            guard !announcementFired else { return }
            announcementFired = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                UIAccessibility.post(
                    notification: .announcement,
                    argument: "\(title). \(subtitle)."
                )
            }
        }
    }
}

// MARK: - Dynamic Type note
//
// AmenToast uses .lineLimit(1) on both Text lines inside toastPill.
// At iOS accessibility text sizes (XXL and above) the subtitle clips silently.
//
// Recommended fix for Agent A (single line change in AmenToast.swift):
//
//   // Add environment read at top of AmenToast struct:
//   @Environment(\.sizeCategory) private var sizeCategory
//
//   // Change subtitle Text's lineLimit:
//   .lineLimit(sizeCategory >= .accessibilityMedium ? 2 : 1)
//
// The pill's glassSurface uses .frame for horizontal constraints only;
// vertical growth is unconstrained, so the pill will expand cleanly.
