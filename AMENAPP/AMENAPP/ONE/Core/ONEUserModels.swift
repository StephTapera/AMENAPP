// ONEUserModels.swift
// ONE — User Identity, Presence, Entitlement
// P0-F | FROZEN contracts. See CONTRACTS.md §3.

import Foundation

// MARK: - ONEUser

struct ONEUser: Codable, Identifiable, Sendable {
    var id: String { uid }
    let uid: String
    var displayName: String
    var avatarURL: String?
    var bio: String?
    var privacyMirror: ONEPrivacyMirrorLevel
    var presenceState: ONEPresenceState
    var entitlement: ONEEntitlement
    var reachBudgetRemaining: Int   // replenishes weekly; default 20
    var isMemorialized: Bool
    var legacyDirectiveID: String?
}

// MARK: - ONEPrivacyMirrorLevel

enum ONEPrivacyMirrorLevel: String, Codable, Sendable, CaseIterable {
    case sealed        // anonymous browsing renders you anonymous to the subject
    case opaque        // profile exists; no detail visible to strangers
    case translucent   // name + bio visible; posts require witness relationship
    case open          // public profile

    var displayLabel: String {
        switch self {
        case .sealed:      return "Private"
        case .opaque:      return "Opaque"
        case .translucent: return "Translucent"
        case .open:        return "Open"
        }
    }

    var icon: String {
        switch self {
        case .sealed:      return "lock.fill"
        case .opaque:      return "eye.slash.fill"
        case .translucent: return "eye.fill"
        case .open:        return "globe"
        }
    }
}

// MARK: - ONEPresenceState

enum ONEPresenceState: String, Codable, Sendable, CaseIterable {
    case available
    case focused       // do not disturb
    case driving       // no auto-notifications
    case sleeping
    case worship       // silences non-urgent pings
    case traveling
    case withFamily
    case unknown       // default; never inferred server-side

    var displayLabel: String {
        switch self {
        case .available:  return "Available"
        case .focused:    return "Focused"
        case .driving:    return "Driving"
        case .sleeping:   return "Sleeping"
        case .worship:    return "In Worship"
        case .traveling:  return "Traveling"
        case .withFamily: return "With Family"
        case .unknown:    return ""
        }
    }

    var icon: String {
        switch self {
        case .available:  return "checkmark.circle.fill"
        case .focused:    return "moon.fill"
        case .driving:    return "car.fill"
        case .sleeping:   return "zzz"
        case .worship:    return "hands.sparkles.fill"
        case .traveling:  return "airplane"
        case .withFamily: return "house.fill"
        case .unknown:    return ""
        }
    }
}

// MARK: - ONEEntitlement

struct ONEEntitlement: Codable, Sendable {
    let tier: ONEEntitlementTier
    var storeKitTransactionID: UInt64?  // App Store transaction ID (not Stripe)
    var validUntil: Date?
    var trialUsed: Bool

    static var free: ONEEntitlement {
        ONEEntitlement(tier: .free, storeKitTransactionID: nil, validUntil: nil, trialUsed: false)
    }

    var isActive: Bool {
        guard tier == .subscriber else { return false }
        if let until = validUntil { return until > Date() }
        return true  // no expiry = managed by App Store
    }
}

// MARK: - ONEEntitlementTier

enum ONEEntitlementTier: String, Codable, Sendable {
    case free
    case subscriber  // StoreKit auto-renewable subscription; verified by App Store
}
