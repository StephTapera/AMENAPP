//
//  AgeAssuranceModels.swift
//  AMENAPP
//
//  Layered age assurance system following Meta's Instagram/Threads pattern.
//  Uses declared age + triggered verification + AI detection for comprehensive protection.
//

import Foundation
import FirebaseFirestore

// MARK: - Age Assurance Tier

/// Age tier determines feature access and content filtering
enum AgeAssuranceTier: String, Codable {
    case underMinimum = "under_minimum"  // < 13: blocked
    case teen = "teen"                    // 13-17: restricted features
    case adult = "adult"                  // 18+: full access
    
    var isMinor: Bool {
        self == .underMinimum || self == .teen
    }
    
    var canAccessDMs: Bool {
        self == .adult  // Only adults can send/receive DMs
    }
    
    var requiresParentalConsent: Bool {
        self == .teen
    }
}

// MARK: - Age Verification Status

/// Verification status for age assurance
enum AgeVerificationStatus: String, Codable {
    case declared = "declared"           // User entered DOB, not verified
    case verified = "verified"           // Passed ID or video selfie verification
    case pending = "pending"             // Verification in progress
    case failed = "failed"               // Verification failed
    case flagged = "flagged"             // AI flagged as potentially false
}

// MARK: - Age Verification Method

/// Method used to verify age
enum AgeVerificationMethod: String, Codable {
    case dateOfBirth = "date_of_birth"   // Initial DOB entry at sign-up
    case governmentID = "government_id"  // ID document upload
    case videoSelfie = "video_selfie"    // Age estimation from selfie
    case parentalConsent = "parental_consent"  // Parent verified for under-16
}

// MARK: - User Age Profile

/// Comprehensive age assurance data stored in Firestore users/{uid}/private/age_assurance
struct UserAgeProfile: Codable {
    /// Encrypted date of birth (stored as timestamp)
    /// NOTE: Store in private subcollection, never in main user document
    let dateOfBirth: Date
    
    /// Current age tier (derived from DOB or verification)
    var tier: AgeAssuranceTier
    
    /// Verification status
    var verificationStatus: AgeVerificationStatus
    
    /// Methods used to verify age (can have multiple)
    var verificationMethods: [AgeVerificationMethod]
    
    /// When age was last verified
    var lastVerified: Date
    
    /// Whether AI flagged this user as potentially underage
    var aiRiskScore: Double  // 0.0 - 1.0 (higher = more likely underage)
    
    /// Verification attempts (track for rate limiting)
    var verificationAttempts: Int
    
    /// Last verification attempt timestamp
    var lastVerificationAttempt: Date?
    
    /// Country code (for age thresholds: some countries require 16+)
    var countryCode: String
    
    /// Parental supervision enabled (for under-16 in some regions)
    var parentalSupervisionEnabled: Bool
    
    /// Parent/guardian user ID (if supervision active)
    var parentUserId: String?
    
    /// When profile was created
    let createdAt: Date
    
    /// When profile was last updated
    var updatedAt: Date
    
    // MARK: - Computed Properties
    
    /// Current age in years
    var age: Int {
        Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date()).year ?? 0
    }
    
    /// Whether user meets minimum age requirement
    var meetsMinimumAge: Bool {
        age >= AppConfig.Legal.minimumAge
    }
    
    /// Whether user needs triggered verification (suspicious activity)
    var needsVerification: Bool {
        verificationStatus == .declared && (aiRiskScore > 0.6 || verificationAttempts > 0)
    }
    
    /// Whether user can access age-restricted features
    func canAccess(feature: AgeRestrictedFeature) -> Bool {
        switch feature {
        case .directMessages:
            return tier.canAccessDMs
        case .publicProfile:
            return tier != .underMinimum
        case .sensitiveContent:
            return tier == .adult
        case .commerce:
            return tier == .adult
        case .liveStreaming:
            return tier == .adult
        }
    }
    
    // MARK: - Initialization
    
    init(
        dateOfBirth: Date,
        countryCode: String = "US",
        verificationMethod: AgeVerificationMethod = .dateOfBirth
    ) {
        self.dateOfBirth = dateOfBirth
        self.countryCode = countryCode
        self.verificationMethods = [verificationMethod]
        self.verificationStatus = .declared
        self.lastVerified = Date()
        self.aiRiskScore = 0.0
        self.verificationAttempts = 0
        self.parentalSupervisionEnabled = false
        self.createdAt = Date()
        self.updatedAt = Date()
        
        // Compute tier from age
        let age = Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date()).year ?? 0
        if age < AppConfig.Legal.minimumAge {
            self.tier = .underMinimum
        } else if age < 18 {
            self.tier = .teen
        } else {
            self.tier = .adult
        }
    }
}

// MARK: - Age Restricted Features

/// Features that require age gating
enum AgeRestrictedFeature {
    case directMessages       // DMs: adult only
    case publicProfile       // Public profiles: 13+
    case sensitiveContent    // Sensitive content: 18+
    case commerce            // In-app purchases, marketplace: 18+
    case liveStreaming       // Live video: 18+
}

// MARK: - Age Verification Event

/// Log verification events for audit trail
struct AgeVerificationEvent: Codable {
    let userId: String
    let eventType: EventType
    let method: AgeVerificationMethod?
    let previousTier: AgeAssuranceTier?
    let newTier: AgeAssuranceTier?
    let success: Bool
    let failureReason: String?
    let timestamp: Date
    let ipAddress: String?
    let deviceId: String?
    
    enum EventType: String, Codable {
        case ageCollected = "age_collected"           // Initial DOB entry
        case ageChanged = "age_changed"               // User changed DOB
        case verificationRequested = "verification_requested"
        case verificationCompleted = "verification_completed"
        case verificationFailed = "verification_failed"
        case aiFlagged = "ai_flagged"                 // AI detected potential underage
        case tierChanged = "tier_changed"             // Teen -> Adult or vice versa
        case parentalConsentGranted = "parental_consent_granted"
        case featureBlocked = "feature_blocked"       // User tried to access gated feature
    }
    
    init(
        userId: String,
        eventType: EventType,
        method: AgeVerificationMethod? = nil,
        previousTier: AgeAssuranceTier? = nil,
        newTier: AgeAssuranceTier? = nil,
        success: Bool = true,
        failureReason: String? = nil,
        ipAddress: String? = nil,
        deviceId: String? = nil
    ) {
        self.userId = userId
        self.eventType = eventType
        self.method = method
        self.previousTier = previousTier
        self.newTier = newTier
        self.success = success
        self.failureReason = failureReason
        self.timestamp = Date()
        self.ipAddress = ipAddress
        self.deviceId = deviceId
    }
}

// MARK: - Age Gate Configuration

/// Remote configuration for age verification thresholds
struct AgeGateConfig {
    /// Minimum age by country (default: 13)
    let minimumAgeByCountry: [String: Int]
    
    /// Teen protection age threshold (default: 18)
    let teenProtectionAge: Int
    
    /// AI risk threshold for triggering verification (default: 0.6)
    let aiRiskThreshold: Double
    
    /// Maximum verification attempts before manual review (default: 3)
    let maxVerificationAttempts: Int
    
    /// Cooldown period between verification attempts (default: 24h)
    let verificationCooldown: TimeInterval
    
    /// Whether to enforce parental consent for under-16 (default: false)
    let requireParentalConsentUnder16: Bool
    
    /// Whether to enable AI age detection (default: true)
    let enableAIAgeDetection: Bool
    
    static let `default` = AgeGateConfig(
        minimumAgeByCountry: ["US": 13, "EU": 13, "UK": 13, "KR": 14],
        teenProtectionAge: 18,
        aiRiskThreshold: 0.6,
        maxVerificationAttempts: 3,
        verificationCooldown: 86400,  // 24 hours
        // PROTECTIVE DEFAULT: consent UI not yet complete — under-16 restricted until consent received
        // OPEN-2: Build guardian consent UI. To relax this default, Steph explicit decision required.
        requireParentalConsentUnder16: true,
        enableAIAgeDetection: true
    )
}
