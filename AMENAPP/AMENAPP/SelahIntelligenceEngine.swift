import Foundation

// MARK: - Selah Intelligence Engine
// Local, on-device scoring for Selah Media OS. Zero network requests.
// All scores are deterministic given the same inputs — safe to call freely.

final class SelahIntelligenceEngine {
    static let shared = SelahIntelligenceEngine()
    private init() {}

    // MARK: - Media Ranking

    /// Ranks media items by relevance to the current session context.
    func rankMediaItems(
        _ items: [SelahMediaItem],
        context: SelahSessionContext
    ) -> [SelahRankedMedia] {
        items
            .map { item in
                let score = scoreMediaItem(item, context: context)
                let reason = matchReason(for: item, context: context)
                return SelahRankedMedia(item: item, score: score, matchReason: reason)
            }
            .sorted { $0.score > $1.score }
    }

    private func scoreMediaItem(
        _ item: SelahMediaItem,
        context: SelahSessionContext
    ) -> Double {
        var score = 0.0

        // Category overlap with recent session interest
        let itemCategories = item.meaningTags.compactMap {
            SelahMeaningCategory(rawValue: $0.category)
        }
        let overlap = Set(itemCategories).intersection(Set(context.recentMeaningCategories))
        score += Double(overlap.count) * 0.25

        // Scripture ref overlap
        if let ref = item.scriptureRef,
           context.recentScriptureRefs.contains(where: { $0.hasPrefix(ref.prefix(5)) }) {
            score += 0.20
        }

        // Recency boost (decay over 7 days)
        let age = Date().timeIntervalSince(item.createdAt) / 86_400
        score += max(0, 0.15 * (1 - min(age / 7, 1)))

        // Sunday morning boost for worship/community content
        if context.dayOfWeek == 1 {
            let hasSundayCategory = itemCategories.contains(where: { $0 == .worship || $0 == .community })
            if hasSundayCategory { score += 0.15 }
        }

        // Time-of-day alignment
        switch context.timeOfDay {
        case .earlyMorning, .morning:
            if itemCategories.contains(.faith) || itemCategories.contains(.gratitude) { score += 0.10 }
        case .evening, .lateNight:
            if itemCategories.contains(.rest) || itemCategories.contains(.hope) { score += 0.10 }
        default:
            break
        }

        // Quiet hours — surface contemplative content
        if context.isInQuietHours && itemCategories.contains(.rest) { score += 0.12 }

        // Engagement signal: items with saves suggest higher quality
        let saveBoost = min(Double(item.saveCount) / 50.0, 0.10)
        score += saveBoost

        return min(score, 1.0)
    }

    private func matchReason(
        for item: SelahMediaItem,
        context: SelahSessionContext
    ) -> String {
        let itemCategories = item.meaningTags.compactMap {
            SelahMeaningCategory(rawValue: $0.category)
        }
        let overlap = Set(itemCategories).intersection(Set(context.recentMeaningCategories))

        if let first = overlap.first { return "Matches your \(first.rawValue) theme" }
        if item.scriptureRef != nil { return "Scripture-anchored moment" }
        if context.dayOfWeek == 1 { return "Relevant for today" }
        return "Meaningful content"
    }

    // MARK: - Mode Suggestion

    /// Suggests which mode the user should transition to next.
    func suggestNextMode(from context: SelahSessionContext) -> SelahMediaMode {
        // After long media browsing, suggest memory or pause
        if context.mediaViewedCount > 8 && context.currentMode == .media {
            return .memory
        }
        // After a while in memory, suggest a continuation
        if context.currentMode == .memory && context.sessionDurationSeconds > 300 {
            return .continue_
        }
        // Evening / quiet hours → Pause
        if context.isInQuietHours || context.timeOfDay == .lateNight {
            return .pause
        }
        // Morning → Media (fresh content)
        if context.timeOfDay == .earlyMorning || context.timeOfDay == .morning {
            return .media
        }
        // Default: stay in current mode
        return context.currentMode
    }

    // MARK: - Rest Signal

    /// Returns true when the session patterns suggest the user needs a Pause.
    func detectRestSignal(from context: SelahSessionContext) -> Bool {
        context.isInQuietHours
            || context.timeOfDay == .lateNight
            || context.sessionDurationSeconds > 1800
            || (context.currentMode == .media && context.mediaViewedCount > 15)
    }

    // MARK: - Meaning Relevance Scoring

    func scoreMeaningRelevance(tag: SelahMeaningTag, in item: SelahMediaItem) -> Double {
        var score = 0.0
        // Same category match
        if item.meaningTags.contains(where: { $0.category == tag.category }) { score += 0.6 }
        // Scripture ref alignment
        if let tagRef = tag.scriptureRef, let itemRef = item.scriptureRef,
           tagRef.prefix(4) == itemRef.prefix(4) { score += 0.3 }
        // Label text overlap (simple word matching)
        let tagWords = Set(tag.label.lowercased().split(separator: " ").map(String.init))
        let captionWords = Set(item.caption.lowercased().split(separator: " ").map(String.init))
        if !tagWords.intersection(captionWords).isEmpty { score += 0.1 }
        return min(score, 1.0)
    }

    // MARK: - Context Window

    func buildContextWindow(
        from session: SelahSessionContext,
        memories: [SelahMediaMemory]
    ) -> SelahContextWindow {
        // Find dominant category from recent categories
        let categoryCounts = Dictionary(
            grouping: session.recentMeaningCategories, by: { $0 }
        ).mapValues { $0.count }
        let dominant = categoryCounts.max(by: { $0.value < $1.value })?.key

        let suggestedMode = suggestNextMode(from: session)
        let restSignal = detectRestSignal(from: session)
        let continuation = shapeSession(context: SelahContextWindow(
            dominantCategory: dominant,
            suggestedMode: suggestedMode,
            suggestedContinuation: .reflect,
            restSignalDetected: restSignal,
            meaningGraphNodes: [],
            sessionSummary: ""
        ))

        // Build meaning graph nodes from memories
        let allTags = memories.flatMap { $0.meaningTags }
        let uniqueTags = Array(
            Dictionary(grouping: allTags, by: { $0.category })
                .compactMapValues { $0.max(by: { $0.confidence < $1.confidence }) }
                .values
        ).prefix(12)

        let summary = buildSessionSummary(session: session, dominant: dominant)

        return SelahContextWindow(
            dominantCategory: dominant,
            suggestedMode: suggestedMode,
            suggestedContinuation: continuation,
            restSignalDetected: restSignal,
            meaningGraphNodes: Array(uniqueTags),
            sessionSummary: summary
        )
    }

    private func buildSessionSummary(
        session: SelahSessionContext,
        dominant: SelahMeaningCategory?
    ) -> String {
        let minutes = Int(session.sessionDurationSeconds / 60)
        let modeLabel = session.currentMode.label.lowercased()
        let catLabel = dominant?.rawValue ?? "spiritual"

        if minutes < 2 { return "Just getting started in \(modeLabel)" }
        if minutes < 10 { return "\(minutes) min exploring \(catLabel) content" }
        return "Deep \(minutes)-min \(catLabel) session"
    }

    // MARK: - Session Shaping

    /// Determines the best next spiritual action based on context.
    func shapeSession(context: SelahContextWindow) -> SelahContinuationAction {
        if context.restSignalDetected { return .rest }
        switch context.dominantCategory {
        case .faith, .identity:   return .reflect
        case .worship:            return .pray
        case .mission, .community: return .share
        case .grace, .suffering:  return .journal
        case .hope, .nature, .rest: return .rest
        default:                  return .study
        }
    }

    // MARK: - Meaning Graph

    /// Finds edges between two sets of meaning tags.
    func computeGraphEdgeStrength(
        between a: [SelahMeaningTag],
        and b: [SelahMeaningTag]
    ) -> Double {
        let catsA = Set(a.map { $0.category })
        let catsB = Set(b.map { $0.category })
        let sharedCats = catsA.intersection(catsB)

        let refsA = Set(a.compactMap { $0.scriptureRef?.prefix(5).description })
        let refsB = Set(b.compactMap { $0.scriptureRef?.prefix(5).description })
        let sharedRefs = refsA.intersection(refsB)

        let catScore = Double(sharedCats.count) * 0.3
        let refScore = Double(sharedRefs.count) * 0.4
        return min(catScore + refScore, 1.0)
    }

    /// Finds the N most related media items to a given item by meaning graph distance.
    func findRelatedMedia(
        to target: SelahMediaItem,
        in feed: [SelahMediaItem],
        limit: Int = 5
    ) -> [SelahMediaItem] {
        feed
            .filter { $0.id != target.id }
            .map { item -> (SelahMediaItem, Double) in
                let strength = computeGraphEdgeStrength(
                    between: target.meaningTags,
                    and: item.meaningTags
                )
                return (item, strength)
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    // MARK: - Continuation Generation

    func generateContinuations(
        from context: SelahContextWindow,
        userId: String,
        linkedMediaId: String? = nil
    ) -> [SelahMediaContinuation] {
        let actions: [SelahContinuationAction] = [
            context.suggestedContinuation,
            context.restSignalDetected ? .rest : .pray,
            .journal
        ]

        return actions.enumerated().map { index, action in
            let prompt = continuationPrompt(action: action, context: context)
            let scripture = context.meaningGraphNodes.first?.scriptureRef
            return SelahMediaContinuation(
                userId: userId,
                promptText: prompt,
                contextSummary: context.sessionSummary,
                action: action,
                linkedMediaId: linkedMediaId,
                scriptureRef: scripture,
                relevanceScore: 1.0 - Double(index) * 0.2
            )
        }
    }

    private func continuationPrompt(
        action: SelahContinuationAction,
        context: SelahContextWindow
    ) -> String {
        let cat = context.dominantCategory?.rawValue ?? "spiritual"
        switch action {
        case .reflect:  return "Take a moment to reflect on the \(cat) themes you've encountered."
        case .pray:     return "Turn what you've seen today into a personal prayer."
        case .share:    return "Share something from your \(cat) journey with your community."
        case .study:    return "Dive deeper into the scripture behind these moments."
        case .create:   return "Create something that captures what you've experienced."
        case .journal:  return "Write down what stood out to you in your \(cat) exploration."
        case .rest:     return "Take a quiet moment — rest and let these truths settle."
        }
    }

}
