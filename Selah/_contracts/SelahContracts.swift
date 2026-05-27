import Foundation

// MARK: - Shared Selah Contracts

let SelahContractsVersion = "2026-05-25-v1"

enum SelahSafetyTheme: String, Codable, CaseIterable, Equatable, Identifiable {
    case neutral
    case anxiety
    case grief
    case doubt
    case addiction
    case selfHarm
    case abuse
    case trafficking
    case coercion

    var id: String { rawValue }

    var blocksAIDevotionalGeneration: Bool {
        switch self {
        case .selfHarm, .abuse, .trafficking, .coercion:
            return true
        case .neutral, .anxiety, .grief, .doubt, .addiction:
            return false
        }
    }

    var blocksSharing: Bool {
        switch self {
        case .selfHarm, .abuse, .trafficking, .coercion:
            return true
        case .neutral, .anxiety, .grief, .doubt, .addiction:
            return false
        }
    }
}

enum SelahTranslation: String, Codable, CaseIterable, Equatable, Identifiable {
    case kjv = "KJV"
    case esv = "ESV"

    var id: String { rawValue }
}

struct SelahVerseReference: Codable, Hashable, Identifiable {
    let verseId: String
    let translation: SelahTranslation

    var id: String { "\(translation.rawValue):\(verseId)" }
}

struct BereanStudySheetRequest: Codable, Equatable {
    let verseId: String
    let translation: SelahTranslation
    let verseText: String
    let locale: String?
}

struct BereanStudySheetResponse: Codable, Equatable {
    let cacheKey: String
    let verseId: String
    let translation: SelahTranslation
    let layers: BereanStudySheetLayers
    let crossReferences: [String]
    let provenance: BereanStudySheetProvenance
    let generatedAt: Date
    let promptVersion: String

    // The model may receive scripture text as input, but response contracts never
    // include verse text. Clients resolve every verseId from the trusted scripture store.
}

struct BereanStudySheetLayers: Codable, Equatable {
    let text: BereanStudySheetTextLayer
    let context: BereanStudySheetContextLayer
    let interpretation: BereanStudySheetInterpretationLayer
    let application: BereanStudySheetApplicationLayer
}

struct BereanStudySheetTextLayer: Codable, Equatable {
    let observations: [String]
    let keyTerms: [BereanKeyTerm]
    let uncertaintyNotes: [String]
}

struct BereanKeyTerm: Codable, Equatable, Identifiable {
    let id: String
    let term: String
    let note: String
}

struct BereanStudySheetContextLayer: Codable, Equatable {
    let historicalNotes: [String]
    let literaryNotes: [String]
    let canonicalLinks: [String]
}

struct BereanStudySheetInterpretationLayer: Codable, Equatable {
    let summary: String
    let interpretiveOptions: [BereanInterpretiveOption]
    let denominationalPosture: String
    let uncertaintyNotes: [String]
}

struct BereanInterpretiveOption: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let summary: String
    let confidence: Double
}

struct BereanStudySheetApplicationLayer: Codable, Equatable {
    let prompts: [String]
    let cautions: [String]
    let prayerSeed: String?
}

struct BereanStudySheetProvenance: Codable, Equatable {
    let provider: String
    let model: String
    let runId: String
    let scriptureSource: String
    let scriptureLoadedByClient: Bool
    let factInterpretationSeparated: Bool
}

struct ClassifyVerseThemeRequest: Codable, Equatable {
    let verseId: String
    let translation: SelahTranslation
    let verseText: String
}

struct ClassifyVerseThemeResponse: Codable, Equatable {
    let verseId: String
    let theme: SelahSafetyTheme
    let confidence: Double
    let suggestedActions: [SelahLensActionKind]
    let promptVersion: String
}

enum SelahLensActionKind: String, Codable, CaseIterable, Equatable, Identifiable {
    case understand
    case crossReferences
    case reflect
    case pray
    case addToSession
    case more

    var id: String { rawValue }
}

struct ClassifySafetyRequest: Codable, Equatable {
    let reflectionText: String
    let verseId: String?
    let locale: String?
}

struct ClassifySafetyResponse: Codable, Equatable {
    let theme: SelahSafetyTheme
    let confidence: Double
    let canGenerateDevotional: Bool
    let canShare: Bool
    let supportPayload: SelahSupportPayload?
    let promptVersion: String
}

struct SelahSupportPayload: Codable, Equatable {
    let groundingTitle: String
    let groundingSteps: [String]
    let trustedHumanPrompt: String
    let resourceLinks: [SelahResourceLink]
}

struct SelahResourceLink: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let url: URL
    let region: String?
}

enum SelahReflectionShareScope: String, Codable, CaseIterable, Equatable, Identifiable {
    case justMe
    case accountabilityPartner
    case namedGroup

    var id: String { rawValue }
}

struct SelahReflectionDocument: Codable, Identifiable, Equatable {
    let id: String
    let ownerUid: String
    let verseId: String?
    let translation: SelahTranslation?
    let body: String
    let safetyTheme: SelahSafetyTheme
    let shareScope: SelahReflectionShareScope
    let sharedWithUid: String?
    let sharedWithGroupId: String?
    let isShareEligible: Bool
    let relationalSignals: SelahRelationalSignals
    let createdAt: Date
    let updatedAt: Date
}

struct SelahRelationalSignals: Codable, Equatable {
    let prayedByGroupCount: Int
    let lastPrayerAt: Date?
}

enum GuidedSelahStep: String, Codable, CaseIterable, Equatable, Identifiable {
    case read
    case listen
    case understand
    case reflect
    case pray
    case apply
    case complete

    var id: String { rawValue }
}

struct GuidedSelahSessionDocument: Codable, Identifiable, Equatable {
    let id: String
    let ownerUid: String
    let verseId: String
    let translation: SelahTranslation
    let currentStep: GuidedSelahStep
    let completedSteps: [GuidedSelahStep]
    let reflectionId: String?
    let cachedStudySheetKey: String?
    let recentThemes: [SelahSafetyTheme]
    let startedAt: Date
    let updatedAt: Date
    let completedAt: Date?
}

struct SelahVerseThemeTagDocument: Codable, Identifiable, Equatable {
    let id: String
    let verseId: String
    let translation: SelahTranslation
    let theme: SelahSafetyTheme
    let confidence: Double
    let promptVersion: String
    let updatedAt: Date
}

struct SelahStudySheetCacheDocument: Codable, Identifiable, Equatable {
    let id: String
    let verseId: String
    let translation: SelahTranslation
    let response: BereanStudySheetResponse
    let promptVersion: String
    let createdAt: Date
    let expiresAt: Date
}
