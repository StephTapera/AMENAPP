//
//  BereanStudyTools.swift
//  AMENAPP
//
//  Interactive, structured Bible study methods:
//  - SOAP method (Scripture → Observation → Application → Prayer)
//  - Inductive study (Observation → Interpretation → Application)
//  - Word study deep-dives (tap any word → Greek/Hebrew, usage, significance)
//  - Character studies ("Tell me about David" → comprehensive narrative)
//  - Passage comparison (compare translations side-by-side)
//

import Foundation
import SwiftUI

// MARK: - Study Method Models

/// SOAP Study (Scripture, Observation, Application, Prayer)
struct SOAPStudy: Identifiable, Codable {
    let id: String
    let passage: String            // e.g., "Romans 8:28"
    let scripture: String          // Full verse text
    let observation: String        // What does the text say? (AI-guided)
    let application: String        // How does it apply to my life? (AI-guided)
    let prayer: String             // A prayer response (AI-generated)
    let userNotes: String          // User's own notes
    let createdAt: Date
}

/// Inductive Bible Study
struct InductiveStudy: Identifiable, Codable {
    let id: String
    let passage: String
    let scripture: String
    let observation: ObservationStep
    let interpretation: InterpretationStep
    let application: ApplicationStep
    let createdAt: Date

    struct ObservationStep: Codable {
        let keyWords: [String]         // Important words in the passage
        let repeatedPhrases: [String]  // Patterns in the text
        let literaryDevices: [String]  // Metaphor, parallelism, etc.
        let context: String            // Who, what, when, where
    }

    struct InterpretationStep: Codable {
        let mainIdea: String           // Central teaching
        let historicalContext: String   // Original audience and setting
        let theologicalThemes: [String] // Key doctrinal themes
        let crossReferences: [String]  // Related passages
    }

    struct ApplicationStep: Codable {
        let personalApplication: String  // How this applies today
        let actionSteps: [String]        // Concrete things to do
        let reflectionQuestions: [String] // Questions to ponder
    }
}

/// Character Study
struct CharacterStudy: Identifiable, Codable {
    let id: String
    let character: String          // e.g., "David", "Ruth", "Paul"
    let overview: String           // Brief biography
    let timeline: [TimelineEvent]
    let keyPassages: [String]      // Verse references
    let characterTraits: [CharacterTrait]
    let lessonsLearned: [String]
    let relatedCharacters: [String]
    let createdAt: Date

    struct TimelineEvent: Codable, Identifiable {
        let id: String
        let event: String
        let passage: String
        let significance: String
    }

    struct CharacterTrait: Codable, Identifiable {
        let id: String
        let trait: String          // e.g., "Courageous", "Faithful"
        let evidence: String       // Scripture showing this trait
        let passage: String        // Reference
    }
}

/// Word Study Result
struct WordStudyResult: Identifiable {
    let id: String
    let word: String
    let originalLanguage: String   // Greek or Hebrew word
    let transliteration: String
    let pronunciation: String
    let strongsNumber: String
    let definition: String
    let fullDefinition: String
    let usageInBible: Int          // Number of occurrences
    let notableUsages: [NotableUsage]
    let relatedWords: [RelatedWord]
    let theologicalSignificance: String

    struct NotableUsage: Identifiable {
        let id: String
        let reference: String
        let context: String
    }

    struct RelatedWord: Identifiable {
        let id: String
        let word: String
        let relationship: String   // e.g., "synonym", "antonym", "root"
    }
}

/// Passage Comparison
struct PassageComparison: Identifiable {
    let id: String
    let reference: String
    let translations: [TranslationEntry]
    let keyDifferences: [String]
    let insight: String

    struct TranslationEntry: Identifiable {
        let id: String
        let version: String        // e.g., "ESV", "NIV"
        let text: String
    }
}

// MARK: - Study Tools Service

@MainActor
final class BereanStudyTools: ObservableObject {
    static let shared = BereanStudyTools()

    @Published var isProcessing = false
    @Published var currentStep: String = ""

    private let claude = ClaudeService.shared
    private let youVersion = YouVersionBibleService.shared
    private let crossRefs = BereanCrossReferences.shared

    private init() {}

    // MARK: - SOAP Study

    /// Generate a guided SOAP study for a passage
    func generateSOAPStudy(passage: String) async throws -> SOAPStudy {
        isProcessing = true
        currentStep = "Fetching scripture..."
        defer { isProcessing = false; currentStep = "" }

        // Fetch the verse
        let scripture: ScripturePassage
        do {
            scripture = try await youVersion.fetchVerse(reference: passage)
        } catch {
            throw BereanStudyError.verseNotFound(passage)
        }

        currentStep = "Generating SOAP study..."

        let prompt = """
        Generate a SOAP Bible study for this passage. Output strict JSON only.

        Passage: \(passage)
        Text: "\(scripture.text)"

        Schema:
        {
          "observation": "string (2-3 sentences: What does the text say? Key facts, words, context.)",
          "application": "string (2-3 sentences: How does this apply to daily life today? Be specific and practical.)",
          "prayer": "string (3-4 sentences: A heartfelt prayer response to this passage. First person, sincere.)"
        }
        """

        let response = try await claude.sendMessageSync(prompt, mode: .scholar)
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        struct SOAPDTO: Decodable {
            let observation: String
            let application: String
            let prayer: String
        }

        guard let data = cleaned.data(using: .utf8),
              let dto = try? JSONDecoder().decode(SOAPDTO.self, from: data) else {
            throw BereanStudyError.parsingFailed
        }

        return SOAPStudy(
            id: UUID().uuidString,
            passage: passage,
            scripture: scripture.text,
            observation: dto.observation,
            application: dto.application,
            prayer: dto.prayer,
            userNotes: "",
            createdAt: Date()
        )
    }

    // MARK: - Inductive Study

    /// Generate a guided inductive Bible study
    func generateInductiveStudy(passage: String) async throws -> InductiveStudy {
        isProcessing = true
        currentStep = "Analyzing passage..."
        defer { isProcessing = false; currentStep = "" }

        let scripture: ScripturePassage
        do {
            scripture = try await youVersion.fetchVerse(reference: passage)
        } catch {
            throw BereanStudyError.verseNotFound(passage)
        }

        // Get cross-references for richer analysis
        let crossReferences = await crossRefs.getCrossReferences(for: passage)
        let crossRefList = crossReferences.prefix(5).map { $0.targetVerse }.joined(separator: ", ")

        currentStep = "Building inductive study..."

        let prompt = """
        Generate a comprehensive inductive Bible study. Output strict JSON only.

        Passage: \(passage)
        Text: "\(scripture.text)"
        Cross-references: \(crossRefList)

        Schema:
        {
          "observation": {
            "keyWords": ["string (3-5 important words in the passage)"],
            "repeatedPhrases": ["string (patterns or repeated ideas)"],
            "literaryDevices": ["string (metaphor, parallelism, etc.)"],
            "context": "string (who is speaking, to whom, when, where)"
          },
          "interpretation": {
            "mainIdea": "string (central teaching in 1-2 sentences)",
            "historicalContext": "string (original audience, cultural setting)",
            "theologicalThemes": ["string (2-3 key doctrinal themes)"],
            "crossReferences": ["string (2-3 related passages with brief connection)"]
          },
          "application": {
            "personalApplication": "string (how this applies to believers today)",
            "actionSteps": ["string (2-3 concrete things to do this week)"],
            "reflectionQuestions": ["string (2-3 questions to ponder)"]
          }
        }
        """

        let response = try await claude.sendMessageSync(prompt, mode: .scholar)
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw BereanStudyError.parsingFailed
        }

        struct InductiveDTO: Decodable {
            let observation: InductiveStudy.ObservationStep
            let interpretation: InductiveStudy.InterpretationStep
            let application: InductiveStudy.ApplicationStep
        }

        let dto = try JSONDecoder().decode(InductiveDTO.self, from: data)

        return InductiveStudy(
            id: UUID().uuidString,
            passage: passage,
            scripture: scripture.text,
            observation: dto.observation,
            interpretation: dto.interpretation,
            application: dto.application,
            createdAt: Date()
        )
    }

    // MARK: - Character Study

    /// Generate a comprehensive character study
    func generateCharacterStudy(character: String) async throws -> CharacterStudy {
        isProcessing = true
        currentStep = "Researching \(character)..."
        defer { isProcessing = false; currentStep = "" }

        let prompt = """
        Generate a comprehensive Bible character study. Output strict JSON only.

        Character: \(character)

        Schema:
        {
          "overview": "string (3-4 sentence biography)",
          "timeline": [
            {"event": "string", "passage": "string (verse reference)", "significance": "string (1 sentence)"}
          ],
          "keyPassages": ["string (5-8 key verse references)"],
          "characterTraits": [
            {"trait": "string", "evidence": "string (1 sentence)", "passage": "string (reference)"}
          ],
          "lessonsLearned": ["string (3-4 practical lessons from this person's life)"],
          "relatedCharacters": ["string (2-3 other biblical figures connected to them)"]
        }
        Provide 4-6 timeline events and 3-5 character traits.
        """

        let response = try await claude.sendMessageSync(prompt, mode: .scholar)
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw BereanStudyError.parsingFailed
        }

        struct CharacterDTO: Decodable {
            let overview: String
            let timeline: [TimelineDTO]
            let keyPassages: [String]
            let characterTraits: [TraitDTO]
            let lessonsLearned: [String]
            let relatedCharacters: [String]

            struct TimelineDTO: Decodable {
                let event: String
                let passage: String
                let significance: String
            }

            struct TraitDTO: Decodable {
                let trait: String
                let evidence: String
                let passage: String
            }
        }

        let dto = try JSONDecoder().decode(CharacterDTO.self, from: data)

        return CharacterStudy(
            id: UUID().uuidString,
            character: character,
            overview: dto.overview,
            timeline: dto.timeline.map { t in
                CharacterStudy.TimelineEvent(
                    id: UUID().uuidString,
                    event: t.event,
                    passage: t.passage,
                    significance: t.significance
                )
            },
            keyPassages: dto.keyPassages,
            characterTraits: dto.characterTraits.map { t in
                CharacterStudy.CharacterTrait(
                    id: UUID().uuidString,
                    trait: t.trait,
                    evidence: t.evidence,
                    passage: t.passage
                )
            },
            lessonsLearned: dto.lessonsLearned,
            relatedCharacters: dto.relatedCharacters,
            createdAt: Date()
        )
    }

    // MARK: - Word Study

    /// Deep-dive into a specific word's original language meaning
    func generateWordStudy(word: String, verseContext: String? = nil) async throws -> WordStudyResult {
        isProcessing = true
        currentStep = "Studying '\(word)'..."
        defer { isProcessing = false; currentStep = "" }

        // Check if we have a Strong's entry in Firestore first
        let existingStudy = await crossRefs.lookupWord(word)

        let contextClause = verseContext.map { " as used in \($0)" } ?? ""

        let prompt = """
        Generate a word study for the biblical word "\(word)"\(contextClause). Output strict JSON only.

        \(existingStudy.map { "Known Strong's data: \($0.strongsNumber) — \($0.originalWord) (\($0.language.rawValue))" } ?? "")

        Schema:
        {
          "originalLanguage": "string (the Greek or Hebrew word)",
          "transliteration": "string (romanized pronunciation)",
          "pronunciation": "string (phonetic guide)",
          "strongsNumber": "string (e.g., G26 or H157)",
          "definition": "string (1 sentence)",
          "fullDefinition": "string (2-3 sentences with nuance)",
          "usageInBible": 0,
          "notableUsages": [
            {"reference": "string", "context": "string (how the word is used here)"}
          ],
          "relatedWords": [
            {"word": "string", "relationship": "string (synonym, antonym, root)"}
          ],
          "theologicalSignificance": "string (2-3 sentences on why this word matters theologically)"
        }
        Provide 3-4 notable usages and 2-3 related words. Be accurate about Strong's numbers.
        """

        let response = try await claude.sendMessageSync(prompt, mode: .scholar)
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw BereanStudyError.parsingFailed
        }

        struct WordDTO: Decodable {
            let originalLanguage: String
            let transliteration: String
            let pronunciation: String
            let strongsNumber: String
            let definition: String
            let fullDefinition: String
            let usageInBible: Int
            let notableUsages: [NotableDTO]
            let relatedWords: [RelatedDTO]
            let theologicalSignificance: String

            struct NotableDTO: Decodable {
                let reference: String
                let context: String
            }

            struct RelatedDTO: Decodable {
                let word: String
                let relationship: String
            }
        }

        let dto = try JSONDecoder().decode(WordDTO.self, from: data)

        return WordStudyResult(
            id: UUID().uuidString,
            word: word,
            originalLanguage: dto.originalLanguage,
            transliteration: dto.transliteration,
            pronunciation: dto.pronunciation,
            strongsNumber: dto.strongsNumber,
            definition: dto.definition,
            fullDefinition: dto.fullDefinition,
            usageInBible: dto.usageInBible,
            notableUsages: dto.notableUsages.map { u in
                WordStudyResult.NotableUsage(
                    id: UUID().uuidString,
                    reference: u.reference,
                    context: u.context
                )
            },
            relatedWords: dto.relatedWords.map { r in
                WordStudyResult.RelatedWord(
                    id: UUID().uuidString,
                    word: r.word,
                    relationship: r.relationship
                )
            },
            theologicalSignificance: dto.theologicalSignificance
        )
    }

    // MARK: - Passage Comparison

    /// Compare a passage across multiple Bible translations
    func compareTranslations(reference: String) async throws -> PassageComparison {
        isProcessing = true
        currentStep = "Fetching translations..."
        defer { isProcessing = false; currentStep = "" }

        let versions: [ScripturePassage.BibleVersion] = [.esv, .niv, .kjv, .nlt, .nasb]
        var translations: [PassageComparison.TranslationEntry] = []

        for version in versions {
            do {
                let passage = try await youVersion.fetchVerse(reference: reference, version: version)
                translations.append(PassageComparison.TranslationEntry(
                    id: UUID().uuidString,
                    version: version.rawValue,
                    text: passage.text
                ))
            } catch {
                // Skip failed translations
                continue
            }
        }

        guard translations.count >= 2 else {
            throw BereanStudyError.insufficientTranslations
        }

        currentStep = "Analyzing differences..."

        // Ask AI to highlight key differences
        let translationTexts = translations.map { "\($0.version): \"\($0.text)\"" }.joined(separator: "\n")

        let prompt = """
        Compare these Bible translations of \(reference). Output strict JSON only.

        \(translationTexts)

        Schema:
        {
          "keyDifferences": ["string (2-3 notable translation differences and why they matter)"],
          "insight": "string (2-3 sentences: what does comparing these translations reveal about the passage's meaning?)"
        }
        """

        let response = try await claude.sendMessageSync(prompt, mode: .scholar)
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        struct ComparisonDTO: Decodable {
            let keyDifferences: [String]
            let insight: String
        }

        var keyDifferences: [String] = []
        var insight = ""

        if let data = cleaned.data(using: .utf8),
           let dto = try? JSONDecoder().decode(ComparisonDTO.self, from: data) {
            keyDifferences = dto.keyDifferences
            insight = dto.insight
        }

        return PassageComparison(
            id: UUID().uuidString,
            reference: reference,
            translations: translations,
            keyDifferences: keyDifferences,
            insight: insight
        )
    }
}

// MARK: - Errors

enum BereanStudyError: LocalizedError {
    case verseNotFound(String)
    case parsingFailed
    case insufficientTranslations

    var errorDescription: String? {
        switch self {
        case .verseNotFound(let ref): return "Could not find verse: \(ref)"
        case .parsingFailed: return "Failed to parse study results. Please try again."
        case .insufficientTranslations: return "Could not fetch enough translations for comparison."
        }
    }
}
