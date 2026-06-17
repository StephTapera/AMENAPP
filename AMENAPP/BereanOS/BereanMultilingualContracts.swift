// BereanMultilingualContracts.swift
// AMENAPP - Berean multilingual layer Wave 0 contracts
//
// Frozen after Wave 0. Behavior belongs in later waves; this file only defines
// contracts and invariant checks shared by all Berean modes.

import Foundation

typealias LanguageCode = String

enum SupportedLanguages: String, Codable, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case portuguese = "pt"
    case german = "de"

    var id: String { rawValue }

    static func isSupported(_ code: LanguageCode) -> Bool {
        allCases.contains { $0.rawValue == code }
    }
}

enum BereanMode: String, Codable, CaseIterable, Identifiable {
    case ask
    case discern
    case build
    case guard
    case reflect

    var id: String { rawValue }
}

struct ScriptureRef: Codable, Equatable, Hashable, Identifiable {
    let book: String
    let chapter: Int
    let verseStart: Int
    let verseEnd: Int?

    var id: String {
        if let verseEnd {
            return "\(book).\(chapter).\(verseStart)-\(verseEnd)"
        }
        return "\(book).\(chapter).\(verseStart)"
    }

    init(book: String, chapter: Int, verseStart: Int, verseEnd: Int? = nil) throws {
        guard !book.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BereanMultilingualContractViolation.invalidScriptureReference
        }
        guard chapter > 0, verseStart > 0 else {
            throw BereanMultilingualContractViolation.invalidScriptureReference
        }
        if let verseEnd, verseEnd < verseStart {
            throw BereanMultilingualContractViolation.invalidScriptureReference
        }

        self.book = book
        self.chapter = chapter
        self.verseStart = verseStart
        self.verseEnd = verseEnd
    }
}

enum LicenseTag: Codable, Equatable, Hashable {
    case publicDomain
    case licensed(id: String)

    enum CodingKeys: String, CodingKey {
        case kind
        case id
    }

    enum Kind: String, Codable {
        case publicDomain
        case licensed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .publicDomain:
            self = .publicDomain
        case .licensed:
            let id = try container.decode(String.self, forKey: .id)
            guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BereanMultilingualContractViolation.licenseRequired
            }
            self = .licensed(id: id)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .publicDomain:
            try container.encode(Kind.publicDomain, forKey: .kind)
        case .licensed(let id):
            try container.encode(Kind.licensed, forKey: .kind)
            try container.encode(id, forKey: .id)
        }
    }

    var isPublicDomain: Bool {
        if case .publicDomain = self { return true }
        return false
    }
}

struct VerseText: Codable, Equatable, Identifiable {
    let ref: ScriptureRef
    let translationId: String
    let languageCode: LanguageCode
    let text: String
    let attribution: String
    let license: LicenseTag
    let source: VerseTextSource

    var id: String { "\(translationId):\(languageCode):\(ref.id)" }

    enum VerseTextSource: String, Codable {
        case scriptureTextStore
    }

    init(
        ref: ScriptureRef,
        translationId: String,
        languageCode: LanguageCode,
        text: String,
        attribution: String,
        license: LicenseTag,
        source: VerseTextSource = .scriptureTextStore
    ) throws {
        guard source == .scriptureTextStore else {
            throw BereanMultilingualContractViolation.modelGeneratedVerseTextBlocked
        }
        guard SupportedLanguages.isSupported(languageCode) else {
            throw BereanMultilingualContractViolation.unsupportedLanguage(languageCode)
        }
        guard !translationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !attribution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BereanMultilingualContractViolation.missingRequiredField
        }

        self.ref = ref
        self.translationId = translationId
        self.languageCode = languageCode
        self.text = text
        self.attribution = attribution
        self.license = license
        self.source = source
    }
}

struct TranslationManifest: Codable, Equatable, Identifiable {
    let translationId: String
    let languageCode: LanguageCode
    let license: LicenseTag
    let isPublicDomain: Bool
    let attribution: String
    let enabled: Bool
    let humanApprovedLicense: Bool

    var id: String { "\(translationId):\(languageCode)" }

    init(
        translationId: String,
        languageCode: LanguageCode,
        license: LicenseTag,
        isPublicDomain: Bool,
        attribution: String,
        enabled: Bool,
        humanApprovedLicense: Bool
    ) throws {
        guard SupportedLanguages.isSupported(languageCode) else {
            throw BereanMultilingualContractViolation.unsupportedLanguage(languageCode)
        }
        guard !translationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !attribution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BereanMultilingualContractViolation.missingRequiredField
        }
        guard isPublicDomain == license.isPublicDomain else {
            throw BereanMultilingualContractViolation.licenseMismatch
        }
        if enabled {
            guard isPublicDomain || humanApprovedLicense else {
                throw BereanMultilingualContractViolation.licenseRequired
            }
        }

        self.translationId = translationId
        self.languageCode = languageCode
        self.license = license
        self.isPublicDomain = isPublicDomain
        self.attribution = attribution
        self.enabled = enabled
        self.humanApprovedLicense = humanApprovedLicense
    }
}

struct Citation: Codable, Equatable, Identifiable {
    let sourceId: String
    let sourceType: SourceType
    let label: String
    let url: URL?

    var id: String { sourceId }

    enum SourceType: String, Codable, CaseIterable {
        case lexicon
        case crossref
        case tradition
        case history
    }

    init(sourceId: String, sourceType: SourceType, label: String, url: URL? = nil) throws {
        guard !sourceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BereanMultilingualContractViolation.unresolvedCitation
        }

        self.sourceId = sourceId
        self.sourceType = sourceType
        self.label = label
        self.url = url
    }
}

struct Explanation: Codable, Equatable {
    let sourceRefs: [ScriptureRef]
    let languageCode: LanguageCode
    let body: String
    let citations: [Citation]
    let generatedByModel: Bool

    init(sourceRefs: [ScriptureRef], languageCode: LanguageCode, body: String, citations: [Citation]) throws {
        guard SupportedLanguages.isSupported(languageCode) else {
            throw BereanMultilingualContractViolation.unsupportedLanguage(languageCode)
        }
        guard !sourceRefs.isEmpty,
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BereanMultilingualContractViolation.missingRequiredField
        }
        guard !citations.isEmpty else {
            throw BereanMultilingualContractViolation.citationRequired
        }

        self.sourceRefs = sourceRefs
        self.languageCode = languageCode
        self.body = body
        self.citations = citations
        self.generatedByModel = true
    }
}

struct MultilingualRequest: Codable, Equatable {
    let mode: BereanMode
    let inputText: String
    let inputLanguage: LanguageCode
    let targetLanguage: LanguageCode
    let refs: [ScriptureRef]?

    init(
        mode: BereanMode,
        inputText: String,
        inputLanguage: LanguageCode,
        targetLanguage: LanguageCode,
        refs: [ScriptureRef]? = nil
    ) throws {
        guard SupportedLanguages.isSupported(inputLanguage) else {
            throw BereanMultilingualContractViolation.unsupportedLanguage(inputLanguage)
        }
        guard SupportedLanguages.isSupported(targetLanguage) else {
            throw BereanMultilingualContractViolation.unsupportedLanguage(targetLanguage)
        }
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BereanMultilingualContractViolation.missingRequiredField
        }

        self.mode = mode
        self.inputText = inputText
        self.inputLanguage = inputLanguage
        self.targetLanguage = targetLanguage
        self.refs = refs
    }
}

struct ModerationVerdict: Codable, Equatable {
    let passed: Bool
    let capabilitiesTriggered: [String]
    let languageDetected: LanguageCode
    let coverageVerified: Bool
    let reason: String?

    init(
        passed: Bool,
        capabilitiesTriggered: [String],
        languageDetected: LanguageCode,
        coverageVerified: Bool,
        reason: String? = nil
    ) throws {
        guard SupportedLanguages.isSupported(languageDetected) else {
            throw BereanMultilingualContractViolation.unsupportedLanguage(languageDetected)
        }
        if passed {
            guard coverageVerified else {
                throw BereanMultilingualContractViolation.moderationCoverageRequired
            }
        }

        self.passed = passed
        self.capabilitiesTriggered = capabilitiesTriggered
        self.languageDetected = languageDetected
        self.coverageVerified = coverageVerified
        self.reason = reason
    }
}

struct MultilingualResponse: Codable, Equatable {
    let verses: [VerseText]
    let explanation: Explanation
    let moderation: ModerationVerdict

    init(verses: [VerseText], explanation: Explanation, moderation: ModerationVerdict) throws {
        guard moderation.passed else {
            throw BereanMultilingualContractViolation.moderationBlocked
        }
        guard verses.allSatisfy({ $0.source == .scriptureTextStore }) else {
            throw BereanMultilingualContractViolation.modelGeneratedVerseTextBlocked
        }

        self.verses = verses
        self.explanation = explanation
        self.moderation = moderation
    }
}

enum BereanMultilingualContractViolation: Error, Equatable, LocalizedError {
    case invalidScriptureReference
    case unsupportedLanguage(LanguageCode)
    case missingRequiredField
    case licenseRequired
    case licenseMismatch
    case modelGeneratedVerseTextBlocked
    case citationRequired
    case unresolvedCitation
    case moderationCoverageRequired
    case moderationBlocked
    case offlineLiveModelPathBlocked

    var errorDescription: String? {
        switch self {
        case .invalidScriptureReference:
            return "Scripture reference is invalid."
        case .unsupportedLanguage(let code):
            return "Unsupported language code: \(code)."
        case .missingRequiredField:
            return "A required multilingual contract field is missing."
        case .licenseRequired:
            return "Enabled translations require public-domain status or a human-approved license."
        case .licenseMismatch:
            return "Translation manifest license fields disagree."
        case .modelGeneratedVerseTextBlocked:
            return "Verse text must come only from the Scripture text store."
        case .citationRequired:
            return "Explanation claims require citations."
        case .unresolvedCitation:
            return "Citation must resolve to a real source entry."
        case .moderationCoverageRequired:
            return "Multilingual moderation coverage must be verified before passing."
        case .moderationBlocked:
            return "Multilingual moderation blocked the response."
        case .offlineLiveModelPathBlocked:
            return "Offline mode cannot contain a live model path."
        }
    }
}

enum BereanMultilingualInvariant: String, Codable, CaseIterable, Identifiable {
    case m1VerseIntegrity
    case m2LicenseGate
    case m3CitationGate
    case m4VoiceStaysOnDevice
    case m5UGCRelayModerated
    case m6OfflineIsStatic
    case m7MinorPostureInherited
    case m8FlagsOff

    var id: String { rawValue }
}
