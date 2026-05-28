// SpacesChatModels.swift
// AMENAPP — Spaces Chat Core (Agent B)
//
// Additive models for the ChatCore layer.
//
// NOTE: SpaceMessage and SpaceThread are already declared in:
//   AMENAPP/Spaces/Chat/SpacesChatModels.swift  — SpaceMessage, ThreadSummary, etc.
//   AMENAPP/AMENAPP/Spaces/SpacesModels.swift   — SpaceThread (Firestore-backed)
//
// This file owns only what those files do not provide:
//   - SpaceFilterSignals: per-space unread + VIP signals for Agent C's list view
//   - SpaceDraftMessage: local compose state (never persisted as-is)
//
// Firestore authority: spaces-spec/CONTRACT_A.md
// All agents import SpaceFilterSignals from here. Do not redefine.

import Foundation

// MARK: - SpaceFilterSignals

/// Per-space signals that drive the All / VIP / Unreads / External list view
/// in Agent C's Spaces navigation shell.
///
/// Computed by `SpacesFilterService` and exposed on `SpacesChatViewModel.filterSignals`.
/// Agent C imports these; it does NOT recompute them.
struct SpaceFilterSignals {
    /// The spaceId these signals belong to.
    let spaceId: String

    /// True if the user has at least one unread message in this space.
    let hasUnread: Bool

    /// Total count of messages the user has not yet read in this space.
    /// Sourced from local `lastSeenAt` in UserDefaults vs. thread `lastMessageAt`.
    let unreadCount: Int

    /// True if any member of this space has a non-empty `homeCommunityId`
    /// (i.e., they are from a linked external community).
    let hasExternalMembers: Bool

    /// Preview text of the most recent active (non-deleted) message, if any.
    let latestMessagePreview: String?

    /// Timestamp of the most recent message, for sorting the space list.
    let latestMessageAt: Date?

    /// True if the space is starred by the current user (stored in UserDefaults).
    /// VIP = spaces manually starred. An optional future pass can upgrade this
    /// to "any recent message author is in the user's following list".
    let isVIP: Bool
}

// MARK: - SpaceDraftMessage

/// Local compose state. Never written to Firestore as-is;
/// `SpacesChatViewModel.sendMessage()` reads `.body` and calls the service.
struct SpaceDraftMessage {
    var body: String = ""
    var replyToMessageId: String? = nil
    var attachments: [DraftAttachment] = []

    var isReady: Bool {
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - DraftAttachment

/// Transient local attachment before upload. Resolved to a `MessageAttachment`
/// after the upload completes; never stored in this form.
struct DraftAttachment: Identifiable {
    let id: String = UUID().uuidString
    var localURL: URL
    var mimeType: String
    var fileName: String
}
