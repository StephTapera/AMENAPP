//
//  MessagingInboxFilterAvailability.swift
//  AMENAPP
//
//  Derives `MessagingInboxFilterCapabilities` and per-conversation
//  `MessagingConversationMetadata` from the inbox state we already have
//  locally. Only filters with REAL backing data are reported available —
//  everything else stays hidden so the picker never lies.
//
//  Phase 1 (local-only):
//      - hasUnread          (ChatConversation.unreadCount > 0)
//      - hasGroups          (ChatConversation.isGroup)
//      - hasMuted           (ChatConversation.isMuted)
//      - hasUnknownContacts (ChatConversation.status == "pending")
//      - hasArchived        (archived list non-empty)
//
//  Everything else stays false until backend signals land (Phase 3/4).
//

import Foundation

@available(iOS 17.0, *)
public enum MessagingInboxFilterAvailability {

    /// Compute capabilities from the locally-available conversation state.
    /// Caller is responsible for any block/permission filtering before
    /// passing the array in; we only inspect fields on `ChatConversation`.
    public static func capabilities(
        conversations: [ChatConversation],
        archivedConversations: [ChatConversation],
        canViewBlocked: Bool = false,
        prayerRequestConversationIds: Set<String> = [],
        safetyReviewConversationIds: Set<String> = [],
        blockedConversationIds: Set<String> = []
    ) -> MessagingInboxFilterCapabilities {
        MessagingInboxFilterCapabilities(
            hasUnread: conversations.contains(where: { $0.unreadCount > 0 }),
            hasDrafts: false,
            hasMentions: false,
            hasNeedsReply: false,
            hasStarred: false,
            hasUnknownContacts: conversations.contains(where: { $0.status == "pending" }),
            hasGroups: conversations.contains(where: { $0.isGroup }),
            hasPrayerRequests: !prayerRequestConversationIds.isEmpty,
            hasMedia: false,
            hasLinks: false,
            hasFiles: false,
            hasScheduled: false,
            hasMuted: conversations.contains(where: { $0.isMuted }),
            hasArchived: !archivedConversations.isEmpty,
            canViewBlocked: canViewBlocked,
            hasBlocked: !blockedConversationIds.isEmpty,
            hasSafetyReviewSignals: !safetyReviewConversationIds.isEmpty
        )
    }

    /// Build a metadata adapter closure suitable for
    /// `MessagingInboxFilter.apply(to:metadata:)`. Each per-conversation
    /// boolean is derived only from real signal sets the caller passes —
    /// never invented locally.
    public static func metadataAdapter(
        prayerRequestConversationIds: Set<String> = [],
        safetyReviewConversationIds: Set<String> = [],
        blockedConversationIds: Set<String> = [],
        archivedConversationIds: Set<String> = []
    ) -> (ChatConversation) -> MessagingConversationMetadata {
        return { conversation in
            MessagingConversationMetadata(
                hasDraft: false,
                hasMentionForUser: false,
                needsReply: false,
                isStarred: false,
                isUnknownContact: conversation.status == "pending",
                hasPrayerRequest: prayerRequestConversationIds.contains(conversation.id),
                hasMedia: false,
                hasLink: false,
                hasFile: false,
                hasScheduled: false,
                isArchivedForUser: archivedConversationIds.contains(conversation.id),
                isBlockedOrRestricted: blockedConversationIds.contains(conversation.id),
                needsSafetyReview: safetyReviewConversationIds.contains(conversation.id)
            )
        }
    }
}
