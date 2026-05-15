import Testing
@testable import AMENAPP

// MARK: - Data Model Tests

@Suite("DynamicReplyPreview — model")
struct DynamicReplyPreviewModelTests {

    @Test("isSafe returns true only for approved state")
    func isSafe() {
        let approved = DynamicReplyPreview(id: "1", postId: "p", type: .topReply, previewText: "x", moderationState: "approved")
        let pending  = DynamicReplyPreview(id: "2", postId: "p", type: .topReply, previewText: "x", moderationState: "pending")
        let rejected = DynamicReplyPreview(id: "3", postId: "p", type: .topReply, previewText: "x", moderationState: "rejected")

        #expect(approved.isSafe == true)
        #expect(pending.isSafe == false)
        #expect(rejected.isSafe == false)
    }

    @Test("isExpired returns false when expiresAt is nil")
    func isExpiredNil() {
        let preview = DynamicReplyPreview(id: "1", postId: "p", type: .topReply, previewText: "x", expiresAt: nil)
        #expect(preview.isExpired == false)
    }

    @Test("isExpired returns true when expiresAt is in the past")
    func isExpiredPast() {
        let past = Date().addingTimeInterval(-60)
        let preview = DynamicReplyPreview(id: "1", postId: "p", type: .topReply, previewText: "x", expiresAt: past)
        #expect(preview.isExpired == true)
    }

    @Test("isExpired returns false when expiresAt is in the future")
    func isExpiredFuture() {
        let future = Date().addingTimeInterval(3600)
        let preview = DynamicReplyPreview(id: "1", postId: "p", type: .topReply, previewText: "x", expiresAt: future)
        #expect(preview.isExpired == false)
    }

    @Test("All ReplyPreviewType raw values round-trip through Codable")
    func previewTypeRoundTrip() throws {
        let types: [ReplyPreviewType] = [
            .topReply, .followedReply, .communityPulse,
            .bereanInsight, .prayerMomentum, .trustedCommunitySignal
        ]
        for type in types {
            let encoded = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(ReplyPreviewType.self, from: encoded)
            #expect(decoded == type)
        }
    }

    @Test("DynamicReplyPreview round-trips through Codable")
    func previewCodableRoundTrip() throws {
        let original = DynamicReplyPreview(
            id: "prev-123",
            postId: "post-456",
            replyId: "reply-789",
            type: .followedReply,
            previewText: "This is a test reply",
            authorDisplayName: "TestUser",
            avatarURLs: ["https://example.com/avatar.jpg"],
            participantUserIds: ["uid-1", "uid-2"],
            score: 0.85,
            moderationState: "approved",
            source: "comment"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DynamicReplyPreview.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.postId == original.postId)
        #expect(decoded.replyId == original.replyId)
        #expect(decoded.type == original.type)
        #expect(decoded.previewText == original.previewText)
        #expect(decoded.authorDisplayName == original.authorDisplayName)
        #expect(decoded.avatarURLs == original.avatarURLs)
        #expect(decoded.participantUserIds == original.participantUserIds)
        #expect(decoded.score == original.score)
        #expect(decoded.moderationState == original.moderationState)
        #expect(decoded.source == original.source)
    }

    @Test("avatarURLs defaults to empty when missing from JSON")
    func avatarURLsDefaultsEmpty() throws {
        let json = """
        {"id":"1","postId":"p","type":"topReply","previewText":"hi",
         "authorId":null,"authorDisplayName":null,"score":0.5,
         "moderationState":"approved","source":null,
         "generatedAt":1000000.0,"participantUserIds":[]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DynamicReplyPreview.self, from: json)
        #expect(decoded.avatarURLs == [])
    }

    @Test("moderationState defaults to pending when missing")
    func moderationStateDefaultsPending() throws {
        let json = """
        {"id":"1","postId":"p","type":"topReply","previewText":"hi",
         "authorId":null,"authorDisplayName":null,"score":0.5,
         "source":null,"generatedAt":1000000.0,
         "avatarURLs":[],"participantUserIds":[]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DynamicReplyPreview.self, from: json)
        #expect(decoded.moderationState == "pending")
        #expect(decoded.isSafe == false)
    }
}

// MARK: - Post Model Tests

@Suite("Post — dynamicReplyPreviewCandidates")
struct PostDynamicPreviewFieldTests {

    @Test("dynamicReplyPreviewCandidates defaults to nil")
    func defaultsNil() {
        let post = Post(
            id: UUID(), firebaseId: nil,
            authorId: "uid-1", authorName: "Test", authorUsername: nil, authorInitials: "T",
            timeAgo: "1m", content: "Hello", category: .openTable,
            visibility: .everyone, allowComments: true,
            linkURL: nil, linkPreviewTitle: nil, linkPreviewDescription: nil,
            linkPreviewImageURL: nil, linkPreviewSiteName: nil, linkPreviewType: nil,
            verseReference: nil, verseText: nil,
            createdAt: Date(),
            amenCount: 0, lightbulbCount: 0, commentCount: 0, repostCount: 0
        )
        #expect(post.dynamicReplyPreviewCandidates == nil)
    }

    @Test("dynamicReplyPreviewCandidates can be set")
    func canBeSet() {
        var post = Post(
            id: UUID(), firebaseId: nil,
            authorId: "uid-1", authorName: "Test", authorUsername: nil, authorInitials: "T",
            timeAgo: "1m", content: "Hello", category: .openTable,
            visibility: .everyone, allowComments: true,
            linkURL: nil, linkPreviewTitle: nil, linkPreviewDescription: nil,
            linkPreviewImageURL: nil, linkPreviewSiteName: nil, linkPreviewType: nil,
            verseReference: nil, verseText: nil,
            createdAt: Date(),
            amenCount: 0, lightbulbCount: 0, commentCount: 0, repostCount: 0
        )
        post.dynamicReplyPreviewCandidates = [.previewTopReply, .previewPrayer]
        #expect(post.dynamicReplyPreviewCandidates?.count == 2)
    }
}

// MARK: - Rotator Logic Tests

@Suite("LiquidReplyPreviewRotator — candidate filtering")
struct RotatorCandidateFilteringTests {

    private func safeCandidates(from candidates: [DynamicReplyPreview]) -> [DynamicReplyPreview] {
        candidates
            .filter { $0.isSafe && !$0.isExpired }
            .sorted { $0.score > $1.score }
    }

    @Test("Filters out non-approved candidates")
    func filtersUnsafe() {
        let candidates = [
            DynamicReplyPreview(id: "1", postId: "p", type: .topReply, previewText: "a", moderationState: "approved"),
            DynamicReplyPreview(id: "2", postId: "p", type: .topReply, previewText: "b", moderationState: "pending"),
            DynamicReplyPreview(id: "3", postId: "p", type: .topReply, previewText: "c", moderationState: "rejected"),
        ]
        let result = safeCandidates(from: candidates)
        #expect(result.count == 1)
        #expect(result.first?.id == "1")
    }

    @Test("Filters out expired candidates")
    func filtersExpired() {
        let past = Date().addingTimeInterval(-60)
        let candidates = [
            DynamicReplyPreview(id: "1", postId: "p", type: .topReply, previewText: "a", score: 0.9, expiresAt: nil),
            DynamicReplyPreview(id: "2", postId: "p", type: .topReply, previewText: "b", score: 0.8, expiresAt: past),
        ]
        let result = safeCandidates(from: candidates)
        #expect(result.count == 1)
        #expect(result.first?.id == "1")
    }

    @Test("Sorts by score descending")
    func sortsByScore() {
        let candidates = [
            DynamicReplyPreview(id: "low",  postId: "p", type: .topReply, previewText: "x", score: 0.3),
            DynamicReplyPreview(id: "high", postId: "p", type: .topReply, previewText: "x", score: 0.9),
            DynamicReplyPreview(id: "mid",  postId: "p", type: .topReply, previewText: "x", score: 0.6),
        ]
        let result = safeCandidates(from: candidates)
        #expect(result.map(\.id) == ["high", "mid", "low"])
    }

    @Test("Returns empty when all candidates are unsafe")
    func allUnsafeReturnsEmpty() {
        let candidates = [
            DynamicReplyPreview(id: "1", postId: "p", type: .topReply, previewText: "x", moderationState: "pending"),
            DynamicReplyPreview(id: "2", postId: "p", type: .topReply, previewText: "x", moderationState: "rejected"),
        ]
        let result = safeCandidates(from: candidates)
        #expect(result.isEmpty)
    }

    @Test("Single approved candidate passes through")
    func singleApproved() {
        let candidates = [
            DynamicReplyPreview(id: "1", postId: "p", type: .prayerMomentum,
                                previewText: "3 people are praying", score: 0.78)
        ]
        let result = safeCandidates(from: candidates)
        #expect(result.count == 1)
        #expect(result.first?.type == .prayerMomentum)
    }
}
