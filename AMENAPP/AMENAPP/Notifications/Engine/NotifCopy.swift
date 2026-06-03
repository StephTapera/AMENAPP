// NotifCopy.swift
// AMENAPP — Smart Notification Engine
//
// Single source of truth for all UI strings in the notification system.
// No notification-related user-facing copy lives anywhere else.
//
// Structure:
//   NotifCopy.table[.amen]?.cardTitle   // "You Prayed With Someone"
//   NotifCopy.table[.give]?.toastTitle  // "Gift Pending"

import Foundation

// MARK: - NotifCopy

enum NotifCopy {

    // MARK: - Entry

    /// All strings needed to render both the card and the toast for one action.
    struct Entry {
        /// Heading displayed in the full educational card.
        let cardTitle: String

        /// Body text for the card. May contain the literal string "Learn more"
        /// as a marker for views that want to render a tappable link anchor.
        let cardBody: String

        /// Optional URL surfaced via the "Learn more" anchor in `cardBody`.
        /// `nil` means no learn-more link is shown.
        let learnMoreURL: String?

        /// Label for the card's primary CTA button.
        let primaryLabel: String

        /// Short title shown in the compact toast.
        let toastTitle: String

        /// Secondary subtitle shown beneath `toastTitle` in the toast.
        let toastSubtitle: String
    }

    // MARK: - Table

    /// Keyed by `AmenAction`. All five actions are guaranteed to have an entry.
    static let table: [AmenAction: Entry] = [

        .amen: Entry(
            cardTitle: "You Prayed With Someone",
            cardBody: "When you Amen a post, you're letting them know you're standing with them in prayer. This is private — only they can see it.",
            learnMoreURL: nil,
            primaryLabel: "Keep Praying",
            toastTitle: "Prayed With",
            toastSubtitle: "Only they can see this"
        ),

        .repost: Entry(
            cardTitle: "You Shared This",
            cardBody: "Reposting amplifies this moment to your Sanctuary. The original author is notified.",
            learnMoreURL: nil,
            primaryLabel: "Got It",
            toastTitle: "Reposted",
            toastSubtitle: "Your Sanctuary can see this"
        ),

        .save: Entry(
            cardTitle: "Saved to Your Library",
            cardBody: "Saved posts live in your private Library. Only you can see them.",
            learnMoreURL: nil,
            primaryLabel: "View Library",
            toastTitle: "Saved",
            toastSubtitle: "Private to you"
        ),

        .join: Entry(
            cardTitle: "You Joined a Sanctuary",
            cardBody: "You're now part of this Sanctuary. Members can see you in the roster.",
            learnMoreURL: nil,
            primaryLabel: "Explore Sanctuary",
            toastTitle: "Joined Sanctuary",
            toastSubtitle: "Members can see you"
        ),

        .give: Entry(
            cardTitle: "Gift Pending Confirmation",
            cardBody: "Your gift will be sent when the window closes. Tap Undo within 6 seconds to cancel.",
            learnMoreURL: nil,
            primaryLabel: "Confirm Gift",
            toastTitle: "Gift Pending",
            toastSubtitle: "Tap Undo to cancel"
        )
    ]
}
