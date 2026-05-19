import Foundation

struct AmenFeedDirectionDetector {
    static let shared = AmenFeedDirectionDetector()
    private init() {}

    func detect(text: String) -> FeedDirectionDetectionResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { return .empty }
        let lower = trimmed.lowercased()

        var confidence: Double = 0
        var triggerPhrase: String? = nil
        var category: FeedDirectionLocalCategory = .unknown
        var summary: String? = nil

        // Strong triggers — explicit feed instruction openers
        let strongTriggers: [(String, FeedDirectionLocalCategory, String)] = [
            ("amen,", .feedMode, "Feed direction detected"),
            ("dear amen", .feedMode, "Feed direction detected"),
            ("dear algo", .feedMode, "Feed direction detected"),
            ("show me more", .moreOfTopic, "Show more of something"),
            ("show me less", .lessOfTopic, "Show less of something"),
            ("more of ", .moreOfTopic, "Show more content"),
            ("less of ", .lessOfTopic, "Reduce this content"),
            ("stop showing me", .lessOfTopic, "Stop showing a topic"),
            ("make my feed", .feedMode, "Feed adjustment"),
            ("i want my feed", .feedMode, "Feed adjustment"),
            ("my feed should", .feedMode, "Feed adjustment"),
            ("calmer feed", .emotionalState, "Calmer feed"),
            ("less drama", .lessOfTopic, "Less conflict-heavy content"),
            ("less politics", .lessOfTopic, "Reduce political content"),
            ("less arguments", .lessOfTopic, "Reduce conflict"),
            ("more scripture", .moreOfTopic, "More scripture content"),
            ("more worship", .moreOfTopic, "More worship content"),
            ("more testimonies", .moreOfTopic, "More testimonies"),
            ("more berean", .spiritualIntent, "Berean-style content"),
            ("berean mode", .spiritualIntent, "Berean mode"),
            ("local church", .moreOfTopic, "Local church content"),
            ("bible study", .spiritualIntent, "Bible study content"),
            ("keep sundays", .temporalPreference, "Sunday preference"),
            ("sunday rest", .temporalPreference, "Sunday rest mode"),
            ("sabbath", .temporalPreference, "Sabbath/rest mode"),
        ]

        for (phrase, cat, sum) in strongTriggers {
            if lower.contains(phrase) {
                confidence = max(confidence, 0.80)
                if triggerPhrase == nil { triggerPhrase = phrase; category = cat; summary = sum }
            }
        }

        // Medium triggers — emotional/state signals
        let mediumTriggers: [(String, FeedDirectionLocalCategory, String)] = [
            ("overwhelmed", .emotionalState, "Calmer, lower-stimulation feed"),
            ("anxious", .emotionalState, "Calmer content"),
            ("distracted", .emotionalState, "More focused content"),
            ("calm my", .emotionalState, "Calmer feed"),
            ("feel better", .emotionalState, "More uplifting content"),
            ("less noise", .emotionalState, "Reduce stimulation"),
            ("less outrage", .lessOfTopic, "Less outrage-heavy content"),
            ("less conflict", .lessOfTopic, "Less conflict"),
            ("more prayer", .moreOfTopic, "More prayer content"),
            ("more devotional", .moreOfTopic, "More devotionals"),
            ("worship music", .moreOfTopic, "Worship music"),
            ("scripture breakdown", .spiritualIntent, "Scripture teaching"),
            ("teach scripture", .spiritualIntent, "Scripture teaching"),
            ("theology", .spiritualIntent, "Theological content"),
        ]

        for (phrase, cat, sum) in mediumTriggers {
            if lower.contains(phrase) {
                confidence = max(confidence, 0.65)
                if triggerPhrase == nil { triggerPhrase = phrase; category = cat; summary = sum }
            }
        }

        // Boost confidence if text starts with "Amen" or action verb + topic combo
        if lower.hasPrefix("amen") { confidence = min(confidence + 0.10, 1.0) }
        if lower.hasPrefix("show") || lower.hasPrefix("make") || lower.hasPrefix("keep") {
            confidence = min(confidence + 0.05, 1.0)
        }

        guard confidence >= 0.55 else { return .empty }
        return FeedDirectionDetectionResult(
            isDetected: true,
            confidence: confidence,
            triggerPhrase: triggerPhrase,
            detectedCategory: category,
            suggestedSummary: summary
        )
    }

    /// Builds a sensible default draft from detection result and raw text.
    func buildDraft(from result: FeedDirectionDetectionResult, rawText: String) -> FeedDirectionDraft {
        let defaultDuration: FeedDirectionDuration
        let defaultSurfaces: [FeedSurface]

        switch result.detectedCategory {
        case .emotionalState:
            defaultDuration = .today
            defaultSurfaces = [.home, .media, .notifications]
        case .temporalPreference:
            defaultDuration = .always
            defaultSurfaces = [.home, .media]
        case .spiritualIntent:
            defaultDuration = .always
            defaultSurfaces = [.home, .media, .suggestedCreators]
        default:
            defaultDuration = .today
            defaultSurfaces = [.home, .media]
        }

        return FeedDirectionDraft(
            rawText: rawText,
            interpretedSummary: result.suggestedSummary,
            intentType: intentType(for: result.detectedCategory ?? .unknown),
            duration: defaultDuration,
            intensity: .medium,
            visibility: .privateOnly,
            affectedSurfaces: defaultSurfaces
        )
    }

    private func intentType(for category: FeedDirectionLocalCategory) -> FeedDirectionIntentType {
        switch category {
        case .moreOfTopic: return .increaseTopic
        case .lessOfTopic: return .decreaseTopic
        case .emotionalState: return .emotionalRegulation
        case .spiritualIntent: return .spiritualGrowth
        case .temporalPreference: return .timeBasedPreference
        case .feedMode: return .unknown
        case .contentSafety: return .safetyConcern
        case .creatorPreference: return .creatorAffinity
        case .unknown: return .unknown
        }
    }
}
