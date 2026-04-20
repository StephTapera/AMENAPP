// ChurchNotesIntelligenceService.swift
// AMENAPP
//
// Local intelligence service for Church Notes.
// Runs on-device with no network calls required for basic signals.
// Handles:
//   - Posture detection (heuristic keyword matching)
//   - Theme extraction (keyword frequency across blocks)
//   - Note connection finding (theme overlap scoring)
//   - Pre-save review suggestions
//   - God Has Been Saying local summary computation
//
// All analysis is private-first. No raw note content leaves the device
// unless the user explicitly triggers a backend function.

import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class ChurchNotesIntelligenceService {

    static let shared = ChurchNotesIntelligenceService()
    private init() {}

    // MARK: - Posture Detection

    /// Detects the most likely spiritual posture from combined block text.
    /// Returns nil if no signal is strong enough (confidence < 2 keyword hits).
    func detectPosture(from blocks: [ChurchNoteBlockV2]) -> CNPostureSignal? {
        let allText = blocks
            .map { $0.text.lowercased() }
            .joined(separator: " ")

        var scores: [CNPostureSignal: Int] = [:]
        for signal in CNPostureSignal.allCases {
            let count = signal.keywords.reduce(0) { total, keyword in
                total + (allText.contains(keyword) ? 1 : 0)
            }
            if count > 0 { scores[signal] = count }
        }

        guard let best = scores.max(by: { $0.value < $1.value }),
              best.value >= 1 else { return nil }
        return best.key
    }

    // MARK: - Theme Extraction

    /// Extracts candidate themes from block text using frequency + semantic heuristics.
    /// Returns up to 5 themes, each with an occurrence count.
    func extractThemes(from blocks: [ChurchNoteBlockV2]) -> [(theme: String, count: Int)] {
        let words = blocks
            .map { $0.text }
            .joined(separator: " ")
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 }

        // Spiritual theme keyword groupings
        let themeGroups: [(theme: String, keywords: [String])] = [
            ("trust",       ["trust", "faith", "believe", "relying", "depend"]),
            ("surrender",   ["surrender", "yield", "let go", "release", "give up"]),
            ("waiting",     ["wait", "waiting", "patient", "patience", "season"]),
            ("obedience",   ["obey", "obedience", "step out", "follow", "submit"]),
            ("identity",    ["identity", "who I am", "beloved", "child of God", "worth"]),
            ("forgiveness", ["forgive", "forgiveness", "mercy", "grace", "pardon"]),
            ("purpose",     ["purpose", "calling", "destiny", "mission", "why"]),
            ("prayer",      ["pray", "prayer", "intercede", "petition", "ask God"]),
            ("family",      ["family", "marriage", "children", "spouse", "home"]),
            ("grief",       ["grief", "loss", "mourn", "pain", "hurt"]),
            ("hope",        ["hope", "expectation", "anticipate", "future", "ahead"]),
            ("fear",        ["fear", "afraid", "anxious", "worry", "anxiety"]),
            ("leadership",  ["lead", "leader", "shepherd", "influence", "serve"]),
            ("humility",    ["humble", "humility", "meek", "lowly", "pride"]),
            ("community",   ["community", "church", "together", "fellowship", "body"]),
        ]

        var scores: [String: Int] = [:]
        for group in themeGroups {
            let score = group.keywords.reduce(0) { total, kw in
                total + words.filter { $0.contains(kw) }.count
            }
            if score > 0 { scores[group.theme] = score }
        }

        return scores
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { (theme: $0.key, count: $0.value) }
    }

    // MARK: - Note Connections

    /// Finds notes related to `sourceNote` by theme + scripture overlap.
    /// Returns connections sorted by strength (descending).
    func findConnections(
        sourceNote: ChurchNoteV2,
        sourceBlocks: [ChurchNoteBlockV2],
        allNotes: [ChurchNoteV2]
    ) -> [ChurchNoteConnection] {
        let sourceThemes = Set(extractThemes(from: sourceBlocks).map { $0.theme })
        let sourceScriptures = Set(sourceNote.scriptureReferences.map { $0.lowercased() })

        var connections: [ChurchNoteConnection] = []

        for candidate in allNotes {
            guard candidate.id != sourceNote.id else { continue }

            // Build candidate theme set from tags (fast, no subcollection read)
            let candidateThemes: Set<String> = Set(
                candidate.tags.flatMap { tag -> [String] in
                    extractThemeKeys(from: tag.lowercased())
                }
            )
            let candidateScriptures = Set(candidate.scriptureReferences.map { $0.lowercased() })

            let themeOverlap = sourceThemes.intersection(candidateThemes)
            let scriptureOverlap = sourceScriptures.intersection(candidateScriptures)

            let themeScore = Double(themeOverlap.count) / max(Double(sourceThemes.count), 1)
            let scriptureScore = Double(scriptureOverlap.count) / max(Double(sourceScriptures.count), 1)
            let strength = (themeScore * 0.6) + (scriptureScore * 0.4)

            guard strength > 0.15 else { continue }

            let sharedLabels = Array(themeOverlap.union(scriptureOverlap)).sorted().prefix(3).map { $0 }
            connections.append(ChurchNoteConnection(
                relatedNoteId: candidate.id,
                relatedNoteTitle: candidate.title.isEmpty ? "Untitled note" : candidate.title,
                relatedNoteDate: candidate.updatedAt,
                sharedThemes: Array(sharedLabels),
                connectionStrength: min(strength, 1.0)
            ))
        }

        return connections
            .sorted { $0.connectionStrength > $1.connectionStrength }
            .prefix(4)
            .map { $0 }
    }

    private func extractThemeKeys(from text: String) -> [String] {
        let map: [String: String] = [
            "trust": "trust", "faith": "trust",
            "wait": "waiting", "patience": "waiting",
            "obey": "obedience", "obedience": "obedience",
            "surrender": "surrender", "yield": "surrender",
            "hope": "hope", "expect": "hope",
            "fear": "fear", "anxiety": "fear",
            "family": "family", "marriage": "family",
            "prayer": "prayer", "pray": "prayer",
            "forgive": "forgiveness",
            "purpose": "purpose", "calling": "purpose",
        ]
        return map.compactMap { text.contains($0.key) ? $0.value : nil }
    }

    // MARK: - Pre-Save Review Suggestions

    /// Returns contextual suggestions for the user before closing a note.
    /// Suggestions are progressive — only shown if the note is missing that element.
    func reviewSuggestions(
        for blocks: [ChurchNoteBlockV2],
        bridge: CNSermonBridge?,
        reflections: [ChurchNoteReflection]
    ) -> [CNReviewSuggestion] {
        var suggestions: [CNReviewSuggestion] = []

        let hasKeyInsight = blocks.contains { $0.semanticType == .keyTruth || $0.type == .takeaway }
        let hasPrayer = blocks.contains { $0.semanticType == .prayerPoint || $0.type == .prayer }
        let hasVerse = blocks.contains { $0.type == .verseEmbed || $0.semanticType == .verseInsight }
        let hasAction = blocks.contains { $0.semanticType == .actionStep || $0.type == .action || $0.type == .checklist }
        let hasAnchor = blocks.contains { $0.semanticType != .general }
        let hasBridge = bridge?.isPopulated == true
        let hasReflection = !reflections.isEmpty

        if !hasKeyInsight {
            suggestions.append(CNReviewSuggestion(
                icon: "lightbulb.fill",
                label: "Add a key insight",
                action: .addTakeaway
            ))
        }
        if !hasPrayer {
            suggestions.append(CNReviewSuggestion(
                icon: "hands.sparkles.fill",
                label: "Add a prayer",
                action: .addPrayer
            ))
        }
        if !hasVerse {
            suggestions.append(CNReviewSuggestion(
                icon: "book.fill",
                label: "Add a verse",
                action: .addVerse
            ))
        }
        if !hasAction {
            suggestions.append(CNReviewSuggestion(
                icon: "checkmark.circle.fill",
                label: "Add an action step",
                action: .addAction
            ))
        }
        if !hasAnchor && blocks.count >= 3 {
            suggestions.append(CNReviewSuggestion(
                icon: "anchor",
                label: "Mark what stood out most",
                action: .markAnchor
            ))
        }
        if !hasBridge && blocks.count >= 2 {
            suggestions.append(CNReviewSuggestion(
                icon: "calendar.badge.checkmark",
                label: "Carry this into the week",
                action: .fillBridge
            ))
        }
        if !hasReflection {
            suggestions.append(CNReviewSuggestion(
                icon: "arrow.circlepath",
                label: "Revisit this note later",
                action: .setReflectionReminder
            ))
        }

        // Cap at 4 to avoid overwhelming
        return Array(suggestions.prefix(4))
    }

    // MARK: - Local God Has Been Saying

    /// Computes a local summary of recurring themes from available notes.
    /// This is a fast local computation — backend can supplement with deeper AI analysis.
    func computeLocalSummary(
        from notes: [ChurchNoteV2],
        userId: String
    ) -> ChurchNotesSummary {
        guard !notes.isEmpty else { return .empty(userId: userId) }

        // Count theme appearances across note tags
        var themeFreq: [String: (count: Int, noteIds: [String], first: Date, last: Date)] = [:]
        var scriptureFreq: [String: (count: Int, last: Date)] = [:]

        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recentNotes = notes.filter { $0.updatedAt >= thirtyDaysAgo }

        for note in notes {
            // Theme tallying from tags
            for tag in note.tags {
                let key = tag.lowercased().trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty else { continue }
                if var existing = themeFreq[key] {
                    existing.count += 1
                    existing.noteIds.append(note.id)
                    existing.last = max(existing.last, note.updatedAt)
                    themeFreq[key] = existing
                } else {
                    themeFreq[key] = (1, [note.id], note.updatedAt, note.updatedAt)
                }
            }
            // Scripture tallying
            for ref in note.scriptureReferences {
                let book = ref.components(separatedBy: " ").first ?? ref
                if var existing = scriptureFreq[ref] {
                    existing.count += 1
                    existing.last = max(existing.last, note.updatedAt)
                    scriptureFreq[ref] = existing
                } else {
                    scriptureFreq[ref] = (1, note.updatedAt)
                    let _ = book  // captured above for book extraction
                }
            }
        }

        let topThemes = themeFreq
            .filter { $0.value.count >= 2 }
            .sorted { $0.value.count > $1.value.count }
            .prefix(6)
            .map { (key, val) in
                CNThemePattern(
                    id: key,
                    theme: key.capitalized,
                    noteCount: val.count,
                    recentNoteIds: Array(val.noteIds.suffix(3)),
                    firstSeenAt: val.first,
                    lastSeenAt: val.last
                )
            }

        let repeatedScriptures = scriptureFreq
            .filter { $0.value.count >= 2 }
            .sorted { $0.value.count > $1.value.count }
            .prefix(4)
            .map { (ref, val) in
                CNScripturePattern(
                    reference: ref,
                    book: ref.components(separatedBy: " ").first ?? ref,
                    timesAttached: val.count,
                    lastSeenAt: val.last
                )
            }

        // Build a human-readable reflection statement
        let statement = buildReflectionStatement(
            topThemes: Array(topThemes),
            noteCount: notes.count,
            recentCount: recentNotes.count
        )

        return ChurchNotesSummary(
            id: userId,
            topThemes: Array(topThemes),
            repeatedScriptures: Array(repeatedScriptures),
            postureTrend: nil,  // populated by backend AI analysis
            noteCountLast30Days: recentNotes.count,
            noteCountAllTime: notes.count,
            reflectionStatement: statement,
            generatedAt: Date(),
            showInsights: true,
            dismissedAt: nil
        )
    }

    private func buildReflectionStatement(
        topThemes: [CNThemePattern],
        noteCount: Int,
        recentCount: Int
    ) -> String {
        guard noteCount >= 2 else { return "" }

        let recurringThemes = topThemes.filter { $0.isRecurring }
        let themeNames = recurringThemes.prefix(3).map { $0.theme.lowercased() }

        if themeNames.isEmpty && topThemes.isEmpty { return "" }

        let displayThemes = themeNames.isEmpty
            ? topThemes.prefix(2).map { $0.theme.lowercased() }
            : Array(themeNames)

        switch displayThemes.count {
        case 1:
            return "Your recent notes often return to \(displayThemes[0])."
        case 2:
            return "Your recent notes often return to \(displayThemes[0]) and \(displayThemes[1])."
        default:
            let joined = displayThemes.dropLast().joined(separator: ", ")
            return "Your recent notes often return to \(joined), and \(displayThemes.last ?? "")."
        }
    }

    // MARK: - Sermon Map

    /// Builds a structured map representation of a note's blocks for the Map View.
    /// Returns sections: theme, supporting points, prayers, actions, questions, verses.
    func buildSermonMap(from blocks: [ChurchNoteBlockV2]) -> CNSermonMap {
        let theme = blocks.first { $0.semanticType == .keyTruth || $0.pinnedState == .anchorInsight }
        let supporting = blocks.filter {
            $0.type == .heading || $0.type == .subheading
        }
        let prayers = blocks.filter { $0.semanticType == .prayerPoint || $0.type == .prayer }
        let actions = blocks.filter { $0.semanticType == .actionStep || $0.type == .action }
        let questions = blocks.filter { $0.semanticType == .question }
        let verses = blocks.filter { $0.type == .verseEmbed || $0.semanticType == .verseInsight }
        let quotes = blocks.filter { $0.semanticType == .pastorQuote || $0.type == .quote }

        return CNSermonMap(
            centralTheme: theme?.text ?? "",
            supportingPoints: supporting.map { $0.text },
            prayers: prayers.map { $0.text },
            actions: actions.map { $0.text },
            questions: questions.map { $0.text },
            verses: verses.map { $0.versePayload?.reference ?? $0.text },
            quotes: quotes.map { $0.text }
        )
    }
}

// MARK: - Sermon Map Model

struct CNSermonMap {
    var centralTheme: String
    var supportingPoints: [String]
    var prayers: [String]
    var actions: [String]
    var questions: [String]
    var verses: [String]
    var quotes: [String]

    var isEmpty: Bool {
        centralTheme.isEmpty && supportingPoints.isEmpty && prayers.isEmpty
            && actions.isEmpty && questions.isEmpty && verses.isEmpty
    }
}
