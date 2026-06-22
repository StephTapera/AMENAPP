// AmenLiveActivityAttributes.swift
// AMENAPP
//
// ActivityKit attributes struct — defines the static and dynamic state of the
// Amen Live Activity. Static data is set once at creation; ContentState updates
// in real-time via ActivityKit or remote APNs push.
//
// Placement: AMENAPP main target (shared with widget extension via module import
// or by adding this file to AMENWidgetExtension target membership).

import Foundation

// MARK: - ActivityKit import guard

#if canImport(ActivityKit)
import ActivityKit

// MARK: - Live Activity Phase

/// Finite lifecycle states for an Amen Live Activity.
/// There are no infinite loops — every activity must reach .closing or .followUp.
enum LiveActivityPhase: String, Codable, Hashable, Sendable {
    /// The backing event or prayer is ongoing and active.
    case active
    /// The event or prayer session is starting within 30 minutes.
    case starting
    /// The event is ending or the prayer request has been answered.
    case closing
    /// Loop-closing phase: the user acted on the card — show what happened next.
    case followUp

    /// Human-readable label shown in the Live Activity UI.
    /// Not a count. Not a metric. A status word only.
    var displayLabel: String {
        switch self {
        case .active:    return "Active"
        case .starting:  return "Starting Soon"
        case .closing:   return "Closing"
        case .followUp:  return "You Responded"
        }
    }

    /// SF Symbol name for phase indicator (compact trailing / minimal).
    var symbolName: String {
        switch self {
        case .active:    return "circle.fill"
        case .starting:  return "clock.fill"
        case .closing:   return "checkmark.circle.fill"
        case .followUp:  return "arrow.uturn.right.circle.fill"
        }
    }

    /// Tint color (as RGB components) for the phase indicator.
    /// Avoid Color here — ActivityKit attributes must be Codable/Sendable.
    var tintRed: Double {
        switch self {
        case .active:    return 0.2
        case .starting:  return 0.9
        case .closing:   return 0.4
        case .followUp:  return 0.3
        }
    }
    var tintGreen: Double {
        switch self {
        case .active:    return 0.7
        case .starting:  return 0.6
        case .closing:   return 0.8
        case .followUp:  return 0.6
        }
    }
    var tintBlue: Double {
        switch self {
        case .active:    return 0.3
        case .starting:  return 0.1
        case .closing:   return 0.3
        case .followUp:  return 0.9
        }
    }
}

// MARK: - Tier Icons

/// Tier display helpers scoped to the Live Activity layer.
/// Mirrors the Tier type from contracts.ts: SPIRITUAL | COMMUNITY | LOCAL | GLOBAL.
/// (FAMILY is excluded — family tier never generates a Live Activity.)
enum LiveActivityTier: String, Codable, Hashable, Sendable {
    case spiritual  = "SPIRITUAL"
    case community  = "COMMUNITY"
    case local      = "LOCAL"
    case global     = "GLOBAL"

    /// SF Symbol name for compact / minimal display.
    var symbolName: String {
        switch self {
        case .spiritual:  return "hands.sparkles.fill"
        case .community:  return "person.2.fill"
        case .local:      return "mappin.and.ellipse"
        case .global:     return "globe"
        }
    }

    /// Accessibility label for the tier icon.
    var accessibilityLabel: String {
        switch self {
        case .spiritual:  return "Spiritual"
        case .community:  return "Community"
        case .local:      return "Local"
        case .global:     return "Global"
        }
    }

    /// Fallback when tier string cannot be parsed.
    static let fallback: LiveActivityTier = .community
}

// MARK: - AmenLiveActivityAttributes

/// ActivityKit attributes for the Amen Living Intelligence Live Activity.
///
/// Static data (set once at `Activity.request` time):
///   - intelligenceCardId — links back to the `IntelligenceCard` doc
///   - backingKind — raw BackingKind from contracts.ts (CHURCH | ORG | EVENT | ...)
///   - backingId — Firestore document ID of the backing entity
///   - tier — LiveActivityTier for icon routing
///   - loopParentId — optional: card that this activity closes a loop for
///
/// Dynamic data (ContentState — updated via `activity.update` or APNs):
///   - title, subtitle, actionLabel, phase, updatedAt
///
/// Formation invariants respected:
///   - NO spectacle counters in ContentState
///   - Finite: `staleDate` is always set to `card.expiresAt` at creation
///   - Loop-closing: `.followUp` phase wired to `loopParentId` when present
@available(iOS 16.2, *)
struct AmenLiveActivityAttributes: ActivityAttributes {

    // MARK: - ContentState (dynamic, real-time updates)

    struct ContentState: Codable, Hashable, Sendable {
        /// Primary headline. Max ~40 chars for compact display.
        var title: String

        /// Supporting line. Describes current status — never a count.
        /// Examples: "Prayer request answered", "Event starting in 10 min", "Closing in 5 min"
        var subtitle: String

        /// CTA label that deep-links into the app when the Live Activity is tapped.
        /// Examples: "Join", "Pray", "See What Happened"
        var actionLabel: String

        /// Current lifecycle phase of this Live Activity.
        var phase: LiveActivityPhase

        /// Timestamp of the last update — used for stale-detection in AmenLiveActivityManager.
        var updatedAt: Date

        // MARK: Formation invariants — deliberately absent
        // NO: likeCount, prayerCount, attendeeCount, viewCount
        // NO: spectacle counters of any kind
        // Finite: staleDate supplied externally at Activity.request time
    }

    // MARK: - Static Attributes (set once at creation)

    /// ID of the `IntelligenceCard` that spawned this Live Activity.
    /// Used to correlate back to Firestore and to check `hasActiveActivity(for:)`.
    var intelligenceCardId: String

    /// Raw `BackingKind` string from contracts.ts:
    /// "CHURCH" | "ORG" | "EVENT" | "PRAYER_REQUEST" | "STUDY" | "NEED"
    var backingKind: String

    /// Firestore document ID of the backing entity (event, prayer request, etc.).
    var backingId: String

    /// Tier of the originating IntelligenceCard. Controls icon routing.
    var tier: LiveActivityTier

    /// Optional: the `loopParentId` from `card.formation` — used to wire
    /// the `.followUp` phase back to the prior user action card.
    var loopParentId: String?
}

#endif // canImport(ActivityKit)
