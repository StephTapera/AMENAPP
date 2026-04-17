//
//  ComposerInsightEngine.swift
//  AMENAPP
//
//  Smart composition analysis engine for CreatePostView.
//  Provides context-aware suggestions, readiness state, and attachment prioritization.
//  Local-first heuristics with 300ms debounced analysis pipeline.
//

import SwiftUI
import Foundation

// MARK: - Models

/// Detected intent of the user's draft
enum ComposerIntent: String, CaseIterable {
    case prayer
    case testimony
    case question
    case event
    case discussion
    case verse
    case encouragement
    case announcement
    case general
}

/// Suggested action the engine recommends to the user
enum ComposerSuggestedAction: String, CaseIterable {
    case attachVerse
    case addTopicTag
    case addCalendarDate
    case switchToThread
    case tagPeople
    case adjustAudience
    case addImage
    case addPoll

    var icon: String {
        switch self {
        case .attachVerse:     return "text.book.closed"
        case .addTopicTag:     return "tag"
        case .addCalendarDate: return "calendar"
        case .switchToThread:  return "text.line.first.and.arrowtriangle.forward"
        case .tagPeople:       return "person.badge.plus"
        case .adjustAudience:  return "person.2"
        case .addImage:        return "photo"
        case .addPoll:         return "chart.bar.xaxis"
        }
    }

    var label: String {
        switch self {
        case .attachVerse:     return "Add verse"
        case .addTopicTag:     return "Add topic"
        case .addCalendarDate: return "Add date"
        case .switchToThread:  return "Make thread"
        case .tagPeople:       return "Tag people"
        case .adjustAudience:  return "Refine audience"
        case .addImage:        return "Add photo"
        case .addPoll:         return "Add poll"
        }
    }

    /// Maps to SF Symbol icon name used in threadsAttachmentBar
    var attachmentBarIcon: String? {
        switch self {
        case .attachVerse:     return "text.book.closed"
        case .addCalendarDate: return "calendar"
        case .addImage:        return "photo"
        case .addPoll:         return "chart.bar.xaxis"
        default:               return nil
        }
    }
}

/// How "ready" the post is for publishing
enum ComposerReadinessState: String {
    case empty
    case missingRequiredTopic
    case tooShort
    case drafting
    case ready

    static var `default`: ComposerReadinessState { .empty }
}

/// The result container from analysis
struct ComposerInsightResult: Equatable {
    let intent: ComposerIntent
    let confidence: Double
    let primarySuggestion: ComposerSuggestedAction?
    let secondarySuggestions: [ComposerSuggestedAction]
    let readinessState: ComposerReadinessState

    static let empty = ComposerInsightResult(
        intent: .general,
        confidence: 0,
        primarySuggestion: nil,
        secondarySuggestions: [],
        readinessState: .empty
    )
}

// MARK: - Engine

@MainActor
final class ComposerInsightEngine: ObservableObject {
    static let shared = ComposerInsightEngine()

    @Published private(set) var result: ComposerInsightResult = .empty

    private var analysisTask: Task<Void, Never>?
    private init() {}

    /// Debounced analysis — call on every text change, engine handles 300ms debounce internally
    func analyzeText(
        _ text: String,
        category: String,
        hasVerse: Bool,
        hasTopicTag: Bool,
        hasPoll: Bool,
        hasImages: Bool
    ) {
        analysisTask?.cancel()
        analysisTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled else { return }
            let newResult = performAnalysis(
                text,
                category: category,
                hasVerse: hasVerse,
                hasTopicTag: hasTopicTag,
                hasPoll: hasPoll,
                hasImages: hasImages
            )
            // Only update if meaningfully changed to avoid unnecessary SwiftUI invalidation
            if newResult != result {
                result = newResult
            }
        }
    }

    /// Reset state when composer is dismissed
    func reset() {
        analysisTask?.cancel()
        analysisTask = nil
        result = .empty
    }

    // MARK: - Private Analysis

    private func performAnalysis(
        _ text: String,
        category: String,
        hasVerse: Bool,
        hasTopicTag: Bool,
        hasPoll: Bool,
        hasImages: Bool
    ) -> ComposerInsightResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // Empty state
        guard !trimmed.isEmpty else {
            return ComposerInsightResult(
                intent: .general,
                confidence: 0,
                primarySuggestion: nil,
                secondarySuggestions: [],
                readinessState: .empty
            )
        }

        // Detect intent
        let (intent, confidence) = detectIntent(lower)

        // Calculate readiness
        let readiness = calculateReadiness(
            text: trimmed,
            category: category,
            hasTopicTag: hasTopicTag
        )

        // Generate suggestions
        let (primary, secondary) = generateSuggestions(
            intent: intent,
            confidence: confidence,
            text: trimmed,
            category: category,
            hasVerse: hasVerse,
            hasTopicTag: hasTopicTag,
            hasPoll: hasPoll,
            hasImages: hasImages,
            readiness: readiness
        )

        return ComposerInsightResult(
            intent: intent,
            confidence: confidence,
            primarySuggestion: primary,
            secondarySuggestions: secondary,
            readinessState: readiness
        )
    }

    // MARK: - Intent Detection

    private struct KeywordSet {
        let intent: ComposerIntent
        let keywords: [String]
        let weight: Double
    }

    private static let keywordSets: [KeywordSet] = [
        KeywordSet(intent: .prayer, keywords: [
            "pray", "prayer", "praying", "intercede", "intercession",
            "lord", "healing", "comfort", "bless", "blessing",
            "strength", "guide", "please pray", "struggling",
            "grateful", "burden", "anxious", "thankful", "peace"
        ], weight: 0.85),

        KeywordSet(intent: .testimony, keywords: [
            "testimony", "testify", "god did", "breakthrough",
            "miracle", "answered prayer", "transformed", "delivered",
            "overcame", "set free", "god showed", "faithful",
            "witness", "share what god"
        ], weight: 0.85),

        KeywordSet(intent: .event, keywords: [
            "this sunday", "next week", "tomorrow", "tonight",
            "event", "service", "gathering", "meetup", "conference",
            "bible study", "worship night", "join us", "register",
            "rsvp", "location", "church event"
        ], weight: 0.75),

        KeywordSet(intent: .question, keywords: [
            "what does", "how do", "why does", "has anyone",
            "does anyone", "thoughts on", "opinions about",
            "can someone explain", "what are your", "help me understand"
        ], weight: 0.70),

        KeywordSet(intent: .verse, keywords: [
            "scripture", "verse", "bible says", "word of god",
            "devotional", "meditation", "reading plan"
        ], weight: 0.70),

        KeywordSet(intent: .encouragement, keywords: [
            "you are loved", "keep going", "don't give up",
            "reminder", "encouragement", "be strong",
            "god is with you", "you're not alone", "stay faithful"
        ], weight: 0.65),

        KeywordSet(intent: .announcement, keywords: [
            "announcing", "excited to share", "big news",
            "update", "new", "launching", "starting",
            "introducing", "check out"
        ], weight: 0.60)
    ]

    // Scripture book regex — matches all 66 books with optional number prefix
    private static let scripturePattern: String = {
        let books = [
            "genesis", "exodus", "leviticus", "numbers", "deuteronomy",
            "joshua", "judges", "ruth", "samuel", "kings", "chronicles",
            "ezra", "nehemiah", "esther", "job", "psalm", "psalms",
            "proverbs", "ecclesiastes", "song of solomon", "isaiah",
            "jeremiah", "lamentations", "ezekiel", "daniel", "hosea",
            "joel", "amos", "obadiah", "jonah", "micah", "nahum",
            "habakkuk", "zephaniah", "haggai", "zechariah", "malachi",
            "matthew", "mark", "luke", "john", "acts", "romans",
            "corinthians", "galatians", "ephesians", "philippians",
            "colossians", "thessalonians", "timothy", "titus", "philemon",
            "hebrews", "james", "peter", "jude", "revelation"
        ]
        let bookGroup = books.joined(separator: "|")
        return "(?:1|2|3|i|ii|iii)?\\s*(?:\(bookGroup))\\s+\\d+(?:[:\\.]\\d+)?(?:\\s*-\\s*\\d+)?"
    }()

    private static let scriptureRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: scripturePattern, options: .caseInsensitive)
    }()

    private func detectIntent(_ lower: String) -> (ComposerIntent, Double) {
        var scores: [(ComposerIntent, Double)] = []

        // Check scripture references first (high-confidence signal)
        if let regex = Self.scriptureRegex {
            let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
            let matches = regex.numberOfMatches(in: lower, range: range)
            if matches > 0 {
                scores.append((.verse, 0.90))
            }
        }

        // Check question mark
        if lower.hasSuffix("?") || lower.contains("?") {
            scores.append((.question, 0.55))
        }

        // Check keyword sets
        for set in Self.keywordSets {
            let matchCount = set.keywords.filter { lower.contains($0) }.count
            if matchCount > 0 {
                // Scale weight by number of matches (diminishing returns)
                let scaledWeight = set.weight * min(1.0, Double(matchCount) * 0.5)
                scores.append((set.intent, scaledWeight))
            }
        }

        // Return highest scoring intent above threshold
        if let best = scores.max(by: { $0.1 < $1.1 }), best.1 >= 0.30 {
            return best
        }

        return (.general, 0.0)
    }

    // MARK: - Readiness Calculation

    private func calculateReadiness(
        text: String,
        category: String,
        hasTopicTag: Bool
    ) -> ComposerReadinessState {
        let charCount = text.count

        // Check topic tag requirement for openTable and prayer
        if (category == "openTable" || category == "prayer") && !hasTopicTag {
            return charCount > 0 ? .missingRequiredTopic : .empty
        }

        if charCount == 0 { return .empty }
        if charCount < 15 { return .tooShort }
        if charCount < 30 { return .drafting }

        return .ready
    }

    // MARK: - Suggestion Generation

    private func generateSuggestions(
        intent: ComposerIntent,
        confidence: Double,
        text: String,
        category: String,
        hasVerse: Bool,
        hasTopicTag: Bool,
        hasPoll: Bool,
        hasImages: Bool,
        readiness: ComposerReadinessState
    ) -> (ComposerSuggestedAction?, [ComposerSuggestedAction]) {
        // Don't suggest if confidence is too low or text is too short
        guard confidence >= 0.30, text.count >= 30 else {
            return (nil, [])
        }

        var candidates: [ComposerSuggestedAction] = []

        // Intent-based primary suggestions
        switch intent {
        case .prayer, .verse, .encouragement:
            if !hasVerse { candidates.append(.attachVerse) }
            if !hasTopicTag { candidates.append(.addTopicTag) }
            if text.count > 100 { candidates.append(.switchToThread) }

        case .testimony:
            if !hasTopicTag { candidates.append(.addTopicTag) }
            if !hasVerse { candidates.append(.attachVerse) }

        case .event, .announcement:
            candidates.append(.addCalendarDate)
            if !hasTopicTag { candidates.append(.addTopicTag) }

        case .question, .discussion:
            if text.count > 80 { candidates.append(.switchToThread) }
            if !hasTopicTag { candidates.append(.addTopicTag) }
            if !hasPoll { candidates.append(.addPoll) }

        case .general:
            // Minimal suggestions for general content
            if !hasTopicTag && (category == "openTable" || category == "prayer") {
                candidates.append(.addTopicTag)
            }
        }

        // Filter out already-satisfied actions
        candidates = candidates.filter { action in
            switch action {
            case .attachVerse:     return !hasVerse
            case .addTopicTag:     return !hasTopicTag
            case .addImage:        return !hasImages
            case .addPoll:         return !hasPoll
            default:               return true
            }
        }

        // Remove duplicates preserving order
        var seen = Set<ComposerSuggestedAction>()
        candidates = candidates.filter { seen.insert($0).inserted }

        // Split into primary + secondary (max 2)
        let primary = candidates.first
        let secondary = Array(candidates.dropFirst().prefix(2))

        return (primary, secondary)
    }
}
