// PrayerModels.swift
// AMEN App — Community OS / Prayer OS (A7)
//
// Domain models for Prayer Requests, prayer rooms, and related types.
// These types complement the existing Prayer schema in C1 §5 and integrate with
// the ActionThread.prayerCircle workflow from ActionThreadModels.swift.
//
// Note: PrayerRoomRealtimeCoordinator (AIIntelligence/) handles live translation
// and real-time session management for prayer rooms. These models represent the
// Firestore-persisted prayer request domain objects.
//
// Contract references:
//   C1 §5 (Prayer schema), C2 §2.3 (pray privacy defaults),
//   C2 §1 ("Pray" intent: private by default, can widen to trustedCircle)
//   ActionThreadModels.ActionThreadType.prayerCircle

import Foundation

// MARK: - PrayerPrivacyLevel

/// Privacy levels for prayer requests and rooms.
/// PRIVATE is the default and must be treated as the "safe" choice in the UI.
/// Maps to C1 Prayer.visibility and C2 §2.3 Pray intent defaults.
enum PrayerPrivacyLevel: String, Codable, CaseIterable {
    /// Only visible to the author. The default and recommended choice.
    case `private` = "private"
    /// Visible to the author's trusted circle (mutuals with the trust signal set).
    case trustedCircle = "trusted_circle"
    /// Visible to the author's church membership.
    case church = "church"
    /// Visible to members of an AMEN Space the author belongs to.
    case space = "space"
    /// Visible to the full public feed.
    case `public` = "public"
    /// Visible publicly but author identity is hidden.
    case anonymous = "anonymous"

    var displayName: String {
        switch self {
        case .private:      return "Private"
        case .trustedCircle: return "Trusted Circle"
        case .church:       return "My Church"
        case .space:        return "My Space"
        case .public:       return "Public"
        case .anonymous:    return "Anonymous"
        }
    }

    var systemImage: String {
        switch self {
        case .private:      return "lock.fill"
        case .trustedCircle: return "person.2.fill"
        case .church:       return "building.columns.fill"
        case .space:        return "square.stack.3d.up.fill"
        case .public:       return "globe"
        case .anonymous:    return "person.fill.questionmark"
        }
    }

    /// Short description used as an accessibility tooltip and onboarding hint.
    var description: String {
        switch self {
        case .private:
            return "Only you can see this prayer. Nothing is shared."
        case .trustedCircle:
            return "Shared with people you trust most — mutual connections who have opted in."
        case .church:
            return "Shared with verified members of your church."
        case .space:
            return "Shared with members of your AMEN Space."
        case .public:
            return "Visible to everyone on AMEN."
        case .anonymous:
            return "Visible publicly, but your name is hidden."
        }
    }

    /// True for levels where identity or content has extra protection.
    var isHighTrustLevel: Bool {
        switch self {
        case .private, .trustedCircle: return true
        default: return false
        }
    }
}

// MARK: - PrayerType

/// The lifecycle stage or sub-type of a prayer document.
/// Maps to C2 §1 "pray" intent outputs and ActionThread.prayerCircle.
enum PrayerType: String, Codable, CaseIterable {
    /// An active prayer request seeking intercession
    case request = "request"
    /// A live or persistent group prayer room (integrates with PrayerRoomRealtimeCoordinator)
    case room = "room"
    /// An update to an existing prayer — sharing how it has progressed
    case update = "update"
    /// A testimony that a prayer was answered
    case testimony = "testimony"

    var displayName: String {
        switch self {
        case .request:   return "Prayer Request"
        case .room:      return "Prayer Room"
        case .update:    return "Update"
        case .testimony: return "Testimony"
        }
    }

    var systemImage: String {
        switch self {
        case .request:   return "hands.sparkles"
        case .room:      return "person.3"
        case .update:    return "arrow.clockwise"
        case .testimony: return "star"
        }
    }
}

// MARK: - CommunityPrayerStatus

/// Lifecycle status of a prayer request.
enum CommunityPrayerStatus: String, Codable, CaseIterable, Sendable {
    /// Prayer is active and awaiting or receiving intercession
    case active = "active"
    /// Prayer has an update from the author
    case updated = "updated"
    /// Prayer has been answered — the author has confirmed
    case answered = "answered"
    /// Prayer has been closed (no longer active; not necessarily answered)
    case closed = "closed"

    var displayName: String {
        switch self {
        case .active:   return "Active"
        case .updated:  return "Updated"
        case .answered: return "Answered"
        case .closed:   return "Closed"
        }
    }

    var systemImage: String {
        switch self {
        case .active:   return "circle"
        case .updated:  return "arrow.clockwise"
        case .answered: return "checkmark.circle.fill"
        case .closed:   return "xmark.circle"
        }
    }
}

// MARK: - PrayerRequest

/// A prayer request, room, update, or testimony.
/// Stored at: /prayers/{prayerId}
/// Corresponds to C1 §5 Prayer schema with additional PrayerOS-specific fields.
/// SpawnProvenance is defined in DiscussionModels.swift (same module).
struct PrayerRequest: Identifiable, Codable {
    /// Firestore document ID
    let id: String
    /// UID of the prayer's author
    let authorId: String
    /// Short title displayed in list views and room headers
    var title: String
    /// Full prayer text body
    var body: String
    /// Sub-type: request, room, update, or testimony
    let prayerType: PrayerType
    /// Privacy level — defaults to .private
    var privacyLevel: PrayerPrivacyLevel
    /// Lifecycle status
    var status: CommunityPrayerStatus
    /// UIDs of prayer partners who are actively interceding
    var partnerIds: [String]
    /// When true, the author has opted in to reminder notifications for this prayer
    var reminderEnabled: Bool
    /// Immutable provenance — present when the prayer was spawned from another object
    let provenance: SpawnProvenance?
    /// Server-assigned creation timestamp
    let createdAt: Date
    /// True when soft-deleted; item should not appear in public feeds
    var softDeleted: Bool

    // MARK: - Computed

    var isActive: Bool { status == .active }
    var isAnswered: Bool { status == .answered }
    var hasPartners: Bool { !partnerIds.isEmpty }

    /// True when this prayer was spawned from another object (not created directly)
    var hasProvenance: Bool { provenance != nil }
}
