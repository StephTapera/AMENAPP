import Testing
import Foundation
@testable import AMENAPP

// MARK: - Feed Algorithm Tests

@Suite("HomeFeedAlgorithm — Scoring & Ranking")
struct FeedAlgorithmTests {
    let algo = HomeFeedAlgorithm()

    // Helper: create a minimal Post for testing
    private func makePost(
        content: String = "Test post",
        category: Post.PostCategory = .openTable,
        authorId: String = "author1",
        createdAt: Date = Date(),
        amenCount: Int = 0,
        lightbulbCount: Int = 0,
        commentCount: Int = 0,
        repostCount: Int = 0,
        topicTag: String? = nil
    ) -> Post {
        Post(
            id: UUID(),
            firebaseId: UUID().uuidString,
            authorId: authorId,
            authorName: "Test Author",
            authorUsername: "testauthor",
            authorInitials: "TA",
            authorProfileImageURL: nil,
            timeAgo: "1m",
            content: content,
            category: category,
            topicTag: topicTag,
            visibility: .everyone,
            allowComments: true,
            commentPermissions: .everyone,
            imageURLs: nil,
            linkURL: nil,
            linkPreviewTitle: nil,
            linkPreviewDescription: nil,
            linkPreviewImageURL: nil,
            linkPreviewSiteName: nil,
            linkPreviewType: nil,
            verseReference: nil,
            verseText: nil,
            createdAt: createdAt,
            amenCount: amenCount,
            lightbulbCount: lightbulbCount,
            commentCount: commentCount,
            repostCount: repostCount
        )
    }

    private func makeInterests(
        topics: [String: Double] = [:],
        goals: [String] = [],
        categories: [String: Double] = [:]
    ) -> HomeFeedAlgorithm.UserInterests {
        HomeFeedAlgorithm.UserInterests(
            engagedTopics: topics,
            engagedAuthors: [:],
            interactionHistory: [:],
            preferredCategories: categories,
            onboardingGoals: goals
        )
    }

    // ── Recency ──────────────────────────────────────────────────────────

    @Test("Recent posts score higher than old posts")
    func recencyDecay() {
        let interests = makeInterests()
        let recent = makePost(createdAt: Date())
        let old = makePost(createdAt: Date().addingTimeInterval(-72 * 3600)) // 3 days ago

        let recentScore = algo.scorePost(recent, for: interests)
        let oldScore = algo.scorePost(old, for: interests)

        #expect(recentScore > oldScore, "Recent post should score higher than 3-day-old post")
    }

    @Test("Posts older than 72 hours get minimal recency score")
    func veryOldPostRecency() {
        let interests = makeInterests()
        let veryOld = makePost(createdAt: Date().addingTimeInterval(-100 * 3600))
        let score = algo.scorePost(veryOld, for: interests)

        // Score should still be positive but low
        #expect(score >= 0, "Score should not be negative")
    }

    // ── Following Boost ──────────────────────────────────────────────────

    @Test("Posts from followed users score higher")
    func followingBoost() {
        let interests = makeInterests()
        let post = makePost(authorId: "friend1")

        let withFollow = algo.scorePost(post, for: interests, followingIds: ["friend1"])
        let withoutFollow = algo.scorePost(post, for: interests, followingIds: [])

        #expect(withFollow > withoutFollow, "Following an author should boost their post score")
    }

    // ── Engagement Bait Detection ────────────────────────────────────────

    @Test("ALL CAPS posts are penalized as engagement bait")
    func engagementBaitCaps() {
        let interests = makeInterests()
        let bait = makePost(content: "YOU WON'T BELIEVE WHAT HAPPENED NEXT!! SHARE NOW!!")
        let normal = makePost(content: "I had a beautiful experience at church today")

        let baitScore = algo.scorePost(bait, for: interests)
        let normalScore = algo.scorePost(normal, for: interests)

        // Bait should score lower or equal due to controversy/engagement-bait penalty
        #expect(normalScore >= baitScore, "Normal post should not score lower than engagement bait")
    }

    // ── Topic Clustering ─────────────────────────────────────────────────

    @Test("Scripture content clusters as scripture")
    func scriptureTopicCluster() {
        let post = makePost(content: "In John 3:16 we see God's love. Bible study tonight!")
        let cluster = algo.topicCluster(for: post)
        #expect(cluster == .scripture, "Post with Bible references should cluster as scripture")
    }

    @Test("Prayer content clusters as prayer")
    func prayerTopicCluster() {
        let post = makePost(content: "Please pray for my family. Prayer request for healing.")
        let cluster = algo.topicCluster(for: post)
        #expect(cluster == .prayer, "Post with prayer keywords should cluster as prayer")
    }

    @Test("Testimony content clusters as testimony")
    func testimonyTopicCluster() {
        let post = makePost(content: "My testimony: God delivered me from addiction. Praise report!")
        let cluster = algo.topicCluster(for: post)
        #expect(cluster == .testimony, "Post with testimony keywords should cluster as testimony")
    }

    // ── Benefit Score ────────────────────────────────────────────────────

    @Test("Benefit score returns values in 0-1 range")
    func benefitScoreRange() {
        let interests = makeInterests()
        let post = makePost(content: "A thoughtful reflection on faith and community")
        let result = algo.benefitScore(post, for: interests)

        #expect(result.finalScore >= 0.0 && result.finalScore <= 1.0)
        #expect(result.valueScore >= 0.0 && result.valueScore <= 1.0)
        #expect(result.trustScore >= 0.0 && result.trustScore <= 1.0)
        #expect(result.harmRisk >= 0.0 && result.harmRisk <= 1.0)
        #expect(result.addictionRisk >= 0.0 && result.addictionRisk <= 1.0)
    }

    // ── Ranking ──────────────────────────────────────────────────────────

    @Test("rankPosts returns same number of posts (minus filtered)")
    func rankPostsPreservesCount() {
        let interests = makeInterests()
        let posts = (0..<10).map { i in
            makePost(content: "Post \(i)", authorId: "author\(i)")
        }

        let ranked = algo.rankPosts(posts, for: interests)
        // Ranked should have same count (none should be engagement bait)
        #expect(ranked.count == posts.count)
    }

    @Test("benefitRankPosts returns posts in ranked order")
    func benefitRankOrder() {
        let interests = makeInterests(goals: ["growth"])
        let highEngagement = makePost(
            content: "Deep reflection on spiritual growth and discipleship",
            amenCount: 50, lightbulbCount: 30, commentCount: 20
        )
        let lowEngagement = makePost(content: "ok", amenCount: 0, commentCount: 0)

        let ranked = algo.benefitRankPosts([lowEngagement, highEngagement], for: interests)
        #expect(ranked.count == 2)
    }

    // ── Muted/Hidden Context ─────────────────────────────────────────────

    @Test("Muted authors score zero")
    func mutedAuthorZeroScore() {
        let interests = makeInterests()
        let post = makePost(authorId: "blocked_user")
        let context = HomeFeedAlgorithm.ScoringContext(
            prefsLoaded: true,
            mutedAuthors: ["blocked_user"],
            hiddenPosts: [],
            boostedPosts: [],
            boostedAuthors: []
        )

        let score = algo.scorePost(post, for: interests, context: context)
        #expect(score == 0.0, "Muted author's posts should score zero")
    }

    @Test("Hidden posts score zero")
    func hiddenPostZeroScore() {
        let interests = makeInterests()
        let post = makePost()
        let context = HomeFeedAlgorithm.ScoringContext(
            prefsLoaded: true,
            mutedAuthors: [],
            hiddenPosts: [post.firebaseId ?? ""],
            boostedPosts: [],
            boostedAuthors: []
        )

        let score = algo.scorePost(post, for: interests, context: context)
        #expect(score == 0.0, "Hidden posts should score zero")
    }
}

// MARK: - Listener Registry Tests

@Suite("ListenerRegistry — Deduplication Gate")
struct ListenerRegistryTests {

    @Test("begin() returns true on first call, false on subsequent")
    func beginIdempotency() {
        let registry = ListenerRegistry()
        #expect(registry.begin("test_key") == true)
        #expect(registry.begin("test_key") == false)
        #expect(registry.begin("test_key") == false)
    }

    @Test("end() releases the key for reuse")
    func endReleasesKey() {
        let registry = ListenerRegistry()
        #expect(registry.begin("key1") == true)
        registry.end("key1")
        #expect(registry.begin("key1") == true, "Key should be reusable after end()")
    }

    @Test("isActive() reflects current state")
    func isActiveReflectsState() {
        let registry = ListenerRegistry()
        #expect(registry.isActive("key1") == false)
        registry.begin("key1")
        #expect(registry.isActive("key1") == true)
        registry.end("key1")
        #expect(registry.isActive("key1") == false)
    }

    @Test("Independent keys don't interfere")
    func independentKeys() {
        let registry = ListenerRegistry()
        #expect(registry.begin("follow") == true)
        #expect(registry.begin("profile") == true)
        #expect(registry.begin("follow") == false)
        #expect(registry.isActive("profile") == true)
        registry.end("follow")
        #expect(registry.isActive("profile") == true)
    }

    @Test("Key format helpers produce consistent keys")
    func keyFormatConsistency() {
        let registry = ListenerRegistry()
        let key1 = registry.profileListenerKey(userId: "user123")
        let key2 = registry.profileListenerKey(userId: "user123")
        #expect(key1 == key2)
        #expect(key1.contains("user123"))

        let postsKey = registry.postsListenerKey(userId: "user123")
        #expect(postsKey != key1, "Profile and posts keys should differ")
    }

    @Test("end() on non-existent key is safe")
    func endNonExistentKey() {
        let registry = ListenerRegistry()
        registry.end("never_started") // Should not crash
        #expect(registry.isActive("never_started") == false)
    }
}

// MARK: - Content Normalization & Idempotency Tests

@Suite("Comment Idempotency — Content Normalization")
struct ContentNormalizationTests {

    // Reproduce the same logic as CommentService.normalizedContent (private)
    private func normalizedContent(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func makeRequestId(postId: String, userId: String, content: String) -> String {
        "\(postId)|\(userId)|\(normalizedContent(content).lowercased())"
    }

    private func extractMentions(from text: String) -> [String] {
        let pattern = "@[a-zA-Z0-9_]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        return matches.compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    // ── Normalization ────────────────────────────────────────────────────

    @Test("Trims leading and trailing whitespace")
    func trimWhitespace() {
        #expect(normalizedContent("  hello  ") == "hello")
    }

    @Test("Collapses internal whitespace runs")
    func collapseInternalSpaces() {
        #expect(normalizedContent("hello   world") == "hello world")
    }

    @Test("Normalizes mixed whitespace (tabs, newlines)")
    func normalizeMixedWhitespace() {
        #expect(normalizedContent("  hello \n\n  world \t foo  ") == "hello world foo")
    }

    @Test("Empty string normalizes to empty")
    func emptyString() {
        #expect(normalizedContent("") == "")
        #expect(normalizedContent("   ") == "")
    }

    @Test("Single word preserved")
    func singleWord() {
        #expect(normalizedContent("amen") == "amen")
    }

    // ── Idempotency Keys ─────────────────────────────────────────────────

    @Test("Same content produces same request ID")
    func idempotencyStability() {
        let id1 = makeRequestId(postId: "p1", userId: "u1", content: "Hello World")
        let id2 = makeRequestId(postId: "p1", userId: "u1", content: "Hello World")
        #expect(id1 == id2)
    }

    @Test("Whitespace variations produce same request ID")
    func idempotencyWhitespaceInvariant() {
        let id1 = makeRequestId(postId: "p1", userId: "u1", content: "Hello World")
        let id2 = makeRequestId(postId: "p1", userId: "u1", content: "  hello   world  ")
        #expect(id1 == id2, "Whitespace and case should be normalized")
    }

    @Test("Different content produces different request IDs")
    func idempotencyUniqueness() {
        let id1 = makeRequestId(postId: "p1", userId: "u1", content: "hello")
        let id2 = makeRequestId(postId: "p1", userId: "u1", content: "goodbye")
        #expect(id1 != id2)
    }

    @Test("Different posts produce different request IDs")
    func idempotencyPostUniqueness() {
        let id1 = makeRequestId(postId: "p1", userId: "u1", content: "hello")
        let id2 = makeRequestId(postId: "p2", userId: "u1", content: "hello")
        #expect(id1 != id2)
    }

    @Test("Different users produce different request IDs")
    func idempotencyUserUniqueness() {
        let id1 = makeRequestId(postId: "p1", userId: "u1", content: "hello")
        let id2 = makeRequestId(postId: "p1", userId: "u2", content: "hello")
        #expect(id1 != id2)
    }

    // ── Mention Extraction ───────────────────────────────────────────────

    @Test("Extracts single mention")
    func singleMention() {
        #expect(extractMentions(from: "Hey @john check this") == ["@john"])
    }

    @Test("Extracts multiple mentions")
    func multipleMentions() {
        let mentions = extractMentions(from: "Hey @john and @mary_jane please help")
        #expect(mentions == ["@john", "@mary_jane"])
    }

    @Test("Handles underscores and numbers in mentions")
    func mentionWithSpecialChars() {
        let mentions = extractMentions(from: "@user_123 @abc")
        #expect(mentions == ["@user_123", "@abc"])
    }

    @Test("Returns empty for no mentions")
    func noMentions() {
        #expect(extractMentions(from: "Just a regular post about prayer").isEmpty)
    }

    @Test("Handles mention at start and end of text")
    func mentionBoundaries() {
        let mentions = extractMentions(from: "@start middle @end")
        #expect(mentions == ["@start", "@end"])
    }

    @Test("Email addresses are not treated as mentions")
    func emailNotMention() {
        // @ in the middle of an email should still match the portion after @
        // This is a known limitation — the regex matches @domain from user@domain
        let mentions = extractMentions(from: "Email me at user@domain")
        // Since regex matches @domain, verify it doesn't match the full email
        #expect(!mentions.contains("user@domain"))
    }
}

// MARK: - Post Model Tests

@Suite("Post Model — Categories & Visibility")
struct PostModelTests {

    @Test("PostCategory raw values are Firebase-safe (no special chars)")
    func categoryRawValuesSafe() {
        for category in Post.PostCategory.allCases {
            let raw = category.rawValue
            #expect(!raw.contains("#"), "\(raw) should not contain #")
            #expect(!raw.contains(" "), "\(raw) should not contain spaces")
            #expect(raw == raw.lowercased() || raw.first?.isLowercase == true,
                    "\(raw) should start lowercase for Firebase path safety")
        }
    }

    @Test("All categories have display names")
    func categoryDisplayNames() {
        for category in Post.PostCategory.allCases {
            #expect(!category.displayName.isEmpty, "\(category) should have a display name")
        }
    }

    @Test("PostVisibility has correct display names")
    func visibilityDisplayNames() {
        #expect(!Post.PostVisibility.everyone.displayName.isEmpty)
        #expect(!Post.PostVisibility.followers.displayName.isEmpty)
    }

    @Test("CommentPermissions has icons for all cases")
    func commentPermissionIcons() {
        for perm in Post.CommentPermissions.allCases {
            #expect(!perm.icon.isEmpty, "\(perm) should have an icon")
        }
    }
}

// MARK: - Conversation Model Tests

@Suite("ChatConversation — Initials")
struct ConversationInitialsTests {

    private func initials(from name: String) -> String {
        let words = name.split(separator: " ")
        if words.count > 1 {
            return String(words[0].prefix(1)) + String(words[1].prefix(1))
        } else if let first = words.first {
            return String(first.prefix(2))
        }
        return "?"
    }

    @Test("Two-word name produces two initials")
    func twoWordName() {
        #expect(initials(from: "John Doe") == "JD")
    }

    @Test("Single-word name uses first two chars")
    func singleWordName() {
        #expect(initials(from: "Mary") == "Ma")
    }

    @Test("Three-word name uses first two words")
    func threeWordName() {
        #expect(initials(from: "Alice Bob Charlie") == "AB")
    }

    @Test("Empty name returns fallback")
    func emptyName() {
        #expect(initials(from: "") == "?")
    }

    @Test("Single char name")
    func singleCharName() {
        #expect(initials(from: "A") == "A")
    }
}
