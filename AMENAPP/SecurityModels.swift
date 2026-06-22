//
//  SecurityModels.swift
//  AMENAPP
//
//  Comprehensive security models for account lifecycle, sessions, and verification
//

import Foundation
import FirebaseAuth

// MARK: - Account Security Status

enum AccountSecurityLevel: String, Codable {
    case unverified = "unverified"
    case basicVerified = "basic_verified"
    case strongVerified = "strong_verified"
    case highRiskVerified = "high_risk_verified"
}

enum AccountStatus: String, Codable {
    case active = "active"
    case limited = "limited"
    case locked = "locked"
    case deactivated = "deactivated"
    case pendingDelete = "pending_delete"
    case deleted = "deleted"
    case suspended = "suspended"
}

// MARK: - Contact Verification

struct ContactMethod: Codable, Identifiable {
    var id: String { type.rawValue + value }
    let type: ContactType
    let value: String
    var verified: Bool
    var verifiedAt: Date?
    var primary: Bool
    var canReceiveSecurityAlerts: Bool
    
    enum ContactType: String, Codable {
        case email
        case phone
    }
}

// MARK: - Login History

struct LoginRecord: Codable, Identifiable {
    let id: String
    let userId: String
    let timestamp: Date
    let success: Bool
    let deviceInfo: DeviceInfo
    let location: LocationInfo?
    let ipAddress: String
    let riskScore: Double
    let failureReason: String?
    let mfaUsed: Bool
}

struct DeviceInfo: Codable {
    let deviceId: String
    let deviceName: String
    let platform: String
    let osVersion: String
    let appVersion: String
    let trusted: Bool
}

struct LocationInfo: Codable {
    let city: String?
    let region: String?
    let country: String
    let latitude: Double?
    let longitude: Double?
}

// MARK: - Active Sessions

struct ActiveSession: Codable, Identifiable {
    let id: String
    let userId: String
    let deviceInfo: DeviceInfo
    let createdAt: Date
    var lastActiveAt: Date
    let ipAddress: String
    let location: LocationInfo?
    let refreshToken: String
    var riskScore: Double
    let current: Bool
    
    var displayName: String {
        deviceInfo.deviceName.isEmpty ? deviceInfo.platform : deviceInfo.deviceName
    }
    
    var isExpired: Bool {
        // Sessions expire after 90 days of inactivity
        Date().timeIntervalSince(lastActiveAt) > 90 * 24 * 60 * 60
    }
}

// MARK: - Security Events

enum SecurityEventType: String, Codable {
    case signupInitiated = "signup_initiated"
    case signupCompleted = "signup_completed"
    case emailVerified = "email_verified"
    case phoneVerified = "phone_verified"
    case loginSuccess = "login_success"
    case loginFailure = "login_failure"
    case mfaEnabled = "mfa_enabled"
    case mfaDisabled = "mfa_disabled"
    case mfaChallengeSuccess = "mfa_challenge_success"
    case mfaChallengeFailure = "mfa_challenge_failure"
    case passwordResetRequested = "password_reset_requested"
    case passwordResetCompleted = "password_reset_completed"
    case passwordChanged = "password_changed"
    case emailChangeRequested = "email_change_requested"
    case emailChangeCompleted = "email_change_completed"
    case emailChangeReverted = "email_change_reverted"
    case phoneChangeRequested = "phone_change_requested"
    case phoneChangeCompleted = "phone_change_completed"
    case sessionCreated = "session_created"
    case sessionRevoked = "session_revoked"
    case allSessionsRevoked = "all_sessions_revoked"
    case deviceTrusted = "device_trusted"
    case deviceUntrusted = "device_untrusted"
    case accountDeactivated = "account_deactivated"
    case accountReactivated = "account_reactivated"
    case deletionRequested = "deletion_requested"
    case deletionCanceled = "deletion_canceled"
    case deletionCompleted = "deletion_completed"
    case recoveryAttempted = "recovery_attempted"
    case connectedAppAdded = "connected_app_added"
    case connectedAppRemoved = "connected_app_removed"
    case suspiciousActivityDetected = "suspicious_activity_detected"
    case accountLocked = "account_locked"
    case accountUnlocked = "account_unlocked"
}

struct SecurityEvent: Codable, Identifiable {
    let id: String
    let userId: String
    let eventType: SecurityEventType
    let timestamp: Date
    let deviceInfo: DeviceInfo?
    let ipAddress: String?
    let location: LocationInfo?
    let metadata: [String: String]?
    let riskScore: Double?
    
    var displayTitle: String {
        switch eventType {
        case .loginSuccess: return "Successful login"
        case .loginFailure: return "Failed login attempt"
        case .passwordChanged: return "Password changed"
        case .emailChangeCompleted: return "Email changed"
        case .phoneChangeCompleted: return "Phone changed"
        case .mfaEnabled: return "Two-factor authentication enabled"
        case .mfaDisabled: return "Two-factor authentication disabled"
        case .sessionRevoked: return "Session logged out"
        case .allSessionsRevoked: return "All sessions logged out"
        case .accountDeactivated: return "Account deactivated"
        case .accountReactivated: return "Account reactivated"
        case .suspiciousActivityDetected: return "Suspicious activity detected"
        default: return eventType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

// MARK: - MFA Methods

enum MFAType: String, Codable {
    case totp = "totp"
    case sms = "sms"
    case backupCodes = "backup_codes"
}

struct MFAMethod: Codable, Identifiable {
    let id: String
    let userId: String
    let type: MFAType
    var enabled: Bool
    let createdAt: Date
    var lastUsedAt: Date?
    let metadata: [String: String]?
    
    var displayName: String {
        switch type {
        case .totp: return "Authenticator App"
        case .sms: return "SMS Verification"
        case .backupCodes: return "Backup Codes"
        }
    }
}

// MARK: - Backup Codes

struct BackupCode: Codable, Identifiable {
    let id: String
    let userId: String
    let code: String
    var used: Bool
    var usedAt: Date?
    let createdAt: Date
}

// MARK: - Trusted Devices

struct TrustedDevice: Codable, Identifiable {
    let id: String
    let userId: String
    let deviceInfo: DeviceInfo
    let trustedAt: Date
    var expiresAt: Date
    var lastUsedAt: Date
    
    var isExpired: Bool {
        Date() > expiresAt
    }
}

// MARK: - Risk Signals

enum SecurityRiskLevel: String, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

struct SecurityRiskSignal: Codable {
    let type: String
    let level: SecurityRiskLevel
    let score: Double
    let details: String
    let timestamp: Date
}

// MARK: - Account Deletion Request

struct DeletionRequest: Codable, Identifiable {
    let id: String
    let userId: String
    let requestedAt: Date
    let scheduledDeletionAt: Date
    var canceled: Bool
    var canceledAt: Date?
    let reason: String?
}

// MARK: - Recovery Case

enum RecoveryType: String, Codable {
    case forgotPassword = "forgot_password"
    case lostEmail = "lost_email"
    case lostPhone = "lost_phone"
    case lostMFA = "lost_mfa"
    case suspectedHack = "suspected_hack"
    case simSwap = "sim_swap"
}

struct RecoveryCase: Codable, Identifiable {
    let id: String
    let userId: String
    let type: RecoveryType
    let initiatedAt: Date
    var resolvedAt: Date?
    var status: String
    let oldEmail: String?
    let newEmail: String?
    let oldPhone: String?
    let newPhone: String?
}

// MARK: - Contact Change Protection

struct ContactChangeRequest: Codable, Identifiable {
    let id: String
    let userId: String
    let changeType: ContactMethod.ContactType
    let oldValue: String
    let newValue: String
    let requestedAt: Date
    var confirmedAt: Date?
    var revertedAt: Date?
    let revertDeadline: Date
    var status: String
}
