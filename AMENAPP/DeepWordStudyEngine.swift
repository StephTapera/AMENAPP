// DeepWordStudyEngine.swift
// AMENAPP
//
// Deep Word Study: Highlight → Original Meaning
//
// Pipeline:
//   1. User highlights any word or phrase
//   2. Detect if English / biblical term / Greek root / Hebrew root
//   3. Map to original language (if applicable)
//   4. Definition spectrum (not just one meaning)
//   5. Usage across scripture
//
// Output layers:
//   - Plain meaning
//   - Original Greek/Hebrew meaning
//   - First biblical usage
//   - How meaning changes across contexts
//   - Related word family
//
// Entry points:
//   DeepWordStudyEngine.shared.study(word:inContext:) async -> ComprehensiveWordStudy
//   DeepWordStudyEngine.shared.compareWords(_ words:) async -> WordComparison

import Foundation
import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth

// MARK: - Models

/// Complete deep word study result
struct ComprehensiveWordStudy: Identifiable, Codable {
    let id: String
    let word: String
    let timestamp: Date

    // Language layer
    let languageOrigin: LanguageOrigin
    let originalWord: String?           // Greek/Hebrew
    let transliteration: String?
    let pronunciation: String?

    // Definition layer
    let plainMeaning: String
    let definitionSpectrum: [DefinitionEntry]
    let synonyms: [String]
    let antonyms: [String]

    // Biblical usage layer
    let firstBiblicalUsage: BiblicalUsage?
    let totalOccurrences: Int
    let contextualUsages: [BiblicalUsage]

    // Semantic evolution
    let meaningEvolution: [MeaningShift]

    // Related word family
    let relatedWords: [RelatedWord]
}

enum LanguageOrigin: String, Codable {
    case greek = "Greek"
    case hebrew = "Hebrew"
    case aramaic = "Aramaic"
    case english = "English"
    case latin = "Latin"
}

struct DefinitionEntry: Codable, Identifiable {
    var id: String { meaning }
    let meaning: String
    let nuance: String              // Subtle distinction
    let exampleVerse: String?       // Scripture reference
}

struct BiblicalUsage: Codable, Identifiable {
    var id: String { reference }
    let reference: String           // e.g. "Genesis 1:1"
    let text: String                // The verse text
    let meaningInContext: String    // What the word means HERE
    let testament: Testament
}

enum Testament: String, Codable {
    case old = "Old Testament"
    case new = "New Testament"
}

struct MeaningShift: Codable, Identifiable {
    var id: String { period }
    let period: String              // e.g. "Pentateuch", "Prophets", "Gospels", "Epistles"
    let primaryMeaning: String
    let significance: String        // Why the shift matters
}

struct RelatedWord: Codable, Identifiable {
    var id: String { word }
    let word: String
    let original: String?
    let relationship: String        // e.g. "same root", "antonym", "intensified form"
    let exampleVerse: String?
}

/// Word comparison result (e.g., agape vs phileo)
struct WordComparison: Codable {
    let words: [String]
    let distinctions: [WordDistinction]
    let summary: String
    let keyVersesForComparison: [String]
}

struct WordDistinction: Codable, Identifiable {
    var id: String { word }
    let word: String
    let original: String?
    let coreMeaning: String
    let emphasis: String
    let typicalContext: String
}

// MARK: - DeepWordStudyEngine

@MainActor
final class DeepWordStudyEngine: ObservableObject {

    static let shared = DeepWordStudyEngine()

    @Published var isStudying = false
    @Published var currentStudy: ComprehensiveWordStudy?
    @Published var recentStudies: [ComprehensiveWordStudy] = []

    private let aiService = ClaudeService.shared
    private let db = Firestore.firestore()

    // Cache: word → study
    private var studyCache: [String: ComprehensiveWordStudy] = [:]

    private init() {
        loadRecentStudies()
    }

    // MARK: - Public API

    /// Perform a comprehensive word study
    func study(word: String, inContext context: String = "") async -> ComprehensiveWordStudy? {
        let cacheKey = "\(word.lowercased())_\(context)"
        if let cached = studyCache[cacheKey] {
            currentStudy = cached
            return cached
        }

        isStudying = true
        defer { isStudying = false }

        let prompt = """
        Perform an exhaustive word study for "\(word)"\(context.isEmpty ? "" : " in the context of \(context)").

        Return as JSON:
        {
            "id": "\(UUID().uuidString)",
            "word": "\(word)",
            "timestamp": "\(ISO8601DateFormatter().string(from: Date()))",
            "languageOrigin": "Greek|Hebrew|Aramaic|English|Latin",
            "originalWord": "The original Greek/Hebrew/Aramaic term (null if purely English)",
            "transliteration": "How to write it in English letters",
            "pronunciation": "Phonetic pronunciation guide",
            "plainMeaning": "Simple, clear definition anyone can understand",
            "definitionSpectrum": [
                {"meaning": "Primary meaning", "nuance": "Subtle distinction", "exampleVerse": "John 3:16"},
                {"meaning": "Secondary meaning", "nuance": "How it differs", "exampleVerse": "Romans 5:8"}
            ],
            "synonyms": ["word1", "word2"],
            "antonyms": ["word1", "word2"],
            "firstBiblicalUsage": {
                "reference": "Genesis 1:1",
                "text": "The verse text",
                "meaningInContext": "What it means in its first appearance",
                "testament": "Old Testament"
            },
            "totalOccurrences": 150,
            "contextualUsages": [
                {"reference": "Verse ref", "text": "Verse text", "meaningInContext": "Meaning here", "testament": "Old Testament|New Testament"}
            ],
            "meaningEvolution": [
                {"period": "Pentateuch", "primaryMeaning": "Original meaning", "significance": "Why this matters"}
            ],
            "relatedWords": [
                {"word": "Related English word", "original": "Greek/Hebrew", "relationship": "same root", "exampleVerse": "Ref"}
            ]
        }

        Include 4-6 contextual usages showing different shades of meaning.
        Include 3-4 meaning evolution entries across biblical periods.
        Include 3-5 related words.
        Be scholarly but accessible. Return ONLY valid JSON.
        """

        do {
            let response = try await aiService.sendMessage(prompt)
            let cleaned = cleanJSON(response)
            let data = Data(cleaned.utf8)

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let study = try decoder.decode(ComprehensiveWordStudy.self, from: data)

            studyCache[cacheKey] = study
            currentStudy = study

            // Persist to recent studies
            recentStudies.insert(study, at: 0)
            if recentStudies.count > 50 { recentStudies.removeLast() }
            saveStudyToFirestore(study)

            return study
        } catch {
            dlog("❌ [DeepWordStudy] Failed: \(error)")
            return nil
        }
    }

    /// Compare multiple words (e.g., agape vs phileo vs eros)
    func compareWords(_ words: [String]) async -> WordComparison? {
        let wordList = words.joined(separator: ", ")
        let prompt = """
        Compare these biblical/theological words: \(wordList)

        Return as JSON:
        {
            "words": \(words),
            "distinctions": [
                {"word": "word", "original": "Greek/Hebrew", "coreMeaning": "Core meaning", "emphasis": "What it emphasizes", "typicalContext": "When this word is used"}
            ],
            "summary": "A clear summary of how these words differ and why it matters",
            "keyVersesForComparison": ["Verse refs where the distinction is most visible"]
        }

        Return ONLY valid JSON.
        """

        do {
            let response = try await aiService.sendMessage(prompt)
            let data = Data(cleanJSON(response).utf8)
            return try JSONDecoder().decode(WordComparison.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Persistence

    private func saveStudyToFirestore(_ study: ComprehensiveWordStudy) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let data: [String: Any] = [
            "word": study.word,
            "originalWord": study.originalWord ?? "",
            "plainMeaning": study.plainMeaning,
            "languageOrigin": study.languageOrigin.rawValue,
            "timestamp": Timestamp(date: study.timestamp),
            "userId": uid
        ]
        db.collection("users").document(uid)
            .collection("wordStudies").document(study.id)
            .setData(data, merge: true)
    }

    private func loadRecentStudies() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid)
            .collection("wordStudies")
            .order(by: "timestamp", descending: true)
            .limit(to: 20)
            .getDocuments { [weak self] snapshot, _ in
                // Lightweight load — full studies are fetched on-demand
                guard let docs = snapshot?.documents else { return }
                dlog("📖 [DeepWordStudy] Loaded \(docs.count) recent studies")
            }
    }

    // MARK: - Helpers

    private func cleanJSON(_ response: String) -> String {
        var s = response
        if let start = s.range(of: "{"), let end = s.range(of: "}", options: .backwards) {
            s = String(s[start.lowerBound...end.upperBound])
        }
        return s
    }
}

// MARK: - Deep Word Study View

struct DeepWordStudyView: View {
    let initialWord: String
    let context: String

    @StateObject private var engine = DeepWordStudyEngine.shared
    @State private var compareMode = false
    @State private var compareWords: [String] = []
    @State private var comparison: WordComparison?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if engine.isStudying {
                        studyingView
                    } else if let study = engine.currentStudy {
                        studyResultView(study)
                    }
                }
                .padding()
            }
            .navigationTitle("Word Study: \(initialWord)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await engine.study(word: initialWord, inContext: context)
            }
        }
    }

    private var studyingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Studying \"\(initialWord)\"...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 100)
    }

    private func studyResultView(_ study: ComprehensiveWordStudy) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(study.word.capitalized)
                        .font(.largeTitle.bold())
                    if let original = study.originalWord {
                        Text(original)
                            .font(.title2)
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                }
                if let trans = study.transliteration {
                    Text(trans)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(study.languageOrigin.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.1))
                    .clipShape(Capsule())
            }

            // Plain meaning
            Text(study.plainMeaning)
                .font(.body)

            Divider()

            // Definition spectrum
            VStack(alignment: .leading, spacing: 12) {
                Text("Definition Spectrum")
                    .font(.headline)

                ForEach(study.definitionSpectrum) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.meaning)
                            .font(.subheadline.bold())
                        Text(entry.nuance)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let verse = entry.exampleVerse {
                            Text(verse)
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            // First usage
            if let first = study.firstBiblicalUsage {
                VStack(alignment: .leading, spacing: 8) {
                    Text("First Biblical Usage")
                        .font(.headline)
                    Text(first.reference)
                        .font(.subheadline.bold())
                    Text(first.text)
                        .font(.subheadline)
                        .italic()
                    Text(first.meaningInContext)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Meaning evolution
            if !study.meaningEvolution.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("How the Meaning Evolves")
                        .font(.headline)

                    ForEach(study.meaningEvolution) { shift in
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(.blue.gradient)
                                .frame(width: 8, height: 8)
                                .padding(.top, 6)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(shift.period)
                                    .font(.subheadline.bold())
                                Text(shift.primaryMeaning)
                                    .font(.caption)
                                Text(shift.significance)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            // Contextual usages
            if !study.contextualUsages.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Usage Across Scripture")
                        .font(.headline)
                    Text("\(study.totalOccurrences) occurrences")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(study.contextualUsages) { usage in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(usage.reference)
                                .font(.subheadline.bold())
                                .foregroundStyle(.blue)
                            Text(usage.meaningInContext)
                                .font(.caption)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            // Related words
            if !study.relatedWords.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Related Words")
                        .font(.headline)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(study.relatedWords) { related in
                                VStack(spacing: 4) {
                                    Text(related.word)
                                        .font(.subheadline.bold())
                                    if let orig = related.original {
                                        Text(orig)
                                            .font(.caption2)
                                            .italic()
                                    }
                                    Text(related.relationship)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
            }
        }
    }
}
