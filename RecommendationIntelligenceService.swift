// RecommendationIntelligenceService.swift
// AMENAPP
//
// Cross-surface semantic recommendation engine.
// Powers:
//   - "Related verses" chips on post cards and Berean responses
//   - "Related resources" in Wisdom Library + Resources
//   - Contextual "Ask Berean" prompt suggestions
//   - Church discovery personalization
//   - Opportunity/job matching
//   - "People you might want to follow" faith-interest matching
//   - Smart empty states with personalized suggestions
//   - "Continue where you left off" Berean session suggestions
//
// Architecture:
//   - Fast on-device keyword/topic matching for immediate suggestions
//   - Async Vertex AI embedding similarity for deeper recommendations
//   - UserSignalsService for personalization context
//   - Result caching (TTL 10 minutes)

import Foundation

// MARK: - Recommendation Item

struct RecommendationItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let type: RecommendationType
    let relevanceScore: Double      // 0-1.0
    let sourceContext: String       // why this was recommended
    let actionPayload: AIAction?    // what happens when tapped
    let topicTags: [String]
}

enum RecommendationType: String {
    case verse          = "verse"
    case resource       = "resource"
    case bereanPrompt   = "berean_prompt"
    case church         = "church"
    case person         = "person"
    case note           = "note"
    case topic          = "topic"
    case opportunity    = "opportunity"
}

// MARK: - Recommendation Context

struct RecommendationContext {
    let surface: AMENSurface
    let currentText: String
    let userId: String?
    let topicTags: [String]
    let signals: AggregatedUserSignals
}

// MARK: - RecommendationIntelligenceService

@MainActor
final class RecommendationIntelligenceService {

    static let shared = RecommendationIntelligenceService()

    private var cache: [String: CachedRecommendations] = [:]
    private let cacheTTL: TimeInterval = 600  // 10 minutes

    private init() {}

    // MARK: - Surface-Specific APIs

    /// Contextual "Ask Berean" prompt suggestions for any surface
    func suggestedPrompts(
        surface: AMENSurface,
        context: String,
        userId: String?
    ) async -> [String] {
        let cacheKey = "prompts_\(surface.rawValue)_\(context.hashValue)"
        if let cached = cache[cacheKey], !cached.isExpired {
            return cached.prompts
        }

        let topics = SemanticTopicService.shared.classifyText(context).map { $0.cluster }
        let prompts = buildContextualPrompts(surface: surface, topics: topics, context: context)
        cache[cacheKey] = CachedRecommendations(prompts: prompts, expiresAt: Date().addingTimeInterval(cacheTTL))
        return prompts
    }

    /// Related verses for a post or AI response
    func relatedVerses(for text: String) -> [String] {
        let lower = text.lowercased()
        var verses: [String] = []

        // Topic → canonical verse mapping (curated, spiritually grounded)
        let topicVerses: [(keywords: [String], verse: String)] = [
            (["anxiety", "worry", "fear", "stressed"],     "Philippians 4:6-7"),
            (["hope", "hopeless", "future"],                "Jeremiah 29:11"),
            (["strength", "tired", "weak", "exhausted"],   "Isaiah 40:31"),
            (["love", "loving", "compassion"],              "1 Corinthians 13:4-7"),
            (["forgiveness", "forgive", "forgiven"],        "Ephesians 4:32"),
            (["faith", "believe", "trust"],                 "Hebrews 11:1"),
            (["prayer", "pray", "asking god"],              "Matthew 6:9-13"),
            (["peace", "calm", "still"],                    "John 14:27"),
            (["joy", "rejoice", "happy"],                   "Philippians 4:4"),
            (["guidance", "direction", "lost", "way"],      "Proverbs 3:5-6"),
            (["protection", "safe", "shelter"],             "Psalm 91:1-2"),
            (["grief", "mourning", "loss", "death"],        "Psalm 23"),
            (["money", "finances", "wealth", "generosity"], "Proverbs 11:24-25"),
            (["marriage", "spouse", "relationship"],        "Ephesians 5:25"),
            (["purpose", "calling", "why am i here"],       "Romans 8:28"),
            (["anger", "angry", "frustration"],             "Ephesians 4:26"),
            (["shame", "guilt", "condemned"],               "Romans 8:1"),
            (["loneliness", "alone", "lonely"],             "Deuteronomy 31:6"),
            (["healing", "sick", "illness"],                "James 5:14-15"),
            (["salvation", "saved", "eternal life"],        "John 3:16"),
            (["wisdom", "knowledge", "understanding"],      "James 1:5"),
            (["work", "labor", "career"],                   "Colossians 3:23"),
            (["children", "parenting", "kids"],             "Proverbs 22:6"),
            (["community", "church", "together", "unity"],  "Hebrews 10:24-25"),
            (["worship", "praise"],                         "Psalm 150:6"),
            (["trials", "suffering", "hardship", "pain"],   "James 1:2-4"),
            (["identity", "who am i", "worth"],             "Psalm 139:14"),
        ]

        for (keywords, verse) in topicVerses {
            if keywords.contains(where: { lower.contains($0) }) {
                verses.append(verse)
            }
        }

        return Array(Set(verses)).prefix(3).map { $0 }
    }

    /// Resource recommendations based on topic context
    func relatedResources(for text: String, userId: String?) async -> [RecommendationItem] {
        let topics = SemanticTopicService.shared.classifyText(text)
        return buildResourceRecommendations(from: topics)
    }

    /// Church discovery suggestions based on user interests
    func churchSuggestions(
        userInterests: [String],
        location: String?,
        userId: String?
    ) async -> [RecommendationItem] {
        let context = userInterests.joined(separator: " ")
        let topics = SemanticTopicService.shared.classifyText(context)
        return buildChurchRecommendations(topics: topics, location: location)
    }

    /// Berean "continue where you left off" session suggestion
    func bereanResumeSuggestion(lastTopic: String?) -> String? {
        guard let topic = lastTopic, !topic.isEmpty else { return nil }
        let verseRefs = relatedVerses(for: topic)
        if let firstVerse = verseRefs.first {
            return "Continue exploring \(topic)? We could look at \(firstVerse) next."
        }
        return "Ready to continue your study on \(topic)?"
    }

    /// Smart empty state prompts for a given surface
    func emptyStatePrompts(surface: AMENSurface, userId: String?) -> [String] {
        let signals = UserSignalsService.shared
        let topTopics = signals.topTopics(limit: 2).map(\.topic)

        switch surface {
        case .bereanChat:
            if topTopics.isEmpty {
                return [
                    "What does the Bible say about anxiety?",
                    "Help me understand John 3:16 more deeply",
                    "What is the meaning of grace?",
                    "Give me a short devotional for today"
                ]
            }
            return topTopics.flatMap { topic -> [String] in
                [
                    "What does the Bible say about \(topic)?",
                    "Give me a verse about \(topic)"
                ]
            } + ["What should I read today?"]

        case .wisdomLibrary:
            return [
                "Books on deepening prayer",
                "Theology for everyday life",
                "Spiritual formation for busy people",
                "Understanding the Psalms"
            ]

        case .discovery:
            return topTopics.isEmpty ?
                ["Faith & Work", "Prayer", "Community", "Scripture"] :
                topTopics + ["Theology", "Worship"]

        case .resources:
            return [
                "Mental health and faith",
                "Church for new believers",
                "Grief and loss support",
                "Christian community near me"
            ]

        default:
            return []
        }
    }

    // MARK: - Private Builder Helpers

    private func buildContextualPrompts(
        surface: AMENSurface,
        topics: [SpiritualTopicCluster],
        context: String
    ) -> [String] {
        var prompts: [String] = []

        switch surface {
        case .postCreation:
            prompts += [
                "Help me write this more clearly",
                "Suggest a relevant scripture verse",
                "Is my tone kind and constructive?",
                "Help me make this more encouraging"
            ]

        case .churchNotes:
            prompts += [
                "Summarize the key points of this note",
                "Extract the scripture references",
                "What action steps can I take from this?",
                "Help me write a reflection prayer"
            ]

        case .prayerRequest:
            prompts += [
                "Help me express this more clearly",
                "Find scripture that speaks to this situation",
                "Write a short prayer around this",
                "How can others pray with me?"
            ]

        case .wisdomLibrary:
            prompts += [
                "What books would help me grow in prayer?",
                "Recommend something on Christian leadership",
                "I'm going through grief — what should I read?",
                "Books that changed people's faith"
            ]

        case .bereanChat:
            let topicPrompts: [SpiritualTopicCluster: [String]] = [
                .prayer:     ["What makes prayer powerful?", "Teach me to pray like Jesus did"],
                .scripture:  ["Explain this passage to me", "What are the key themes here?"],
                .theology:   ["What does the Church teach about this?", "How do different traditions view this?"],
                .grief:      ["How does the Bible address grief?", "What did David say in his grief?"],
                .faithAndWork: ["How do I honor God in my work?", "What does Proverbs say about business?"]
            ]
            for topic in topics.prefix(2) {
                if let tp = topicPrompts[topic] { prompts += tp.prefix(2) }
            }
            if prompts.isEmpty {
                prompts = ["What does the Bible say about this?", "Give me a scripture on this topic"]
            }

        default:
            prompts = ["Ask Berean about this", "Find scripture on this topic"]
        }

        return Array(prompts.prefix(4))
    }

    private func buildResourceRecommendations(from topics: [TopicTag]) -> [RecommendationItem] {
        // In production this queries the Resources Firestore collection with topic filters
        // Returning curated static recommendations as the foundation
        let resourceMap: [SpiritualTopicCluster: (title: String, subtitle: String)] = [
            .prayer:        ("Knowing God Through Prayer", "A guide to deeper conversation with God"),
            .scripture:     ("Scripture Memory System", "Memorize God's Word effectively"),
            .grief:         ("Walking Through Grief Biblically", "Finding hope in loss"),
            .mentalHealth:  ("Faith & Mental Health", "Caring for your whole self"),
            .theology:      ("Core Christian Doctrines", "Understanding what we believe and why"),
            .faithAndWork:  ("Faith in the Marketplace", "Integrating faith and career"),
            .community:     ("The Importance of Church", "Why we need each other"),
            .discipleship:  ("Disciplines of a Godly Life", "Spiritual practices that transform"),
        ]

        return topics.prefix(3).compactMap { tag -> RecommendationItem? in
            guard let resource = resourceMap[tag.cluster] else { return nil }
            return RecommendationItem(
                id: UUID().uuidString,
                title: resource.title,
                subtitle: resource.subtitle,
                type: .resource,
                relevanceScore: tag.confidence,
                sourceContext: "Based on \(tag.cluster.rawValue) content",
                actionPayload: nil,
                topicTags: [tag.cluster.rawValue]
            )
        }
    }

    private func buildChurchRecommendations(
        topics: [TopicTag],
        location: String?
    ) -> [RecommendationItem] {
        // In production this queries the Churches Firestore collection
        // This method provides the recommendation framing
        let locationStr = location ?? "your area"
        return topics.prefix(2).map { tag in
            RecommendationItem(
                id: UUID().uuidString,
                title: "Churches emphasizing \(tag.cluster.rawValue) in \(locationStr)",
                subtitle: nil,
                type: .church,
                relevanceScore: tag.confidence,
                sourceContext: "Matched to your \(tag.cluster.rawValue) interest",
                actionPayload: .openChurch(id: ""),
                topicTags: [tag.cluster.rawValue]
            )
        }
    }
}

// MARK: - Cache

private struct CachedRecommendations {
    let prompts: [String]
    let expiresAt: Date
    var isExpired: Bool { Date() > expiresAt }
}

// MARK: - Related Verses UI Strip

import SwiftUI

/// Horizontal scrolling strip of related verse chips.
/// Drop into any feed card, AI response, or resource view.
struct RelatedVersesStrip: View {
    let text: String
    let onVerseTapped: (String) -> Void

    @State private var verses: [String] = []

    var body: some View {
        Group {
            if !verses.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(verses, id: \.self) { verse in
                            Button {
                                onVerseTapped(verse)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "book.closed.fill")
                                        .font(.system(size: 9, weight: .medium))
                                    Text(verse)
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundStyle(Color(red: 0.88, green: 0.38, blue: 0.28))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(Color(red: 0.88, green: 0.38, blue: 0.28).opacity(0.09))
                                        .overlay(
                                            Capsule().stroke(
                                                Color(red: 0.88, green: 0.38, blue: 0.28).opacity(0.22),
                                                lineWidth: 0.5
                                            )
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                }
            }
        }
        .task {
            verses = RecommendationIntelligenceService.shared.relatedVerses(for: text)
        }
    }
}

/// Contextual "Ask Berean" prompt suggestion row.
/// Shows 2-3 prompts relevant to current surface/content.
struct AskBereanPromptSuggestions: View {
    let surface: AMENSurface
    let context: String
    let userId: String?
    let onPromptTapped: (String) -> Void

    @State private var prompts: [String] = []

    var body: some View {
        Group {
            if !prompts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(red: 0.88, green: 0.38, blue: 0.28))
                        Text("Ask Berean")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(white: 0.40))
                            .tracking(0.3)
                    }

                    ForEach(prompts.prefix(3), id: \.self) { prompt in
                        Button {
                            onPromptTapped(prompt)
                        } label: {
                            HStack {
                                Text(prompt)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(Color(white: 0.18))
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Color(white: 0.55))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.72))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.black.opacity(0.06), lineWidth: 0.75)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task(id: context) {
            prompts = await RecommendationIntelligenceService.shared.suggestedPrompts(
                surface: surface,
                context: context,
                userId: userId
            )
        }
    }
}
