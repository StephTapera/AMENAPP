// BereanRecommendationEngine.swift
// AMEN App — Community Around Content OS / Berean Connector
//
// Recommends related communities and surfaces reflection/prayer prompts
// based on the meaning alignment of a ContentObject.
// Gated by CommunityOSFlag.bereanContentConnector.

import Foundation
import FirebaseFirestore

// MARK: - BereanRecommendationEngine

actor BereanRecommendationEngine {

    // MARK: Shared

    static let shared = BereanRecommendationEngine()

    // MARK: Dependencies

    private let connector: BereanContentConnector
    private let db: Firestore

    // MARK: Init

    private init(
        connector: BereanContentConnector = .shared,
        db: Firestore = Firestore.firestore()
    ) {
        self.connector = connector
        self.db = db
    }

    // MARK: - Community Recommendations

    /// Queries Firestore `communityNodes` for thematically-similar nodes and filters out
    /// communities the user has already joined. Returns up to 8 results.
    func recommendCommunities(
        for contentObject: ContentObject,
        userId: String
    ) async throws -> [CommunityNode] {
        guard CommunityOSFlagService.shared.isEnabled(.bereanContentConnector) else {
            dlog("[BereanRecommendationEngine] Flag disabled — skipping community recommendations")
            return []
        }

        // Build the candidate theme set from content themes + linked verse refs
        var candidateThemes: [String] = contentObject.themes
        candidateThemes.append(contentsOf: contentObject.linkedVerseRefs)

        guard !candidateThemes.isEmpty else {
            dlog("[BereanRecommendationEngine] No themes for '\(contentObject.title)' — returning empty")
            return []
        }

        // Firestore array-contains-any supports up to 30 values
        let queryThemes = Array(candidateThemes.prefix(30))

        let snapshot = try await db
            .collection("communityNodes")
            .whereField("themes", arrayContainsAny: queryThemes)
            .limit(to: 50)
            .getDocuments()

        // Parse and deduplicate
        let allNodes: [CommunityNode] = snapshot.documents.compactMap { doc in
            var data = doc.data()
            if data["id"] == nil { data["id"] = doc.documentID }
            return CommunityNode(from: data)
        }

        // Exclude communities the user has already joined
        let joinedSnapshot = try await db
            .collection("communityMemberships")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()

        let joinedNodeIds = Set(
            joinedSnapshot.documents.compactMap { $0.data()["communityNodeId"] as? String }
        )

        let filtered = allNodes.filter { !joinedNodeIds.contains($0.id) }

        // Sort by health score descending, return top 8
        let ranked = filtered
            .sorted { $0.healthScore > $1.healthScore }
            .prefix(8)

        dlog("[BereanRecommendationEngine] Recommended \(ranked.count) communities for '\(contentObject.title)'")
        return Array(ranked)
    }

    // MARK: - Related Verse Recommendations

    /// Delegates to BereanContentConnector to surface the most relevant scripture chips.
    func recommendRelatedVerses(for contentObject: ContentObject) -> [BereanScriptureChip] {
        guard CommunityOSFlagService.shared.isEnabled(.bereanContentConnector) else {
            dlog("[BereanRecommendationEngine] Flag disabled — skipping verse recommendations")
            return []
        }
        return connector.findVerses(for: contentObject)
    }

    // MARK: - Reflection Prompts

    /// Returns 3 context-sensitive reflection questions tailored to the content kind and themes.
    func reflectionPrompts(for contentObject: ContentObject) -> [String] {
        guard CommunityOSFlagService.shared.isEnabled(.bereanContentConnector) else {
            dlog("[BereanRecommendationEngine] Flag disabled — skipping reflection prompts")
            return []
        }

        switch contentObject.kind {

        case .song:
            return [
                "What emotion does this song bring up in your faith journey?",
                "How does this song connect to what God is doing in your life?",
                "What scripture does this song remind you of?"
            ]

        case .podcast:
            return [
                "What was the most challenging insight from this episode?",
                "How will you apply this teaching to your life this week?",
                "Who needs to hear this message?"
            ]

        case .book:
            return [
                "What chapter challenged your thinking most?",
                "How does this author's perspective align with scripture?",
                "Who would you recommend this book to and why?"
            ]

        case .sermon:
            return [
                "What was the main truth you are taking away from this sermon?",
                "How does this message apply to something you are currently facing?",
                "What action step will you take based on what you heard?"
            ]

        case .bibleVerse:
            return [
                "How does this passage speak to your current season of life?",
                "What does this verse reveal about God's character?",
                "How can you memorize and apply this scripture this week?"
            ]

        case .video:
            return [
                "What moment in this video impacted you most spiritually?",
                "How does this content point you toward or away from God?",
                "What conversation could this video spark in your community?"
            ]

        case .course:
            return [
                "What is the most transformative concept you have learned so far?",
                "How is this course reshaping your understanding of your faith?",
                "What accountability structures are you building around this learning?"
            ]

        case .testimony:
            return [
                "What part of this testimony resonates most with your own story?",
                "How does this person's experience strengthen your faith?",
                "What would you share about God's work in your own life right now?"
            ]

        case .article:
            return [
                "What claim in this article most challenged your existing beliefs?",
                "How does this content align with or diverge from scripture?",
                "Who in your community should read and discuss this article?"
            ]

        case .prayerRequest:
            return [
                "How can you specifically intercede for this request this week?",
                "What scripture can you stand on in prayer for this need?",
                "How has God answered similar prayers in your own life?"
            ]

        case .event:
            return [
                "What do you hope to experience spiritually at this event?",
                "Who could you invite to join you?",
                "How will you carry what you receive into your everyday life?"
            ]

        case .userPost:
            return [
                "How does this post connect to your own spiritual journey?",
                "What scripture comes to mind when you read this?",
                "How can you encourage the person who shared this?"
            ]
        }
    }

    // MARK: - Prayer Prompts

    /// Returns 2 prayer-focused prompts tailored to the content kind and themes.
    func prayerPrompts(for contentObject: ContentObject) -> [String] {
        guard CommunityOSFlagService.shared.isEnabled(.bereanContentConnector) else {
            dlog("[BereanRecommendationEngine] Flag disabled — skipping prayer prompts")
            return []
        }

        switch contentObject.kind {

        case .song:
            return [
                "Lord, let the worship in this song become a genuine expression of my heart toward You.",
                "God, use this music to draw me and others closer to Your presence today."
            ]

        case .podcast:
            return [
                "Father, let this teaching take root in my heart and produce lasting fruit.",
                "Holy Spirit, guide me as I apply what I have heard to my walk with You."
            ]

        case .book:
            return [
                "God, give me discernment as I read, filtering every idea through the truth of Your Word.",
                "Lord, use this book to deepen my understanding of You and Your purposes for my life."
            ]

        case .sermon:
            return [
                "Father, let the seeds planted through this message grow deep roots in my life.",
                "Lord, I surrender my resistance to the areas of my life this sermon has exposed."
            ]

        case .bibleVerse:
            return [
                "God, let Your Word be a lamp to my feet and a light to my path today.",
                "Holy Spirit, write this scripture on my heart so that I do not sin against You."
            ]

        case .video:
            return [
                "Lord, give me eyes to see what You want to show me through this content.",
                "Father, guard my heart and mind as I engage with media — let it serve Your purposes."
            ]

        case .course:
            return [
                "God, grant me discipline and wisdom as I invest in growing in this area of my faith.",
                "Lord, connect me with others on this learning journey who will sharpen me as iron sharpens iron."
            ]

        case .testimony:
            return [
                "Father, thank You for Your faithfulness in this person's life — may their story magnify Your name.",
                "Lord, use this testimony to ignite fresh faith in everyone who hears it."
            ]

        case .article:
            return [
                "God, give me discernment to weigh every idea in this article against Your Word.",
                "Lord, help me engage with content that stretches my thinking while keeping me anchored in truth."
            ]

        case .prayerRequest:
            return [
                "Father, I lift this need before Your throne of grace — You alone can provide and heal.",
                "Lord, surround this person with Your peace that surpasses all understanding."
            ]

        case .event:
            return [
                "God, prepare my heart to receive everything You want to pour into me at this event.",
                "Father, let Your Spirit move powerfully and draw many to Yourself through this gathering."
            ]

        case .userPost:
            return [
                "Lord, bless the person who shared this and meet every need behind their words.",
                "Father, let this community be a place where people encounter Your love through every interaction."
            ]
        }
    }
}
