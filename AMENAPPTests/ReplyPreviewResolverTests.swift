// ReplyPreviewResolverTests.swift
// AMENAPPTests
//
// CONTRACT: CONTRACT.md v1.0.1 — Section 13 (Resolver Ladder), Section 15 (Scoring)
//
// Covers all 10 selection-ladder branches with the Swift Testing framework.
// These are pure-logic tests: no Firebase, no network, no MainActor required.

import Testing
import Foundation
@testable import AMENAPP

// MARK: - Fixtures

private extension Date {
    /// A date exactly `hours` before `now`.
    static func hoursAgo(_ hours: Double) -> Date {
        Date(timeIntervalSinceNow: -hours * 3600)
    }
}

private func makeCandidate(
    id: String = UUID().uuidString,
    postId: String = "post-1",
    authorUID: String = "uid-unknown",
    authorDisplayName: String = "Author",
    text: String = "Test reply text",
    relevanceScore: Double = 0.8,
    spiritualUsefulness: Double = 0.8,
    engagementScore: Double = 0.8,
    createdAt: Date = .hoursAgo(1),
    safetyPassed: Bool = true
) -> ReplyCandidate {
    ReplyCandidate(
        id: id,
        postId: postId,
        authorUID: authorUID,
        authorDisplayName: authorDisplayName,
        text: text,
        relevanceScore: relevanceScore,
        spiritualUsefulness: spiritualUsefulness,
        engagementScore: engagementScore,
        createdAt: createdAt,
        safetyPassed: safetyPassed
    )
}

private func makeBereanInsight(
    postId: String = "post-1",
    displayText: String = "replies centered on hope",
    confidence: Double = 0.85,
    safetyPassed: Bool = true
) -> BereanInsightInput {
    BereanInsightInput(
        postId: postId,
        displayText: displayText,
        confidence: confidence,
        safetyPassed: safetyPassed
    )
}

private func makePulse(
    postId: String = "post-1",
    displayText: String = "grief, hope, faith",
    participantUserIds: [String] = ["uid-a", "uid-b", "uid-c"],
    safetyPassed: Bool = true
) -> CommunityPulseInput {
    CommunityPulseInput(
        postId: postId,
        displayText: displayText,
        participantUserIds: participantUserIds,
        safetyPassed: safetyPassed
    )
}

/// Constructs a DynamicReplyPreview for client-side resolver tests.
private func makeDynamicPreview(
    id: String = UUID().uuidString,
    postId: String = "post-1",
    type: ReplyPreviewType = .topReply,
    previewText: String = "Test preview",
    authorId: String? = nil,
    participantUserIds: [String] = [],
    score: Double = 0.8,
    moderationState: String = "approved",
    expiresAt: Date? = nil
) -> DynamicReplyPreview {
    DynamicReplyPreview(
        id: id,
        postId: postId,
        type: type,
        previewText: previewText,
        authorId: authorId,
        participantUserIds: participantUserIds,
        score: score,
        expiresAt: expiresAt,
        moderationState: moderationState
    )
}

// MARK: - Backend Resolver Ladder Tests (10 branches)
// Tests BackendReplyPreviewResolver — the scoring-aware backend ladder struct.

struct ReplyPreviewResolverTests {

    let resolver = BackendReplyPreviewResolver()

    // MARK: Branch 1 — followedReply: viewer follows a safe candidate

    @Test func branch1_followedReplySafeCandidate() {
        let followedUID = "uid-followed"
        let candidate = makeCandidate(authorUID: followedUID, text: "Blessed reply")
        let viewerFollows: Set<String> = [followedUID]

        let result = resolver.resolve(
            postId: "post-1",
            candidates: [candidate],
            viewerUID: "uid-viewer",
            viewerFollows: viewerFollows,
            replyCount: 20
        )

        #expect(result != nil)
        #expect(result?.type == .followedReply)
        #expect(result?.text == "Blessed reply")
        #expect(result?.authorUID == followedUID)
    }

    // MARK: Branch 2 — followedReply skipped: viewer is signed out (empty UID)

    @Test func branch2_followedReplySkippedWhenSignedOut() {
        let followedUID = "uid-followed"
        let candidate = makeCandidate(authorUID: followedUID, text: "Should not surface")
        let viewerFollows: Set<String> = [followedUID]

        // No berean, no pulse, one safe topReply candidate → should fall to topReply
        let result = resolver.resolve(
            postId: "post-1",
            candidates: [candidate],
            viewerUID: "",            // signed-out: step 1 skipped
            viewerFollows: viewerFollows,
            replyCount: 3             // below berean and pulse thresholds
        )

        #expect(result != nil)
        #expect(result?.type == .topReply)
    }

    // MARK: Branch 3 — followedReply skipped: viewer follows nobody in candidate set

    @Test func branch3_followedReplySkippedWhenNoFollowedCandidates() {
        let candidate = makeCandidate(authorUID: "uid-stranger", text: "Stranger reply")
        let viewerFollows: Set<String> = ["uid-someone-else"]  // doesn't overlap

        // replyCount >= 5 and pulse provided → should land on communityPulse
        let pulse = makePulse()
        let result = resolver.resolve(
            postId: "post-1",
            candidates: [candidate],
            viewerUID: "uid-viewer",
            viewerFollows: viewerFollows,
            replyCount: 5,
            pulseCandidate: pulse
        )

        #expect(result?.type == .communityPulse)
    }

    // MARK: Branch 4 — bereanInsight: confidence and volume both qualify

    @Test func branch4_bereanInsightQualifies() {
        let insight = makeBereanInsight(confidence: 0.72)   // exactly at threshold

        let result = resolver.resolve(
            postId: "post-1",
            candidates: [],           // no followed candidates
            viewerUID: "uid-viewer",
            viewerFollows: [],
            replyCount: 12,           // exactly at berean volume threshold
            bereanInsight: insight
        )

        #expect(result != nil)
        #expect(result?.type == .bereanInsight)
        #expect(result?.text == insight.displayText)
    }

    // MARK: Branch 5 — bereanInsight skipped: confidence below 0.72

    @Test func branch5_bereanInsightSkippedLowConfidence() {
        let insight = makeBereanInsight(confidence: 0.71)   // just below threshold
        let candidate = makeCandidate(text: "Community top reply")

        let result = resolver.resolve(
            postId: "post-1",
            candidates: [candidate],
            viewerUID: "uid-viewer",
            viewerFollows: [],
            replyCount: 12,
            bereanInsight: insight
        )

        // Should fall through berean → no pulse → topReply
        #expect(result?.type == .topReply)
    }

    // MARK: Branch 6 — bereanInsight skipped: replyCount below 12

    @Test func branch6_bereanInsightSkippedLowVolume() {
        let insight = makeBereanInsight(confidence: 0.95)   // confidence fine
        let pulse = makePulse()

        let result = resolver.resolve(
            postId: "post-1",
            candidates: [],
            viewerUID: "uid-viewer",
            viewerFollows: [],
            replyCount: 11,           // one below berean threshold
            bereanInsight: insight,
            pulseCandidate: pulse
        )

        // Berean skipped (volume too low), pulse qualifies (>= 5)
        #expect(result?.type == .communityPulse)
    }

    // MARK: Branch 7 — communityPulse: volume gate passed, safetyPassed true

    @Test func branch7_communityPulseQualifies() {
        let pulse = makePulse(displayText: "grief, hope, faith", participantUserIds: ["uid-a", "uid-b"])

        let result = resolver.resolve(
            postId: "post-1",
            candidates: [],
            viewerUID: "uid-viewer",
            viewerFollows: [],
            replyCount: 5,            // exactly at pulse volume threshold
            pulseCandidate: pulse
        )

        #expect(result != nil)
        #expect(result?.type == .communityPulse)
        #expect(result?.text == "grief, hope, faith")
    }

    // MARK: Branch 8 — communityPulse skipped: replyCount below 5

    @Test func branch8_communityPulseSkippedLowVolume() {
        let pulse = makePulse()
        let candidate = makeCandidate(text: "Only reply")

        let result = resolver.resolve(
            postId: "post-1",
            candidates: [candidate],
            viewerUID: "uid-viewer",
            viewerFollows: [],
            replyCount: 4,            // one below pulse threshold
            pulseCandidate: pulse
        )

        // Pulse skipped → topReply
        #expect(result?.type == .topReply)
    }

    // MARK: Branch 9 — topReply: no berean/pulse, one safe candidate

    @Test func branch9_topReplyFallback() {
        let candidate = makeCandidate(text: "Great insight here")

        let result = resolver.resolve(
            postId: "post-1",
            candidates: [candidate],
            viewerUID: "uid-viewer",
            viewerFollows: [],
            replyCount: 3             // below all volume gates
        )

        #expect(result != nil)
        #expect(result?.type == .topReply)
        #expect(result?.text == "Great insight here")
    }

    // MARK: Branch 10 — nil: no candidates pass safety, no berean, no pulse

    @Test func branch10_nilWhenNothingQualifies() {
        let unsafeCandidate = makeCandidate(safetyPassed: false)

        let result = resolver.resolve(
            postId: "post-1",
            candidates: [unsafeCandidate],
            viewerUID: "uid-viewer",
            viewerFollows: [],
            replyCount: 2
        )

        #expect(result == nil)
    }
}

// MARK: - Scoring Formula Tests
// Tests BackendReplyPreviewResolver static scoring methods (Section 15).

struct ReplyPreviewScoringTests {

    // MARK: compositeScore formula (Section 15)

    @Test func compositeScoreFreshCandidate() {
        // A brand-new candidate (0 hours old) has recencyScore = 1.0
        let candidate = makeCandidate(
            relevanceScore: 1.0,
            spiritualUsefulness: 1.0,
            engagementScore: 1.0,
            createdAt: Date()         // now = recencyScore 1.0
        )
        let score = BackendReplyPreviewResolver.compositeScore(for: candidate, now: Date())
        // 0.35×1 + 0.25×1 + 0.25×1 + 0.15×1 = 1.0
        #expect(score > 0.99)
        #expect(score <= 1.0)
    }

    @Test func compositeScoreFullyDecayedCandidate() {
        // 168+ hours old → recencyScore = 0.0
        let candidate = makeCandidate(
            relevanceScore: 1.0,
            spiritualUsefulness: 1.0,
            engagementScore: 1.0,
            createdAt: .hoursAgo(168)
        )
        let score = BackendReplyPreviewResolver.compositeScore(for: candidate, now: Date())
        // 0.35 + 0.25 + 0.25 + 0 = 0.85
        #expect(abs(score - 0.85) < 0.001)
    }

    @Test func highestScoredPicksBestCandidate() {
        let weak = makeCandidate(
            id: "weak",
            relevanceScore: 0.1,
            spiritualUsefulness: 0.1,
            engagementScore: 0.1,
            createdAt: .hoursAgo(100)
        )
        let strong = makeCandidate(
            id: "strong",
            relevanceScore: 0.9,
            spiritualUsefulness: 0.9,
            engagementScore: 0.9,
            createdAt: Date()
        )
        let best = BackendReplyPreviewResolver.highestScored([weak, strong])
        #expect(best?.id == "strong")
    }
}

// MARK: - contentHash Stability Tests
// BackendReplyPreviewResolver produces ResolvedReplyPreview with a SHA-256 contentHash.

struct ReplyPreviewHashTests {

    @Test func contentHashIsDeterministic() {
        let resolver = BackendReplyPreviewResolver()

        let candidate = makeCandidate(authorUID: "uid-x", text: "Romans 8:28")
        let result1 = resolver.resolve(
            postId: "post-hash",
            candidates: [candidate],
            viewerUID: "uid-viewer",
            viewerFollows: [],
            replyCount: 1
        )
        let result2 = resolver.resolve(
            postId: "post-hash",
            candidates: [candidate],
            viewerUID: "uid-viewer",
            viewerFollows: [],
            replyCount: 1
        )

        #expect(result1?.contentHash == result2?.contentHash)
    }

    @Test func contentHashChangesWithDifferentText() {
        let resolver = BackendReplyPreviewResolver()

        let c1 = makeCandidate(authorUID: "uid-a", text: "Text A")
        let c2 = makeCandidate(authorUID: "uid-a", text: "Text B")

        let r1 = resolver.resolve(
            postId: "post-hash",
            candidates: [c1],
            viewerUID: "",
            viewerFollows: [],
            replyCount: 1
        )
        let r2 = resolver.resolve(
            postId: "post-hash",
            candidates: [c2],
            viewerUID: "",
            viewerFollows: [],
            replyCount: 1
        )

        #expect(r1?.contentHash != r2?.contentHash)
    }

    @Test func contentHashIsIdProperty() {
        let resolver = BackendReplyPreviewResolver()
        let candidate = makeCandidate(text: "Hash test")

        let result = resolver.resolve(
            postId: "post-id-test",
            candidates: [candidate],
            viewerUID: "",
            viewerFollows: [],
            replyCount: 1
        )

        #expect(result?.id == result?.contentHash)
    }
}

// MARK: - Client-Side Display Selector Tests
// Tests ReplyPreviewResolver (@MainActor class) — selects from DynamicReplyPreview
// documents already written to Firestore. No scoring; pure priority-ladder + safety gate.

@MainActor
struct ClientReplyPreviewResolverTests {

    let resolver = ReplyPreviewResolver()

    // MARK: Safety gate — only "approved", non-expired previews are eligible

    @Test func safetyGateFiltersUnapproved() {
        let rejected = makeDynamicPreview(
            type: .topReply,
            previewText: "Should not show",
            score: 0.99,
            moderationState: "rejected"
        )
        let result = resolver.resolve(candidates: [rejected], viewerFollowing: [])
        #expect(result == nil)
    }

    @Test func safetyGateFiltersPending() {
        let pending = makeDynamicPreview(
            type: .topReply,
            previewText: "Pending moderation",
            score: 0.99,
            moderationState: "pending"
        )
        let result = resolver.resolve(candidates: [pending], viewerFollowing: [])
        #expect(result == nil)
    }

    @Test func safetyGateFiltersExpiredPreviews() {
        let expired = makeDynamicPreview(
            type: .topReply,
            previewText: "Expired preview",
            score: 0.99,
            expiresAt: Date(timeIntervalSinceNow: -1)  // expired 1 second ago
        )
        let result = resolver.resolve(candidates: [expired], viewerFollowing: [])
        #expect(result == nil)
    }

    // MARK: Priority: followedReply > bereanInsight > communityPulse > topReply

    @Test func clientPriority_followedReplyWinsOverTopReply() {
        let followedUID = "uid-followed"
        let topReply = makeDynamicPreview(
            id: "top",
            type: .topReply,
            previewText: "Top reply",
            score: 0.95
        )
        let followed = makeDynamicPreview(
            id: "followed",
            type: .followedReply,
            previewText: "Followed reply",
            participantUserIds: [followedUID],
            score: 0.5   // lower raw score but higher priority
        )
        let result = resolver.resolve(
            candidates: [topReply, followed],
            viewerFollowing: [followedUID]
        )
        #expect(result?.id == "followed")
        #expect(result?.type == .followedReply)
    }

    @Test func clientPriority_bereanInsightWinsOverCommunityPulse() {
        let berean = makeDynamicPreview(
            id: "berean",
            type: .bereanInsight,
            previewText: "Berean insight text",
            score: 0.6
        )
        let pulse = makeDynamicPreview(
            id: "pulse",
            type: .communityPulse,
            previewText: "Community pulse text",
            score: 0.9   // higher score but lower priority
        )
        let result = resolver.resolve(
            candidates: [berean, pulse],
            viewerFollowing: []
        )
        #expect(result?.id == "berean")
        #expect(result?.type == .bereanInsight)
    }

    @Test func clientPriority_communityPulseWinsOverTopReply() {
        let pulse = makeDynamicPreview(
            id: "pulse",
            type: .communityPulse,
            previewText: "Community pulse text",
            score: 0.6
        )
        let top = makeDynamicPreview(
            id: "top",
            type: .topReply,
            previewText: "Top reply text",
            score: 0.9
        )
        let result = resolver.resolve(
            candidates: [pulse, top],
            viewerFollowing: []
        )
        #expect(result?.id == "pulse")
        #expect(result?.type == .communityPulse)
    }

    @Test func clientPriority_topReplyFallback() {
        let top = makeDynamicPreview(
            id: "top",
            type: .topReply,
            previewText: "Fallback top reply",
            score: 0.75
        )
        let result = resolver.resolve(
            candidates: [top],
            viewerFollowing: []
        )
        #expect(result?.id == "top")
        #expect(result?.type == .topReply)
    }

    @Test func clientFollowedReplyRequiresParticipantOverlap() {
        // A followedReply whose participantUserIds do NOT overlap → skipped
        let nonOverlapping = makeDynamicPreview(
            id: "followed-no-overlap",
            type: .followedReply,
            previewText: "No overlap followed reply",
            participantUserIds: ["uid-other"],
            score: 0.99
        )
        let top = makeDynamicPreview(
            id: "top",
            type: .topReply,
            previewText: "Fallback",
            score: 0.5
        )
        let result = resolver.resolve(
            candidates: [nonOverlapping, top],
            viewerFollowing: ["uid-different"]  // no overlap with uid-other
        )
        #expect(result?.id == "top")
        #expect(result?.type == .topReply)
    }

    @Test func clientHighestScoreWinsWithinSameType() {
        let low = makeDynamicPreview(
            id: "low",
            type: .topReply,
            previewText: "Low score",
            score: 0.4
        )
        let high = makeDynamicPreview(
            id: "high",
            type: .topReply,
            previewText: "High score",
            score: 0.9
        )
        let result = resolver.resolve(
            candidates: [low, high],
            viewerFollowing: []
        )
        #expect(result?.id == "high")
    }

    @Test func clientNilWhenNoCandidatesQualify() {
        let result = resolver.resolve(candidates: [], viewerFollowing: [])
        #expect(result == nil)
    }
}
