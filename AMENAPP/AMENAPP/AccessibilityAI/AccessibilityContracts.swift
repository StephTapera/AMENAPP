//
//  AccessibilityContracts.swift
//  AMENAPP
//
//  Phase 0 — Unified contracts for the Trust Layer + Universal Accessibility Engine.
//  All downstream T1–T4 (Trust) and A1–A8 (Accessibility) modules import from here.
//  Nothing else modifies these types; they are read-only contracts.
//

import Foundation

// MARK: - T1: Provenance

/// Current provenance state of a piece of media or post.
enum ProvenanceState: String, Codable {
    case unknown
    case verified        // Server-confirmed hash + creator declaration match
    case pending         // Registration submitted, not yet confirmed
    case tampered        // Hash mismatch detected post-upload
    case unregistered    // Not in the provenance registry
    case syntheticFlagged // Synthetic-detection service flagged this content
}

/// Creator's declaration of how the content was produced.
enum ProvenanceCreatorDeclaration: String, Codable {
    case originalCapture    // Directly captured by this person
    case editedCapture      // Edited from an original they own
    case curatedRepublish   // Republished with rights
    case aiAssisted         // Human-directed, AI-assisted creation
    case aiGenerated        // Substantially AI-generated content
    case unknown
}

/// Verifiable credential attached to a media upload.
struct MediaCredential: Codable, Equatable, Identifiable {
    var id: String { mediaId }
    let mediaId: String
    let uploaderId: String
    let storageUri: String
    let originalHash: String        // SHA-256 of the raw file before any processing
    let mimeType: String
    let fileSizeBytes: Int
    let creatorDeclaration: ProvenanceCreatorDeclaration
    let sourceChain: [String]       // Ordered list of prior provenance IDs (for remixes)
    let registeredAt: Date
    var state: ProvenanceState
    var serverConfidenceScore: Double?   // Set by backend after verification (0–1)
}

// MARK: - T3: Authenticity Scoring

/// Server-derived authenticity assessment — never computed on-device.
struct AuthenticityScore: Codable, Equatable {
    let mediaId: String
    let score: Double                   // 0.0 (definitely fake) – 1.0 (definitely real)
    let label: AuthenticityScoreLabel
    let signals: [AuthenticitySignalRecord]
    let computedAt: Date
    let modelVersion: String

    var isHighConfidence: Bool { score >= 0.80 || score <= 0.20 }
}

enum AuthenticityScoreLabel: String, Codable {
    case likelyAuthentic    // score >= 0.75
    case uncertain          // 0.40 <= score < 0.75
    case likelySynthetic    // score < 0.40
}

struct AuthenticitySignalRecord: Codable, Equatable {
    let signal: String
    let weight: Double
    let description: String
}

// MARK: - T4: AI Contribution

/// What role AI played in producing a piece of content.
struct AIContribution: Codable, Equatable {
    let contentId: String
    let contentType: AIContentType
    let extent: AIContributionExtent
    let modelFamily: String?    // e.g. "Claude", "Gemini"
    let disclosedAt: Date
    let disclosedBy: String     // uid who submitted the disclosure
}

enum AIContentType: String, Codable {
    case image, video, audio, text, voiceover, profilePhoto
}

enum AIContributionExtent: String, Codable {
    case none               // Human-only
    case minorAssist        // Spell check, grammar, minor edit suggestions
    case substantialAssist  // AI drafted, human edited
    case fullyGenerated     // Primarily AI-generated
}

// MARK: - A0: Accessibility Profile

/// Stored accessibility preferences for a user.
struct AccessibilityProfile: Codable, Equatable {
    var userId: String
    var autoTranslateEnabled: Bool
    var preferredLanguage: String?          // BCP-47 locale
    var autoSimplifyEnabled: Bool
    var targetReadingLevel: ReadingLevel
    var autoCaptionsEnabled: Bool
    var highContrastPreferred: Bool
    var preferredFontSize: FontSizePreference
    var voiceNavigationEnabled: Bool
    var faithGlossaryEnabled: Bool
    var updatedAt: Date

    static var `default`: AccessibilityProfile {
        AccessibilityProfile(
            userId: "",
            autoTranslateEnabled: false,
            preferredLanguage: nil,
            autoSimplifyEnabled: false,
            targetReadingLevel: .standard,
            autoCaptionsEnabled: false,
            highContrastPreferred: false,
            preferredFontSize: .medium,
            voiceNavigationEnabled: false,
            faithGlossaryEnabled: true,
            updatedAt: Date()
        )
    }
}

enum ReadingLevel: String, Codable, CaseIterable {
    case elementary = "elementary"  // Grade 3–5
    case standard   = "standard"    // Grade 6–8
    case advanced   = "advanced"    // Grade 9+
    case scholarly  = "scholarly"   // Seminary/academic
}

enum FontSizePreference: String, Codable, CaseIterable {
    case small, medium, large, extraLarge
}

// MARK: - T4: Constitutional Constraint Violation

/// Violation record produced by GenerativePolicyGate.
struct GenerativePolicyViolation: Equatable {
    let rule: GenerativeRule
    let reason: String
    let isFatal: Bool    // True = hard block; false = warning only
}

/// The set of generative AI rules enforced client-side before any CF call.
enum GenerativeRule: String, Codable, CaseIterable {
    case noAIFaceGeneration
    case noVoiceCloning
    case noDeepfakeSermon
    case noDeepfakeTestimony
    case noDeepfakePrayer
    case noAITestimonyPosingAsHuman
    case noAIPrayerPosingAsHuman
    case noFabricatedConversations
    case noDefaultAIProfilePhoto
    case noUndisclosedAIContent

    var description: String {
        switch self {
        case .noAIFaceGeneration:
            return "AI-generated face images are not permitted."
        case .noVoiceCloning:
            return "Voice cloning of real people is not permitted."
        case .noDeepfakeSermon:
            return "AI-generated sermons attributed to real pastors are not permitted."
        case .noDeepfakeTestimony:
            return "AI-generated testimonies attributed to real people are not permitted."
        case .noDeepfakePrayer:
            return "AI-generated prayers attributed to real people are not permitted."
        case .noAITestimonyPosingAsHuman:
            return "AI-written testimonies presented as human-authored are not permitted."
        case .noAIPrayerPosingAsHuman:
            return "AI-written prayers presented as human-authored are not permitted."
        case .noFabricatedConversations:
            return "Fabricated conversations between real people are not permitted."
        case .noDefaultAIProfilePhoto:
            return "AI-generated profile photos must be explicitly disclosed."
        case .noUndisclosedAIContent:
            return "AI-generated content must be disclosed before sharing."
        }
    }
}
