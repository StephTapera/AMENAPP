//
//  CrisisSupportModels.swift
//  AMENAPP
//
//  Enhanced Crisis Support Models
//  Non-punitive, supportive intervention system
//

import Foundation
import SwiftUI

// MARK: - Enhanced Crisis Risk Score

/// Detailed risk assessment with scoring (0-1) and reason codes
struct CrisisRiskAssessment: Codable {
    let riskScore: Double  // 0.0 (no risk) to 1.0 (critical)
    let riskLevel: RiskLevel
    let reasonCodes: [ReasonCode]
    let context: CrisisContext
    let falsePositiveFilters: [String]  // Phrases that reduced the score
    let timestamp: Date
    
    enum RiskLevel: String, Codable {
        case none = "none"           // 0.0 - 0.2
        case low = "low"             // 0.2 - 0.4
        case moderate = "moderate"   // 0.4 - 0.6
        case high = "high"           // 0.6 - 0.8
        case critical = "critical"   // 0.8 - 1.0
        
        var interventionType: InterventionType {
            switch self {
            case .none: return .none
            case .low: return .subtleLink
            case .moderate: return .supportCard
            case .high: return .supportCard
            case .critical: return .fullIntervention
            }
        }
    }
    
    enum ReasonCode: String, Codable {
        case ideation          // Thoughts of suicide
        case plan              // Specific plan mentioned
        case means             // Access to means (pills, weapon, etc.)
        case timeframe         // Specific time mentioned
        case goodbyeLanguage   // Farewell messages
        case hopelessness      // Extreme hopelessness
        case isolation         // Feeling alone/burden
        case recentLoss        // Mentioned recent loss
        case substanceUse      // Mentioned substance use
        case selfHarm          // Cutting, burning, etc.
        case panicSymptoms     // Physical panic symptoms
        case flashbacks        // PTSD symptoms
        
        var displayName: String {
            switch self {
            case .ideation: return "Suicidal thoughts"
            case .plan: return "Specific plan"
            case .means: return "Access to means"
            case .timeframe: return "Immediate timeframe"
            case .goodbyeLanguage: return "Goodbye messages"
            case .hopelessness: return "Extreme hopelessness"
            case .isolation: return "Feeling isolated"
            case .recentLoss: return "Recent loss"
            case .substanceUse: return "Substance use"
            case .selfHarm: return "Self-harm"
            case .panicSymptoms: return "Panic symptoms"
            case .flashbacks: return "Trauma symptoms"
            }
        }
        
        var weight: Double {
            switch self {
            case .plan, .means, .timeframe, .goodbyeLanguage: return 0.3
            case .ideation, .hopelessness: return 0.2
            case .selfHarm, .isolation: return 0.15
            default: return 0.1
            }
        }
    }
    
    enum CrisisContext: String, Codable {
        case post
        case comment
        case dm
        case prayerRequest
        case churchNotes
    }
    
    enum InterventionType {
        case none
        case subtleLink      // Small "Need support?" link
        case supportCard     // Full support card
        case fullIntervention // Support card + trusted circle option
    }
}

// MARK: - Trusted Circle

/// User's trusted contacts who can be notified in crisis
struct TrustedCircle: Codable {
    let userId: String
    var contacts: [TrustedContact]
    var escalationRule: EscalationRule
    var isEnabled: Bool
    let createdAt: Date
    var updatedAt: Date
    
    struct TrustedContact: Codable, Identifiable {
        let id: String
        let userId: String?  // If AMEN user
        let name: String
        let phoneNumber: String?
        let email: String?
        let relationship: String  // "Friend", "Family", "Counselor", etc.
        let addedAt: Date
        let isVerified: Bool
    }
    
    enum EscalationRule: String, Codable {
        case askFirst = "ask_first"  // Always ask user first (default)
        case autoHigh = "auto_high"  // Auto-notify if high risk + no response after 10 min
        case autoCritical = "auto_critical"  // Auto-notify only if critical risk
        case manual = "manual"  // Never auto-notify
        
        var displayName: String {
            switch self {
            case .askFirst: return "Ask me first"
            case .autoHigh: return "Auto-notify if high risk (10 min delay)"
            case .autoCritical: return "Auto-notify only if critical"
            case .manual: return "Manual only (never auto-notify)"
            }
        }
        
        var description: String {
            switch self {
            case .askFirst:
                return "AMEN will ask you if you want to notify someone. You're in control."
            case .autoHigh:
                return "If AMEN detects high risk and you don't respond within 10 minutes, your trusted circle will be notified."
            case .autoCritical:
                return "Only in critical situations will your trusted circle be notified automatically."
            case .manual:
                return "You'll always have to manually notify someone. No automatic alerts."
            }
        }
    }
}

// MARK: - Crisis Alert Log

/// Tracks crisis alerts sent to trusted circle
struct CrisisAlertLog: Codable {
    let id: String
    let userId: String
    let triggeredAt: Date
    let riskLevel: CrisisRiskAssessment.RiskLevel
    let contentContext: CrisisRiskAssessment.CrisisContext
    let notifiedContacts: [String]  // Contact IDs
    let userConsented: Bool  // True if user clicked "Yes, notify"
    let autoTriggered: Bool  // True if escalation rule triggered
    let responseTime: TimeInterval?  // How long until user/contact responded
    let outcome: AlertOutcome?
    
    enum AlertOutcome: String, Codable {
        case userSafe = "user_safe"
        case contactReached = "contact_reached"
        case emergencyServices = "emergency_services"
        case noResponse = "no_response"
    }
}

// MARK: - Safe Conversation Mode

/// Settings for protecting vulnerable users in DMs/comments
struct SafeConversationSettings: Codable {
    let userId: String
    var isEnabled: Bool
    var mode: SafeMode
    var trustedUserIds: Set<String>  // Messages from these users always go through
    var enableKindnessFilter: Bool
    var enableSlowMode: Bool
    var showSupportiveReplySuggestions: Bool
    var autoEnabledUntil: Date?  // If system auto-enabled, when does it expire
    let enabledAt: Date
    var updatedAt: Date
    
    enum SafeMode: String, Codable {
        case off = "off"
        case requestsOnly = "requests_only"  // Non-trusted go to requests
        case filtered = "filtered"           // Kindness filter + requests
        case lockdown = "lockdown"           // Only trusted contacts can message
        
        var displayName: String {
            switch self {
            case .off: return "Off"
            case .requestsOnly: return "Requests Only"
            case .filtered: return "Filtered"
            case .lockdown: return "Trusted Only"
            }
        }
        
        var description: String {
            switch self {
            case .off:
                return "Anyone can message you normally."
            case .requestsOnly:
                return "Messages from non-trusted accounts go to Message Requests (no notifications)."
            case .filtered:
                return "Harmful messages are filtered out, others go to Requests."
            case .lockdown:
                return "Only your trusted contacts can message you directly."
            }
        }
    }
}

// MARK: - Conversation Heat Score

/// Tracks conversation escalation to apply protective measures
struct ConversationHeatScore: Codable {
    let conversationId: String
    var score: Double  // 0.0 (calm) to 1.0 (hostile)
    var recentMessages: [MessageHeat]
    var slowModeEnabled: Bool
    var participantWarnings: [String: Int]  // userId: warning count
    let calculatedAt: Date
    
    struct MessageHeat: Codable {
        let messageId: String
        let senderId: String
        let timestamp: Date
        let toxicityScore: Double
        let flags: [ToxicityFlag]
    }
    
    enum ToxicityFlag: String, Codable {
        case insult
        case threat
        case profanity
        case sexualHarassment
        case spam
        case escalation  // Conversation getting heated
    }
    
    var shouldEnableSlowMode: Bool {
        score > 0.6
    }
    
    var shouldSuggestSupportiveReplies: Bool {
        score > 0.3
    }
}

// MARK: - Grounding Exercise

/// 60-second grounding exercises for crisis moments
struct GroundingExercise: Identifiable, Codable {
    let id: String
    let name: String
    let duration: Int  // seconds
    let type: ExerciseType
    let steps: [String]
    let audioURL: String?
    
    enum ExerciseType: String, Codable {
        case breathing = "breathing"
        case fiveSenses = "five_senses"
        case bodyScanning = "body_scanning"
        case countingObjects = "counting_objects"
        
        var icon: String {
            switch self {
            case .breathing: return "wind"
            case .fiveSenses: return "hand.raised.fill"
            case .bodyScanning: return "figure.walk"
            case .countingObjects: return "eye.fill"
            }
        }
    }
    
    static let exercises: [GroundingExercise] = [
        GroundingExercise(
            id: "54321",
            name: "5-4-3-2-1 Technique",
            duration: 60,
            type: .fiveSenses,
            steps: [
                "Name 5 things you can see around you",
                "Name 4 things you can touch",
                "Name 3 things you can hear",
                "Name 2 things you can smell",
                "Name 1 thing you can taste"
            ],
            audioURL: nil
        ),
        GroundingExercise(
            id: "box-breathing",
            name: "Box Breathing",
            duration: 60,
            type: .breathing,
            steps: [
                "Breathe in for 4 seconds",
                "Hold for 4 seconds",
                "Breathe out for 4 seconds",
                "Hold for 4 seconds",
                "Repeat 3-4 times"
            ],
            audioURL: nil
        ),
        GroundingExercise(
            id: "body-scan",
            name: "Body Scan",
            duration: 90,
            type: .bodyScanning,
            steps: [
                "Feel your feet on the ground",
                "Notice your legs and hips",
                "Feel your back against the chair",
                "Relax your shoulders",
                "Soften your jaw and face"
            ],
            audioURL: nil
        )
    ]
}

// MARK: - User Preferences

/// User preferences for crisis support features
struct CrisisSupportPreferences: Codable {
    let userId: String
    var enableCrisisDetection: Bool
    var showSubtleSupport: Bool  // Show "Need support?" links
    var dontShowAgainUntil: Date?  // User dismissed support card
    var hasSeenGroundingExercises: Bool
    var preferredGroundingExercise: String?
    var optedIntoTrustedCircle: Bool
    let createdAt: Date
    var updatedAt: Date
    
    static func defaultPreferences(userId: String) -> CrisisSupportPreferences {
        CrisisSupportPreferences(
            userId: userId,
            enableCrisisDetection: true,
            showSubtleSupport: true,
            dontShowAgainUntil: nil,
            hasSeenGroundingExercises: false,
            preferredGroundingExercise: nil,
            optedIntoTrustedCircle: false,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
