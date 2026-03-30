// FeedIntelligenceService.swift
// AMEN App — Intentional Feed Intelligence + Anti-Doomscroll System
//
// Purpose: Augment the existing HomeFeedAlgorithm with:
//   - Spiritual value signals (prayer depth, testimony quality, scripture grounding)
//   - Content quality scoring (discussion depth, thoughtfulness)
//   - Anti-doomscroll session pacing
//   - Reflection prompts at key scroll intervals
//   - Session quality metrics (not vanity metrics)
//   - "Take a moment" breaks for passive, endless scrolling
//
// Integration: FeedIntelligenceService wraps HomeFeedAlgorithm.
// Existing scoring logic is preserved — this adds on top, never replaces.
//
// Anti-doomscroll philosophy:
//   - Track session scroll velocity, not just count
//   - Fast passive scrolling with no engagement = pacing prompt
//   - Meaningful engagement resets the pacing clock
//   - Never force-stop the user — always optional

import Foundation
import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Spiritual Value Scoring

/// Additional scoring signals for AMEN-specific content quality.
/// These extend HomeFeedAlgorithm without modifying it.
struct SpiritualValueScorer {

    /// Returns a 0–1.0 spiritual value boost for a post.
    /// High scores: scripture-grounded, prayerful, testimony-rich, discussion-deepening
    /// Low scores: surface-level, repeated/generic, rage-adjacent
    static func score(_ post: Post) -> Double {
        var score = 0.0
        let content = post.content.lowercased()

        // ── Scripture grounding ──────────────────────────────────────────
        // Posts that include scripture references are inherently more valuable
        let scripturePatterns = ["verse", "scripture", "psalm", "proverbs", "romans",
                                  "ephesians", "matthew", "john", "genesis", "corinthians",
                                  "philippians", "hebrews", "james", "peter", "isaiah",
                                  "jeremiah", "acts", "galatians", "colossians", "timothy"]
        let scriptureMatches = scripturePatterns.filter { content.contains($0) }.count
        score += min(0.3, Double(scriptureMatches) * 0.1)

        // Chapter:verse pattern (e.g., "3:16", "5:7") is strongest signal
        if content.range(of: "\\d+:\\d+", options: .regularExpression) != nil {
            score += 0.15
        }

        // ── Category value signals ───────────────────────────────────────
        switch post.category {
        case .prayer:
            score += 0.20    // Prayer is inherently high-value on AMEN
        case .testimonies:
            score += 0.18    // Personal transformation stories
        case .openTable:
            // Longer thoughtful posts have more value
            if post.content.count > 200 { score += 0.08 }
        default:
            break
        }

        // ── Discussion depth signals ─────────────────────────────────────
        // Posts that generate thoughtful replies (high comment relative to size)
        // Note: We don't want to boost purely controversial posts (handled by HomeFeedAlgorithm)
        if post.commentCount > 0 && post.amenCount > 0 {
            let ratio = Double(post.commentCount) / Double(max(1, post.amenCount))
            // Healthy discussion ratio 0.3–1.0 = valuable; >1.5 = controversy
            if ratio >= 0.3 && ratio <= 1.0 {
                score += min(0.15, ratio * 0.15)
            }
        }

        // ── Content length / depth ───────────────────────────────────────
        let wordCount = post.content.split(separator: " ").count
        if wordCount > 50 { score += 0.05 }   // Thoughtful length
        if wordCount > 150 { score += 0.05 }  // Substantial content

        // ── Questions encourage reflection ───────────────────────────────
        if content.contains("?") { score += 0.04 }

        // ── Negative quality signals ─────────────────────────────────────
        // Very short posts with no scripture and high engagement (likely viral-bait)
        if wordCount < 10 && post.amenCount > 50 { score -= 0.15 }

        return min(1.0, max(0.0, score))
    }

    /// Content diversity bonus — reward posts from underrepresented categories
    static func diversityBonus(for post: Post, recentCategories: [String]) -> Double {
        let categoryStr = post.category.rawValue
        let recent5 = recentCategories.suffix(5)
        let count = recent5.filter { $0 == categoryStr }.count
        // If same category appeared 3+ times in last 5, apply diversity bonus to other categories
        if count == 0 { return 0.1 }    // Fresh category
        if count == 1 { return 0.05 }
        return 0.0
    }
}

// MARK: - Session Quality Tracker

/// Tracks the quality of the current feed session, not just duration.
/// Metrics: meaningful interactions, passive scroll ratio, reflection engagements
@MainActor
final class FeedSessionQualityTracker {

    static let shared = FeedSessionQualityTracker()

    private var sessionStart: Date?
    private var scrollEventCount: Int = 0
    private var meaningfulInteractions: Int = 0  // Saves, comments, prayer responses
    private var passiveDwellTime: TimeInterval = 0
    private var lastScrollTime: Date?
    private var continuousPassiveScrollDuration: TimeInterval = 0
    private var recentCategoryHistory: [String] = []

    private init() {}

    // MARK: - Session Lifecycle

    func sessionStarted() {
        sessionStart = Date()
        scrollEventCount = 0
        meaningfulInteractions = 0
        passiveDwellTime = 0
        continuousPassiveScrollDuration = 0
        lastScrollTime = nil
        recentCategoryHistory = []
    }

    func sessionEnded() {
        logSessionQuality()
        sessionStart = nil
    }

    // MARK: - Event Recording

    func recordScroll(post: Post?) {
        scrollEventCount += 1
        let now = Date()

        if let last = lastScrollTime {
            let gap = now.timeIntervalSince(last)
            if gap < 2.0 {  // Fast scroll (< 2s per post)
                continuousPassiveScrollDuration += gap
            } else {
                // Paused — reset continuous passive scroll counter
                continuousPassiveScrollDuration = 0
            }
        }
        lastScrollTime = now

        if let category = post?.category.rawValue {
            recentCategoryHistory.append(category)
            if recentCategoryHistory.count > 20 { recentCategoryHistory.removeFirst() }
        }
    }

    func recordMeaningfulInteraction() {
        meaningfulInteractions += 1
        continuousPassiveScrollDuration = 0  // Reset passive scroll on interaction
    }

    // MARK: - Doomscroll Detection

    /// Returns true if the user has been passively scrolling without engagement
    /// for long enough to warrant a gentle pacing prompt.
    var shouldShowPacingPrompt: Bool {
        // 3+ minutes of continuous fast scrolling without any meaningful interaction
        return continuousPassiveScrollDuration > 180
    }

    /// Returns a pacing prompt if warranted, nil otherwise
    func pacePrompt() -> FeedPacingPrompt? {
        guard shouldShowPacingPrompt else { return nil }
        continuousPassiveScrollDuration = 0  // Reset after showing

        let prompts: [FeedPacingPrompt] = [
            FeedPacingPrompt(
                message: "You've been scrolling for a while. Ready to engage with something meaningful?",
                actionLabel: "Find something to reflect on",
                type: .reflection
            ),
            FeedPacingPrompt(
                message: "Take a breath. Is there something specific you were looking for?",
                actionLabel: "Search for a topic",
                type: .redirect
            ),
            FeedPacingPrompt(
                message: "Consider taking a moment to pray or journal.",
                actionLabel: "Open prayer",
                type: .prayer
            ),
        ]
        return prompts.randomElement()
    }

    var recentCategories: [String] { recentCategoryHistory }

    // MARK: - Quality Metrics

    struct SessionQuality: Codable {
        let sessionDurationMinutes: Double
        let scrollCount: Int
        let meaningfulInteractions: Int
        let qualityScore: Double   // 0–1.0, ratio of meaningful / scroll
        let date: Date
    }

    private func computeQuality() -> SessionQuality {
        let duration = sessionStart.map { Date().timeIntervalSince($0) / 60 } ?? 0
        let qualityScore = scrollEventCount > 0
            ? min(1.0, Double(meaningfulInteractions) / Double(scrollEventCount))
            : 0
        return SessionQuality(
            sessionDurationMinutes: duration,
            scrollCount: scrollEventCount,
            meaningfulInteractions: meaningfulInteractions,
            qualityScore: qualityScore,
            date: Date()
        )
    }

    private func logSessionQuality() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let quality = computeQuality()
        let db = Firestore.firestore()
        Task.detached(priority: .background) {
            try? await db
                .collection("users").document(uid)
                .collection("feedSessions")
                .addDocument(data: [
                    "durationMinutes": quality.sessionDurationMinutes,
                    "scrollCount": quality.scrollCount,
                    "meaningfulInteractions": quality.meaningfulInteractions,
                    "qualityScore": quality.qualityScore,
                    "date": Timestamp(date: quality.date)
                ])
        }
    }
}

// MARK: - Feed Pacing Prompt

struct FeedPacingPrompt: Identifiable {
    let id = UUID()
    let message: String
    let actionLabel: String
    let type: PromptType

    enum PromptType {
        case reflection
        case redirect
        case prayer
    }
}

// MARK: - Feed Reflection Prompt

/// Occasional reflection prompts surfaced between posts — never intrusive, always skippable.
struct FeedReflectionPrompt: Identifiable {
    let id = UUID()
    let text: String
    let scripture: String?
    let scriptureRef: String?

    static let catalog: [FeedReflectionPrompt] = [
        FeedReflectionPrompt(
            text: "What is one thing you've read today that you want to take with you?",
            scripture: nil, scriptureRef: nil
        ),
        FeedReflectionPrompt(
            text: "Is there someone in your community you haven't connected with in a while?",
            scripture: nil, scriptureRef: nil
        ),
        FeedReflectionPrompt(
            text: "\"Let everything that has breath praise the Lord.\"",
            scripture: "Psalm 150:6", scriptureRef: "Psalm 150:6"
        ),
        FeedReflectionPrompt(
            text: "Take a moment to reflect on one thing you're grateful for today.",
            scripture: nil, scriptureRef: nil
        ),
        FeedReflectionPrompt(
            text: "\"Whatever you do, work at it with all your heart, as working for the Lord.\"",
            scripture: "Colossians 3:23", scriptureRef: "Col 3:23"
        ),
        FeedReflectionPrompt(
            text: "Is there something on your heart worth praying about right now?",
            scripture: nil, scriptureRef: nil
        ),
        FeedReflectionPrompt(
            text: "\"Trust in the Lord with all your heart.\"",
            scripture: "Proverbs 3:5", scriptureRef: "Prov 3:5"
        ),
        FeedReflectionPrompt(
            text: "Who has encouraged you recently? Consider sending them a kind word.",
            scripture: nil, scriptureRef: nil
        ),
    ]

    static func random() -> FeedReflectionPrompt {
        catalog.randomElement() ?? catalog[0]
    }
}

// MARK: - Feed Reflection Card View

struct FeedReflectionCard: View {
    let prompt: FeedReflectionPrompt
    let onDismiss: () -> Void
    let onPray: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.purple)
                Text("Moment of reflection")
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundColor(.purple)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            Text(prompt.text)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let ref = prompt.scriptureRef {
                Text(ref)
                    .font(.custom("OpenSans-Medium", size: 12))
                    .foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button("Pray about this") {
                    onPray()
                }
                .font(.custom("OpenSans-Medium", size: 13))
                .foregroundColor(.purple)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.purple.opacity(0.1), in: Capsule())
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.purple.opacity(0.15), lineWidth: 1)
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Feed Intelligence Service (Orchestrator)

/// Top-level service that coordinates all feed intelligence features.
/// Lightweight — designed to be composed with existing HomeFeedAlgorithm.
@MainActor
final class FeedIntelligenceService: ObservableObject {

    static let shared = FeedIntelligenceService()

    private let flags = AMENFeatureFlags.shared
    private let sessionTracker = FeedSessionQualityTracker.shared
    private let checkInService = SpiritualCheckInService.shared

    @Published private(set) var currentPacingPrompt: FeedPacingPrompt? = nil
    @Published private(set) var currentReflectionPrompt: FeedReflectionPrompt? = nil
    @Published var reflectionPromptScrollPosition: Int = 30  // Show after 30 posts

    private var reflectionPromptCounter: Int = 0
    private var postsScrolledSinceReflection: Int = 0

    private init() {}

    // MARK: - Session Management

    func feedSessionStarted() {
        guard flags.feedRankingV2Enabled else { return }
        sessionTracker.sessionStarted()
        reflectionPromptCounter = 0
        postsScrolledSinceReflection = 0
    }

    func feedSessionEnded() {
        guard flags.feedRankingV2Enabled else { return }
        sessionTracker.sessionEnded()
    }

    // MARK: - Post Scroll Tracking

    func postScrolled(post: Post) {
        guard flags.feedRankingV2Enabled else { return }
        sessionTracker.recordScroll(post: post)
        postsScrolledSinceReflection += 1

        // Spiritual check-in content analysis (no storage)
        checkInService.analyzeContent(post.content)

        // Doomscroll detection
        if flags.antiDoomscrollEnabled {
            if let prompt = sessionTracker.pacePrompt() {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    currentPacingPrompt = prompt
                }
            }
        }

        // Reflection prompt injection
        if flags.feedReflectionPromptsEnabled && postsScrolledSinceReflection >= reflectionPromptScrollPosition {
            injectReflectionPrompt()
        }
    }

    func userEngaged(with post: Post) {
        guard flags.feedRankingV2Enabled else { return }
        sessionTracker.recordMeaningfulInteraction()
        checkInService.recordPositiveEngagement()
        dismissPacingPrompt()
    }

    // MARK: - Ranking Enhancement

    /// Apply spiritual value and diversity bonuses on top of HomeFeedAlgorithm scores.
    /// Call after HomeFeedAlgorithm.rankPosts() to add AMEN-specific signals.
    nonisolated func enhanceRanking(
        scoredPosts: [(post: Post, baseScore: Double)],
        recentCategories: [String]
    ) -> [Post] {
        // Access flag synchronously on main actor via assumeIsolated (safe when called from main thread)
        let enabled = MainActor.assumeIsolated { AMENFeatureFlags.shared.feedRankingV2Enabled }
        guard enabled else {
            return scoredPosts.map { $0.post }
        }

        let enhanced = scoredPosts.map { item -> (post: Post, finalScore: Double) in
            let spiritualBonus = MainActor.assumeIsolated { SpiritualValueScorer.score(item.post) } * 15.0
            let diversityBonus = MainActor.assumeIsolated { SpiritualValueScorer.diversityBonus(for: item.post, recentCategories: recentCategories) } * 10.0
            return (item.post, item.baseScore + spiritualBonus + diversityBonus)
        }

        return enhanced.sorted { $0.finalScore > $1.finalScore }.map { $0.post }
    }

    // MARK: - Reflection Prompt

    private func injectReflectionPrompt() {
        postsScrolledSinceReflection = 0
        reflectionPromptScrollPosition = Int.random(in: 25...40)  // Vary to feel organic
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            currentReflectionPrompt = FeedReflectionPrompt.random()
        }
    }

    func dismissReflectionPrompt() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            currentReflectionPrompt = nil
        }
    }

    func dismissPacingPrompt() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            currentPacingPrompt = nil
        }
    }
}

// MARK: - Pacing Prompt View

struct FeedPacingPromptView: View {
    let prompt: FeedPacingPrompt
    let onAction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(.teal)

            VStack(alignment: .leading, spacing: 4) {
                Text(prompt.message)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(prompt.actionLabel) {
                    onAction()
                }
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundColor(.teal)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(Color.gray.opacity(0.12), in: Circle())
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.teal.opacity(0.2), lineWidth: 1)
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}
