import Foundation

enum BiblicalAlignmentStatus: String, Codable, Equatable, CaseIterable {
    case aligned
    case contextNeeded = "context_needed"
    case needsDiscernment = "needs_discernment"
    case blocked
    case humanReview = "human_review"
}

enum BiblicalAlignmentSuggestedAction: String, Codable, Equatable {
    case allow
    case allowWithContext = "allow_with_context"
    case askUserPreference = "ask_user_preference"
    case suggestRewrite = "suggest_rewrite"
    case holdForReview = "hold_for_review"
    case block
}

enum AlignmentLens: String, Codable, Equatable, CaseIterable, Identifiable {
    case balancedBiblical = "balanced_biblical"
    case graceCentered = "grace_centered"
    case pastoral
    case bereanStudy = "berean_study"
    case apologetics
    case practicalWisdom = "practical_wisdom"
    case simple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balancedBiblical: return "Balanced Biblical"
        case .graceCentered: return "Grace-centered"
        case .pastoral: return "Pastoral"
        case .bereanStudy: return "Berean Study"
        case .apologetics: return "Apologetics"
        case .practicalWisdom: return "Practical Wisdom"
        case .simple: return "Simple"
        }
    }
}

enum DiscernmentMode: String, Codable, Equatable, CaseIterable, Identifiable {
    case auto
    case ask
    case off

    var id: String { rawValue }
}

enum KnowledgeIntegrityBadge: String, Codable, Equatable {
    case none
    case bereanVerified = "berean_verified"
    case contextCheck = "context_check"
    case needsDiscernment = "needs_discernment"
    case heldForReview = "held_for_review"
}

enum SpiritualProtectionCategory: String, Codable, Equatable, CaseIterable {
    case pride
    case greed
    case lust
    case envy
    case gluttony
    case wrath
    case sloth
    case pornography
    case explicitSexualContent = "explicit_sexual_content"
    case grooming
    case trafficking
    case coercion
    case sexualBlackmail = "sexual_blackmail"
    case exploitation
    case harassment
    case threats
}

struct ScriptureSuggestion: Codable, Equatable, Identifiable {
    let reference: String
    let reason: String

    var id: String { "\(reference)-\(reason)" }
}

struct BiblicalAlignmentCheckResult: Codable, Equatable, Identifiable {
    let checkId: String
    let status: BiblicalAlignmentStatus
    let alignmentScore: Double
    let confidence: Double
    let suggestedAction: BiblicalAlignmentSuggestedAction
    let userVisibleSummary: String
    let flags: [String]
    let scriptureSuggestions: [ScriptureSuggestion]
    let rewriteSuggestion: String?

    var id: String { checkId }
}

struct DiscernmentPromptOption: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let description: String
}

struct DiscernmentPromptResult: Codable, Equatable {
    let shouldPrompt: Bool
    let promptTitle: String
    let promptMessage: String
    let options: [DiscernmentPromptOption]
}

struct AlignmentProfile: Codable, Equatable {
    let userId: String
    let defaultLens: AlignmentLens
    let discernmentMode: DiscernmentMode
    let scripturePreference: String
    let correctionMemoryEnabled: Bool
    let weeklySummaryEnabled: Bool
    let simpleModeEnabled: Bool
    let explicitContentProtectionEnabled: Bool
    let exploitationProtectionEnabled: Bool
    let preferredTone: String
    let aggregateStats: AggregateStats

    struct AggregateStats: Codable, Equatable {
        let totalChecks: Int?
        let alignedCount: Int?
        let contextNeededCount: Int?
        let discernmentCount: Int?
        let correctionCount: Int?
        let blockedCount: Int?
        let humanReviewCount: Int?
        let protectionMoments: Int?
    }
}

struct WeeklyAlignmentSummary: Codable, Equatable {
    let userId: String?
    let weekStart: Date?
    let weekEnd: Date?
    let stats: Stats
    let insights: [String]
    let suggestedPractices: [String]
    let topScriptureThemes: [String]

    struct Stats: Codable, Equatable {
        let totalInteractions: Int
        let alignedPercent: Int
        let correctionsMade: Int
        let discernmentMoments: Int
        let contextChecksAdded: Int
        let blockedOrHeldItems: Int
        let spiritualProtectionMoments: Int?
    }
}

struct SharedKnowledgeIntegrityRecord: Codable, Equatable {
    let targetType: String
    let targetId: String
    let status: String
    let badge: KnowledgeIntegrityBadge
    let userVisibleSummary: String
    let scriptureContext: [ScriptureSuggestion]
}
