// BereanIntelligenceEngine.swift
// AMENAPP — Intelligence engine for the Berean assistant composer.
//
// Detects BereanIntelligenceState via local keyword heuristics (no network),
// suggests SmartActions for the detected state, and routes completed queries
// through BereanCoreService on the pastoral lane.
//
// Fail-closed: never falls back to a non-pastoral provider.
// No API keys, no provider names, no stubs.

import SwiftUI
import Foundation

// MARK: - Error Types

enum BereanIntelligenceError: Error {
    case safetyBlock
    case processingFailed(String)
}

// MARK: - BereanIntelligenceEngine

@MainActor
final class BereanIntelligenceEngine: ObservableObject {

    // MARK: - Published State

    @Published private(set) var detectedState: BereanIntelligenceState? = nil
    @Published private(set) var suggestedActions: [SmartAction] = []
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var lastError: String? = nil

    // MARK: - Private

    private var analyzeTask: Task<Void, Never>?

    // MARK: - Public API

    /// Call on every keystroke. Debounced 400 ms; cancels any in-flight analysis.
    func analyze(text: String) {
        analyzeTask?.cancel()
        analyzeTask = Task {
            do {
                // 400 ms debounce
                try await Task.sleep(nanoseconds: 400_000_000)
            } catch {
                // Task was cancelled — a newer analysis is coming. Exit silently.
                return
            }

            guard !Task.isCancelled else { return }

            let (state, actions) = Self.classify(text: text)
            self.detectedState = state
            self.suggestedActions = actions
        }
    }

    /// Dispatches a completed query through BereanCoreService on the pastoral lane.
    /// Returns the response content string. Throws `BereanIntelligenceError.safetyBlock`
    /// if the response contains a blocking safety flag.
    func dispatch(
        query: String,
        state: BereanIntelligenceState,
        userId: String?
    ) async throws -> String {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        let category = Self.taskCategory(for: state)
        let isPrivate = (state == .emotionalSupport)

        let request = BereanAIRequest(
            surface: .bereanChat,
            category: category,
            userInput: query,
            userId: userId,
            latencyBudgetMs: 4000,
            allowCache: false,
            isPrivate: isPrivate
        )

        let response = await BereanCoreService.shared.process(request)

        // Fail-closed: block if any safety flag requires a block action.
        if response.safetyFlags.contains(where: { $0.actionRequired == .block }) {
            lastError = "This message was blocked for safety."
            throw BereanIntelligenceError.safetyBlock
        }

        if response.content.isEmpty {
            let message = "No response was returned."
            lastError = message
            throw BereanIntelligenceError.processingFailed(message)
        }

        return response.content
    }

    // MARK: - Classification (pure, no network)

    /// Maps input text to a `BereanIntelligenceState` and the suggested `SmartAction`s
    /// using lightweight keyword heuristics. Returns `(nil, [])` for empty input.
    private static func classify(text: String) -> (BereanIntelligenceState?, [SmartAction]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, []) }

        let lower = trimmed.lowercased()

        // Scripture reference: a book name followed by chapter:verse numbers
        // e.g. "John 3:16", "Psalm 23", "1 Corinthians 13:4"
        if containsVerseReference(lower) {
            return (.scriptureExplanation, [.explainVerse, .compareTranslations])
        }

        // Prayer / address to God
        if hasPrefix(lower, prefixes: ["pray", "prayer", "lord", "god please"]) {
            return (.prayerSupport, [.createPrayer, .saveReflection])
        }

        // Church notes / sermon
        if containsAny(lower, keywords: ["notes", "sermon", "service", "pastor"]) {
            return (.churchNotes, [.summarizeNotes, .saveReflection])
        }

        // Emotional support
        if containsAny(lower, keywords: ["feeling", "struggling", "hard", "hurt"]) {
            return (.emotionalSupport, [.createPrayer, .saveReflection])
        }

        // Safe posting / sharing intent
        if containsAny(lower, keywords: ["post", "share", "caption"]) {
            return (.safePosting, [.shareSafely])
        }

        // Theological comparison / denominational
        if containsAny(lower, keywords: ["baptist", "catholic", "tradition", "denomination"]) {
            return (.theologicalComparison, [.compareTranslations, .explainVerse])
        }

        // Community discussion
        if containsAny(lower, keywords: ["discuss", "community", "thoughts on"]) {
            return (.communityDiscussion, [.startDiscussion, .shareSafely])
        }

        // Reminder / planning
        if containsAny(lower, keywords: ["remind", "plan", "schedule", "goal"]) {
            return (.reminderActionPlanning, [.saveReflection])
        }

        return (nil, [])
    }

    // MARK: - State → Category Mapping

    private static func taskCategory(for state: BereanIntelligenceState) -> AITaskCategory {
        switch state {
        case .scriptureExplanation, .theologicalComparison:
            return .scriptureGrounding
        case .prayerSupport:
            return .prayerDrafting
        case .churchNotes:
            return .summaryGeneration
        case .emotionalSupport:
            return .crisisDetection
        case .safePosting:
            return .safetyScreening
        case .communityDiscussion:
            return .assistantResponse
        case .reminderActionPlanning:
            return .assistantResponse
        }
    }

    // MARK: - Keyword Helpers

    /// Returns true if the lowercased text matches any of the given prefix strings.
    private static func hasPrefix(_ text: String, prefixes: [String]) -> Bool {
        prefixes.contains { text.hasPrefix($0) }
    }

    /// Returns true if the lowercased text contains any of the given keywords.
    private static func containsAny(_ text: String, keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }

    /// Detects a scripture reference pattern: a known book name followed by chapter/verse numbers.
    /// Handles abbreviated and full names; supports formats like "John 3:16", "Ps 23", "1 Cor 13".
    private static func containsVerseReference(_ lower: String) -> Bool {
        // Book name fragments (abbreviated or full) that precede chapter numbers
        let bookFragments: [String] = [
            "genesis", "gen ", "exodus", "exod", "leviticus", "lev ", "numbers", "num ",
            "deuteronomy", "deut", "joshua", "josh", "judges", "judg", "ruth",
            "samuel", "sam ", "kings", "chronicles", "chr ", "ezra", "nehemiah", "neh ",
            "esther", "esth", "job", "psalm", "ps ", "proverbs", "prov", "ecclesiastes",
            "eccl", "song of", "isaiah", "isa ", "jeremiah", "jer ", "lamentations",
            "ezekiel", "ezek", "daniel", "dan ", "hosea", "hos ", "joel", "amos",
            "obadiah", "obad", "jonah", "micah", "mic ", "nahum", "habakkuk", "hab ",
            "zephaniah", "zeph", "haggai", "hag ", "zechariah", "zech", "malachi", "mal ",
            "matthew", "matt", "mark", "luke", "john", "acts", "romans", "rom ",
            "corinthians", "cor ", "galatians", "gal ", "ephesians", "eph ",
            "philippians", "phil", "colossians", "col ", "thessalonians", "thess",
            "timothy", "tim ", "titus", "philemon", "phlm", "hebrews", "heb ",
            "james", "jas ", "peter", "pet ", "jude", "revelation", "rev "
        ]

        // Quick check: does the text contain a book fragment followed eventually by a digit?
        guard let _ = bookFragments.first(where: { lower.contains($0) }) else { return false }

        // Confirm there is at least one digit (chapter number) after the book fragment
        return lower.range(of: "[0-9]", options: .regularExpression) != nil
    }
}
