// OrgProfileModels.swift
// AMEN Community OS — Org OS (A9)
//
// Generic org profile models for schools, universities, businesses,
// nonprofits, ministries, creator accounts, and churches.
//
// Privacy rule: memberCount is ALWAYS nil on OrgProfile and is NEVER
// displayed in any public UI. No comparative metrics, no follower counts.

import Foundation

// MARK: - OrgType

enum OrgType: String, Codable, CaseIterable, Sendable {
    case church     = "church"
    case school     = "school"
    case university = "university"
    case business   = "business"
    case ministry   = "ministry"
    case team       = "team"
    case creator    = "creator"
    case nonprofit  = "nonprofit"

    var displayName: String {
        switch self {
        case .church:     return "Church"
        case .school:     return "School"
        case .university: return "University"
        case .business:   return "Business"
        case .ministry:   return "Ministry"
        case .team:       return "Team"
        case .creator:    return "Creator"
        case .nonprofit:  return "Nonprofit"
        }
    }

    var systemImage: String {
        switch self {
        case .church:     return "building.columns"
        case .school:     return "graduationcap"
        case .university: return "building.2"
        case .business:   return "briefcase"
        case .ministry:   return "hands.and.sparkles"
        case .team:       return "person.3"
        case .creator:    return "paintbrush"
        case .nonprofit:  return "heart.circle"
        }
    }
}

// MARK: - VerificationState

enum VerificationState: String, Codable, CaseIterable, Sendable {
    case none     = "none"
    case pending  = "pending"
    case verified = "verified"
}

// MARK: - EntitlementPlan

enum EntitlementPlan: String, Codable, CaseIterable {
    case free         = "free"
    case communityPro = "communityPro"
    case churchPro    = "churchPro"
    case orgPro       = "orgPro"
    case enterprise   = "enterprise"

    var displayName: String {
        switch self {
        case .free:         return "Free"
        case .communityPro: return "Community Pro"
        case .churchPro:    return "Church Pro"
        case .orgPro:       return "Org Pro"
        case .enterprise:   return "Enterprise"
        }
    }
}

// MARK: - OrgProfile

/// Generic org profile.
/// `memberCount` is intentionally `nil` on this type — it must never be
/// fetched or displayed in any public-facing UI per the privacy contract.
struct OrgProfile: Identifiable, Codable {
    let id: String
    let orgType: OrgType
    var name: String
    var description: String?
    var logoURL: String?
    var coverURL: String?
    var verificationState: VerificationState
    var entitlementPlan: EntitlementPlan

    /// PRIVACY: Always nil for public display.
    /// Never read or display this value outside internal analytics.
    var memberCount: Int?

    var privacyLevel: String    // "public" | "members" | "private"
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, orgType, name, description, logoURL, coverURL
        case verificationState, entitlementPlan, memberCount, privacyLevel, createdAt
    }
}

// MARK: - OrgAnnouncement

/// Org-level announcement broadcast.
struct OrgAnnouncement: Identifiable, Codable {
    let id: String
    let orgId: String
    let title: String
    let body: String
    let authorName: String
    let postedAt: Date
    var isActive: Bool
}

// MARK: - Sample data (for previews only)

extension OrgProfile {
    static var preview: OrgProfile {
        OrgProfile(
            id: "org_preview_01",
            orgType: .church,
            name: "Grace Community Church",
            description: "A welcoming community of faith in the heart of the city. Join us every Sunday for worship, community, and growth.",
            logoURL: nil,
            coverURL: nil,
            verificationState: .verified,
            entitlementPlan: .churchPro,
            memberCount: nil,   // NEVER populated for public display
            privacyLevel: "public",
            createdAt: Date(timeIntervalSinceNow: -60 * 60 * 24 * 365)
        )
    }

    static var nonprofitPreview: OrgProfile {
        OrgProfile(
            id: "org_preview_02",
            orgType: .nonprofit,
            name: "Restoring Hope Foundation",
            description: "Restoring Hope connects believers with practical opportunities to serve their communities.",
            logoURL: nil,
            coverURL: nil,
            verificationState: .verified,
            entitlementPlan: .orgPro,
            memberCount: nil,
            privacyLevel: "public",
            createdAt: Date(timeIntervalSinceNow: -60 * 60 * 24 * 180)
        )
    }
}
