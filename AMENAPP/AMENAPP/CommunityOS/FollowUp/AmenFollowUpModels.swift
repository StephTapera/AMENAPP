// AmenFollowUpModels.swift
// AMEN App — CommunityOS / FollowUp
//
// Phase 2 — Agent A15 (Smart Follow-Up)
// Domain models for platform continuity memory.
//
// Follow-ups are opt-in, private-to-user threads that resurface prayer requests,
// job searches, church visits, mentorship requests, Berean questions, and more
// as revisitable items — gentle, never coercive.
//
// Storage: /users/{uid}/followUps/{itemId}  — private subcollection; Firestore rules
//          must block all reads/writes except the owning uid.
//
// Anti-engagement commitments:
//   - No streak tracking
//   - No comparative gamification
//   - No push notifications or badge manipulation
//   - Never surface more than 3 items at once
//   - Opt-in only; no auto-enrollment

import Foundation
import UserNotifications

// MARK: - FollowUpItemType

/// The category of object being followed up on.
/// Governs warm message copy and icon selection in FollowUpRow.
enum FollowUpItemType: String, Codable, CaseIterable {
    case prayerRequest
    case jobSearch
    case churchVisit
    case mentorshipRequest
    case bereanQuestion
    case discussion
    case volunteerCommitment
    case eventRSVP

    // MARK: Display helpers

    var displayName: String {
        switch self {
        case .prayerRequest:       return "Prayer Request"
        case .jobSearch:           return "Job Search"
        case .churchVisit:         return "Church Visit"
        case .mentorshipRequest:   return "Mentorship"
        case .bereanQuestion:      return "Berean Question"
        case .discussion:          return "Discussion"
        case .volunteerCommitment: return "Volunteer Opportunity"
        case .eventRSVP:           return "Event RSVP"
        }
    }

    /// Monochrome SF Symbol — never coloured to avoid implied urgency.
    var systemImage: String {
        switch self {
        case .prayerRequest:       return "hands.sparkles"
        case .jobSearch:           return "briefcase"
        case .churchVisit:         return "building.columns"
        case .mentorshipRequest:   return "person.2"
        case .bereanQuestion:      return "book.open"
        case .discussion:          return "bubble.left.and.bubble.right"
        case .volunteerCommitment: return "hand.raised"
        case .eventRSVP:           return "calendar"
        }
    }

    /// Warm, non-guilt-inducing resurface message.
    /// Never uses language like "you haven't checked in" or urgency phrases.
    var gentleReminderMessage: String {
        switch self {
        case .prayerRequest:
            return "Wanted to check in — how is your prayer request going?"
        case .jobSearch:
            return "Any updates on your job search? Hoping good things are unfolding."
        case .churchVisit:
            return "Did you get a chance to visit? Would love to hear how it went."
        case .mentorshipRequest:
            return "Checking in on your mentorship journey — how are things going?"
        case .bereanQuestion:
            return "Wanted to revisit your Berean question. Any new thoughts?"
        case .discussion:
            return "The conversation is still here whenever you're ready to return."
        case .volunteerCommitment:
            return "A gentle reminder about your volunteer commitment."
        case .eventRSVP:
            return "Just a soft reminder about the event you saved."
        }
    }
}

// MARK: - FollowUpStatus

/// Lifecycle state of a follow-up item.
/// Only `active` and `snoozed` appear in the inbox. Resolved/dismissed items
/// are retained for journaling but excluded from surface logic.
enum FollowUpStatus: String, Codable {
    /// Actively tracked; eligible to be surfaced when due.
    case active
    /// User asked to be reminded later. `snoozedUntil` governs re-surface date.
    case snoozed
    /// User marked as done / answered. Excluded from surface logic.
    case resolved
    /// User dismissed without resolving. Soft-retained for audit/journal.
    case dismissed
}

// MARK: - AmenFollowUpItem

/// A single follow-up entry stored at `/users/{uid}/followUps/{id}`.
///
/// All fields except `userNote` are written by the client at creation or by
/// `AmenFollowUpService` mutations. `userNote` is purely private journaling;
/// it is never read server-side.
///
/// `isPrivate` is always `true` — this is enforced at the Firestore rules layer.
/// The field is included in the document to make the intent explicit and to allow
/// future security-rule assertions.
struct AmenFollowUpItem: Codable, Identifiable {

    /// Firestore document ID.
    var id: String

    /// Firebase Auth UID of the owning user.
    var userId: String

    /// Category of the followed-up object.
    var itemType: FollowUpItemType

    /// Firestore document path of the source object (e.g. "/prayers/abc123").
    /// Used for deep-linking back to the original item. Never fetched eagerly.
    var objectRef: String

    /// Denormalised display title. Stored at creation so the inbox renders without
    /// a round-trip fetch to the source object.
    var objectTitle: String

    /// Optional brief preview excerpt from the source object body.
    var objectPreview: String?

    /// Current lifecycle state.
    var status: FollowUpStatus

    /// When this item was created. Written by the client (Date.now); server timestamp
    /// is preferred via FieldValue.serverTimestamp() in the service layer.
    var createdAt: Date

    /// Last time this item was surfaced to the user (either in-app or via notification).
    /// Nil = never surfaced since creation.
    var lastSurfacedAt: Date?

    /// When the user marked this item resolved.
    var resolvedAt: Date?

    /// Active only when `status == .snoozed`. Item re-enters surface eligibility
    /// when Date.now > snoozedUntil.
    var snoozedUntil: Date?

    /// How many days after creation to wait before the first gentle resurface.
    /// Nil = no automatic resurface (user must open inbox manually).
    var notifyAfterDays: Int?

    /// A private journal note written by the user about this item.
    /// Never visible to other users or platform systems. Never indexed.
    var userNote: String?

    /// Always true. Follow-ups are private to the owning user.
    /// Enforced at both this layer and the Firestore security rules layer.
    var isPrivate: Bool
}

// MARK: - FollowUpReminderSchedule

/// A value describing a pending local notification for a follow-up item.
///
/// Local notifications only — never push, never badge-count increases.
/// Instances of this struct are used by `AmenFollowUpService.scheduleReminder(for:)`
/// as a staging object before UNNotificationRequest creation.
struct FollowUpReminderSchedule {

    /// The `AmenFollowUpItem.id` this reminder is associated with.
    /// Also used as the `UNNotificationRequest.identifier` to allow cancellation.
    let itemId: String

    /// When the reminder should fire. Derived from `createdAt + notifyAfterDays`.
    let triggerDate: Date

    /// Warm, non-guilt-inducing body text for the notification.
    /// Populated from `FollowUpItemType.gentleReminderMessage`.
    let message: String
}
