// BereanScriptureEngine.swift
// AMENAPP
//
// Scripture Enrichment Engine:
//   1. Detect scripture references in any text (regex + Claude fallback)
//   2. Fetch verse text via BibleService / ClaudeService (cached)
//   3. Generate cross-references + word study (Claude)
//   4. Returns enriched ScriptureInsight objects
//
// Entry points:
//   BereanScriptureEngine.shared.enrich(text:) async -> [ScriptureInsight]
//   BereanScriptureEngine.shared.wordStudy(ref:word:) async -> WordStudy?
//   BereanScriptureEngine.shared.crossRefs(for:) async -> [String]

import Foundation
import SwiftUI
import Combine

// MARK: - Models

struct ScriptureInsight: Identifiable {
    let id = UUID()
    let reference: String       // e.g. "John 3:16"
    let verseText: String       // full verse text
    let crossRefs: [String]     // related references
    let wordStudy: WordStudy?   // optional deep word study
}

struct WordStudy: Identifiable {
    let id = UUID()
    let word: String
    let original: String        // Greek/Hebrew term
    let meaning: String
    let usageCount: Int         // occurrences in Bible (approximate)
    let relatedVerses: [String]
}

// MARK: - BereanScriptureEngine

@MainActor
final class BereanScriptureEngine: ObservableObject {

    static let shared = BereanScriptureEngine()

    @Published var isEnriching = false
    @Published var insights: [ScriptureInsight] = []

    // Simple in-memory cache: ref → insight
    private var insightCache: [String: ScriptureInsight] = [:]
    private var verseCache: [String: String] = [:]

    // Canonical Bible book names for regex anchor
    private static let bookNames: String = {
        let books = [
            "Genesis","Exodus","Leviticus","Numbers","Deuteronomy",
            "Joshua","Judges","Ruth",
            "1 Samuel","2 Samuel","1 Kings","2 Kings",
            "1 Chronicles","2 Chronicles","Ezra","Nehemiah","Esther",
            "Job","Psalms?","Proverbs","Ecclesiastes",
            "Song of Solomon","Song of Songs",
            "Isaiah","Jeremiah","Lamentations","Ezekiel","Daniel",
            "Hosea","Joel","Amos","Obadiah","Jonah","Micah",
            "Nahum","Habakkuk","Zephaniah","Haggai","Zechariah","Malachi",
            "Matthew","Mark","Luke","John","Acts",
            "Romans","1 Corinthians","2 Corinthians","Galatians","Ephesians",
            "Philippians","Colossians","1 Thessalonians","2 Thessalonians",
            "1 Timothy","2 Timothy","Titus","Philemon",
            "Hebrews","James",
            "1 Peter","2 Peter","1 John","2 John","3 John","Jude","Revelation",
            // Common abbreviations
            "Gen","Ex","Lev","Num","Deut","Josh","Judg",
            "1Sam","2Sam","1Kgs","2Kgs","1Chr","2Chr",
            "Neh","Est","Ps","Prov","Eccl","Isa","Jer","Lam","Ezek","Dan",
            "Matt","Mk","Lk","Jn","Rom","1Cor","2Cor","Gal","Eph",
            "Phil","Col","1Thess","2Thess","1Tim","2Tim","Tit","Phlm",
            "Heb","Jas","1Pet","2Pet","Rev",
        ]
        return books.joined(separator: "|")
    }()

    // MARK: - Public API

    /// Detect references in text and enrich each with verse text + cross-refs.
    func enrich(text: String) async -> [ScriptureInsight] {
        let refs = detectReferences(in: text)
        guard !refs.isEmpty else { return [] }

        isEnriching = true
        defer { isEnriching = false }

        var results: [ScriptureInsight] = []
        for ref in refs {
            if let cached = insightCache[ref] {
                results.append(cached)
                continue
            }
            if let insight = await buildInsight(for: ref) {
                insightCache[ref] = insight
                results.append(insight)
            }
        }
        insights = results
        return results
    }

    /// Generate a word study for a specific word in a reference.
    func wordStudy(ref: String, word: String) async -> WordStudy? {
        let prompt = """
        Bible reference: \(ref)
        Word: "\(word)"

        Provide a concise word study. Return JSON only:
        {
          "word": "\(word)",
          "original": "Greek or Hebrew term",
          "meaning": "definition and theological significance (max 3 sentences)",
          "usageCount": approximate number of occurrences in the Bible (integer),
          "relatedVerses": ["verse ref 1", "verse ref 2", "verse ref 3"]
        }
        JSON only, no markdown.
        """
        guard let result = try? await ClaudeService.shared.sendMessageSync(prompt, mode: .scholar),
              let data = cleanJSON(result).data(using: .utf8),
              let json = try? JSONDecoder().decode(WordStudyJSON.self, from: data) else {
            return nil
        }
        return WordStudy(
            word: json.word,
            original: json.original,
            meaning: json.meaning,
            usageCount: json.usageCount,
            relatedVerses: json.relatedVerses
        )
    }

    /// Return cross-reference verses for a given reference.
    func crossRefs(for ref: String) async -> [String] {
        let prompt = """
        Bible reference: \(ref)
        List 5 cross-reference verses that share theme, language, or theological content.
        Return JSON only: { "crossRefs": ["Book Ch:V", ...] }
        JSON only, no markdown.
        """
        guard let result = try? await ClaudeService.shared.sendMessageSync(prompt, mode: .scholar),
              let data = cleanJSON(result).data(using: .utf8),
              let json = try? JSONDecoder().decode(CrossRefJSON.self, from: data) else {
            return []
        }
        return json.crossRefs
    }

    // MARK: - Reference Detection

    func detectReferences(in text: String) -> [String] {
        // Pattern: BookName space+ chapter:verse(-verse)?
        // Handles "John 3:16", "1 Cor 13:4-7", "Ps 23:1"
        let pattern = #"(?:(?:1|2|3)\s)?(?:[A-Z][a-z]+(?:\s[A-Z][a-z]+)?)\s+\d+:\d+(?:-\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        let refs = matches.compactMap { match -> String? in
            guard let r = Range(match.range, in: text) else { return nil }
            return String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Deduplicate while preserving order
        var seen = Set<String>()
        return refs.filter { seen.insert($0).inserted }
    }

    // MARK: - Internal

    private func buildInsight(for ref: String) async -> ScriptureInsight? {
        async let verseText = fetchVerseText(ref)
        async let xrefs = crossRefs(for: ref)
        let (text, refs) = await (verseText, xrefs)
        return ScriptureInsight(
            reference: ref,
            verseText: text,
            crossRefs: refs,
            wordStudy: nil
        )
    }

    private func fetchVerseText(_ ref: String) async -> String {
        if let cached = verseCache[ref] { return cached }
        let prompt = """
        Bible reference: \(ref)
        Return the ESV text of this verse(s). No attribution, no explanation.
        Just the verse text, formatted with the reference first:
        "\(ref) — [verse text here]"
        """
        let result = (try? await ClaudeService.shared.sendMessageSync(prompt, mode: .scholar)) ?? ""
        let clean = result.trimmingCharacters(in: .whitespacesAndNewlines)
        verseCache[ref] = clean
        return clean
    }

    private func cleanJSON(_ text: String) -> String {
        text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```",     with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Codable helpers

private struct WordStudyJSON: Codable {
    var word: String
    var original: String
    var meaning: String
    var usageCount: Int
    var relatedVerses: [String]

    private enum CodingKeys: String, CodingKey {
        case word, original, meaning, usageCount, relatedVerses
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        word         = (try? c.decode(String.self,   forKey: .word))         ?? ""
        original     = (try? c.decode(String.self,   forKey: .original))     ?? ""
        meaning      = (try? c.decode(String.self,   forKey: .meaning))      ?? ""
        usageCount   = (try? c.decode(Int.self,      forKey: .usageCount))   ?? 0
        relatedVerses = (try? c.decode([String].self, forKey: .relatedVerses)) ?? []
    }
}

private struct CrossRefJSON: Codable {
    var crossRefs: [String]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        crossRefs = (try? c.decode([String].self, forKey: .crossRefs)) ?? []
    }
    private enum CodingKeys: String, CodingKey { case crossRefs }
}

// MARK: - ScriptureEnrichmentCard (inline preview in ChurchNotesEditor)

struct ScriptureEnrichmentCard:

    View {
    let insight: ScriptureInsight
    @State private var expanded = false

    var body: some View {
        
        
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.purple)
                    Text(insight.reference)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.purple)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    // Verse text
                    if !insight.verseText.isEmpty {
                        Text(insight.verseText)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(.label))
                            .italic()
                            .padding(.horizontal, 12)
                    }

                    // Cross-refs
                    if !insight.crossRefs.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Cross-References")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color(.tertiaryLabel))
                                .textCase(.uppercase)
                                .padding(.horizontal, 12)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(insight.crossRefs, id: \.self) { ref in
                                        Text(ref)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.purple)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.purple.opacity(0.08), in: Capsule())
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.purple.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.purple.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - ScriptureEnrichmentStrip (shows multiple cards stacked)

struct ScriptureEnrichmentStrip: View {
    let insights: [ScriptureInsight]

    var body: some View {
        if !insights.isEmpty {
            VStack(spacing: 6) {
                HStack {
                    Text("Scripture Insights")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .textCase(.uppercase)
                    Spacer()
                }
                ForEach(insights) { insight in
                    ScriptureEnrichmentCard(insight: insight)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
