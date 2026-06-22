import Foundation

// MARK: - Chat Memory Extraction Engine
/// Local heuristic extraction engine that detects actionable items,
/// promises, decisions, dates, and follow-ups from chat messages.
/// Runs on-device with no network calls — 500ms debounced.

@MainActor
final class ChatMemoryExtractionEngine: ObservableObject {
    static let shared = ChatMemoryExtractionEngine()

    @Published private(set) var pendingSuggestions: [ChatMemorySuggestion] = []

    private var extractionTask: Task<Void, Never>?

    // Per-type cooldowns: type → last dismissal timestamp
    private var typeDismissals: [ChatMemoryItemType: Date] = [:]
    // Per-type dismissal counts (for suppression after 3)
    private var typeDismissalCounts: [ChatMemoryItemType: Int] = [:]
    // Already-seen source message IDs to prevent duplicates
    private var seenSourceIds: Set<String> = []
    // Session extraction count
    private var sessionExtractionCount = 0
    private let maxPerSession = 3

    private init() {}

    // MARK: - Public API

    /// Analyze the last N messages for extractable memory items.
    /// Debounced by 500ms to avoid over-triggering.
    func analyzeMessages(_ messages: [ExtractableMessage], chatId: String) {
        extractionTask?.cancel()
        extractionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            guard sessionExtractionCount < maxPerSession else { return }

            let newSuggestions = performExtraction(messages, chatId: chatId)
            if !newSuggestions.isEmpty {
                sessionExtractionCount += 1
                // Deduplicate against existing
                let existingIds = Set(pendingSuggestions.map(\.id))
                let filtered = newSuggestions.filter { !existingIds.contains($0.id) }
                pendingSuggestions.append(contentsOf: filtered)
            }
        }
    }

    /// Called when user dismisses a suggestion — tracks cooldown.
    func dismissSuggestion(_ suggestion: ChatMemorySuggestion) {
        pendingSuggestions.removeAll { $0.id == suggestion.id }
        typeDismissals[suggestion.type] = Date()
        typeDismissalCounts[suggestion.type, default: 0] += 1
    }

    /// Remove a suggestion by ID (e.g., after user accepts it).
    func removeSuggestion(id: String) {
        pendingSuggestions.removeAll { $0.id == id }
    }

    /// Clear all pending suggestions (e.g., on chat exit).
    func clearPending() {
        pendingSuggestions.removeAll()
    }

    /// Reset session state (e.g., when entering a new chat).
    func resetSession() {
        sessionExtractionCount = 0
        seenSourceIds.removeAll()
        pendingSuggestions.removeAll()
    }

    // MARK: - Extraction Logic

    private func performExtraction(_ messages: [ExtractableMessage], chatId: String) -> [ChatMemorySuggestion] {
        var results: [ChatMemorySuggestion] = []

        for message in messages {
            guard !seenSourceIds.contains(message.id) else { continue }
            let text = message.text.lowercased()
            let originalText = message.text

            // Promise detection
            if let match = detectPromise(text, original: originalText) {
                if shouldSuggest(type: match.type, sourceIds: [message.id]) {
                    results.append(match.withSourceIds([message.id]))
                    seenSourceIds.insert(message.id)
                }
            }

            // Decision detection
            if let match = detectDecision(text, original: originalText) {
                if shouldSuggest(type: match.type, sourceIds: [message.id]) {
                    results.append(match.withSourceIds([message.id]))
                    seenSourceIds.insert(message.id)
                }
            }

            // Date/time detection
            if let match = detectDateReference(text, original: originalText) {
                if shouldSuggest(type: match.type, sourceIds: [message.id]) {
                    results.append(match.withSourceIds([message.id]))
                    seenSourceIds.insert(message.id)
                }
            }

            // Follow-up detection
            if let match = detectFollowUp(text, original: originalText) {
                if shouldSuggest(type: match.type, sourceIds: [message.id]) {
                    results.append(match.withSourceIds([message.id]))
                    seenSourceIds.insert(message.id)
                }
            }

            // Prayer request detection
            if let match = detectPrayerRequest(text, original: originalText) {
                if shouldSuggest(type: match.type, sourceIds: [message.id]) {
                    results.append(match.withSourceIds([message.id]))
                    seenSourceIds.insert(message.id)
                }
            }
        }

        return results
    }

    // MARK: - Pattern Detectors

    private func detectPromise(_ text: String, original: String) -> ChatMemorySuggestion? {
        let promisePatterns = [
            "i'll", "i will", "let me", "i'm going to", "i promise",
            "remind me to", "i need to", "i should", "i'll send"
        ]
        guard let matched = promisePatterns.first(where: { text.contains($0) }) else { return nil }

        let sentence = extractSentence(containing: matched, from: original)
        return ChatMemorySuggestion(
            type: .promise,
            title: "Promise",
            summary: sentence,
            confidence: 0.75,
            sourceMessageIds: []
        )
    }

    private func detectDecision(_ text: String, original: String) -> ChatMemorySuggestion? {
        let decisionPatterns = [
            "we decided", "let's do", "agreed on", "we agreed",
            "let's go with", "the plan is", "we're going to", "settled on"
        ]
        guard let matched = decisionPatterns.first(where: { text.contains($0) }) else { return nil }

        let sentence = extractSentence(containing: matched, from: original)
        return ChatMemorySuggestion(
            type: .decision,
            title: "Decision",
            summary: sentence,
            confidence: 0.80,
            sourceMessageIds: []
        )
    }

    private func detectDateReference(_ text: String, original: String) -> ChatMemorySuggestion? {
        let datePatterns = [
            "tomorrow", "tonight", "this weekend", "next week",
            "next monday", "next tuesday", "next wednesday", "next thursday",
            "next friday", "next saturday", "next sunday",
            "on monday", "on tuesday", "on wednesday", "on thursday",
            "on friday", "on saturday", "on sunday"
        ]

        // Time regex: "at 3pm", "at 3:00", "at noon"
        let timeRegex = try? NSRegularExpression(pattern: "at\\s+\\d{1,2}(:\\d{2})?\\s*(am|pm|AM|PM)?", options: [])
        let hasTime = (timeRegex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil)

        guard let matched = datePatterns.first(where: { text.contains($0) }) ?? (hasTime ? "time" : nil) else {
            return nil
        }

        let sentence = extractSentence(containing: matched == "time" ? "at" : matched, from: original)
        let extractedDate = parseFuzzyDate(from: text)

        return ChatMemorySuggestion(
            type: .calendarCandidate,
            title: "Calendar",
            summary: sentence,
            confidence: hasTime ? 0.85 : 0.65,
            sourceMessageIds: [],
            extractedDate: extractedDate
        )
    }

    private func detectFollowUp(_ text: String, original: String) -> ChatMemorySuggestion? {
        let followUpPatterns = [
            "don't forget", "need to follow up", "waiting on",
            "remind me", "we should check", "follow up on",
            "make sure to", "don't let me forget"
        ]
        guard let matched = followUpPatterns.first(where: { text.contains($0) }) else { return nil }

        let sentence = extractSentence(containing: matched, from: original)
        return ChatMemorySuggestion(
            type: .followUp,
            title: "Follow Up",
            summary: sentence,
            confidence: 0.70,
            sourceMessageIds: []
        )
    }

    private func detectPrayerRequest(_ text: String, original: String) -> ChatMemorySuggestion? {
        let prayerPatterns = [
            "pray for", "please pray", "prayer request",
            "keep me in prayer", "lift up", "praying for",
            "need prayer", "prayer for"
        ]
        guard let matched = prayerPatterns.first(where: { text.contains($0) }) else { return nil }

        let sentence = extractSentence(containing: matched, from: original)
        return ChatMemorySuggestion(
            type: .prayerRequest,
            title: "Prayer Request",
            summary: sentence,
            confidence: 0.80,
            sourceMessageIds: []
        )
    }

    // MARK: - Helpers

    private func shouldSuggest(type: ChatMemoryItemType, sourceIds: [String]) -> Bool {
        // Check type suppression (3 dismissals → permanent suppress for session)
        if let count = typeDismissalCounts[type], count >= 3 {
            return false
        }

        // Check per-type cooldown (5 min after dismiss)
        if let lastDismiss = typeDismissals[type],
           Date().timeIntervalSince(lastDismiss) < 300 {
            return false
        }

        // Check source overlap
        let overlap = Set(sourceIds).intersection(seenSourceIds)
        if !overlap.isEmpty {
            return false
        }

        return true
    }

    private func extractSentence(containing keyword: String, from text: String) -> String {
        // Find the sentence containing the keyword
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
        let lowercased = keyword.lowercased()
        if let match = sentences.first(where: { $0.lowercased().contains(lowercased) }) {
            let trimmed = match.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 120 {
                return String(trimmed.prefix(117)) + "..."
            }
            return trimmed
        }
        // Fallback: return first 120 chars
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 120 {
            return String(trimmed.prefix(117)) + "..."
        }
        return trimmed
    }

    private func parseFuzzyDate(from text: String) -> Date? {
        let calendar = Calendar.current
        let now = Date()

        if text.contains("tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: now)
        }
        if text.contains("tonight") {
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = 20
            return calendar.date(from: components)
        }
        if text.contains("this weekend") {
            let weekday = calendar.component(.weekday, from: now)
            let daysToSaturday = (7 - weekday) % 7
            return calendar.date(byAdding: .day, value: max(daysToSaturday, 1), to: now)
        }
        if text.contains("next week") {
            return calendar.date(byAdding: .weekOfYear, value: 1, to: now)
        }

        // Day-of-week detection
        let dayMap: [(String, Int)] = [
            ("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4),
            ("thursday", 5), ("friday", 6), ("saturday", 7)
        ]
        for (dayName, targetWeekday) in dayMap {
            if text.contains("next \(dayName)") || text.contains("on \(dayName)") {
                let currentWeekday = calendar.component(.weekday, from: now)
                var daysAhead = targetWeekday - currentWeekday
                if text.contains("next") {
                    daysAhead += 7
                }
                if daysAhead <= 0 { daysAhead += 7 }
                return calendar.date(byAdding: .day, value: daysAhead, to: now)
            }
        }

        return nil
    }
}

// MARK: - Extractable Message Protocol

/// Lightweight message representation for extraction.
/// Adapts from AppMessage without coupling to Firestore models.
struct ExtractableMessage: Identifiable {
    let id: String
    let text: String
    let senderId: String
    let timestamp: Date
}

// MARK: - Suggestion Helper Extension

private extension ChatMemorySuggestion {
    func withSourceIds(_ ids: [String]) -> ChatMemorySuggestion {
        ChatMemorySuggestion(
            type: type,
            title: title,
            summary: summary,
            confidence: confidence,
            sourceMessageIds: ids,
            extractedDate: extractedDate
        )
    }
}
