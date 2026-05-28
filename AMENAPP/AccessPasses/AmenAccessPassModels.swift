// AmenAccessPassModels.swift
// AMENAPP — Unified Access Pass System
//
// One model drives QR, NFC, universal links, share links, event passes, and creator invites.
// All route through the same backend permission engine.

import Foundation

// MARK: - Target Types

enum AmenAccessTargetType: String, Codable, CaseIterable {
    case space         = "space"
    case discussion    = "discussion"
    case smallGroup    = "smallGroup"
    case church        = "church"
    case organization  = "organization"
    case event         = "event"
    case sermonNotes   = "sermonNotes"
    case prayerRoom    = "prayerRoom"

    var displayName: String {
        switch self {
        case .space:         return "Space"
        case .discussion:    return "Discussion"
        case .smallGroup:    return "Small Group"
        case .church:        return "Church"
        case .organization:  return "Organization"
        case .event:         return "Event"
        case .sermonNotes:   return "Sermon Notes"
        case .prayerRoom:    return "Prayer Room"
        }
    }

    var isSensitiveByDefault: Bool {
        switch self {
        case .prayerRoom, .smallGroup: return true
        default:                       return false
        }
    }

    var defaultMode: AmenAccessMode {
        switch self {
        case .prayerRoom:    return .request
        case .smallGroup:    return .request
        case .church:        return .preview
        case .organization:  return .preview
        default:             return .join
        }
    }
}

// MARK: - Access Mode

enum AmenAccessMode: String, Codable, CaseIterable {
    case preview    = "preview"
    case join       = "join"
    case request    = "request"
    case checkIn    = "checkIn"
    case roleGated  = "roleGated"

    var displayName: String {
        switch self {
        case .preview:   return "Preview Only"
        case .join:      return "Join Directly"
        case .request:   return "Request Required"
        case .checkIn:   return "Check-In Access"
        case .roleGated: return "Role-Gated"
        }
    }

    var accessStatusLabel: String {
        switch self {
        case .preview:   return "Access: Preview only"
        case .join:      return "Access: Join directly"
        case .request:   return "Access: Request required"
        case .checkIn:   return "Access: Check-in access"
        case .roleGated: return "Access: Role-gated"
        }
    }
}

// MARK: - Pass Status

enum AmenAccessPassStatus: String, Codable {
    case active   = "active"
    case paused   = "paused"
    case revoked  = "revoked"
    case expired  = "expired"

    var displayName: String {
        switch self {
        case .active:  return "Active"
        case .paused:  return "Paused"
        case .revoked: return "Revoked"
        case .expired: return "Expired"
        }
    }

    var badgeColor: String {
        switch self {
        case .active:  return "green"
        case .paused:  return "orange"
        case .revoked: return "red"
        case .expired: return "gray"
        }
    }
}

// MARK: - Allowed Actions

enum AmenAccessAction: String, Codable, CaseIterable {
    case join             = "join"
    case request          = "request"
    case preview          = "preview"
    case checkIn          = "checkIn"
    case openSermonNotes  = "openSermonNotes"
    case askForPrayer     = "askForPrayer"
    case meetLeader       = "meetLeader"
    case followChurch     = "followChurch"

    var label: String {
        switch self {
        case .join:            return "Join"
        case .request:         return "Request to Join"
        case .preview:         return "Preview"
        case .checkIn:         return "Check In"
        case .openSermonNotes: return "Open Sermon Notes"
        case .askForPrayer:    return "Ask for Prayer"
        case .meetLeader:      return "Meet a Group Leader"
        case .followChurch:    return "Follow This Church"
        }
    }

    var isPrimary: Bool {
        switch self {
        case .join, .request, .checkIn: return true
        default:                        return false
        }
    }
}

// MARK: - Access Pass Preview (returned by resolveAccessPass)

struct AmenAccessPassPreview: Codable, Identifiable {
    var id: String { accessPassId }

    let accessPassId: String
    let targetType: AmenAccessTargetType
    let targetId: String
    let title: String
    let subtitle: String?
    let description: String?
    let verifiedHostName: String?
    let verifiedHostBadge: Bool
    let mode: AmenAccessMode
    let requiredAction: String
    let communityRulesSummary: String?
    let visibilityWarning: String?
    let privacyWarning: String?
    let allowedActions: [AmenAccessAction]
    let requiresAuth: Bool
    let requiresApproval: Bool
    let alreadyMember: Bool
    let existingRequestPending: Bool
}

// MARK: - Access Pass Admin Summary (returned by listAccessPassesForTarget)

struct AmenAccessPassSummary: Codable, Identifiable {
    var id: String { accessPassId }

    let accessPassId: String
    let targetType: AmenAccessTargetType
    let targetId: String
    let title: String
    let subtitle: String?
    let mode: AmenAccessMode
    let status: AmenAccessPassStatus
    let verifiedHostName: String?
    let verifiedHostBadge: Bool
    let requiresAuth: Bool
    let requiresApproval: Bool
    let usesCount: Int
    let maxUses: Int?
    let startsAt: Date?
    let expiresAt: Date?
    let checkInDurationMinutes: Int?
    let createdByDisplayName: String?
    let lastUsedAt: Date?
    let pendingRequestCount: Int?
}

// MARK: - Access Request (returned by listAccessRequestsForTarget)

struct AmenAccessRequest: Codable, Identifiable {
    var id: String { requestId }

    let requestId: String
    let accessPassId: String
    let targetType: AmenAccessTargetType
    let targetId: String
    let requesterUid: String
    let requesterDisplayName: String?
    let requesterPhotoURL: String?
    let status: AmenAccessRequestStatus
    let requestMessage: String?
    let createdAt: Date
    let updatedAt: Date
}

enum AmenAccessRequestStatus: String, Codable {
    case pending   = "pending"
    case approved  = "approved"
    case denied    = "denied"
    case cancelled = "cancelled"
    case expired   = "expired"

    var displayName: String {
        switch self {
        case .pending:   return "Pending"
        case .approved:  return "Approved"
        case .denied:    return "Denied"
        case .cancelled: return "Cancelled"
        case .expired:   return "Expired"
        }
    }
}

// MARK: - Create Pass Input

struct AmenCreateAccessPassInput {
    let targetType: AmenAccessTargetType
    let targetId: String
    var orgId: String?
    var churchId: String?
    var spaceId: String?
    var mode: AmenAccessMode
    var title: String
    var subtitle: String?
    var description: String?
    var requiresAuth: Bool
    var requiresApproval: Bool
    var allowedEmailDomains: [String]
    var allowedRoleIds: [String]
    var allowedMemberUids: [String]
    var maxUses: Int?
    var maxUsesPerUser: Int
    var startsAt: Date?
    var expiresAt: Date?
    var checkInDurationMinutes: Int?
    var isSensitive: Bool
    var requiresModeratorApproval: Bool
    var allowYouthAccess: Bool
    var allowGuestPreview: Bool
    var showMemberVisibilityWarning: Bool
    var showPrayerPrivacyWarning: Bool
    var landingHeadline: String
    var landingBody: String
    var primaryActionLabel: String
    var secondaryActionLabel: String?
    var allowedActions: [AmenAccessAction]

    static func defaultInput(for targetType: AmenAccessTargetType, targetId: String, title: String) -> AmenCreateAccessPassInput {
        AmenCreateAccessPassInput(
            targetType: targetType,
            targetId: targetId,
            mode: targetType.defaultMode,
            title: title,
            requiresAuth: true,
            requiresApproval: targetType.isSensitiveByDefault,
            allowedEmailDomains: [],
            allowedRoleIds: [],
            allowedMemberUids: [],
            maxUsesPerUser: 1,
            isSensitive: targetType.isSensitiveByDefault,
            requiresModeratorApproval: targetType.isSensitiveByDefault,
            allowYouthAccess: false,
            allowGuestPreview: targetType == .church || targetType == .organization,
            showMemberVisibilityWarning: true,
            showPrayerPrivacyWarning: targetType == .prayerRoom,
            landingHeadline: "Welcome to \(title)",
            landingBody: "Join the community on Amen.",
            primaryActionLabel: targetType.defaultMode.label,
            allowedActions: targetType.defaultAllowedActions
        )
    }
}

private extension AmenAccessMode {
    var label: String {
        switch self {
        case .preview:   return "Preview"
        case .join:      return "Join"
        case .request:   return "Request to Join"
        case .checkIn:   return "Check In"
        case .roleGated: return "Request Access"
        }
    }
}

private extension AmenAccessTargetType {
    var defaultAllowedActions: [AmenAccessAction] {
        switch self {
        case .church:       return [.preview, .followChurch, .openSermonNotes, .askForPrayer, .meetLeader]
        case .prayerRoom:   return [.request, .askForPrayer]
        case .smallGroup:   return [.request, .meetLeader]
        case .event:        return [.checkIn, .preview]
        case .sermonNotes:  return [.openSermonNotes, .preview]
        default:            return [.join, .preview]
        }
    }
}

// MARK: - Create Pass Response

struct AmenCreateAccessPassResponse: Codable {
    let accessPassId: String
    let rawToken: String
    let universalLink: String
    let qrPayload: String
    let nfcPayload: String
    let shareLink: String
    let previewTitle: String
    let previewSubtitle: String?
}

// MARK: - Accept Pass Response

struct AmenAcceptAccessPassResponse: Codable {
    let success: Bool
    let action: AmenAccessAction
    let targetId: String
    let targetType: AmenAccessTargetType
    let routePayload: String?
    let requestId: String?
    let checkInExpiresAt: Date?
    let message: String?
}

// MARK: - Rotate Token Response

struct AmenRotateTokenResponse: Codable {
    let accessPassId: String
    let newRawToken: String
    let newUniversalLink: String
    let newQrPayload: String
    let newShareLink: String
}

// MARK: - Callable Name Constants

enum AmenAccessPassCallableNames {
    static let create         = "createAccessPass"
    static let resolve        = "resolveAccessPass"
    static let accept         = "acceptAccessPass"
    static let revoke         = "revokeAccessPass"
    static let pause          = "pauseAccessPass"
    static let resume         = "resumeAccessPass"
    static let rotateToken    = "rotateAccessPassToken"
    static let approveRequest = "approveAccessRequest"
    static let denyRequest    = "denyAccessRequest"
    static let listPasses     = "listAccessPassesForTarget"
    static let listRequests   = "listAccessRequestsForTarget"
}

// MARK: - Error States

enum AmenAccessPassError: LocalizedError, Equatable {
    case invalidPass
    case expiredPass
    case revokedPass
    case pausedPass
    case notStartedYet
    case approvalRequired
    case roleRestricted
    case authRequired
    case rateLimited
    case sensitiveDirectJoinBlocked
    case alreadyMember
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidPass:               return "This access pass could not be verified."
        case .expiredPass:               return "This access pass has expired. Ask the host for a new one."
        case .revokedPass:               return "This access pass is no longer active."
        case .pausedPass:                return "This access pass is temporarily paused."
        case .notStartedYet:             return "This access pass is not yet active."
        case .approvalRequired:          return "Your request was sent to the host."
        case .roleRestricted:            return "This access pass is limited to approved members."
        case .authRequired:              return "Sign in to continue."
        case .rateLimited:               return "Too many attempts. Try again later."
        case .sensitiveDirectJoinBlocked: return "This Space requires approval before joining."
        case .alreadyMember:             return "You're already a member."
        case .unknown(let msg):          return msg
        }
    }

    var userFacingTitle: String {
        switch self {
        case .invalidPass:               return "Invalid Invite"
        case .expiredPass:               return "Invite Expired"
        case .revokedPass:               return "Invite No Longer Active"
        case .pausedPass:                return "Invite Paused"
        case .notStartedYet:             return "Not Yet Active"
        case .approvalRequired:          return "Request Sent"
        case .roleRestricted:            return "Access Restricted"
        case .authRequired:              return "Sign In Required"
        case .rateLimited:               return "Too Many Attempts"
        case .sensitiveDirectJoinBlocked: return "Approval Required"
        case .alreadyMember:             return "Already a Member"
        case .unknown:                   return "Something Went Wrong"
        }
    }

    static func from(code: String) -> AmenAccessPassError {
        switch code {
        case "invalid-pass":                      return .invalidPass
        case "expired":                           return .expiredPass
        case "revoked":                           return .revokedPass
        case "paused":                            return .pausedPass
        case "not-started":                       return .notStartedYet
        case "approval-required":                 return .approvalRequired
        case "role-restricted":                   return .roleRestricted
        case "auth-required":                     return .authRequired
        case "rate-limited":                      return .rateLimited
        case "sensitive-direct-join-blocked":     return .sensitiveDirectJoinBlocked
        case "already-member":                    return .alreadyMember
        default:                                  return .unknown(code)
        }
    }
}
