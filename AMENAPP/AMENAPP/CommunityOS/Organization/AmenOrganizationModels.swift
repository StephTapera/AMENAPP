// AmenOrganizationModels.swift
// AMEN Community OS — Organization OS (A9)
//
// Canonical organization model for churches, schools, universities,
// businesses, nonprofits, teams, creators, ministries, and studios.
//
// Reuses existing OrgType + VerificationState from CommunityOS/Org/OrgProfileModels.swift.
// AmenOrganization extends the lighter OrgProfile with Firestore-backed full fields,
// KYC status, plan tier, and privacy-sensitive fields (marked admin-only).
//
// Privacy contract (C1 / OrgProfileModels.swift §1):
//   - memberCount: never displayed in any public-facing UI
//   - contactEmail, ein: admin-visible only — never rendered on public screens
//   - Org RBAC maps Owner/ExecAdmin/Pastor → Owner/ExecAdmin/Leader per AmenRBACService

import Foundation

// MARK: - OrgVerificationStatus

/// Extended verification status aligned with Firestore `verificationStatus` field.
/// Distinct from the lighter VerificationState on OrgProfile.
enum OrgVerificationStatus: String, Codable, CaseIterable, Sendable {
    case unverified  = "unverified"
    case pending     = "pending"
    case verified    = "verified"
    case suspended   = "suspended"
}

// MARK: - AmenOrganization

/// Full organization model persisted to Firestore `/organizations/{orgId}`.
/// Reuses `OrgType` from OrgProfileModels.swift — no duplication.
///
/// PRIVACY: `memberCount`, `contactEmail`, and `ein` must NEVER appear
/// in any public-facing profile or discovery UI.
struct AmenOrganization: Codable, Identifiable, Sendable {
    // MARK: Identity
    var id: String
    var name: String
    var type: OrgType                       // reused from OrgProfileModels
    var tagline: String?
    var bio: String
    var coverImageUrl: String?
    var logoUrl: String?

    // MARK: Contact & Links
    var website: String?
    /// ADMIN-ONLY: never shown in public UI
    var contactEmail: String?
    var socialLinks: [String: String]

    // MARK: Verification & Compliance
    var verificationStatus: OrgVerificationStatus
    var verificationBadge: String?
    var isNonprofit: Bool
    /// ADMIN-ONLY: IRS EIN for nonprofit orgs — never rendered publicly
    var ein: String?
    /// "pending" | "approved" | "rejected"
    var kycStatus: String

    // MARK: Mission
    var missionStatement: String?
    var foundedYear: Int?
    /// Public location string, e.g. "Atlanta, GA"
    var location: String?

    // MARK: Privacy-Sensitive Aggregates
    /// ADMIN-ONLY: aggregate member count — never displayed publicly or comparatively
    var memberCount: Int

    // MARK: Features (plan-gated)
    var givingEnabled: Bool
    /// Requires `planTier != "free"`
    var broadcastEnabled: Bool
    /// Requires `planTier != "free"` — backed by OrgAssistantService
    var orgAssistantEnabled: Bool
    /// "free" | "pro" | "enterprise"
    var planTier: String

    // MARK: RBAC
    /// UIDs with owner/executive-admin rights (mirrors church owner pattern)
    var adminIds: [String]
    var createdBy: String

    // MARK: Lifecycle
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    var isActive: Bool

    // MARK: - Plan Helpers

    /// Returns true when the org's plan unlocks broadcast & assistant features.
    var isProOrAbove: Bool {
        planTier == "pro" || planTier == "enterprise"
    }

    // MARK: - OrgProfile bridge

    /// Converts this full model to the lighter OrgProfile used in the
    /// Org OS (A9) CommunityOS/Org layer — preserves the privacy contract
    /// (memberCount is explicitly nil on OrgProfile).
    func asOrgProfile() -> OrgProfile {
        OrgProfile(
            id: id,
            orgType: type,
            name: name,
            description: bio.isEmpty ? nil : bio,
            logoURL: logoUrl,
            coverURL: coverImageUrl,
            verificationState: verificationStatus == .verified ? .verified
                             : verificationStatus == .pending  ? .pending
                             : .none,
            entitlementPlan: EntitlementPlan(rawValue: planTier) ?? .free,
            memberCount: nil,   // NEVER populated for public display
            privacyLevel: "public",
            createdAt: createdAt
        )
    }
}

// MARK: - OrgAnnouncement (full model)

/// Org-level announcement broadcast stored in
/// Firestore `/organizations/{orgId}/announcements/{announcementId}`.
struct AmenOrgAnnouncement: Codable, Identifiable, Sendable {
    var id: String
    var orgId: String
    var title: String
    var body: String
    var authorId: String
    /// "all" | "members" | "admins"
    var audienceType: String
    var isPinned: Bool
    var expiresAt: Date?
    var createdAt: Date
    var isDeleted: Bool
}

// MARK: - OrgVerificationRequest

/// Written to Firestore `/verificationRequests/{requestId}` when an org
/// admin submits documents for verification.
struct OrgVerificationRequest: Codable, Identifiable, Sendable {
    var id: String
    var orgId: String
    var requesterId: String
    /// Firestore Storage reference path for uploaded documents
    var documentRef: String
    var submittedAt: Date
    /// "pending" | "approved" | "rejected"
    var status: String
    var reviewerNote: String?
}

// MARK: - AmenOrganization Preview stubs

#if DEBUG
extension AmenOrganization {
    static var preview: AmenOrganization {
        AmenOrganization(
            id: "org_preview_a9_01",
            name: "Grace Community Church",
            type: .church,
            tagline: "A welcoming community of faith",
            bio: "We exist to glorify God and make disciples in the heart of Atlanta.",
            coverImageUrl: nil,
            logoUrl: nil,
            website: "https://example.com",
            contactEmail: nil,
            socialLinks: [:],
            verificationStatus: .verified,
            verificationBadge: "verified_church",
            isNonprofit: true,
            ein: nil,
            kycStatus: "approved",
            missionStatement: "Glorify God, make disciples.",
            foundedYear: 2005,
            location: "Atlanta, GA",
            memberCount: 0,       // NEVER displayed publicly
            givingEnabled: true,
            broadcastEnabled: true,
            orgAssistantEnabled: true,
            planTier: "pro",
            adminIds: ["user_admin_01"],
            createdBy: "user_admin_01",
            createdAt: Date(timeIntervalSinceNow: -60 * 60 * 24 * 365),
            updatedAt: Date(),
            isDeleted: false,
            isActive: true
        )
    }

    static var nonprofitPreview: AmenOrganization {
        AmenOrganization(
            id: "org_preview_a9_02",
            name: "Restoring Hope Foundation",
            type: .nonprofit,
            tagline: "Practical service in His name",
            bio: "Connecting believers with opportunities to serve their communities.",
            coverImageUrl: nil,
            logoUrl: nil,
            website: nil,
            contactEmail: nil,
            socialLinks: [:],
            verificationStatus: .verified,
            verificationBadge: "verified_nonprofit",
            isNonprofit: true,
            ein: nil,
            kycStatus: "approved",
            missionStatement: "Restoring hope through tangible acts of service.",
            foundedYear: 2018,
            location: "Nashville, TN",
            memberCount: 0,       // NEVER displayed publicly
            givingEnabled: true,
            broadcastEnabled: false,
            orgAssistantEnabled: false,
            planTier: "free",
            adminIds: [],
            createdBy: "user_admin_02",
            createdAt: Date(timeIntervalSinceNow: -60 * 60 * 24 * 180),
            updatedAt: Date(),
            isDeleted: false,
            isActive: true
        )
    }
}
#endif
