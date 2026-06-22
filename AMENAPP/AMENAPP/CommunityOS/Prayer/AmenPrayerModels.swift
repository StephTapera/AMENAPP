// AmenPrayerModels.swift
// AMEN App — CommunityOS / Prayer OS (Phase 2 — Agent A7)
//
// Rich domain models for the full Prayer OS:
//   - AmenPrayerUpdateType    — follow-up lifecycle stages
//   - AmenPrayerPartner       — per-partner intercession record (private)
//   - AmenPrayerFollowUp      — update / testimony / answered note
//   - AmenPrayerRequest       — full prayer request with 6-level privacy
//   - AmenPrayerRoom          — live/scheduled group prayer room
//
// Privacy rules (C5 §3 Option B):
//   - ownerUidEncrypted is set exclusively by Cloud Function.
//     Client code NEVER writes it. It is not included in any model
//     property that the client initialises.
//   - prayerCount is private — never displayed to other users.
//   - Anonymous prayers: displayAuthorName = "Anonymous" set by CF.
//
// These types COMPLEMENT (do not replace) the lightweight PrayerRequest
// in PrayerModels.swift, which is used by PrayerRoomView/PrayerPartnerRow.
//
// Uses:
//   PrayerPrivacyLevel  — defined in PrayerModels.swift (this module)
//   SpawnProvenance     — defined in CommunityObjectTypes.swift
//   SpawnableObject     — defined in AmenCoreModels.swift

import Foundation
import FirebaseFirestore

// MARK: - AmenPrayerUpdateType

/// Lifecycle stage of a follow-up attached to a prayer request.
enum AmenPrayerUpdateType: String, Codable, CaseIterable, Sendable {
    /// General progress update from the request owner
    case update       = "update"
    /// Testimony of God's faithfulness attached to the prayer
    case testimony    = "testimony"
    /// Owner confirms the prayer was answered
    case answered     = "answered"
    /// Owner closes the request (no longer seeking intercession)
    case closeRequest = "close_request"

    var displayName: String {
        switch self {
        case .update:       return "Update"
        case .testimony:    return "Testimony"
        case .answered:     return "Answered"
        case .closeRequest: return "Closed"
        }
    }

    var systemImage: String {
        switch self {
        case .update:       return "arrow.clockwise"
        case .testimony:    return "star.fill"
        case .answered:     return "checkmark.circle.fill"
        case .closeRequest: return "xmark.circle"
        }
    }
}

// MARK: - AmenPrayerPartner

/// A single prayer partner's intercession record for a prayer request.
/// `prayerCount` is private — visible only to the partner themselves, never surfaced to
/// other users or in any aggregate display that could drive comparison.
struct AmenPrayerPartner: Codable, Identifiable, Sendable {
    /// Firestore document ID of this partner record
    var id: String
    /// UID of the interceding user; masked to "" on client reads for anonymous requests
    var userId: String
    /// Display name shown in the partner row; "Anonymous" when masked
    var displayName: String
    /// Server timestamp when the partner joined this prayer
    var prayedAt: Date
    /// Running count of times this partner has prayed — private to the partner only.
    /// NEVER shown to request author or other partners.
    var prayerCount: Int
}

// MARK: - AmenPrayerFollowUp

/// An update, testimony, or close note attached to an `AmenPrayerRequest`.
/// Stored as a Firestore sub-collection at /prayers/{id}/followUps/{followUpId}.
struct AmenPrayerFollowUp: Codable, Identifiable, Sendable {
    /// Firestore document ID
    var id: String
    /// Firestore ID of the parent prayer request
    var prayerRequestId: String
    /// UID of the author (must be the prayer request owner)
    var authorId: String
    /// Follow-up lifecycle type
    var type: AmenPrayerUpdateType
    /// Body text of the follow-up (max 500 chars enforced in the UI layer)
    var body: String
    /// Convenience flag: true when type == .testimony
    var isTestimony: Bool
    /// Server creation timestamp
    var createdAt: Date
    /// Soft-delete flag
    var isDeleted: Bool
}

// MARK: - AmenPrayerRequest

/// Full prayer request document stored at /prayers/{prayerId}.
/// Implements SpawnableObject so it can be spawned from Posts, Church content, etc.
///
/// ANONYMOUS RULES (C5 §3b, Option B):
///   - When isAnonymous == true:
///     · displayAuthorName is "Anonymous" (set server-side by CF)
///     · ownerUidEncrypted is AES-256 encrypted UID (CF-only write; nil on ALL client reads)
///     · The client never writes ownerUidEncrypted under any circumstances.
struct AmenPrayerRequest: Codable, Identifiable, SpawnableObject, Sendable {
    // MARK: Core identity
    /// Firestore document ID
    var id: String
    /// Short title displayed in feed cards and room headers
    var title: String
    /// Full prayer body text
    var body: String

    // MARK: Privacy & identity shielding
    /// Six-level privacy selector value
    var privacyLevel: PrayerPrivacyLevel
    /// When true, identity is shielded; displayAuthorName is "Anonymous"
    var isAnonymous: Bool
    /// Server-only encrypted UID field.
    /// ALWAYS nil on client-side reads. NEVER written by client code.
    /// Included here as optional so Firestore decoding doesn't fail if the field appears —
    /// it should never be accessed or displayed by any UI code.
    var ownerUidEncrypted: String?
    /// Author display name — "Anonymous" when isAnonymous == true (set by CF).
    var displayAuthorName: String

    // MARK: Context references
    /// Firestore church document ID when scoped to a church context
    var churchRef: String?
    /// Firestore space (covenant) document ID when scoped to a space
    var spaceRef: String?

    // MARK: Taxonomy
    /// Free-form topic tags, e.g. ["health", "family", "finances"]
    var tags: [String]

    // MARK: Counts (private — never displayed to other users)
    /// Running prayer count. PRIVATE — never shown publicly, no comparative display.
    var prayerCount: Int

    // MARK: Follow-ups
    /// Denormalised recent follow-ups (last 3) for feed card rendering.
    /// Full list lives in the /prayers/{id}/followUps sub-collection.
    var followUps: [AmenPrayerFollowUp]

    // MARK: Answered state
    /// True when the request has been marked as answered
    var isAnswered: Bool
    /// Optional note from the owner when marking answered
    var answeredNote: String?

    // MARK: Reminder
    /// True when the owner has opted in to a local notification follow-up reminder.
    /// Reminders use UNUserNotificationCenter (local only; no push).
    var reminderScheduled: Bool

    // MARK: SpawnableObject / AmenObject
    /// Immutable spawn provenance; nil for direct (root-level) requests
    var provenance: SpawnProvenance?
    /// Firebase Auth UID of the creating user
    var createdBy: String
    /// Server creation timestamp
    var createdAt: Date
    /// Server last-updated timestamp
    var updatedAt: Date
    /// Soft-delete flag — hard delete never performed
    var isDeleted: Bool
}

// MARK: - AmenPrayerRoom

/// A live or scheduled group prayer room.
/// Stored at /prayerRooms/{roomId}.
/// References prayer requests by their Firestore IDs; does not embed them.
struct AmenPrayerRoom: Codable, Identifiable, Sendable {
    /// Firestore document ID
    var id: String
    /// Display title for the room
    var title: String
    /// UID of the hosting user
    var hostId: String
    /// UIDs of co-hosts who can manage the session
    var coHostIds: [String]
    /// UIDs of all confirmed participants (including host + co-hosts)
    var participantIds: [String]
    /// Privacy level governing who can join the room
    var privacyLevel: PrayerPrivacyLevel
    /// True while the room is live
    var isLive: Bool
    /// Scheduled start time; nil for immediate rooms
    var scheduledAt: Date?
    /// Server timestamp when the room ended; nil if still live or not yet started
    var endedAt: Date?
    /// Firestore prayer request IDs linked to this room for shared intercession
    var prayerRequestRefs: [String]
    /// Server creation timestamp
    var createdAt: Date
    /// Soft-delete flag
    var isDeleted: Bool
}

// MARK: - PrayerContext

/// Scope used to filter prayer requests in `AmenPrayerService.loadPrayerRequests`.
enum PrayerContext: Sendable {
    /// Prayers created by this user (any privacy level)
    case personal(String)
    /// Prayers scoped to a specific church (privacyLevel == .church or broader)
    case church(String)
    /// Prayers scoped to a specific space (privacyLevel == .space or broader)
    case space(String)
    /// Public and anonymous prayers only
    case `public`
}
