// AmenLiveActivityAttributes.swift
// AMENWidgetExtension
//
// Widget-extension copy of the Amen Live Activity data contract.
// Must match AmenLiveActivityAttributes.swift in the main AMENAPP target exactly.
// Both targets compile this independently — they are separate binaries.

import Foundation

#if canImport(ActivityKit)
import ActivityKit

// MARK: - Live Activity Phase

enum LiveActivityPhase: String, Codable, Hashable, Sendable {
    case active
    case starting
    case closing
    case followUp

    var displayLabel: String {
        switch self {
        case .active:    return "Active"
        case .starting:  return "Starting Soon"
        case .closing:   return "Closing"
        case .followUp:  return "You Responded"
        }
    }

    var symbolName: String {
        switch self {
        case .active:    return "circle.fill"
        case .starting:  return "clock.fill"
        case .closing:   return "checkmark.circle.fill"
        case .followUp:  return "arrow.uturn.right.circle.fill"
        }
    }

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

enum LiveActivityTier: String, Codable, Hashable, Sendable {
    case spiritual  = "SPIRITUAL"
    case community  = "COMMUNITY"
    case local      = "LOCAL"
    case global     = "GLOBAL"

    var symbolName: String {
        switch self {
        case .spiritual:  return "hands.sparkles.fill"
        case .community:  return "person.2.fill"
        case .local:      return "mappin.and.ellipse"
        case .global:     return "globe"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .spiritual:  return "Spiritual"
        case .community:  return "Community"
        case .local:      return "Local"
        case .global:     return "Global"
        }
    }

    static let fallback: LiveActivityTier = .community
}

// MARK: - AmenLiveActivityAttributes

@available(iOS 16.2, *)
struct AmenLiveActivityAttributes: ActivityAttributes {

    struct ContentState: Codable, Hashable, Sendable {
        var title: String
        var subtitle: String
        var actionLabel: String
        var phase: LiveActivityPhase
        var updatedAt: Date
        // NO spectacle counters — formation invariant enforced here
    }

    var intelligenceCardId: String
    var backingKind: String
    var backingId: String
    var tier: LiveActivityTier
    var loopParentId: String?
}

#endif // canImport(ActivityKit)
