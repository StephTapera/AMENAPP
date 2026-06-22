//
//  PostIntentDetector.swift
//  AMENAPP
//
//  Detects post intent from text to drive composer adaptations.
//  Pure local heuristic — no network calls, runs entirely on-device.
//
//  Design system: white background, black text (AmenColorScheme)
//  Dependencies: Foundation only.
//

import Foundation

// MARK: - PostIntent

/// The detected purpose of a post, used to adapt the composer UI and
/// surface contextually relevant actions and prompts.
enum PostIntent: String, CaseIterable {
    case reflection    = "reflection"
    case testimony     = "testimony"
    case prayerRequest = "prayerRequest"
    case sermonClip    = "sermonClip"
    case teaching      = "teaching"
    case eventRecap    = "eventRecap"
    case announcement  = "announcement"
    case question      = "question"
    case gratitude     = "gratitude"
    case missionUpdate = "missionUpdate"
    case resource      = "resource"
    case general       = "general"

    // MARK: Composer Placeholder

    /// Text shown in the composer text field when this intent is detected.
    var composerPlaceholder: String {
        switch self {
        case .reflection:
            return "Share what's on your heart…"
        case .testimony:
            return "Tell what God has done…"
        case .prayerRequest:
            return "Share your prayer need with the community…"
        case .sermonClip:
            return "Add context for this message clip…"
        case .teaching:
            return "Share the key insight from this teaching…"
        case .eventRecap:
            return "Describe how it went…"
        case .announcement:
            return "Share the details…"
        case .question:
            return "Ask your question…"
        case .gratitude:
            return "Share what you're grateful for…"
        case .missionUpdate:
            return "Share an update on the work…"
        case .resource:
            return "Describe this resource…"
        case .general:
            return "What's on your mind?"
        }
    }

    // MARK: Suggested Actions

    /// Chip labels shown in the composer when this intent is detected.
    var suggestedActions: [String] {
        switch self {
        case .reflection:
            return ["Add Scripture", "Make Private", "Save as Note"]
        case .testimony:
            return ["Add Scripture", "Tag Church", "Save as Memory"]
        case .prayerRequest:
            return ["Add to Prayer Wall", "Make Anonymous", "Tag Church"]
        case .sermonClip:
            return ["Extract Key Points", "Add Transcript", "Tag Speaker"]
        case .teaching:
            return ["Add Study Guide", "Attach Resource", "Tag Series"]
        case .eventRecap:
            return ["Add Photos", "Tag Attendees", "Save as Memory"]
        case .announcement:
            return ["Set Reminder", "Add RSVP Link", "Pin to Church"]
        case .question:
            return ["Enable Replies", "Make Anonymous", "Tag Topic"]
        case .gratitude:
            return ["Add Scripture", "Tag Community", "Share Publicly"]
        case .missionUpdate:
            return ["Add Goal Progress", "Attach Report", "Tag Organization"]
        case .resource:
            return ["Attach Link", "Tag Category", "Pin to Space"]
        case .general:
            return ["Add Media", "Tag Community", "Set Audience"]
        }
    }

    // MARK: Audience Hint

    /// Optional visibility suggestion surfaced subtly in the composer.
    /// `nil` means no audience hint is shown for this intent.
    var audienceHint: String? {
        switch self {
        case .reflection:
            return "Consider sharing with your circle only"
        case .testimony:
            return nil    // Testimonies are typically public
        case .prayerRequest:
            return "Shared with your church community"
        case .sermonClip:
            return nil    // Church-wide by default
        case .teaching:
            return nil
        case .eventRecap:
            return nil
        case .announcement:
            return "Visible to followers and church members"
        case .question:
            return nil
        case .gratitude:
            return nil
        case .missionUpdate:
            return "Visible to supporters and followers"
        case .resource:
            return nil
        case .general:
            return nil
        }
    }
}

// MARK: - IntentScore (internal)

private struct IntentScore {
    let intent: PostIntent
    var score: Double
}

// MARK: - PostIntentDetector

/// Pure local heuristic intent detector. No network calls, runs on-device.
///
/// Usage:
/// ```swift
/// let result = PostIntentDetector.shared.detect(text: composerText)
/// // result.intent, result.confidence
/// ```
final class PostIntentDetector {

    static let shared = PostIntentDetector()
    private init() {}

    // MARK: - Keyword Tables

    /// Keywords and phrases associated with each intent.
    /// Each entry is a tuple of (phrase, weight) where weight amplifies common
    /// strong indicators vs. weaker single words.
    private let keywordMap: [PostIntent: [(phrase: String, weight: Double)]] = [

        .testimony: [
            ("god did", 2.0), ("testimony", 2.0), ("what he did", 2.0),
            ("breakthrough", 1.5), ("healed", 1.5), ("delivered", 1.5),
            ("god moved", 2.0), ("miracle", 1.5), ("god showed up", 2.0),
            ("i was healed", 2.0), ("he came through", 1.5), ("blessed me", 1.2),
            ("i prayed and", 1.5), ("god answered", 2.0), ("he restored", 1.5),
            ("out of nowhere", 1.0), ("had to share", 1.2), ("had to tell", 1.2),
            ("i can't keep quiet", 1.5), ("watch what god", 1.5),
            ("just want to share", 1.0), ("share my testimony", 2.0)
        ],

        .prayerRequest: [
            ("please pray", 2.5), ("prayer request", 2.5), ("asking for prayer", 2.5),
            ("need prayer", 2.0), ("pray for me", 2.0), ("keep me in prayer", 2.0),
            ("i need prayers", 2.0), ("lift me up", 1.5), ("pray with me", 2.0),
            ("going through", 1.2), ("in a hard season", 1.5), ("struggling", 1.0),
            ("believing god for", 1.5), ("trusting god through", 1.5),
            ("intercession", 1.5), ("cover me in prayer", 2.0)
        ],

        .sermonClip: [
            ("sermon", 2.0), ("preached", 1.8), ("pastor", 1.5),
            ("message today", 2.0), ("sunday message", 2.0), ("he preached", 1.8),
            ("she preached", 1.8), ("the word today", 1.8), ("from the pulpit", 2.0),
            ("this clip", 1.5), ("watch this", 1.0), ("clip from", 1.5),
            ("full sermon", 2.0), ("at church today", 1.5), ("watch the message", 1.8),
            ("this message", 1.2), ("hit different", 1.0), ("had me in tears", 1.0)
        ],

        .teaching: [
            ("key point", 2.0), ("lesson", 1.5), ("today we learned", 2.0),
            ("study", 1.2), ("dive into", 1.5), ("bible study", 2.0),
            ("this week's study", 2.0), ("teaching", 1.5), ("breaking down", 1.5),
            ("what the text says", 1.8), ("in the greek", 1.8), ("in the hebrew", 1.8),
            ("context is", 1.5), ("exegesis", 2.0), ("expository", 2.0),
            ("application point", 2.0), ("three points", 1.5), ("takeaway", 1.2),
            ("deep dive", 1.5), ("unpack", 1.2), ("unpackage", 1.2)
        ],

        .eventRecap: [
            ("last night", 1.8), ("last sunday", 1.8), ("great time", 1.5),
            ("we gathered", 2.0), ("event", 1.2), ("conference", 1.5),
            ("revival", 1.8), ("what a night", 1.8), ("such an amazing", 1.2),
            ("incredible service", 1.8), ("incredible night", 1.8),
            ("we had", 1.0), ("community came out", 1.8), ("packed house", 1.5),
            ("worship was incredible", 1.8), ("atmosphere was", 1.2),
            ("couldn't miss", 1.2), ("recap", 2.0), ("highlights from", 2.0)
        ],

        .announcement: [
            ("this sunday", 2.0), ("join us", 2.0), ("upcoming", 1.8),
            ("happening", 1.5), ("registration", 2.0), ("register now", 2.0),
            ("save the date", 2.0), ("mark your calendar", 2.0),
            ("don't miss", 1.8), ("we're hosting", 2.0), ("rsvp", 2.0),
            ("link in bio", 1.5), ("doors open", 1.8), ("starts at", 1.5),
            ("free event", 1.8), ("open to all", 1.5), ("invite your friends", 1.5),
            ("spread the word", 1.2), ("announcement", 2.0), ("next week", 1.2)
        ],

        .question: [
            ("what do you think", 2.0), ("anyone else", 1.8), ("how do i", 1.8),
            ("thoughts on", 1.8), ("anyone know", 1.8), ("can someone", 1.5),
            ("help me understand", 2.0), ("genuine question", 2.0),
            ("serious question", 2.0), ("quick question", 2.0),
            ("is it just me", 1.8), ("am i the only", 1.8), ("need advice", 1.8),
            ("seeking counsel", 2.0), ("what does the bible say about", 2.0),
            ("does god", 1.2), ("how should", 1.2)
        ],

        .gratitude: [
            ("thankful", 2.0), ("grateful", 2.0), ("blessed", 1.5),
            ("thank god", 2.0), ("appreciate", 1.5), ("giving thanks", 2.0),
            ("so grateful", 2.0), ("so blessed", 1.8), ("count my blessings", 2.0),
            ("i am grateful", 2.0), ("thank you lord", 2.0), ("praise report", 2.0),
            ("god is good", 1.8), ("all things work together", 1.8),
            ("couldn't have done", 1.2), ("shoutout to god", 2.0),
            ("honoring god", 1.5), ("filled with gratitude", 2.0)
        ],

        .missionUpdate: [
            ("mission", 1.5), ("we're building", 1.8), ("organization", 1.2),
            ("impact", 1.2), ("outreach", 2.0), ("ministry update", 2.0),
            ("mission trip", 2.0), ("serving in", 1.8), ("deployed to", 1.5),
            ("on the ground", 1.5), ("progress update", 1.8), ("goal reached", 1.8),
            ("campaign", 1.5), ("nonprofit", 1.8), ("501c3", 2.0),
            ("fundraising", 1.8), ("donors", 1.5), ("lives changed", 1.5),
            ("we served", 1.8), ("meals provided", 1.8), ("families helped", 1.8)
        ],

        .resource: [
            ("check out this", 1.5), ("link below", 1.8), ("free resource", 2.0),
            ("download", 1.5), ("ebook", 2.0), ("guide", 1.5), ("template", 1.8),
            ("worksheet", 2.0), ("devotional", 1.5), ("reading plan", 2.0),
            ("podcast episode", 1.8), ("article", 1.2), ("blog post", 1.5),
            ("study guide", 2.0), ("curriculum", 2.0), ("resources for", 1.8),
            ("here's a resource", 2.0), ("sharing this", 1.2), ("found this helpful", 1.8)
        ],

        .reflection: [
            ("thinking about", 1.5), ("reflecting on", 2.0), ("god showed me", 2.0),
            ("god spoke to me", 2.0), ("i've been pondering", 2.0),
            ("meditating on", 2.0), ("the lord reminded me", 2.0),
            ("journal entry", 2.0), ("writing this down", 1.5),
            ("can't shake this thought", 2.0), ("this verse", 1.5),
            ("hit me today", 1.5), ("sat with this", 1.8), ("quiet time", 1.8),
            ("morning devotion", 1.8), ("devotional thought", 1.8),
            ("processing", 1.2), ("in my heart", 1.5), ("deep in my spirit", 1.8)
        ]
    ]

    // MARK: - Public API

    /// Detects the most likely post intent from partial or complete text.
    ///
    /// Uses keyword/phrase scoring. Scores are normalized and returned
    /// with a confidence value in 0.0–1.0.
    ///
    /// - Parameter text: Composer text, may be partial.
    /// - Returns: Top-scoring intent and its confidence.
    func detect(text: String) -> (intent: PostIntent, confidence: Double) {
        let results = detectAll(text: text)
        return results.first ?? (.general, 0.5)
    }

    /// Returns all detected intents sorted by confidence (highest first).
    ///
    /// Useful for showing secondary intent chips in the composer.
    func detectAll(text: String) -> [(intent: PostIntent, confidence: Double)] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return [(.general, 0.5)]
        }

        let lower = text.lowercased()
        // Count question marks for the question intent boost
        let questionMarkCount = text.filter { $0 == "?" }.count

        var scores: [PostIntent: Double] = [:]

        for (intent, entries) in keywordMap {
            var rawScore = 0.0
            for entry in entries {
                if lower.contains(entry.phrase) {
                    rawScore += entry.weight
                }
            }
            // Boost .question intent for each question mark
            if intent == .question {
                rawScore += Double(questionMarkCount) * 1.2
            }
            if rawScore > 0 { scores[intent] = rawScore }
        }

        guard !scores.isEmpty else { return [(.general, 0.5)] }

        // Normalize scores relative to the max
        let maxScore = scores.values.max() ?? 1.0
        let sorted = scores
            .map { (intent: $0.key, confidence: min($0.value / maxScore, 1.0)) }
            .sorted { $0.confidence > $1.confidence }

        // Append .general as fallback with minimum confidence
        var results = sorted
        if !results.contains(where: { $0.intent == .general }) {
            let fallbackConf = (sorted.first?.confidence ?? 0.5) * 0.4
            results.append((.general, fallbackConf))
        }
        return results
    }

    /// Detects intent from media type and account context when text is short or empty.
    ///
    /// Used to seed the composer before the user types.
    ///
    /// - Parameters:
    ///   - hasVideo: `true` if a video has been attached.
    ///   - hasPhoto: `true` if a photo has been attached.
    ///   - accountType: `"personal"`, `"church"`, or `"business"`.
    ///   - isChurchAdmin: `true` if the user has church admin privileges.
    func detectFromContext(
        hasVideo: Bool,
        hasPhoto: Bool,
        accountType: String,
        isChurchAdmin: Bool
    ) -> PostIntent {
        if hasVideo && isChurchAdmin          { return .sermonClip }
        if hasVideo && accountType == "personal" { return .testimony }
        if hasVideo && accountType == "church"   { return .eventRecap }
        if hasPhoto && isChurchAdmin          { return .announcement }
        if hasPhoto && accountType == "church"   { return .eventRecap }
        if hasPhoto && accountType == "business" { return .missionUpdate }
        return .general
    }
}
