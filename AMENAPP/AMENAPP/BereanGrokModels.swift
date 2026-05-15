import Foundation

// MARK: - Request Classification

enum BereanRequestRisk: String, Codable {
    case low, elevated, high, pastoral, crisis
}

enum BereanRequestIntent: String, Codable {
    case scripture, doctrine, personal, pastoral, external, link, studyOutline, longPrompt, unknown
}

struct BereanRequestClassification: Equatable {
    let intent: BereanRequestIntent
    let risk: BereanRequestRisk
    let isLong: Bool
    let containsLink: Bool
    let detectedLinks: [String]
    let isSensitive: Bool
    let suggestedPills: [BereanComposerPill]
}

// MARK: - Composer Pills

enum BereanComposerPill: String, CaseIterable, Identifiable, Equatable {
    case simplifyFirst       = "Simplify first"
    case summarizeLink       = "Summarize link"
    case extractThemes       = "Extract themes"
    case externalContext     = "External context"
    case checkScripture      = "Check Scripture"
    case createStudyOutline  = "Create study outline"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .simplifyFirst:      return "text.badge.checkmark"
        case .summarizeLink:      return "link.badge.plus"
        case .extractThemes:      return "tag"
        case .externalContext:    return "globe"
        case .checkScripture:     return "book.closed"
        case .createStudyOutline: return "list.bullet.indent"
        }
    }

    var analyticsKey: String {
        switch self {
        case .simplifyFirst:      return "berean_summary_pill_tapped"
        case .summarizeLink:      return "berean_link_summary_created"
        case .extractThemes:      return "berean_link_summary_created"
        case .externalContext:    return "berean_external_context_started"
        case .checkScripture:     return "berean_scripture_check_started"
        case .createStudyOutline: return "berean_study_outline_created"
        }
    }
}

// MARK: - Provenance

enum BereanProvenanceVerdict: String {
    case passed, limited, needsCaution
}

struct BereanProvenanceRecord: Equatable {
    var helperModelUsed: Bool = false
    var externalContextUsed: Bool = false
    var scriptureChecked: Bool = false
    var safetyReviewed: Bool = false
    var bereanVerified: BereanProvenanceVerdict = .passed
    var requiresPastoralCare: Bool = false
    var sensitiveTopicDetected: Bool = false
}

// MARK: - Link Analysis (Flow 3)

struct BereanLinkAnalysis: Identifiable, Equatable {
    let id: UUID = UUID()
    let url: String
    let title: String?
    let sourceLabel: String
    let contentType: String
    let summary: String
    let keyThemes: [String]
    let claimsToCheck: [String]
    let scriptureReferencesFound: [String]
    let suggestedQuestion: String?
}

// MARK: - External Context (Flow 4)

struct BereanViewpointCluster: Identifiable, Equatable {
    let id: UUID = UUID()
    let label: String
    let summary: String
    let isControversial: Bool
}

struct BereanExternalContextResult: Identifiable, Equatable {
    let id: UUID = UUID()
    let query: String
    let publicSummary: String
    let viewpointClusters: [BereanViewpointCluster]
    let cautionNotes: [String]
    let suggestedScriptureAngles: [String]
}

// MARK: - Study Outline (Flows 1 + 2)

struct BereanStudyOutline: Identifiable, Equatable {
    let id: UUID = UUID()
    let title: String
    let mainQuestion: String
    let keyPassages: [String]
    let historicalContextNote: String?
    let reflectionQuestions: [String]
    let nextSteps: [String]
}

// MARK: - Simplified Prompt (Flow 2)

struct BereanSimplifiedPrompt: Equatable {
    let originalText: String
    let simplifiedText: String
    let keyThemes: [String]
    let studyAngles: [String]
}

// MARK: - Thinking Steps (Flow 1 loading states)

enum BereanThinkingStep: String, CaseIterable {
    case understanding = "Understanding your question…"
    case checkingScripture = "Checking Scripture context…"
    case reviewingSafety = "Reviewing safety…"
    case preparingResponse = "Preparing response…"
}

// MARK: - Grok Pipeline State

enum BereanGrokState: Equatable {
    case idle
    case classifying
    case summarizingPrompt
    case analyzingLink(url: String)
    case fetchingExternalContext
    case creatingStudyOutline
    case running
    case failed(String)
}
