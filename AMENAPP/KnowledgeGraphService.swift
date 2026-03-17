// KnowledgeGraphService.swift
// AMEN App — Christian Knowledge Graph + Connected Discovery
//
// Purpose: Create semantic connections between all content types on AMEN:
//   Posts ↔ Verses ↔ Topics ↔ Church Notes ↔ Testimonies ↔ Resources ↔ Prayer
//
// Architecture:
//   KnowledgeGraphService   ← orchestrates all graph queries
//   TopicExtractor          ← extracts canonical topics from text
//   RelatedContentService   ← finds related items for any content entity
//   KnowledgeGraphNode      ← any connected entity in the graph
//   KnowledgeGraphEdge      ← relationship between two nodes
//
// Implementation approach:
//   - Phase 1 (current): keyword + topic matching (fast, local, no embeddings)
//   - Phase 2: semantic embeddings via Cloud Functions (when feature flag enabled)
//
// Privacy: all graph edges are computed from public content metadata + user topics.
// No private content is included without user action.

import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - Knowledge Node

enum KnowledgeNodeType: String, Codable {
    case post = "post"
    case verse = "verse"
    case topic = "topic"
    case churchNote = "church_note"
    case testimony = "testimony"
    case resource = "resource"
    case prayer = "prayer"
    case church = "church"
    case person = "person"
}

struct KnowledgeGraphNode: Identifiable, Equatable {
    let id: String
    let type: KnowledgeNodeType
    let title: String
    let subtitle: String?
    let thumbnail: String?
    let canonicalSlug: String?
    let relevanceScore: Double   // 0.0 – 1.0 relative to source

    var icon: String {
        switch type {
        case .post: return "bubble.left.fill"
        case .verse: return "book.fill"
        case .topic: return "tag.fill"
        case .churchNote: return "doc.text.fill"
        case .testimony: return "star.fill"
        case .resource: return "sparkles"
        case .prayer: return "hands.sparkles.fill"
        case .church: return "building.columns.fill"
        case .person: return "person.fill"
        }
    }

    var iconColor: Color {
        switch type {
        case .post: return .blue
        case .verse: return .indigo
        case .topic: return .purple
        case .churchNote: return .teal
        case .testimony: return .orange
        case .resource: return .green
        case .prayer: return .pink
        case .church: return .brown
        case .person: return .gray
        }
    }

    var displayType: String {
        switch type {
        case .post: return "Post"
        case .verse: return "Scripture"
        case .topic: return "Topic"
        case .churchNote: return "Church Note"
        case .testimony: return "Testimony"
        case .resource: return "Resource"
        case .prayer: return "Prayer"
        case .church: return "Church"
        case .person: return "Person"
        }
    }
}

// MARK: - Related Content Bundle

struct RelatedContentBundle: Equatable {
    let sourceId: String
    let sourceType: KnowledgeNodeType
    var verses: [KnowledgeGraphNode]
    var topics: [KnowledgeGraphNode]
    var relatedPosts: [KnowledgeGraphNode]
    var resources: [KnowledgeGraphNode]
    var prayers: [KnowledgeGraphNode]

    var hasAnyContent: Bool {
        !verses.isEmpty || !topics.isEmpty || !relatedPosts.isEmpty || !resources.isEmpty || !prayers.isEmpty
    }

    /// All nodes flattened, sorted by relevance
    var allNodes: [KnowledgeGraphNode] {
        (verses + topics + relatedPosts + resources + prayers)
            .sorted { $0.relevanceScore > $1.relevanceScore }
    }
}

// MARK: - Topic Extractor

/// Extracts canonical AMEN topics from arbitrary text.
/// Phase 1: keyword matching against topic catalog.
/// Phase 2: semantic embedding similarity (when semantic search flag enabled).
struct TopicExtractor {

    /// Extract canonical topic slugs from text
    static func extract(from text: String) -> [String] {
        let lower = text.lowercased()
        var extracted: [String] = []

        let topicKeywordMap: [String: [String]] = [
            "prayer": ["pray", "prayer", "praying", "intercession", "petition"],
            "bible-study": ["scripture", "bible", "verse", "study", "exegesis", "word of god"],
            "testimonies": ["testimony", "testified", "redemption", "transformation", "god changed"],
            "worship": ["worship", "praise", "song", "hymn", "adoration"],
            "personal-growth": ["grow", "growth", "discipline", "character", "sanctification"],
            "marriage": ["marriage", "spouse", "husband", "wife", "wedding", "relationship"],
            "discipleship": ["disciple", "discipleship", "follow jesus", "mentor", "accountability"],
            "missions": ["mission", "evangelism", "outreach", "witness", "great commission"],
            "mental-wellness": ["anxiety", "depression", "mental health", "healing", "peace of mind"],
            "stewardship": ["money", "finances", "giving", "tithe", "generosity", "stewardship"],
            "theology": ["doctrine", "theology", "belief", "faith tradition", "denomination"],
            "church-notes": ["sermon", "pastor", "preaching", "church notes", "message"],
            "leadership": ["leader", "servant leadership", "pastor", "elder", "ministry"],
            "young-adults": ["college", "young adult", "student", "campus", "generation z"],
            "christian-entrepreneurship": ["business", "career", "calling", "vocation", "work", "entrepreneur"],
            "faith-work": ["workplace", "coworkers", "business ethics", "calling", "monday morning"],
        ]

        for (topic, keywords) in topicKeywordMap {
            if keywords.contains(where: { lower.contains($0) }) {
                extracted.append(topic)
            }
        }

        return extracted
    }

    /// Match against the curated topic catalog and return full DiscoveryTopic objects
    static func matchCatalogTopics(from text: String) -> [DiscoveryTopic] {
        let slugs = Set(extract(from: text))
        return DiscoveryTopic.catalog.filter { slugs.contains($0.id) }
    }
}

// MARK: - Related Content Service

/// Finds related content for any AMEN entity using the knowledge graph.
@MainActor
final class RelatedContentService {

    static let shared = RelatedContentService()

    private let db = Firestore.firestore()
    private let flags = AMENFeatureFlags.shared

    // Local cache: sourceId → RelatedContentBundle
    private var cache: [String: (bundle: RelatedContentBundle, cachedAt: Date)] = [:]
    private let cacheTTL: TimeInterval = 300  // 5 minutes

    private init() {}

    // MARK: - Primary API

    func relatedContent(for text: String, sourceId: String, sourceType: KnowledgeNodeType) async -> RelatedContentBundle {
        guard flags.knowledgeGraphRelatedContentEnabled else {
            return RelatedContentBundle(sourceId: sourceId, sourceType: sourceType, verses: [], topics: [], relatedPosts: [], resources: [], prayers: [])
        }

        // Check cache
        if let cached = cache[sourceId], Date().timeIntervalSince(cached.cachedAt) < cacheTTL {
            return cached.bundle
        }

        // 1. Extract topics from content
        let matchedTopics = TopicExtractor.matchCatalogTopics(from: text)

        // 2. Find related scripture
        let verses = relatedVerses(from: text)

        // 3. Build topic nodes
        let topicNodes = matchedTopics.map { topic in
            KnowledgeGraphNode(
                id: "topic-\(topic.id)",
                type: .topic,
                title: topic.title,
                subtitle: topic.description,
                thumbnail: nil,
                canonicalSlug: topic.canonicalSlug,
                relevanceScore: 0.8
            )
        }

        // 4. Related resource nodes (from local catalog)
        let resourceNodes = relatedResources(for: matchedTopics)

        // 5. Bundle (post and prayer lookups are async — fire separately)
        var bundle = RelatedContentBundle(
            sourceId: sourceId,
            sourceType: sourceType,
            verses: verses,
            topics: topicNodes,
            relatedPosts: [],
            resources: resourceNodes,
            prayers: []
        )

        // 6. Firestore lookup for related posts with shared topics (async)
        if !matchedTopics.isEmpty {
            let topicSlugs = matchedTopics.map { $0.canonicalSlug }
            bundle.relatedPosts = await fetchRelatedPosts(topicSlugs: topicSlugs, excludeId: sourceId)
        }

        cache[sourceId] = (bundle, Date())
        return bundle
    }

    // MARK: - Scripture Relations

    private func relatedVerses(from text: String) -> [KnowledgeGraphNode] {
        ScriptureIndex.search(query: text).prefix(3).map { source in
            KnowledgeGraphNode(
                id: source.id,
                type: .verse,
                title: source.title,
                subtitle: source.content,
                thumbnail: nil,
                canonicalSlug: nil,
                relevanceScore: source.relevanceScore
            )
        }
    }

    // MARK: - Resource Relations

    private func relatedResources(for topics: [DiscoveryTopic]) -> [KnowledgeGraphNode] {
        // Curated local resource catalog keyed by topic
        let resourceCatalog: [String: [KnowledgeGraphNode]] = [
            "prayer": [
                KnowledgeGraphNode(id: "r-prayer-1", type: .resource, title: "The Power of Prayer", subtitle: "A guide to deepening your prayer life", thumbnail: nil, canonicalSlug: nil, relevanceScore: 0.9),
                KnowledgeGraphNode(id: "r-prayer-2", type: .resource, title: "Praying the Psalms", subtitle: "Using scripture as a prayer framework", thumbnail: nil, canonicalSlug: nil, relevanceScore: 0.85),
            ],
            "bible-study": [
                KnowledgeGraphNode(id: "r-bible-1", type: .resource, title: "Inductive Bible Study", subtitle: "A method for deeper scripture engagement", thumbnail: nil, canonicalSlug: nil, relevanceScore: 0.9),
            ],
            "mental-wellness": [
                KnowledgeGraphNode(id: "r-mental-1", type: .resource, title: "Anxious for Nothing", subtitle: "Max Lucado — Finding calm in a chaotic world", thumbnail: nil, canonicalSlug: nil, relevanceScore: 0.85),
                KnowledgeGraphNode(id: "r-mental-2", type: .resource, title: "The Resilient Life", subtitle: "Faith-based tools for mental resilience", thumbnail: nil, canonicalSlug: nil, relevanceScore: 0.8),
            ],
            "marriage": [
                KnowledgeGraphNode(id: "r-marriage-1", type: .resource, title: "The Meaning of Marriage", subtitle: "Tim Keller — A vision for Christian marriage", thumbnail: nil, canonicalSlug: nil, relevanceScore: 0.9),
            ],
            "discipleship": [
                KnowledgeGraphNode(id: "r-disc-1", type: .resource, title: "The Cost of Discipleship", subtitle: "Dietrich Bonhoeffer — Following Christ fully", thumbnail: nil, canonicalSlug: nil, relevanceScore: 0.9),
            ],
            "stewardship": [
                KnowledgeGraphNode(id: "r-stew-1", type: .resource, title: "The Total Money Makeover", subtitle: "Dave Ramsey — Biblical financial principles", thumbnail: nil, canonicalSlug: nil, relevanceScore: 0.85),
            ],
        ]

        var resources: [KnowledgeGraphNode] = []
        for topic in topics {
            if let r = resourceCatalog[topic.id] {
                resources.append(contentsOf: r)
            }
        }
        return Array(Set(resources.map { $0.id }).compactMap { id in resources.first { $0.id == id } }).prefix(3).map { $0 }
    }

    // MARK: - Firestore Related Posts

    private func fetchRelatedPosts(topicSlugs: [String], excludeId: String) async -> [KnowledgeGraphNode] {
        guard !topicSlugs.isEmpty else { return [] }
        do {
            let snapshot = try await db
                .collection("posts")
                .whereField("topicTag", in: topicSlugs.prefix(10).map { $0 })
                .order(by: "createdAt", descending: true)
                .limit(to: 5)
                .getDocuments()
            return snapshot.documents
                .filter { $0.documentID != excludeId }
                .compactMap { doc -> KnowledgeGraphNode? in
                    let data = doc.data()
                    guard let content = data["content"] as? String else { return nil }
                    let authorName = data["authorName"] as? String ?? "Community Member"
                    return KnowledgeGraphNode(
                        id: doc.documentID,
                        type: .post,
                        title: String(content.prefix(60)) + (content.count > 60 ? "..." : ""),
                        subtitle: authorName,
                        thumbnail: data["imageURL"] as? String,
                        canonicalSlug: nil,
                        relevanceScore: 0.7
                    )
                }
        } catch {
            return []
        }
    }

    // MARK: - Cache Management

    func invalidateCache(for sourceId: String) {
        cache.removeValue(forKey: sourceId)
    }
}

// MARK: - Knowledge Graph Service (Orchestrator)

@MainActor
final class KnowledgeGraphService: ObservableObject {

    static let shared = KnowledgeGraphService()

    private let relatedContent = RelatedContentService.shared
    private let flags = AMENFeatureFlags.shared

    @Published private(set) var isEnabled: Bool = true

    private init() {
        isEnabled = flags.knowledgeGraphEnabled
    }

    // MARK: - Public API

    /// Get related content bundle for a post
    func relatedContent(for post: Post) async -> RelatedContentBundle {
        guard flags.knowledgeGraphEnabled else {
            return RelatedContentBundle(
                sourceId: post.firebaseId ?? post.id.uuidString,
                sourceType: .post,
                verses: [], topics: [], relatedPosts: [], resources: [], prayers: []
            )
        }
        return await relatedContent.relatedContent(
            for: post.content,
            sourceId: post.firebaseId ?? post.id.uuidString,
            sourceType: .post
        )
    }

    /// Get related content for arbitrary text (church notes, prayers, etc.)
    func relatedContent(for text: String, id: String, type: KnowledgeNodeType) async -> RelatedContentBundle {
        guard flags.knowledgeGraphEnabled else {
            return RelatedContentBundle(sourceId: id, sourceType: type, verses: [], topics: [], relatedPosts: [], resources: [], prayers: [])
        }
        return await relatedContent.relatedContent(for: text, sourceId: id, sourceType: type)
    }

    /// Extract and return topics for onboarding/profile topic selection
    func extractTopics(from text: String) -> [DiscoveryTopic] {
        TopicExtractor.matchCatalogTopics(from: text)
    }

    /// Find scripture related to a topic slug
    func scripturesForTopic(_ slug: String) -> [KnowledgeGraphNode] {
        let topic = DiscoveryTopic.catalog.first { $0.canonicalSlug == slug }
        guard let t = topic, let scripture = t.relatedScripture else { return [] }
        return [KnowledgeGraphNode(
            id: "verse-\(slug)",
            type: .verse,
            title: scripture,
            subtitle: nil,
            thumbnail: nil,
            canonicalSlug: nil,
            relevanceScore: 1.0
        )]
    }
}

// MARK: - Related Content View Component

struct RelatedContentRail: View {
    let bundle: RelatedContentBundle
    let onNodeTapped: (KnowledgeGraphNode) -> Void

    var body: some View {
        if bundle.hasAnyContent {
            VStack(alignment: .leading, spacing: 10) {
                Text("Related")
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(bundle.allNodes.prefix(6)) { node in
                            RelatedContentPill(node: node)
                                .onTapGesture { onNodeTapped(node) }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

struct RelatedContentPill: View {
    let node: KnowledgeGraphNode

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: node.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(node.iconColor)

            VStack(alignment: .leading, spacing: 1) {
                Text(node.title)
                    .font(.custom("OpenSans-SemiBold", size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if let subtitle = node.subtitle {
                    Text(subtitle)
                        .font(.custom("OpenSans-Regular", size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(node.iconColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(node.iconColor.opacity(0.15), lineWidth: 1)
                )
        }
    }
}
