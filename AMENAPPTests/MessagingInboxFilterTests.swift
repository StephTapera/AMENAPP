// MessagingInboxFilterTests.swift
// AMENAPPTests
//
// System 36: Messaging Filters & Smart Inbox
// Unit tests for the inbox filter model + availability gating + apply().
// Covers:
//   - Filter availability is data-backed (no fake "yes"es)
//   - chips() respects priority + 5-cap + availability
//   - apply() uses the metadata adapter (no invented signals)
//   - All filter cases have stable analytics keys
//

import Testing
import Foundation
import SwiftUI
@testable import AMENAPP

// MARK: — Test Fixtures

private extension ChatConversation {
    static func make(
        id: String = UUID().uuidString,
        name: String = "Test User",
        unreadCount: Int = 0,
        isGroup: Bool = false,
        isMuted: Bool = false,
        status: String = "accepted",
        isPinned: Bool = false
    ) -> ChatConversation {
        ChatConversation(
            id: id,
            name: name,
            lastMessage: "Hi",
            timestamp: "now",
            isGroup: isGroup,
            unreadCount: unreadCount,
            avatarColor: .blue,
            status: status,
            profilePhotoURL: nil,
            isPinned: isPinned,
            isMuted: isMuted,
            requesterId: nil,
            otherParticipantId: "u_\(id)",
            source: .direct,
            otherUserBio: nil,
            otherUserUsername: nil
        )
    }
}

// MARK: — Availability

@Suite("MessagingInboxFilter Availability")
struct MessagingInboxFilterAvailabilityTests {

    @Test(".all is always available regardless of capabilities")
    func allFilterAlwaysAvailable() {
        let empty = MessagingInboxFilterCapabilities()
        #expect(MessagingInboxFilter.all.isAvailable(in: empty) == true)
    }

    @Test("unread is hidden when no conversation has unreadCount > 0")
    func unreadHiddenWithoutBacking() {
        let caps = MessagingInboxFilterAvailability.capabilities(
            conversations: [.make(unreadCount: 0)],
            archivedConversations: []
        )
        #expect(caps.hasUnread == false)
        #expect(MessagingInboxFilter.unread.isAvailable(in: caps) == false)
    }

    @Test("unread is shown when any conversation has unreadCount > 0")
    func unreadShownWithBacking() {
        let caps = MessagingInboxFilterAvailability.capabilities(
            conversations: [.make(unreadCount: 0), .make(unreadCount: 3)],
            archivedConversations: []
        )
        #expect(caps.hasUnread == true)
        #expect(MessagingInboxFilter.unread.isAvailable(in: caps) == true)
    }

    @Test("groups is hidden when no group conversations exist")
    func groupsHiddenWithoutBacking() {
        let caps = MessagingInboxFilterAvailability.capabilities(
            conversations: [.make(isGroup: false)],
            archivedConversations: []
        )
        #expect(caps.hasGroups == false)
        #expect(MessagingInboxFilter.groups.isAvailable(in: caps) == false)
    }

    @Test("groups is shown when at least one group exists")
    func groupsShownWithBacking() {
        let caps = MessagingInboxFilterAvailability.capabilities(
            conversations: [.make(isGroup: true)],
            archivedConversations: []
        )
        #expect(caps.hasGroups == true)
        #expect(MessagingInboxFilter.groups.isAvailable(in: caps) == true)
    }

    @Test("muted reflects ChatConversation.isMuted")
    func mutedAvailability() {
        let empty = MessagingInboxFilterAvailability.capabilities(
            conversations: [.make(isMuted: false)],
            archivedConversations: []
        )
        let withMuted = MessagingInboxFilterAvailability.capabilities(
            conversations: [.make(isMuted: true)],
            archivedConversations: []
        )
        #expect(MessagingInboxFilter.muted.isAvailable(in: empty) == false)
        #expect(MessagingInboxFilter.muted.isAvailable(in: withMuted) == true)
    }

    @Test("archived reflects archivedConversations non-empty")
    func archivedAvailability() {
        let none = MessagingInboxFilterAvailability.capabilities(
            conversations: [.make()],
            archivedConversations: []
        )
        let some = MessagingInboxFilterAvailability.capabilities(
            conversations: [.make()],
            archivedConversations: [.make()]
        )
        #expect(MessagingInboxFilter.archived.isAvailable(in: none) == false)
        #expect(MessagingInboxFilter.archived.isAvailable(in: some) == true)
    }

    @Test("unknown contacts gated by status == pending")
    func unknownAvailability() {
        let none = MessagingInboxFilterAvailability.capabilities(
            conversations: [.make(status: "accepted")],
            archivedConversations: []
        )
        let some = MessagingInboxFilterAvailability.capabilities(
            conversations: [.make(status: "pending")],
            archivedConversations: []
        )
        #expect(MessagingInboxFilter.unknown.isAvailable(in: none) == false)
        #expect(MessagingInboxFilter.unknown.isAvailable(in: some) == true)
    }

    @Test("blocked requires both canViewBlocked AND hasBlocked")
    func blockedRequiresBothGates() {
        let permOnly = MessagingInboxFilterCapabilities(canViewBlocked: true, hasBlocked: false)
        let dataOnly = MessagingInboxFilterCapabilities(canViewBlocked: false, hasBlocked: true)
        let both = MessagingInboxFilterCapabilities(canViewBlocked: true, hasBlocked: true)

        #expect(MessagingInboxFilter.blocked.isAvailable(in: permOnly) == false)
        #expect(MessagingInboxFilter.blocked.isAvailable(in: dataOnly) == false)
        #expect(MessagingInboxFilter.blocked.isAvailable(in: both) == true)
    }

    @Test("Phase 1 derives only locally-available filters — drafts/mentions/needsReply etc. stay OFF")
    func phase1DoesNotInventBackingData() {
        let caps = MessagingInboxFilterAvailability.capabilities(
            conversations: [.make(unreadCount: 1, isGroup: true, isMuted: true, status: "pending")],
            archivedConversations: [.make()]
        )
        #expect(caps.hasDrafts == false)
        #expect(caps.hasMentions == false)
        #expect(caps.hasNeedsReply == false)
        #expect(caps.hasStarred == false)
        #expect(caps.hasMedia == false)
        #expect(caps.hasLinks == false)
        #expect(caps.hasFiles == false)
        #expect(caps.hasScheduled == false)
        #expect(caps.hasPrayerRequests == false)
        #expect(caps.hasSafetyReviewSignals == false)
        #expect(caps.hasBlocked == false)
    }
}

// MARK: — Chips Slice

@Suite("MessagingInboxFilter Chips")
struct MessagingInboxFilterChipsTests {

    @Test("chips() returns empty when only .all is available")
    func chipsEmptyWhenOnlyAll() {
        let caps = MessagingInboxFilterCapabilities()
        let chips = MessagingInboxFilter.chips(for: caps)
        #expect(chips.isEmpty)
    }

    @Test("chips() honors priority order and 5-item cap")
    func chipsRespectsPriorityAndCap() {
        let caps = MessagingInboxFilterCapabilities(
            hasUnread: true,
            hasDrafts: true,
            hasMentions: true,
            hasNeedsReply: true,
            hasStarred: true,
            hasUnknownContacts: true,
            hasMedia: true,
            hasScheduled: true
        )
        let chips = MessagingInboxFilter.chips(for: caps, max: 5)
        #expect(chips.count == 5)
        // Priority order from the spec: unread, needsReply, mentions, drafts, scheduled
        #expect(chips == [.unread, .needsReply, .mentions, .drafts, .scheduled])
    }

    @Test("chips() skips unavailable filters in priority list")
    func chipsSkipsUnavailable() {
        let caps = MessagingInboxFilterCapabilities(
            hasUnread: true,
            hasDrafts: false,
            hasMentions: false,
            hasNeedsReply: false,
            hasStarred: true,
            hasMedia: true,
            hasScheduled: false
        )
        let chips = MessagingInboxFilter.chips(for: caps, max: 5)
        // unread, media, starred (no needsReply/mentions/drafts/scheduled)
        #expect(chips.contains(.unread))
        #expect(chips.contains(.starred))
        #expect(chips.contains(.media))
        #expect(chips.contains(.drafts) == false)
    }
}

// MARK: — Apply (Filtering Behavior)

@Suite("MessagingInboxFilter Apply")
struct MessagingInboxFilterApplyTests {

    @Test(".all returns the input unchanged")
    func allIsIdentity() {
        let convos = [ChatConversation.make(), .make()]
        let result = MessagingInboxFilter.all.apply(to: convos) { _ in .empty }
        #expect(result.count == convos.count)
    }

    @Test(".unread keeps only conversations with unreadCount > 0")
    func unreadFilters() {
        let a = ChatConversation.make(unreadCount: 0)
        let b = ChatConversation.make(unreadCount: 5)
        let result = MessagingInboxFilter.unread.apply(to: [a, b]) { _ in .empty }
        #expect(result.map(\.id) == [b.id])
    }

    @Test(".groups keeps only conversations with isGroup")
    func groupsFilters() {
        let dm = ChatConversation.make(isGroup: false)
        let grp = ChatConversation.make(isGroup: true)
        let result = MessagingInboxFilter.groups.apply(to: [dm, grp]) { _ in .empty }
        #expect(result.map(\.id) == [grp.id])
    }

    @Test(".muted keeps only conversations with isMuted")
    func mutedFilters() {
        let on = ChatConversation.make(isMuted: false)
        let off = ChatConversation.make(isMuted: true)
        let result = MessagingInboxFilter.muted.apply(to: [on, off]) { _ in .empty }
        #expect(result.map(\.id) == [off.id])
    }

    @Test("metadata adapter is consulted, not invented locally")
    func metadataAdapterUsedForExtendedFilters() {
        let a = ChatConversation.make(id: "a")
        let b = ChatConversation.make(id: "b")

        let adapter = MessagingInboxFilterAvailability.metadataAdapter(
            prayerRequestConversationIds: ["b"]
        )

        // No invented prayer flag — only "b" is marked.
        let prayerResults = MessagingInboxFilter.prayerRequests.apply(to: [a, b], metadata: adapter)
        #expect(prayerResults.map(\.id) == ["b"])

        // A different filter without backing data returns nothing — never fakes.
        let starredResults = MessagingInboxFilter.starred.apply(to: [a, b], metadata: adapter)
        #expect(starredResults.isEmpty)
    }
}

// MARK: — Analytics Key Stability

@Suite("MessagingInboxFilter Analytics Keys")
struct MessagingInboxFilterAnalyticsKeyTests {

    @Test("every filter has a stable analytics key matching its raw value")
    func everyFilterHasStableKey() {
        for filter in MessagingInboxFilter.allCases {
            #expect(filter.analyticsKey == filter.rawValue,
                    "analyticsKey drift on \(filter) — dashboard joins will break")
        }
    }

    @Test("analytics keys are stable strings — not localized titles")
    func analyticsKeysAreNotLocalized() {
        // Sanity check: a localized title and an analytics key for the same
        // filter must NOT collide as strings. Title is user-facing copy;
        // key is dashboard infrastructure.
        #expect(MessagingInboxFilter.unread.analyticsKey == "unread")
        #expect(MessagingInboxFilter.unread.title == "Unread")
        #expect(MessagingInboxFilter.prayerRequests.analyticsKey == "prayerRequests")
        #expect(MessagingInboxFilter.prayerRequests.title == "Prayer Requests")
    }
}
