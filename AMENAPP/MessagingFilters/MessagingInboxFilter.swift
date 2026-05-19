//
//  MessagingInboxFilter.swift
//  AMENAPP
//
//  Apple Mail-style inbox filter set. Each filter has a stable analytics key,
//  a localized display title, an SF Symbol, and an `isAvailable(...)` predicate
//  that hides the filter when the data needed to back it does not exist.
//
//  Rules (set by product):
//    1. Only show filters that can be backed by real data.
//    2. Never fake counts.
//    3. High-risk filters (prayerRequest, safetyReview, unknownContact, blocked,
//       restricted) must be wired to real backend/user-relationship signals —
//       this model exposes the *availability* gate, but the calling site must
//       still supply a real signal.
//

import Foundation
import SwiftUI

// MARK: - Filter Enum

public enum MessagingInboxFilter: String, CaseIterable, Identifiable, Equatable {
    case all
    case unread
    case drafts
    case mentions
    case needsReply
    case starred
    case unknown
    case groups
    case prayerRequests
    case media
    case links
    case files
    case scheduled
    case muted
    case archived
    case blocked
    case safetyReview

    public var id: String { rawValue }

    /// Localized title shown on the filter pill / in the picker.
    public var title: String {
        switch self {
        case .all:            return "All"
        case .unread:         return "Unread"
        case .drafts:         return "Unsent Drafts"
        case .mentions:       return "Mentions"
        case .needsReply:     return "Needs Reply"
        case .starred:        return "Starred"
        case .unknown:        return "Unknown Contacts"
        case .groups:         return "Groups"
        case .prayerRequests: return "Prayer Requests"
        case .media:          return "Media"
        case .links:          return "Links"
        case .files:          return "Files"
        case .scheduled:      return "Scheduled"
        case .muted:          return "Muted"
        case .archived:       return "Archived"
        case .blocked:        return "Blocked"
        case .safetyReview:   return "Safety Review"
        }
    }

    /// Short, stable string used as the analytics `filter` parameter.
    /// Never localized — these are dashboard keys, not user-facing labels.
    public var analyticsKey: String { rawValue }

    /// SF Symbol shown to the left of the pill label.
    public var symbol: String {
        switch self {
        case .all:            return "tray.full"
        case .unread:         return "circle.fill"
        case .drafts:         return "pencil.line"
        case .mentions:       return "at"
        case .needsReply:     return "arrowshape.turn.up.left"
        case .starred:        return "star.fill"
        case .unknown:        return "person.crop.circle.badge.questionmark"
        case .groups:         return "person.3.fill"
        case .prayerRequests: return "hands.sparkles"
        case .media:          return "photo.on.rectangle"
        case .links:          return "link"
        case .files:          return "doc"
        case .scheduled:      return "clock.badge"
        case .muted:          return "bell.slash"
        case .archived:       return "archivebox"
        case .blocked:        return "hand.raised.fill"
        case .safetyReview:   return "checkmark.shield"
        }
    }

    /// VoiceOver hint when the user taps the filter pill.
    public var voiceOverHint: String { "Double tap to change message filter" }
}

// MARK: - Availability Capabilities

/// Bundle of capability flags the caller passes to determine which filters
/// can actually be backed by real, present data. Hide anything not backed.
///
/// We pass simple booleans (not collection counts) so the predicate is cheap
/// and never invents data. Each value should be computed by the call site from
/// the conversations array or user permissions, not the filter UI.
public struct MessagingInboxFilterCapabilities: Equatable {
    public var hasUnread: Bool
    public var hasDrafts: Bool
    public var hasMentions: Bool
    public var hasNeedsReply: Bool
    public var hasStarred: Bool
    public var hasUnknownContacts: Bool
    public var hasGroups: Bool
    public var hasPrayerRequests: Bool
    public var hasMedia: Bool
    public var hasLinks: Bool
    public var hasFiles: Bool
    public var hasScheduled: Bool
    public var hasMuted: Bool
    public var hasArchived: Bool
    /// Permission gate: true only when the user is allowed to view blocked/restricted.
    public var canViewBlocked: Bool
    public var hasBlocked: Bool
    /// True only when real safety signals exist on at least one conversation.
    public var hasSafetyReviewSignals: Bool

    public init(
        hasUnread: Bool = false,
        hasDrafts: Bool = false,
        hasMentions: Bool = false,
        hasNeedsReply: Bool = false,
        hasStarred: Bool = false,
        hasUnknownContacts: Bool = false,
        hasGroups: Bool = false,
        hasPrayerRequests: Bool = false,
        hasMedia: Bool = false,
        hasLinks: Bool = false,
        hasFiles: Bool = false,
        hasScheduled: Bool = false,
        hasMuted: Bool = false,
        hasArchived: Bool = false,
        canViewBlocked: Bool = false,
        hasBlocked: Bool = false,
        hasSafetyReviewSignals: Bool = false
    ) {
        self.hasUnread = hasUnread
        self.hasDrafts = hasDrafts
        self.hasMentions = hasMentions
        self.hasNeedsReply = hasNeedsReply
        self.hasStarred = hasStarred
        self.hasUnknownContacts = hasUnknownContacts
        self.hasGroups = hasGroups
        self.hasPrayerRequests = hasPrayerRequests
        self.hasMedia = hasMedia
        self.hasLinks = hasLinks
        self.hasFiles = hasFiles
        self.hasScheduled = hasScheduled
        self.hasMuted = hasMuted
        self.hasArchived = hasArchived
        self.canViewBlocked = canViewBlocked
        self.hasBlocked = hasBlocked
        self.hasSafetyReviewSignals = hasSafetyReviewSignals
    }
}

public extension MessagingInboxFilter {

    /// True when this filter has real backing data and should be shown.
    /// `.all` is always available.
    func isAvailable(in caps: MessagingInboxFilterCapabilities) -> Bool {
        switch self {
        case .all:            return true
        case .unread:         return caps.hasUnread
        case .drafts:         return caps.hasDrafts
        case .mentions:       return caps.hasMentions
        case .needsReply:     return caps.hasNeedsReply
        case .starred:        return caps.hasStarred
        case .unknown:        return caps.hasUnknownContacts
        case .groups:         return caps.hasGroups
        case .prayerRequests: return caps.hasPrayerRequests
        case .media:          return caps.hasMedia
        case .links:          return caps.hasLinks
        case .files:          return caps.hasFiles
        case .scheduled:      return caps.hasScheduled
        case .muted:          return caps.hasMuted
        case .archived:       return caps.hasArchived
        case .blocked:        return caps.canViewBlocked && caps.hasBlocked
        case .safetyReview:   return caps.hasSafetyReviewSignals
        }
    }

    /// All filters that should appear in the picker for the given caps.
    /// Order is deliberate (matches the spec).
    static func available(for caps: MessagingInboxFilterCapabilities) -> [MessagingInboxFilter] {
        Self.allCases.filter { $0.isAvailable(in: caps) }
    }

    /// Short chip set — max 5, only what the user can act on right now.
    /// The chips slice is a UX convenience; the underlying picker still
    /// shows the full available list.
    static let chipPriority: [MessagingInboxFilter] = [
        .unread, .needsReply, .mentions, .drafts, .scheduled, .media, .unknown, .starred
    ]

    static func chips(for caps: MessagingInboxFilterCapabilities, max: Int = 5) -> [MessagingInboxFilter] {
        Self.chipPriority
            .filter { $0.isAvailable(in: caps) }
            .prefix(max)
            .map { $0 }
    }
}

// MARK: - Filter Application over ChatConversation

public extension MessagingInboxFilter {

    /// Apply this filter to a base list of conversations. The caller is
    /// responsible for any tab pre-filter (accepted vs requests vs archived)
    /// and for supplying the auxiliary booleans not on `ChatConversation`
    /// (mentions, drafts, scheduled, media, links, files, etc.) via the
    /// `metadata` closure.
    func apply(
        to conversations: [ChatConversation],
        metadata: (ChatConversation) -> MessagingConversationMetadata
    ) -> [ChatConversation] {
        switch self {
        case .all:
            return conversations
        case .unread:
            return conversations.filter { $0.unreadCount > 0 }
        case .drafts:
            return conversations.filter { metadata($0).hasDraft }
        case .mentions:
            return conversations.filter { metadata($0).hasMentionForUser }
        case .needsReply:
            return conversations.filter { metadata($0).needsReply }
        case .starred:
            return conversations.filter { metadata($0).isStarred }
        case .unknown:
            return conversations.filter { metadata($0).isUnknownContact }
        case .groups:
            return conversations.filter { $0.isGroup }
        case .prayerRequests:
            return conversations.filter { metadata($0).hasPrayerRequest }
        case .media:
            return conversations.filter { metadata($0).hasMedia }
        case .links:
            return conversations.filter { metadata($0).hasLink }
        case .files:
            return conversations.filter { metadata($0).hasFile }
        case .scheduled:
            return conversations.filter { metadata($0).hasScheduled }
        case .muted:
            return conversations.filter { $0.isMuted }
        case .archived:
            return conversations.filter { metadata($0).isArchivedForUser }
        case .blocked:
            return conversations.filter { metadata($0).isBlockedOrRestricted }
        case .safetyReview:
            return conversations.filter { metadata($0).needsSafetyReview }
        }
    }
}

// MARK: - Per-conversation metadata adapter

/// All the *additional* per-conversation booleans that aren't on
/// `ChatConversation` today. The call site computes these from real backend
/// signals or from a denormalized summary doc — never invented locally.
public struct MessagingConversationMetadata: Equatable {
    public var hasDraft: Bool
    public var hasMentionForUser: Bool
    public var needsReply: Bool
    public var isStarred: Bool
    public var isUnknownContact: Bool
    public var hasPrayerRequest: Bool
    public var hasMedia: Bool
    public var hasLink: Bool
    public var hasFile: Bool
    public var hasScheduled: Bool
    public var isArchivedForUser: Bool
    public var isBlockedOrRestricted: Bool
    public var needsSafetyReview: Bool

    public init(
        hasDraft: Bool = false,
        hasMentionForUser: Bool = false,
        needsReply: Bool = false,
        isStarred: Bool = false,
        isUnknownContact: Bool = false,
        hasPrayerRequest: Bool = false,
        hasMedia: Bool = false,
        hasLink: Bool = false,
        hasFile: Bool = false,
        hasScheduled: Bool = false,
        isArchivedForUser: Bool = false,
        isBlockedOrRestricted: Bool = false,
        needsSafetyReview: Bool = false
    ) {
        self.hasDraft = hasDraft
        self.hasMentionForUser = hasMentionForUser
        self.needsReply = needsReply
        self.isStarred = isStarred
        self.isUnknownContact = isUnknownContact
        self.hasPrayerRequest = hasPrayerRequest
        self.hasMedia = hasMedia
        self.hasLink = hasLink
        self.hasFile = hasFile
        self.hasScheduled = hasScheduled
        self.isArchivedForUser = isArchivedForUser
        self.isBlockedOrRestricted = isBlockedOrRestricted
        self.needsSafetyReview = needsSafetyReview
    }

    public static let empty = MessagingConversationMetadata()
}
