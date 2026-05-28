// AmenVerificationModels.swift
// AMENAPP — Verification & Trust System
//
// All models are Codable with a custom date strategy that handles both
// Firestore Timestamp doubles (seconds since epoch) and ISO-8601 strings.

import Foundation

// MARK: - Date Decoding Helpers

private extension KeyedDecodingContainer {
    /// Decodes a Date from either a Double (Firestore Timestamp seconds) or
    /// an ISO-8601 string. Returns nil if the key is missing.
    func decodeFlexDate(forKey key: Key) throws -> Date? {
        if let interval = try? decode(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: interval)
        }
        if let str = try? decode(String.self, forKey: key) {
            let iso = ISO8601DateFormatter()
            return iso.date(from: str)
        }
        return nil
    }

    func decodeFlexDateRequired(forKey key: Key) throws -> Date {
        if let interval = try? decode(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: interval)
        }
        if let str = try? decode(String.self, forKey: key) {
            let iso = ISO8601DateFormatter()
            if let d = iso.date(from: str) { return d }
        }
        throw DecodingError.dataCorruptedError(
            forKey: key, in: self, debugDescription: "Cannot decode Date"
        )
    }
}

// MARK: - AmenSafetyStanding

enum AmenSafetyStanding: String, Codable, Sendable, Equatable {
    case active       = "active"
    case limited      = "limited"
    case suspended    = "suspended"
    case underReview  = "under_review"

    var displayLabel: String {
        switch self {
        case .active:      return "Active"
        case .limited:     return "Limited"
        case .suspended:   return "Suspended"
        case .underReview: return "Under Review"
        }
    }
}

// MARK: - AmenRiskLevel

enum AmenRiskLevel: String, Codable, Sendable, Equatable {
    case low     = "low"
    case medium  = "medium"
    case high    = "high"
    case blocked = "blocked"

    var displayName: String {
        switch self {
        case .low:     return "Low Risk"
        case .medium:  return "Medium Risk"
        case .high:    return "High Risk"
        case .blocked: return "Blocked"
        }
    }
}

// MARK: - VerificationBadgeType

enum VerificationBadgeType: String, Codable, Sendable, Equatable, Hashable, CaseIterable,
                            Identifiable {
    case emailVerified        = "email_verified"
    case phoneVerified        = "phone_verified"
    case identityVerified     = "identity_verified"
    case organizationVerified = "organization_verified"
    case creatorVerified      = "creator_verified"
    case roleVerified         = "role_verified"
    case safetyActive         = "safety_active"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .emailVerified:        return "envelope.badge.shield.half.filled"
        case .phoneVerified:        return "phone.badge.checkmark"
        case .identityVerified:     return "person.badge.shield.checkmark"
        case .organizationVerified: return "building.2.crop.circle.badge.checkmark"
        case .creatorVerified:      return "star.bubble"
        case .roleVerified:         return "rosette"
        case .safetyActive:         return "checkmark.shield.fill"
        }
    }

    var displayName: String {
        switch self {
        case .emailVerified:        return "Email Verified"
        case .phoneVerified:        return "Phone Verified"
        case .identityVerified:     return "Identity Verified"
        case .organizationVerified: return "Organization Verified"
        case .creatorVerified:      return "Creator Verified"
        case .roleVerified:         return "Role Verified"
        case .safetyActive:         return "Safety Standing: Active"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .emailVerified:
            return "Email address has been verified"
        case .phoneVerified:
            return "Phone number has been verified"
        case .identityVerified:
            return "Identity has been verified through a trusted provider"
        case .organizationVerified:
            return "Organization membership has been verified"
        case .creatorVerified:
            return "Creator status has been verified by Amen"
        case .roleVerified:
            return "Ministry or organizational role has been verified"
        case .safetyActive:
            return "Account is in good safety standing"
        }
    }

    var explanationCopy: String {
        switch self {
        case .emailVerified:
            return "This person has confirmed ownership of their email address."
        case .phoneVerified:
            return "This person has confirmed ownership of their phone number."
        case .identityVerified:
            return "This person's identity has been verified through a secure third-party process. Their legal name is not shared publicly."
        case .organizationVerified:
            return "This person has verified they are a member or representative of their listed organization."
        case .creatorVerified:
            return "Amen has verified this person as an active creator on the platform."
        case .roleVerified:
            return "This person's ministry or organizational role has been verified by their organization."
        case .safetyActive:
            return "This account is in good standing and has no active safety restrictions."
        }
    }
}

// MARK: - AmenVerificationRequestType

enum AmenVerificationRequestType: String, Codable, Sendable, Equatable {
    case identity     = "identity"
    case creator      = "creator"
    case role         = "role"
    case organization = "organization"
}

// MARK: - AmenVerificationRequestStatus

enum AmenVerificationRequestStatus: String, Codable, Sendable, Equatable {
    case pending      = "pending"
    case approved     = "approved"
    case rejected     = "rejected"
    case needsMoreInfo = "needs_more_info"
    case expired      = "expired"
    case revoked      = "revoked"

    var displayLabel: String {
        switch self {
        case .pending:       return "Pending Review"
        case .approved:      return "Approved"
        case .rejected:      return "Not Approved"
        case .needsMoreInfo: return "More Info Needed"
        case .expired:       return "Expired"
        case .revoked:       return "Revoked"
        }
    }

    /// No further state transitions are possible from a terminal status.
    var isTerminal: Bool {
        switch self {
        case .approved, .rejected, .expired, .revoked: return true
        case .pending, .needsMoreInfo:                 return false
        }
    }

    /// User can take an action (e.g. supply more info, re-submit) from this status.
    var isActionable: Bool {
        switch self {
        case .needsMoreInfo, .rejected, .expired: return true
        case .pending, .approved, .revoked:       return false
        }
    }
}

// MARK: - AmenVerificationRequest

struct AmenVerificationRequest: Identifiable, Sendable, Equatable {
    let id: String
    let type: AmenVerificationRequestType
    var status: AmenVerificationRequestStatus
    var safeUserReason: String?
    let createdAt: Date?
    var updatedAt: Date?
    var expiresAt: Date?

    static let placeholder = AmenVerificationRequest(
        id: "preview",
        type: .identity,
        status: .pending,
        safeUserReason: nil,
        createdAt: Date(),
        updatedAt: Date(),
        expiresAt: nil
    )
}

extension AmenVerificationRequest: Codable {
    enum CodingKeys: String, CodingKey {
        case id, type, status, safeUserReason, createdAt, updatedAt, expiresAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(String.self, forKey: .id)
        type            = try c.decode(AmenVerificationRequestType.self, forKey: .type)
        status          = try c.decode(AmenVerificationRequestStatus.self, forKey: .status)
        safeUserReason  = try? c.decode(String.self, forKey: .safeUserReason)
        createdAt       = try c.decodeFlexDate(forKey: .createdAt)
        updatedAt       = try c.decodeFlexDate(forKey: .updatedAt)
        expiresAt       = try c.decodeFlexDate(forKey: .expiresAt)
    }
}

// MARK: - AmenRoleVerification

struct AmenRoleVerification: Identifiable, Sendable, Equatable {
    /// Document ID is the user's UID.
    let id: String
    let role: String
    var status: AmenVerificationRequestStatus
    let scope: String
    let issuedBy: String
    let organizationId: String
    var organizationName: String?
    var issuedAt: Date?
    var expiresAt: Date?
    var revokedAt: Date?
    var revokeReason: String?

    var isActive: Bool {
        guard status == .approved else { return false }
        if let exp = expiresAt { return exp > Date() }
        return true
    }

    var displayLabel: String {
        if let org = organizationName, !org.isEmpty {
            return "Verified \(role) at \(org)"
        }
        return "Verified \(role)"
    }

    static let placeholder = AmenRoleVerification(
        id: "preview",
        role: "Pastor",
        status: .approved,
        scope: "congregation",
        issuedBy: "org_preview",
        organizationId: "org_preview",
        organizationName: "Grace Community Church",
        issuedAt: Date(),
        expiresAt: nil,
        revokedAt: nil,
        revokeReason: nil
    )
}

extension AmenRoleVerification: Codable {
    enum CodingKeys: String, CodingKey {
        case id, role, status, scope, issuedBy, organizationId
        case organizationName, issuedAt, expiresAt, revokedAt, revokeReason
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(String.self, forKey: .id)
        role             = try c.decode(String.self, forKey: .role)
        status           = try c.decode(AmenVerificationRequestStatus.self, forKey: .status)
        scope            = try c.decode(String.self, forKey: .scope)
        issuedBy         = try c.decode(String.self, forKey: .issuedBy)
        organizationId   = try c.decode(String.self, forKey: .organizationId)
        organizationName = try? c.decode(String.self, forKey: .organizationName)
        issuedAt         = try c.decodeFlexDate(forKey: .issuedAt)
        expiresAt        = try c.decodeFlexDate(forKey: .expiresAt)
        revokedAt        = try c.decodeFlexDate(forKey: .revokedAt)
        revokeReason     = try? c.decode(String.self, forKey: .revokeReason)
    }
}

// MARK: - AmenPublicVerificationSummary

struct AmenPublicVerificationSummary: Codable, Sendable, Equatable {
    var emailVerified: Bool
    var phoneVerified: Bool
    var identityVerified: Bool
    var creatorVerified: Bool
    var safetyStanding: AmenSafetyStanding
    var visibleBadges: [String]
    var updatedAt: Date?

    static let empty = AmenPublicVerificationSummary(
        emailVerified: false,
        phoneVerified: false,
        identityVerified: false,
        creatorVerified: false,
        safetyStanding: .active,
        visibleBadges: [],
        updatedAt: nil
    )

    enum CodingKeys: String, CodingKey {
        case emailVerified, phoneVerified, identityVerified, creatorVerified
        case safetyStanding, visibleBadges, updatedAt
    }

    init(
        emailVerified: Bool,
        phoneVerified: Bool,
        identityVerified: Bool,
        creatorVerified: Bool,
        safetyStanding: AmenSafetyStanding,
        visibleBadges: [String],
        updatedAt: Date?
    ) {
        self.emailVerified    = emailVerified
        self.phoneVerified    = phoneVerified
        self.identityVerified = identityVerified
        self.creatorVerified  = creatorVerified
        self.safetyStanding   = safetyStanding
        self.visibleBadges    = visibleBadges
        self.updatedAt        = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        emailVerified    = (try? c.decode(Bool.self, forKey: .emailVerified))    ?? false
        phoneVerified    = (try? c.decode(Bool.self, forKey: .phoneVerified))    ?? false
        identityVerified = (try? c.decode(Bool.self, forKey: .identityVerified)) ?? false
        creatorVerified  = (try? c.decode(Bool.self, forKey: .creatorVerified))  ?? false
        safetyStanding   = (try? c.decode(AmenSafetyStanding.self, forKey: .safetyStanding)) ?? .active
        visibleBadges    = (try? c.decode([String].self, forKey: .visibleBadges)) ?? []
        updatedAt        = try c.decodeFlexDate(forKey: .updatedAt)
    }
}

// MARK: - AmenOrganizationVerificationSummary

struct AmenOrganizationVerificationSummary: Codable, Sendable, Equatable {
    var organizationVerified: Bool
    var verifiedName: String?
    var verifiedDomain: String?
    var visibleBadges: [String]
    var updatedAt: Date?

    static let empty = AmenOrganizationVerificationSummary(
        organizationVerified: false,
        verifiedName: nil,
        verifiedDomain: nil,
        visibleBadges: [],
        updatedAt: nil
    )

    enum CodingKeys: String, CodingKey {
        case organizationVerified, verifiedName, verifiedDomain, visibleBadges, updatedAt
    }

    init(
        organizationVerified: Bool,
        verifiedName: String?,
        verifiedDomain: String?,
        visibleBadges: [String],
        updatedAt: Date?
    ) {
        self.organizationVerified = organizationVerified
        self.verifiedName         = verifiedName
        self.verifiedDomain       = verifiedDomain
        self.visibleBadges        = visibleBadges
        self.updatedAt            = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        organizationVerified = (try? c.decode(Bool.self, forKey: .organizationVerified)) ?? false
        verifiedName         = try? c.decode(String.self, forKey: .verifiedName)
        verifiedDomain       = try? c.decode(String.self, forKey: .verifiedDomain)
        visibleBadges        = (try? c.decode([String].self, forKey: .visibleBadges)) ?? []
        updatedAt            = try c.decodeFlexDate(forKey: .updatedAt)
    }
}

// MARK: - AmenIdentitySessionResponse
//
// Safe server response: contains only session routing data.
// No legal name, no government ID data, no biometric data is ever in this struct.

struct AmenIdentitySessionResponse: Codable, Sendable {
    let sessionToken: String
    let sessionUrl: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case sessionToken, sessionUrl, expiresAt
    }

    init(from decoder: Decoder) throws {
        let c    = try decoder.container(keyedBy: CodingKeys.self)
        sessionToken = try c.decode(String.self, forKey: .sessionToken)
        sessionUrl   = try c.decode(String.self, forKey: .sessionUrl)
        expiresAt    = try c.decodeFlexDateRequired(forKey: .expiresAt)
    }

    init(sessionToken: String, sessionUrl: String, expiresAt: Date) {
        self.sessionToken = sessionToken
        self.sessionUrl   = sessionUrl
        self.expiresAt    = expiresAt
    }
}

// MARK: - AmenVerificationSectionState

struct AmenVerificationSectionState: Identifiable, Sendable, Equatable {
    let id: VerificationBadgeType
    var isVerified: Bool
    var isEligible: Bool
    var hasPending: Bool
    var pendingRequest: AmenVerificationRequest?
    var expiresAt: Date?
    var canStart: Bool
    var actionLabel: String

    var displayStatus: String {
        if isVerified {
            if let exp = expiresAt, exp < Date() { return "Expired" }
            return "Verified"
        }
        if hasPending { return pendingRequest?.status.displayLabel ?? "Pending" }
        if !isEligible { return "Not Eligible" }
        return canStart ? "Get Verified" : "Unavailable"
    }
}
