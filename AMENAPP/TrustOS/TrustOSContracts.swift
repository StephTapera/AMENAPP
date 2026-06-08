// TrustOSContracts.swift
// AMENAPP — Trust OS
//
// Frozen Swift contract types matching trust.contracts.ts.
// Pure value types — no business logic here.

import Foundation

// MARK: - Relationship Tier

enum RelationshipTier: String, Codable, CaseIterable {
    case `public`    = "PUBLIC"
    case community   = "COMMUNITY"
    case church      = "CHURCH"
    case friends     = "FRIENDS"
    case family      = "FAMILY"
    case mentor      = "MENTOR"
    case `private`   = "PRIVATE"

    var displayName: String {
        switch self {
        case .public:    return "Public"
        case .community: return "Community"
        case .church:    return "Church"
        case .friends:   return "Friends"
        case .family:    return "Family"
        case .mentor:    return "Mentor"
        case .private:   return "Only Me"
        }
    }

    var systemImage: String {
        switch self {
        case .public:    return "globe"
        case .community: return "person.3"
        case .church:    return "building.2"
        case .friends:   return "person.2"
        case .family:    return "house"
        case .mentor:    return "star.circle"
        case .private:   return "lock"
        }
    }

    // Lower index = narrower audience (safer default)
    var audienceBreadth: Int {
        switch self {
        case .private:   return 0
        case .mentor:    return 1
        case .family:    return 2
        case .friends:   return 3
        case .church:    return 4
        case .community: return 5
        case .public:    return 6
        }
    }
}

// MARK: - Share Context

enum ShareContext: String, Codable, CaseIterable {
    case prayer        = "PRAYER"
    case discussion    = "DISCUSSION"
    case learning      = "LEARNING"
    case news          = "NEWS"
    case encouragement = "ENCOURAGEMENT"
    case personal      = "PERSONAL"

    var displayName: String {
        switch self {
        case .prayer:        return "Prayer Request"
        case .discussion:    return "Discussion"
        case .learning:      return "Learning"
        case .news:          return "News & Updates"
        case .encouragement: return "Encouragement"
        case .personal:      return "Personal"
        }
    }

    var systemImage: String {
        switch self {
        case .prayer:        return "hands.and.sparkles"
        case .discussion:    return "bubble.left.and.bubble.right"
        case .learning:      return "book.open"
        case .news:          return "newspaper"
        case .encouragement: return "heart"
        case .personal:      return "person"
        }
    }

    // Least-surprise default audience for each context
    var defaultTier: RelationshipTier {
        switch self {
        case .prayer:        return .church
        case .discussion:    return .community
        case .learning:      return .community
        case .news:          return .public
        case .encouragement: return .community
        case .personal:      return .friends
        }
    }
}

// MARK: - Context Pill

struct ContextPill: Codable {
    let context: ShareContext
    /// Invariant: always true — context travels with the content
    let travelsWithContent: Bool
    let attachedAt: TimeInterval

    init(context: ShareContext) {
        self.context = context
        self.travelsWithContent = true
        self.attachedAt = Date().timeIntervalSince1970
    }

    func toFirestore() -> [String: Any] {
        ["context": context.rawValue, "travelsWithContent": travelsWithContent, "attachedAt": attachedAt]
    }
}

// MARK: - Passport Level

enum PassportLevel: String, Codable, CaseIterable, Comparable {
    case email    = "EMAIL"
    case phone    = "PHONE"
    case identity = "IDENTITY"
    case church   = "CHURCH"
    case leader   = "LEADER"
    case org      = "ORG"

    private var sortOrder: Int {
        switch self {
        case .email: return 0; case .phone: return 1; case .identity: return 2
        case .church: return 3; case .leader: return 4; case .org: return 5
        }
    }

    static func < (lhs: PassportLevel, rhs: PassportLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    var displayName: String {
        switch self {
        case .email:    return "Email Verified"
        case .phone:    return "Phone Verified"
        case .identity: return "Identity Verified"
        case .church:   return "Church Verified"
        case .leader:   return "Leader Verified"
        case .org:      return "Org Verified"
        }
    }

    var systemImage: String {
        switch self {
        case .email:    return "envelope.badge.checkmark"
        case .phone:    return "phone.badge.checkmark"
        case .identity: return "person.badge.checkmark"
        case .church:   return "building.2.fill"
        case .leader:   return "star.circle.fill"
        case .org:      return "building.2.crop.circle.fill"
        }
    }

    /// Identity and org levels require a third-party vendor (Persona / Stripe Identity).
    var requiresVendorGate: Bool { self == .identity || self == .org }
}

// MARK: - Trust Ledger Entry

struct TrustLedgerEntry: Codable {
    let uid: String
    let action: String
    let whatChanged: String
    let why: String
    let reversible: Bool
    let createdAt: TimeInterval

    var createdDate: Date { Date(timeIntervalSince1970: createdAt) }

    func toFirestore() -> [String: Any] {
        [
            "uid": uid,
            "action": action,
            "whatChanged": whatChanged,
            "why": why,
            "reversible": reversible,
            "createdAt": createdAt
        ]
    }
}

// MARK: - Provenance

struct TrustProvenance: Codable {
    var sourceLinks: [String]?
    var scriptureRefs: [String]?
    var originalSource: String?
    var publishedAt: TimeInterval?
}

// MARK: - Prayer Privacy

struct PrayerPrivacyScope {
    enum Level: String, Codable, CaseIterable {
        case anonymous     = "ANONYMOUS"
        case churchOnly    = "CHURCH_ONLY"
        case leaderOnly    = "LEADER_ONLY"
        case trustedCircle = "TRUSTED_CIRCLE"
        case `public`      = "PUBLIC"

        var displayName: String {
            switch self {
            case .anonymous:     return "Anonymous"
            case .churchOnly:    return "Church Only"
            case .leaderOnly:    return "Leaders Only"
            case .trustedCircle: return "Trusted Circle"
            case .public:        return "Public"
            }
        }

        var systemImage: String {
            switch self {
            case .anonymous:     return "eye.slash"
            case .churchOnly:    return "building.2"
            case .leaderOnly:    return "star.circle"
            case .trustedCircle: return "person.2"
            case .public:        return "globe"
            }
        }

        // Default for first-time prayer request posts
        static var safeDefault: Level { .churchOnly }
    }
}

// MARK: - Domain Enum
// 14-case life-domain taxonomy for content tagging and Berean formation routing.
// Frozen contract — matches audit/00-inventory/contracts.md.

enum Domain: String, Codable, CaseIterable {
    case personal
    case professional
    case spiritual
    case community
    case health
    case relationships
    case growth
    case creativity
    case service
    case faith
    case family
    case learning
    case wellness
    case purpose

    var displayName: String {
        switch self {
        case .personal:       return "Personal"
        case .professional:   return "Professional"
        case .spiritual:      return "Spiritual"
        case .community:      return "Community"
        case .health:         return "Health"
        case .relationships:  return "Relationships"
        case .growth:         return "Growth"
        case .creativity:     return "Creativity"
        case .service:        return "Service"
        case .faith:          return "Faith"
        case .family:         return "Family"
        case .learning:       return "Learning"
        case .wellness:       return "Wellness"
        case .purpose:        return "Purpose"
        }
    }

    var systemImage: String {
        switch self {
        case .personal:       return "person.circle"
        case .professional:   return "briefcase"
        case .spiritual:      return "sparkles"
        case .community:      return "person.3"
        case .health:         return "heart"
        case .relationships:  return "person.2"
        case .growth:         return "arrow.up.circle"
        case .creativity:     return "paintbrush"
        case .service:        return "hands.and.sparkles"
        case .faith:          return "cross"
        case .family:         return "house"
        case .learning:       return "book.open"
        case .wellness:       return "leaf"
        case .purpose:        return "star"
        }
    }
}

// MARK: - Community Health Status

enum CommunityHealthStatus: String, Codable {
    case healthy  = "HEALTHY"
    case atRisk   = "AT_RISK"
    case inactive = "INACTIVE"

    var displayName: String {
        switch self {
        case .healthy:  return "Healthy"
        case .atRisk:   return "At Risk"
        case .inactive: return "Inactive"
        }
    }

    // Per iOS/SwiftUI port contracts
    var systemImage: String {
        switch self {
        case .healthy:  return "heart.text.square"
        case .atRisk:   return "exclamationmark.triangle"
        case .inactive: return "person.slash"
        }
    }
}

// MARK: - iOS Bridge Signal (internal)

struct iOSSafetySignal: Codable {
    let uid: String
    let sessionSignal: String
    let riskCategory: String
    let contentContext: String
    let threatLevel: Int
    let timestamp: TimeInterval
}
