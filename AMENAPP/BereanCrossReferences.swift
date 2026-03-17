//
//  BereanCrossReferences.swift
//  AMENAPP
//
//  Cross-references, commentary, and Greek/Hebrew word study layer.
//  Uses public domain sources:
//  - Treasury of Scripture Knowledge (572K cross-references)
//  - Strong's Concordance (Greek/Hebrew word definitions)
//  - Public domain commentaries (Matthew Henry, Gill)
//
//  Data is loaded from Firestore (populated by Cloud Function from public domain sources).
//  Cached locally for fast lookup.
//

import Foundation
import FirebaseFirestore

// MARK: - Cross Reference Models

struct CrossReference: Codable, Identifiable {
    let id: String
    let sourceVerse: String       // e.g., "John 3:16"
    let targetVerse: String       // e.g., "Romans 5:8"
    let relationship: CrossRefType
    let note: String?             // Brief explanation of the connection

    enum CrossRefType: String, Codable {
        case parallel = "parallel"            // Same event/teaching in different book
        case prophecyFulfillment = "prophecy"  // OT prophecy → NT fulfillment
        case thematic = "thematic"             // Same theme/concept
        case quotation = "quotation"           // Direct quote from another passage
        case allusion = "allusion"             // Indirect reference
        case contrast = "contrast"             // Contrasting teaching
    }
}

struct WordStudy: Codable, Identifiable {
    let id: String
    let word: String              // English word
    let strongsNumber: String     // e.g., "G26" (Greek) or "H157" (Hebrew)
    let originalWord: String      // Greek or Hebrew
    let transliteration: String   // Pronunciation guide
    let language: OriginalLanguage
    let definition: String        // Full definition
    let shortDefinition: String   // One-line definition
    let usage: String             // How the word is used in Scripture
    let occurrences: Int          // Times used in the Bible
    let relatedWords: [String]    // Related Strong's numbers

    enum OriginalLanguage: String, Codable {
        case greek = "greek"
        case hebrew = "hebrew"
    }
}

struct CommentaryEntry: Codable, Identifiable {
    let id: String
    let verse: String             // e.g., "John 3:16"
    let author: String            // e.g., "Matthew Henry"
    let source: String            // e.g., "Matthew Henry's Commentary"
    let commentary: String        // The actual commentary text
    let era: String               // e.g., "18th century"
    let tradition: String         // e.g., "Protestant"
    let isPublicDomain: Bool
}

/// Enriched verse context combining cross-refs, word studies, and commentary
struct EnrichedVerseContext {
    let verse: String
    let crossReferences: [CrossReference]
    let wordStudies: [WordStudy]
    let commentaries: [CommentaryEntry]

    /// Format for prompt injection
    var formattedForPrompt: String {
        var parts: [String] = []

        if !crossReferences.isEmpty {
            let refs = crossReferences.prefix(5).map { cr in
                "  - \(cr.targetVerse) (\(cr.relationship.rawValue))\(cr.note.map { ": \($0)" } ?? "")"
            }.joined(separator: "\n")
            parts.append("[CROSS-REFERENCES for \(verse)]\n\(refs)")
        }

        if !wordStudies.isEmpty {
            let words = wordStudies.prefix(3).map { ws in
                "  - \"\(ws.word)\" (\(ws.originalWord), \(ws.language.rawValue)) — \(ws.shortDefinition)"
            }.joined(separator: "\n")
            parts.append("[KEY WORDS]\n\(words)")
        }

        if !commentaries.isEmpty {
            let comments = commentaries.prefix(2).map { c in
                "  - \(c.author): \(c.commentary.prefix(200))..."
            }.joined(separator: "\n")
            parts.append("[COMMENTARY]\n\(comments)")
        }

        return parts.joined(separator: "\n\n")
    }
}

// MARK: - Cross References Service

@MainActor
final class BereanCrossReferences: ObservableObject {
    static let shared = BereanCrossReferences()

    @Published var isLoading = false

    private let db = Firestore.firestore()

    // Local caches
    private var crossRefCache: [String: [CrossReference]] = [:]
    private var wordStudyCache: [String: [WordStudy]] = [:]
    private var commentaryCache: [String: [CommentaryEntry]] = [:]

    private init() {}

    // MARK: - Enriched Context

    /// Get full enriched context for a verse (cross-refs + word studies + commentary)
    func getEnrichedContext(verse: String) async -> EnrichedVerseContext {
        async let crossRefs = getCrossReferences(for: verse)
        async let words = getWordStudies(for: verse)
        async let comments = getCommentary(for: verse)

        return EnrichedVerseContext(
            verse: verse,
            crossReferences: await crossRefs,
            wordStudies: await words,
            commentaries: await comments
        )
    }

    /// Get enriched context for multiple verses
    func getEnrichedContext(verses: [String]) async -> [EnrichedVerseContext] {
        await withTaskGroup(of: EnrichedVerseContext.self) { group in
            for verse in verses {
                group.addTask {
                    await self.getEnrichedContext(verse: verse)
                }
            }

            var results: [EnrichedVerseContext] = []
            for await context in group {
                results.append(context)
            }
            return results
        }
    }

    // MARK: - Cross References

    func getCrossReferences(for verse: String) async -> [CrossReference] {
        let key = verse.lowercased()

        // Check cache
        if let cached = crossRefCache[key] {
            return cached
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await db.collection("berean_cross_references")
                .whereField("sourceVerse", isEqualTo: verse)
                .limit(to: 20)
                .getDocuments()

            let refs = snapshot.documents.compactMap { doc in
                try? doc.data(as: CrossReference.self)
            }

            crossRefCache[key] = refs
            return refs
        } catch {
            print("⚠️ CrossRef: Failed to fetch for \(verse): \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Word Studies

    func getWordStudies(for verse: String) async -> [WordStudy] {
        let key = verse.lowercased()

        if let cached = wordStudyCache[key] {
            return cached
        }

        do {
            let snapshot = try await db.collection("berean_word_studies")
                .whereField("verses", arrayContains: verse)
                .limit(to: 10)
                .getDocuments()

            let studies = snapshot.documents.compactMap { doc in
                try? doc.data(as: WordStudy.self)
            }

            wordStudyCache[key] = studies
            return studies
        } catch {
            print("⚠️ WordStudy: Failed to fetch for \(verse): \(error.localizedDescription)")
            return []
        }
    }

    /// Look up a specific word's Greek/Hebrew definition
    func lookupWord(_ word: String) async -> WordStudy? {
        do {
            let snapshot = try await db.collection("berean_word_studies")
                .whereField("word", isEqualTo: word.lowercased())
                .limit(to: 1)
                .getDocuments()

            return snapshot.documents.first.flatMap { doc in
                try? doc.data(as: WordStudy.self)
            }
        } catch {
            return nil
        }
    }

    /// Look up by Strong's number
    func lookupStrongs(_ strongsNumber: String) async -> WordStudy? {
        do {
            let snapshot = try await db.collection("berean_word_studies")
                .whereField("strongsNumber", isEqualTo: strongsNumber)
                .limit(to: 1)
                .getDocuments()

            return snapshot.documents.first.flatMap { doc in
                try? doc.data(as: WordStudy.self)
            }
        } catch {
            return nil
        }
    }

    // MARK: - Commentary

    func getCommentary(for verse: String) async -> [CommentaryEntry] {
        let key = verse.lowercased()

        if let cached = commentaryCache[key] {
            return cached
        }

        do {
            let snapshot = try await db.collection("berean_commentaries")
                .whereField("verse", isEqualTo: verse)
                .whereField("isPublicDomain", isEqualTo: true)
                .limit(to: 5)
                .getDocuments()

            let entries = snapshot.documents.compactMap { doc in
                try? doc.data(as: CommentaryEntry.self)
            }

            commentaryCache[key] = entries
            return entries
        } catch {
            print("⚠️ Commentary: Failed to fetch for \(verse): \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Cache Management

    func clearCache() {
        crossRefCache.removeAll()
        wordStudyCache.removeAll()
        commentaryCache.removeAll()
    }
}
