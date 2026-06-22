// AmenLiveModels.swift
// AMENAPP — Amen Live data models
//
// Defines the data types for the Amen Live in-app banner system.
// AmenLiveSession represents a real-time community or spiritual event
// surfaced to users whose church/org is hosting it.
//
// Formation invariants:
//   - NO spectacle counters (no attendee count, no "N watching")
//   - Every session must resolve to a real backingEntity (backingEntityId + backingEntityKind)
//   - actionLabel is a human-readable CTA — never a count or metric

import Foundation

// MARK: - AmenLiveType

/// The category of a live session. Controls banner icon and accessibility label.
enum AmenLiveType: String, Codable, CaseIterable {
    case prayerEvent           = "PRAYER_EVENT"
    case sermonStream          = "SERMON_STREAM"
    case communityMoment       = "COMMUNITY_MOMENT"
    case volunteerMobilization = "VOLUNTEER_MOBILIZATION"
    case crisisResponse        = "CRISIS_RESPONSE"

    /// SF Symbol name for the banner icon. No count-based symbols.
    var symbolName: String {
        switch self {
        case .prayerEvent:           return "hands.sparkles.fill"
        case .sermonStream:          return "play.rectangle.fill"
        case .communityMoment:       return "person.2.fill"
        case .volunteerMobilization: return "figure.walk"
        case .crisisResponse:        return "heart.fill"
        }
    }

    /// Accessibility-friendly display label for the session type.
    var displayLabel: String {
        switch self {
        case .prayerEvent:           return "Prayer Event"
        case .sermonStream:          return "Sermon Stream"
        case .communityMoment:       return "Community Moment"
        case .volunteerMobilization: return "Volunteer Mobilization"
        case .crisisResponse:        return "Crisis Response"
        }
    }

    /// Accent color components (RGB) for type-specific tinting.
    /// Stored as components so this type stays Codable/Sendable.
    var accentRed: Double {
        switch self {
        case .prayerEvent:           return 0.4
        case .sermonStream:          return 0.2
        case .communityMoment:       return 0.2
        case .volunteerMobilization: return 0.15
        case .crisisResponse:        return 0.85
        }
    }
    var accentGreen: Double {
        switch self {
        case .prayerEvent:           return 0.3
        case .sermonStream:          return 0.55
        case .communityMoment:       return 0.55
        case .volunteerMobilization: return 0.65
        case .crisisResponse:        return 0.25
        }
    }
    var accentBlue: Double {
        switch self {
        case .prayerEvent:           return 0.85
        case .sermonStream:          return 0.9
        case .communityMoment:       return 0.85
        case .volunteerMobilization: return 0.45
        case .crisisResponse:        return 0.3
        }
    }
}

// MARK: - AmenLiveSession

/// A single live intelligence context surfaced to the in-app banner.
///
/// Resolves to a real church/org/event document via backingEntityId + backingEntityKind.
/// All fields are server-populated via Admin SDK writes — no client writes.
///
/// Formation invariants:
///   - NO spectacle counters — no attendee count, no "N praying" fields
///   - backingEntityId must exist in its corresponding Firestore collection
///   - actionHandler is a CF callable name; actionTarget is the entity document ID
struct AmenLiveSession: Codable, Identifiable {
    /// Firestore document ID of this session (amen_live_sessions/{id}).
    let id: String

    /// Short headline for the banner. Max ~40 chars for compact display.
    let title: String

    /// Supporting context line. Optional. Describes the session, never a count.
    let subtitle: String?

    /// Category of this live event — controls banner icon and color.
    let type: AmenLiveType

    /// Firestore UID of the hosting church, org, or user.
    let hostId: String

    /// Human-readable host name for display. E.g. "Grace Community Church".
    let hostName: String

    /// Session start time as epoch seconds (Double for Firestore Timestamp compat).
    let startedAt: Double

    /// Optional projected end time as epoch seconds.
    let scheduledEndAt: Double?

    /// Whether this session is currently active. Firestore snapshot listener
    /// filters on isActive == true, so this will always be true for displayed sessions.
    let isActive: Bool

    /// Firestore document ID of the backing entity (church, event, org).
    /// Must resolve to a real document — verified server-side before write.
    let backingEntityId: String

    /// Collection kind of the backing entity.
    /// One of: "CHURCH" | "EVENT" | "ORG"
    let backingEntityKind: String

    /// Human-readable CTA label shown on the action button.
    /// Examples: "Join Prayer", "Watch Now", "RSVP"
    /// NEVER a count. NEVER a metric.
    let actionLabel: String

    /// CF callable name to invoke when the user taps the action button.
    /// Examples: "recordLiveAction", "joinPrayerSession"
    let actionHandler: String

    /// Entity ID passed as the target when calling actionHandler.
    let actionTarget: String

    // ── Formation invariants — deliberately absent ────────────────────────────
    // NO: attendeeCount, viewerCount, prayerCount, watcherCount
    // NO: spectacle counters of any kind
}
