//
//  AmenPermissionModels.swift
//  AMENAPP
//
//  Swift-side types for the Amen Permissions Engine.
//  The resolved PermissionSet is written server-side to permissions/{uid}
//  and read here. Clients never write this document.
//
//  Mirrors permissionsTypes.ts exactly. Any change to the TypeScript types
//  must be reflected here — the Firestore document is the contract.
//

import Foundation
import FirebaseFirestore

// MARK: - Age Tier

/// Account age classification. Mirrors the AgeTier TypeScript type.
/// v1 ships teen + adult only; under-13 (COPPA / Family Mode) is a future release.
enum AmenAgeTier: String, Codable, Equatable {
    case teen  = "teen"
    case adult = "adult"

    var isMinor: Bool { self == .teen }

    /// Bridge from the existing AMENAgeAssuranceTier enum used by the age-assurance flow.
    /// underMinimum maps to teen for v1 — under-13 onboarding is gated at the app level.
    init(from assuranceTier: AMENAgeAssuranceTier) {
        switch assuranceTier {
        case .underMinimum: self = .teen
        case .teen:         self = .teen
        case .adult:        self = .adult
        }
    }
}

// MARK: - Identity Mode

/// How the account is currently presenting itself. Narrows but never raises beyond the ceiling.
enum AmenIdentityMode: String, Codable, Equatable, CaseIterable {
    case social     = "social"
    case discussion = "discussion"
    case study      = "study"
    case quiet      = "quiet"
    case postless   = "postless"
    case campus     = "campus"
    case family     = "family"

    var displayName: String {
        switch self {
        case .social:     return "Social"
        case .discussion: return "Discussion"
        case .study:      return "Study"
        case .quiet:      return "Quiet"
        case .postless:   return "Postless"
        case .campus:     return "Campus"
        case .family:     return "Family"
        }
    }

    var description: String {
        switch self {
        case .social:     return "Full broadcast — post, discover, message openly"
        case .discussion: return "Conversations only — no feed posts"
        case .study:      return "Groups, notes, and mentorship"
        case .quiet:      return "Trusted interactions only"
        case .postless:   return "Exist without broadcasting"
        case .campus:     return "Scoped to your campus or church"
        case .family:     return "Guardian-linked family environment"
        }
    }

    /// Modes available to each tier. Mirrors isModeAllowedForTier in permissionsEngine.ts.
    static func allowed(for tier: AmenAgeTier) -> [AmenIdentityMode] {
        switch tier {
        case .teen:  return [.postless, .discussion, .study, .quiet, .campus, .family]
        case .adult: return AmenIdentityMode.allCases
        }
    }
}

// MARK: - DM Policy

/// Ordered least → most permissive. Matches DMPolicy in permissionsTypes.ts.
enum AmenDMPolicy: String, Codable, Equatable, Comparable {
    case none        = "none"
    case trustedOnly = "trustedOnly"
    case mutualOnly  = "mutualOnly"
    case open        = "open"

    private var order: Int {
        switch self {
        case .none:        return 0
        case .trustedOnly: return 1
        case .mutualOnly:  return 2
        case .open:        return 3
        }
    }

    static func < (lhs: AmenDMPolicy, rhs: AmenDMPolicy) -> Bool {
        lhs.order < rhs.order
    }
}

// MARK: - Reach Tier

/// Ordered least → most permissive. Matches ReachTier in permissionsTypes.ts.
enum AmenReachTier: String, Codable, Equatable, Comparable {
    case restricted = "restricted"
    case normal     = "normal"
    case amplified  = "amplified"

    private var order: Int {
        switch self {
        case .restricted: return 0
        case .normal:     return 1
        case .amplified:  return 2
        }
    }

    static func < (lhs: AmenReachTier, rhs: AmenReachTier) -> Bool {
        lhs.order < rhs.order
    }
}

// MARK: - Permission Set

/// The resolved set of capabilities for an account. Read from permissions/{uid}.
/// This document is written exclusively by Cloud Functions — clients never write it.
struct AmenPermissionSet: Codable, Equatable {
    let canPostPublic: Bool
    let canBeDiscovered: Bool
    let canCreateGroup: Bool
    let canUploadMedia: Bool
    let sendDM: AmenDMPolicy
    let receiveDM: AmenDMPolicy
    let reachTier: AmenReachTier
    /// Pre-distribution human/quarantine hold. Not the fast ML classifier.
    let requiresPrePublishReview: Bool
    /// Adult-side; true only when verified + mentorApproved.
    let canContactMinors: Bool

    // Metadata stored alongside the permission fields
    let resolvedAt: Date?
    let ceilingTier: AmenAgeTier?

    enum CodingKeys: String, CodingKey {
        case canPostPublic, canBeDiscovered, canCreateGroup, canUploadMedia
        case sendDM, receiveDM, reachTier, requiresPrePublishReview, canContactMinors
        case resolvedAt, ceilingTier
    }

    // MARK: Firestore timestamp decoding

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        canPostPublic            = try c.decode(Bool.self, forKey: .canPostPublic)
        canBeDiscovered          = try c.decode(Bool.self, forKey: .canBeDiscovered)
        canCreateGroup           = try c.decode(Bool.self, forKey: .canCreateGroup)
        canUploadMedia           = try c.decode(Bool.self, forKey: .canUploadMedia)
        sendDM                   = try c.decode(AmenDMPolicy.self, forKey: .sendDM)
        receiveDM                = try c.decode(AmenDMPolicy.self, forKey: .receiveDM)
        reachTier                = try c.decode(AmenReachTier.self, forKey: .reachTier)
        requiresPrePublishReview = try c.decode(Bool.self, forKey: .requiresPrePublishReview)
        canContactMinors         = try c.decode(Bool.self, forKey: .canContactMinors)
        ceilingTier              = try c.decodeIfPresent(AmenAgeTier.self, forKey: .ceilingTier)
        // Firestore Timestamps are decoded as Date when using the Firestore decoder
        resolvedAt               = try c.decodeIfPresent(Date.self, forKey: .resolvedAt)
    }

    // MARK: Convenience checks

    /// Whether the account can send a DM to someone (regardless of recipient policy).
    var canSendAnyDM: Bool { sendDM != .none }

    /// Whether the account can receive any DM.
    var canReceiveAnyDM: Bool { receiveDM != .none }

    /// Whether the composer should be shown.
    var shouldShowComposer: Bool { canPostPublic }

    /// Whether the DM entry point should be shown.
    func shouldShowDMEntry(for policy: AmenDMPolicy = .trustedOnly) -> Bool {
        sendDM >= policy
    }

    // MARK: Restricted base (mirrors RESTRICTED_BASE in permissionsEngine.ts)

    static let restrictedBase = AmenPermissionSet(
        canPostPublic: false,
        canBeDiscovered: false,
        canCreateGroup: false,
        canUploadMedia: false,
        sendDM: .none,
        receiveDM: .none,
        reachTier: .restricted,
        requiresPrePublishReview: true,
        canContactMinors: false,
        resolvedAt: nil,
        ceilingTier: nil
    )

    // memberwise init for the static constant and testing
    init(
        canPostPublic: Bool,
        canBeDiscovered: Bool,
        canCreateGroup: Bool,
        canUploadMedia: Bool,
        sendDM: AmenDMPolicy,
        receiveDM: AmenDMPolicy,
        reachTier: AmenReachTier,
        requiresPrePublishReview: Bool,
        canContactMinors: Bool,
        resolvedAt: Date?,
        ceilingTier: AmenAgeTier?
    ) {
        self.canPostPublic = canPostPublic
        self.canBeDiscovered = canBeDiscovered
        self.canCreateGroup = canCreateGroup
        self.canUploadMedia = canUploadMedia
        self.sendDM = sendDM
        self.receiveDM = receiveDM
        self.reachTier = reachTier
        self.requiresPrePublishReview = requiresPrePublishReview
        self.canContactMinors = canContactMinors
        self.resolvedAt = resolvedAt
        self.ceilingTier = ceilingTier
    }
}

// MARK: - Set Mode Response

struct AmenSetModeResponse: Codable {
    let success: Bool
    let permissions: AmenPermissionSet
}

// MARK: - Initiate DM Response

struct AmenInitiateDMResponse: Codable {
    let allowed: Bool
    let reason: String?
}
