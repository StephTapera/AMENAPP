// AmenSmartContextDetectionEngine.swift
// AMENAPP — Deterministic (no LLM) text context parser
//
// Detects links, dates, music mentions, task triggers, memory phrases, and
// safety signals in any user-typed string. Used by both messaging (DMs / group
// threads) and posting (CreatePostView) surfaces.
//
// NO LLM calls are made here. All detection is local and synchronous inside the
// Swift actor, then returned as a value type result. Callers should call
// `detect(in:)` from a Task so the actor hop stays off the main thread.
//
// Safety signals:
//   · V1 ships with a deterministic crisis keyword baseline.
//   · Keywords can be replaced at runtime via the Aegis/Remote Config path.
//   · The engine NEVER blocks content — it only surfaces informational chips.
//   · Human moderators make all final decisions.

import Foundation

// MARK: - Result models

struct AmenDetectedLink: Identifiable {
    let id: UUID
    let url: URL
    let displayText: String     // host name or raw URL text
}

struct AmenDetectedDate: Identifiable {
    let id: UUID
    let displayText: String     // e.g. "tomorrow at 6 PM"
    let resolvedDate: Date?     // nil when NSDataDetector cannot resolve
}

struct AmenDetectedMusicMention: Identifiable {
    let id: UUID
    let mention: String         // e.g. "Church Clothes by Lecrae"
    let context: String         // surrounding sentence (≤ 100 chars)
}

struct AmenDetectedTask: Identifiable {
    let id: UUID
    let phrase: String          // matched trigger phrase, e.g. "let me know"
}

struct AmenDetectedMemoryPhrase: Identifiable {
    let id: UUID
    let phrase: String          // matched trigger phrase, e.g. "remember when"
}

enum AmenSafetySignalSeverity {
    /// Show an informational suggestion chip only.
    case info
    /// Suggest a support resource (e.g. "Would you like to talk to someone?").
    /// Never auto-blocks — human moderation decides.
    case warning
}

struct AmenDetectedSafetySignal: Identifiable {
    let id: UUID
    let category: String                    // e.g. "crisis", "self-harm"
    let severity: AmenSafetySignalSeverity
}

// MARK: - Aggregate result

struct AmenTextContextDetectionResult {
    let links: [AmenDetectedLink]
    let dates: [AmenDetectedDate]
    let musicMentions: [AmenDetectedMusicMention]
    let tasks: [AmenDetectedTask]
    let memoryPhrases: [AmenDetectedMemoryPhrase]
    let safetySignals: [AmenDetectedSafetySignal]

    var isEmpty: Bool {
        links.isEmpty
            && dates.isEmpty
            && musicMentions.isEmpty
            && tasks.isEmpty
            && memoryPhrases.isEmpty
            && safetySignals.isEmpty
    }

    var totalCount: Int {
        links.count
            + dates.count
            + musicMentions.count
            + tasks.count
            + memoryPhrases.count
            + safetySignals.count
    }
}

// MARK: - Engine

/// Deterministic, actor-isolated context detection engine.
///
/// All heavy regex / NSDataDetector work happens inside the actor, so callers
/// can `await` from any async context without blocking the main thread.
///
/// Usage:
/// ```swift
/// let result = await AmenSmartContextDetectionEngine.shared.detect(in: text)
/// let chips  = AmenContextDetectionBridge.toInsightChips(from: result)
/// ```
actor AmenSmartContextDetectionEngine {
    static let shared = AmenSmartContextDetectionEngine()

    // MARK: - NSDataDetectors (lazy so init() stays infallible)

    private lazy var linkDetector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()

    private lazy var dateDetector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    }()

    // MARK: - Music heuristics

    /// Lower-cased keywords that suggest a music context in the surrounding sentence.
    private let musicKeywords: [String] = [
        "album", "song", "track", "playlist", "mixtape", "ep", "single",
        "music by", "produced by", "feat.", "ft.", "remix"
    ]

    /// Matches patterns like "Church Clothes by Lecrae" (Title Case "X by Y").
    /// Compiled once. May be nil if the pattern is somehow invalid (should never happen).
    private lazy var musicByPattern: NSRegularExpression? = {
        // Matches one or more Title-Case words, followed by " by ", followed by a
        // Title-Case word — keeps false-positive rate low.
        try? NSRegularExpression(
            pattern: #"\b([A-Z][a-zA-Z]+(?:\s[A-Z][a-zA-Z]+)*)\s+by\s+[A-Z][a-zA-Z]"#,
            options: []
        )
    }()

    // MARK: - Task trigger phrases (lower-cased)

    private let taskTriggers: [String] = [
        "let me know",
        "send me",
        "follow up",
        "remind me",
        "don't forget",
        "dont forget",
        "can you",
        "could you",
        "will you",
        "would you mind",
        "please send",
        "get back to me"
    ]

    // MARK: - Memory phrase triggers (lower-cased)

    private let memoryTriggers: [String] = [
        "remember when",
        "i'll never forget",
        "ill never forget",
        "back when",
        "that time we",
        "do you remember",
        "throwback",
        "when we",
        "years ago",
        "back in the day"
    ]

    // MARK: - Safety signal configuration
    //
    // V1 ships with a deterministic baseline so crisis detection never becomes
    // silently empty when runtime config is absent. Aegis/Remote Config can
    // replace it without an App Store release.
    //
    // Structure: (keyword: String, category: String, severity: AmenSafetySignalSeverity)
    // The engine never blocks — it only surfaces a chip the caller can act on.

    private static let defaultCrisisKeywords: [(keyword: String, category: String, severity: AmenSafetySignalSeverity)] = [
        ("kill myself", "self-harm", .warning),
        ("end my life", "self-harm", .warning),
        ("suicide", "self-harm", .warning),
        ("hurt myself", "self-harm", .warning),
        ("self harm", "self-harm", .warning),
        ("can't go on", "self-harm", .warning),
        ("want to die", "self-harm", .warning),
        ("abuse", "abuse", .warning),
        ("being threatened", "abuse", .warning),
        ("not safe at home", "abuse", .warning),
        ("domestic violence", "abuse", .warning),
        ("trafficking", "exploitation", .warning),
        ("grooming", "exploitation", .warning),
        ("blackmail", "exploitation", .warning),
        ("sextortion", "exploitation", .warning)
    ]

    private var runtimeCrisisKeywords: [(keyword: String, category: String, severity: AmenSafetySignalSeverity)] = AmenSmartContextDetectionEngine.defaultCrisisKeywords

    // MARK: - Public API

    /// Run all detectors against `text` and return a consolidated result.
    ///
    /// - Parameter text: Raw user-typed string. Must not be pre-processed by the caller.
    /// - Returns: An `AmenTextContextDetectionResult`; call `.isEmpty` to skip chip rendering.
    func detect(in text: String) -> AmenTextContextDetectionResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AmenTextContextDetectionResult(
                links: [], dates: [], musicMentions: [],
                tasks: [], memoryPhrases: [], safetySignals: []
            )
        }
        return AmenTextContextDetectionResult(
            links: detectLinks(in: text),
            dates: detectDates(in: text),
            musicMentions: detectMusicMentions(in: text),
            tasks: detectTasks(in: text),
            memoryPhrases: detectMemoryPhrases(in: text),
            safetySignals: detectSafetySignals(in: text)
        )
    }

    /// Allows the app delegate / Remote Config observer to push a curated crisis
    /// keyword list at runtime without a new build.
    ///
    /// - Parameter keywords: Tuples of (keyword, category, severity).
    func configureRuntimeCrisisKeywords(
        _ keywords: [(keyword: String, category: String, severity: AmenSafetySignalSeverity)]
    ) {
        runtimeCrisisKeywords = keywords.isEmpty ? Self.defaultCrisisKeywords : keywords
    }

    // MARK: - Link detection

    private func detectLinks(in text: String) -> [AmenDetectedLink] {
        guard let detector = linkDetector else { return [] }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = detector.matches(in: text, options: [], range: range)

        return matches.compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            let rawString = String(text[swiftRange])

            // NSDataDetector sometimes emits partial strings; validate with URL
            let candidateURL: URL?
            if rawString.hasPrefix("http://") || rawString.hasPrefix("https://") {
                candidateURL = URL(string: rawString)
            } else {
                candidateURL = URL(string: "https://\(rawString)")
            }
            guard let url = candidateURL else { return nil }

            let display = url.host ?? rawString
            return AmenDetectedLink(id: UUID(), url: url, displayText: display)
        }
    }

    // MARK: - Date detection

    private func detectDates(in text: String) -> [AmenDetectedDate] {
        guard let detector = dateDetector else { return [] }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = detector.matches(in: text, options: [], range: range)

        return matches.compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            let displayText = String(text[swiftRange])
            return AmenDetectedDate(id: UUID(), displayText: displayText, resolvedDate: match.date)
        }
    }

    // MARK: - Music mention detection

    private func detectMusicMentions(in text: String) -> [AmenDetectedMusicMention] {
        var results: [AmenDetectedMusicMention] = []
        let lowered = text.lowercased()

        // 1. Keyword scan (catches "new album", "saved playlist", etc.)
        var seenSentences = Set<String>()
        for keyword in musicKeywords where lowered.contains(keyword) {
            let sentence = extractSentence(containing: keyword, from: text, windowBefore: 40, windowAfter: 60)
            guard !seenSentences.contains(sentence) else { continue }
            seenSentences.insert(sentence)
            results.append(
                AmenDetectedMusicMention(id: UUID(), mention: sentence, context: text)
            )
        }

        // 2. Pattern scan for "Title by Artist" (Title Case)
        if let pattern = musicByPattern {
            let nsText = text as NSString
            let range = NSRange(location: 0, length: nsText.length)
            let matches = pattern.matches(in: text, options: [], range: range)
            for match in matches {
                guard let swiftRange = Range(match.range, in: text) else { continue }
                let mention = String(text[swiftRange])
                guard !seenSentences.contains(mention) else { continue }
                seenSentences.insert(mention)
                results.append(
                    AmenDetectedMusicMention(id: UUID(), mention: mention, context: text)
                )
            }
        }

        return results
    }

    // MARK: - Task trigger detection

    private func detectTasks(in text: String) -> [AmenDetectedTask] {
        let lowered = text.lowercased()
        return taskTriggers.compactMap { trigger in
            guard lowered.contains(trigger) else { return nil }
            return AmenDetectedTask(id: UUID(), phrase: trigger)
        }
    }

    // MARK: - Memory phrase detection

    private func detectMemoryPhrases(in text: String) -> [AmenDetectedMemoryPhrase] {
        let lowered = text.lowercased()
        return memoryTriggers.compactMap { trigger in
            guard lowered.contains(trigger) else { return nil }
            return AmenDetectedMemoryPhrase(id: UUID(), phrase: trigger)
        }
    }

    // MARK: - Safety signal detection

    private func detectSafetySignals(in text: String) -> [AmenDetectedSafetySignal] {
        let lowered = text.lowercased()
        var signals: [AmenDetectedSafetySignal] = []
        var seenCategories = Set<String>()

        for entry in runtimeCrisisKeywords where lowered.contains(entry.keyword) {
            // Emit at most one signal per category to avoid flooding the chip tray.
            guard !seenCategories.contains(entry.category) else { continue }
            seenCategories.insert(entry.category)
            signals.append(
                AmenDetectedSafetySignal(
                    id: UUID(),
                    category: entry.category,
                    severity: entry.severity
                )
            )
        }
        return signals
    }

    // MARK: - Sentence extraction helper

    /// Returns a trimmed snippet of `text` centered on `keyword`, up to
    /// `windowBefore + keyword.count + windowAfter` characters.
    ///
    /// - Parameters:
    ///   - keyword: Lower-cased keyword to locate. Searches `text.lowercased()`.
    ///   - text: Original (not lowercased) text to extract from.
    ///   - windowBefore: Maximum characters to include before the keyword.
    ///   - windowAfter: Maximum characters to include after the keyword end.
    private func extractSentence(
        containing keyword: String,
        from text: String,
        windowBefore: Int = 30,
        windowAfter: Int = 50
    ) -> String {
        let lowered = text.lowercased()
        guard let keywordRange = lowered.range(of: keyword) else { return keyword }

        // Walk back up to windowBefore characters, stopping at a sentence boundary
        let beforeStart = text.index(
            keywordRange.lowerBound,
            offsetBy: -windowBefore,
            limitedBy: text.startIndex
        ) ?? text.startIndex

        // Walk forward up to windowAfter characters past the keyword end
        let afterEnd = text.index(
            keywordRange.upperBound,
            offsetBy: windowAfter,
            limitedBy: text.endIndex
        ) ?? text.endIndex

        return String(text[beforeStart..<afterEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
