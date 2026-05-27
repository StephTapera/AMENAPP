// AmenContentSuggestions.swift
// AMENAPP
// On-device smart content suggestions.
// Scores topics by engagement (UserDefaults) using NaturalLanguage keyword extraction.
// No server calls. No per-user cloud data.

import SwiftUI
import NaturalLanguage

// MARK: - Model

struct AmenContentSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let tag: String
    let systemImage: String
    let score: Double
}

// MARK: - Service

@MainActor
final class AmenSuggestionsService: ObservableObject {
    static let shared = AmenSuggestionsService()
    private init() { refresh() }

    @Published private(set) var suggestions: [AmenContentSuggestion] = []

    private let storageKey = "amen.suggestions.engagement.v1"
    private let tagger = NLTagger(tagSchemes: [.namedEntity, .lexicalClass])

    // MARK: Record engagement

    /// Call when the user opens/interacts with content that carries keywords.
    func recordEngagement(keywords: [String]) {
        var scores = loadScores()
        for kw in keywords.map({ $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }) where !kw.isEmpty {
            scores[kw, default: 0.0] += 1.0
        }
        saveScores(scores)
        refresh()
    }

    /// Extracts meaningful keywords from free text (scripture ref, topic, name).
    func extractKeywords(from text: String) -> [String] {
        var found: Set<String> = []

        tagger.string = text
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .namedEntity,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, range in
            if tag != nil { found.insert(String(text[range]).lowercased()) }
            return true
        }

        // Capitalize-word pass — catches "John 3:16", "Romans", "Psalms", etc.
        for word in text.components(separatedBy: .whitespacesAndNewlines) {
            let clean = word.trimmingCharacters(in: .punctuationCharacters)
            if clean.count > 3, clean.first?.isUppercase == true {
                found.insert(clean.lowercased())
            }
        }

        return Array(found)
    }

    // MARK: Dismiss

    func dismiss(suggestion: AmenContentSuggestion) {
        var scores = loadScores()
        scores[suggestion.tag] = max(0, (scores[suggestion.tag] ?? 0) - 2.0)
        saveScores(scores)
        suggestions.removeAll { $0.id == suggestion.id }
    }

    // MARK: Refresh

    func refresh() {
        let scores = loadScores()
        var built: [AmenContentSuggestion] = []

        if !scores.isEmpty {
            let sorted = scores.sorted { $0.value > $1.value }.prefix(6)
            built = sorted.compactMap { makeSuggestion(tag: $0.key, score: $0.value) }
        }

        let needed = max(0, 3 - built.count)
        if needed > 0 { built += Array(defaults().prefix(needed)) }

        suggestions = built
    }

    // MARK: Private

    private func makeSuggestion(tag: String, score: Double) -> AmenContentSuggestion? {
        let catalog: [String: (String, String, String)] = [
            "prayer":       ("Prayer Journal",      "Continue where you left off",       "text.book.pages"),
            "psalm":        ("Psalms",               "Explore the book of praise",         "music.note"),
            "psalms":       ("Psalms",               "Explore the book of praise",         "music.note"),
            "faith":        ("Faith & Trust",        "Scriptures on walking in faith",     "figure.walk"),
            "grace":        ("Grace",                "Verses on unmerited favor",           "heart.circle"),
            "worship":      ("Worship Mode",         "Berean study for worship",           "music.quarternote.3"),
            "church":       ("Church Profile",       "Your saved churches",                "building.columns"),
            "proverbs":     ("Proverbs",             "Wisdom for today",                   "lightbulb"),
            "anxiety":      ("Peace & Rest",         "Matthew 6 & Philippians 4",          "leaf"),
            "healing":      ("Healing",              "Scriptures on restoration",          "cross.case"),
            "love":         ("Love",                 "1 Corinthians 13 study",             "heart"),
            "genesis":      ("Genesis",              "In the beginning…",                  "book"),
            "exodus":       ("Exodus",               "The story of deliverance",           "book"),
            "matthew":      ("Matthew",              "The Gospel of the King",             "book"),
            "mark":         ("Mark",                 "The Gospel of action",               "book"),
            "luke":         ("Luke",                 "The Gospel of the physician",        "book"),
            "john":         ("John",                 "The Gospel of love",                 "book"),
            "romans":       ("Romans",               "The foundation of faith",            "book"),
            "ephesians":    ("Ephesians",            "Spiritual riches in Christ",         "book"),
            "philippians":  ("Philippians",          "Joy in all circumstances",           "book"),
            "hebrews":      ("Hebrews",              "Christ as high priest",              "book"),
            "james":        ("James",                "Faith without works is dead",        "book"),
            "revelation":   ("Revelation",           "The final victory",                  "book"),
            "hope":         ("Hope",                 "Romans 5 & Lamentations 3",         "sunrise"),
            "forgiveness":  ("Forgiveness",          "Matthew 18 & Psalm 103",            "arrow.counterclockwise.circle"),
            "strength":     ("Strength",             "Isaiah 40:31 and Philippians 4:13", "bolt.circle"),
        ]

        if let (title, sub, icon) = catalog[tag] {
            return AmenContentSuggestion(title: title, subtitle: sub, tag: tag, systemImage: icon, score: score)
        }
        return nil
    }

    private func defaults() -> [AmenContentSuggestion] {[
        AmenContentSuggestion(title: "Daily Verse",    subtitle: "Start your day with scripture",  tag: "verse",   systemImage: "sun.horizon",   score: 0),
        AmenContentSuggestion(title: "Prayer Journal", subtitle: "Record your thoughts",           tag: "prayer",  systemImage: "text.book.pages", score: 0),
        AmenContentSuggestion(title: "Berean Chat",    subtitle: "Ask any scripture question",     tag: "berean",  systemImage: "sparkles",       score: 0),
    ]}

    private func loadScores() -> [String: Double] {
        (UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Double]) ?? [:]
    }

    private func saveScores(_ scores: [String: Double]) {
        UserDefaults.standard.set(scores, forKey: storageKey)
    }
}

// MARK: - Suggestions Strip (embed in any feed/home view)

struct AmenSuggestionsStrip: View {
    @StateObject private var service = AmenSuggestionsService.shared

    var body: some View {
        if !service.suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Suggested for You")
                    .font(.headline)
                    .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(service.suggestions) { s in
                            SuggestionCard(suggestion: s) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    service.dismiss(suggestion: s)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

// MARK: - Card

private struct SuggestionCard: View {
    let suggestion: AmenContentSuggestion
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: suggestion.systemImage)
                    .font(.title3)
                    .foregroundStyle(.primary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.quaternary)
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
            Text(suggestion.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(suggestion.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 160, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }
}
