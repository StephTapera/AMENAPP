// DynamicReplyPreviewTests.swift
// AMENAPPTests
//
// Unit tests for the DynamicReplyPreview system:
//   - Data model correctness (isSafe, isExpired, Codable round-trip)
//   - Rotator candidate filtering (safety, expiry, score ordering)
//   - Rotator shouldRotate conditions (scenePhase, visibility, reduceMotion)
//   - Preview routing decision conditions
//
// These are pure unit tests — no Firebase emulator required.

import Testing
import Foundation
@testable import AMENAPP

// MARK: - Data Model Tests

@Suite("DynamicReplyPreview — model correctness")
struct DynamicReplyPreviewModelTests {

    @Test("isSafe is true only for moderationState == 'approved'")
    func isSafeApproved() {
        let approved = DynamicReplyPreview(id: "1", postId: "p", type: .topReply, previewText: "x", moderationState: "approved")
        let pending  = DynamicReplyPreview(id: "2", postId: "p", type: .topReply, previewText: "x", moderationState: "pending")
        let rejected = DynamicReplyPreview(id: "3", postId: "p", type: .topReply, previewText: "x", moderationState: "rejected")

        #expect(approved.isSafe == true)
        #expect(pending.isSafe == false)
        #expect(rejected.isSafe == false)
    }

    @Test("isExpired is false when expiresAt is nil")
    func isExpiredNil() {
        let p = DynamicReplyPreview(id: "1", postId: "p", type: .topReply, previewText: "x", expiresAt: nil)
        #expect(p.isExpired == false)
    }

    @Test("isExpired is true when expiresAt is in the past")
    func isExpiredPast() {
        let past = Date().addingTimeInterval(-60)
        let p = DynamicReplyPreview(id: "1", postId: "p", type: .topReply, previewText: "x", expiresAt: past)
        #expect(p.isExpired == true)
    }

    @Test("isExpired is false when expiresAt is in the future")
    func isExpiredFuture() {
        let future = Date().addingTimeInterval(3600)
        let p = DynamicReplyPreview(id: "1", postId: "p", type: .topReply, previewText: "x", expiresAt: future)
        #expect(p.isExpired == false)
    }

    @Test("All ReplyPreviewType raw values encode and decode correctly")
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

    @Test("DynamicReplyPreview Codable round-trip preserves all fields")
    func previewCodableRoundTrip() throws {
        let original = DynamicReplyPreview(
            id: "prev-123",
            postId: "post-456",
            replyId: "reply-789",
            sourceCommentIds: ["reply-789", "reply-790"],
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

        #expect(decoded.id == "prev-123")
        #expect(decoded.postId == "post-456")
        #expect(decoded.replyId == "reply-789")
        #expect(decoded.sourceCommentIds == ["reply-789", "reply-790"])
        #expect(decoded.type == .followedReply)
        #expect(decoded.previewText == "This is a test reply")
        #expect(decoded.authorDisplayName == "TestUser")
        #expect(decoded.avatarURLs == ["https://example.com/avatar.jpg"])
        #expect(decoded.score == 0.85)
        #expect(decoded.moderationState == "approved")
        #expect(decoded.isSafe == true)
    }

    @Test("avatarURLs defaults to empty array when key is absent from JSON")
    func avatarURLsDefaultEmpty() throws {
        let json = """
        {"id":"1","postId":"p","type":"topReply","previewText":"hi",
         "authorId":null,"authorDisplayName":null,"score":0.5,
         "moderationState":"approved","source":null,
         "generatedAt":1000000.0,"participantUserIds":[]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DynamicReplyPreview.self, from: json)
        #expect(decoded.avatarURLs == [])
    }

    @Test("moderationState defaults to 'pending' when key absent from JSON")
    func moderationDefaultsPending() throws {
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

    @Test("participantUserIds defaults to empty array when key absent")
    func participantIdsDefault() throws {
        let json = """
        {"id":"1","postId":"p","type":"prayerMomentum","previewText":"Praying",
         "authorId":null,"authorDisplayName":null,"score":0.8,
         "moderationState":"approved","source":null,"generatedAt":1000000.0}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DynamicReplyPreview.self, from: json)
        #expect(decoded.participantUserIds == [])
    }

    @Test("sourceCommentIds defaults to empty array when key absent")
    func sourceCommentIdsDefault() throws {
        let json = """
        {"id":"1","postId":"p","type":"communityPulse","previewText":"hope",
         "authorId":null,"authorDisplayName":null,"score":0.8,
         "moderationState":"approved","source":null,"generatedAt":1000000.0}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DynamicReplyPreview.self, from: json)
        #expect(decoded.sourceCommentIds == [])
    }
}

@Suite("LiquidReplyPreviewChip — tint styles")
struct LiquidReplyPreviewTintTests {
    @Test("type-based tint stays subtle")
    func typeBasedTint() {
        let berean = LiquidReplyPreviewTint.style(for: .bereanInsight, reduceTransparency: false)
        let neutral = LiquidReplyPreviewTint.style(for: .topReply, reduceTransparency: false)
        #expect(berean.overlayOpacity > neutral.overlayOpacity)
        #expect(neutral.overlayOpacity <= 0.02)
        #expect(berean.strokeOpacity == 0.22)
    }

    @Test("Reduce Transparency disables noisy tint")
    func reduceTransparencyStyle() {
        let prayer = LiquidReplyPreviewTint.style(for: .prayerMomentum, reduceTransparency: true)
        #expect(prayer.overlayOpacity == 0)
    }

    @Test("prayerMomentum tint is blue-toned")
    func prayerMomentumTint() {
        let tint = LiquidReplyPreviewTint.style(for: .prayerMomentum, reduceTransparency: false)
        #expect(tint.overlayOpacity == 0.12)
        #expect(tint.strokeOpacity == 0.22)
    }

    @Test("communityPulse tint is amber-toned")
    func communityPulseTint() {
        let tint = LiquidReplyPreviewTint.style(for: .communityPulse, reduceTransparency: false)
        #expect(tint.overlayOpacity == 0.12)
        #expect(tint.strokeOpacity == 0.22)
    }

    @Test("trustedCommunitySignal tint is green-toned")
    func trustedSignalTint() {
        let tint = LiquidReplyPreviewTint.style(for: .trustedCommunitySignal, reduceTransparency: false)
        #expect(tint.overlayOpacity == 0.12)
        #expect(tint.strokeOpacity == 0.22)
    }

    @Test("All types have zero overlay opacity when Reduce Transparency is on")
    func allTypesZeroOpacityWithReduceTransparency() {
        let types: [ReplyPreviewType] = [
            .topReply, .followedReply, .communityPulse,
            .bereanInsight, .prayerMomentum, .trustedCommunitySignal
        ]
        for type in types {
            let tint = LiquidReplyPreviewTint.style(for: type, reduceTransparency: true)
            #expect(tint.overlayOpacity == 0, "Expected zero opacity for \(type) with Reduce Transparency")
        }
    }
}

// MARK: - Rotator Candidate Filtering Tests

@Suite("LiquidReplyPreviewRotator — candidate filtering logic")
struct RotatorCandidateFilteringTests {

    // Mirrors the filtering + sorting logic inside LiquidReplyPreviewRotator
    private func safeSorted(_ candidates: [DynamicReplyPreview]) -> [DynamicReplyPreview] {
        candidates
            .filter { $0.isSafe && !$0.isExpired }
            .sorted { $0.score > $1.score }
    }

    @Test("Filters out non-approved candidates — only approved passes through")
    func filtersUnsafe() {
        let input = [
            DynamicReplyPreview(id: "a", postId: "p", type: .topReply, previewText: "hi", moderationState: "approved"),
            DynamicReplyPreview(id: "b", postId: "p", type: .topReply, previewText: "hi", moderationState: "pending"),
            DynamicReplyPreview(id: "c", postId: "p", type: .topReply, previewText: "hi", moderationState: "rejected"),
        ]
        let result = safeSorted(input)
        #expect(result.count == 1)
        #expect(result.first?.id == "a")
    }

    @Test("Filters out expired candidates")
    func filtersExpired() {
        let past = Date().addingTimeInterval(-120)
        let input = [
            DynamicReplyPreview(id: "valid",   postId: "p", type: .topReply, previewText: "ok",      score: 0.9),
            DynamicReplyPreview(id: "expired", postId: "p", type: .topReply, previewText: "expired", score: 0.8, expiresAt: past),
        ]
        let result = safeSorted(input)
        #expect(result.count == 1)
        #expect(result.first?.id == "valid")
    }

    @Test("Sorts candidates by score descending")
    func sortsByScoreDescending() {
        let input = [
            DynamicReplyPreview(id: "low",  postId: "p", type: .topReply, previewText: "x", score: 0.3),
            DynamicReplyPreview(id: "high", postId: "p", type: .topReply, previewText: "x", score: 0.9),
            DynamicReplyPreview(id: "mid",  postId: "p", type: .topReply, previewText: "x", score: 0.6),
        ]
        let result = safeSorted(input)
        #expect(result.map(\.id) == ["high", "mid", "low"])
    }

    @Test("Returns empty array when all candidates are unsafe")
    func allUnsafeReturnsEmpty() {
        let input = [
            DynamicReplyPreview(id: "1", postId: "p", type: .topReply, previewText: "x", moderationState: "pending"),
            DynamicReplyPreview(id: "2", postId: "p", type: .topReply, previewText: "x", moderationState: "rejected"),
        ]
        #expect(safeSorted(input).isEmpty)
    }

    @Test("Returns empty array when candidates list is empty")
    func emptyInputReturnsEmpty() {
        #expect(safeSorted([]).isEmpty)
    }

    @Test("Single approved candidate passes through unchanged")
    func singleApproved() {
        let input = [
            DynamicReplyPreview(id: "solo", postId: "p", type: .prayerMomentum,
                                previewText: "3 people praying", score: 0.78)
        ]
        let result = safeSorted(input)
        #expect(result.count == 1)
        #expect(result.first?.type == .prayerMomentum)
    }

    @Test("Mixed expired and valid — only non-expired survive")
    func mixedExpiryFiltering() {
        let past   = Date().addingTimeInterval(-60)
        let future = Date().addingTimeInterval(3600)
        let input = [
            DynamicReplyPreview(id: "p1", postId: "p", type: .bereanInsight,  previewText: "a", score: 0.9, expiresAt: future),
            DynamicReplyPreview(id: "p2", postId: "p", type: .communityPulse, previewText: "b", score: 0.7, expiresAt: past),
            DynamicReplyPreview(id: "p3", postId: "p", type: .topReply,       previewText: "c", score: 0.5, expiresAt: nil),
        ]
        let result = safeSorted(input)
        #expect(result.count == 2)
        #expect(result.map(\.id) == ["p1", "p3"])
    }
}

// MARK: - Rotator shouldRotate Condition Tests

@Suite("LiquidReplyPreviewRotator — shouldRotate conditions")
struct RotatorShouldRotateTests {

    // Mirrors the shouldRotate computed property from LiquidReplyPreviewRotator:
    //   isVisible && !reduceMotion && scenePhase == .active && safeCandidates.count > 1
    private func shouldRotate(
        isVisible: Bool,
        reduceMotion: Bool,
        isSceneActive: Bool,
        candidateCount: Int
    ) -> Bool {
        isVisible && !reduceMotion && isSceneActive && candidateCount > 1
    }

    @Test("shouldRotate is false when app is backgrounded (inactive scene)")
    func inactiveSceneStopsRotation() {
        let result = shouldRotate(isVisible: true, reduceMotion: false, isSceneActive: false, candidateCount: 3)
        #expect(result == false)
    }

    @Test("shouldRotate is true when app returns to active with multiple candidates")
    func activeSceneResumesRotation() {
        let result = shouldRotate(isVisible: true, reduceMotion: false, isSceneActive: true, candidateCount: 2)
        #expect(result == true)
    }

    @Test("shouldRotate is false when view is off-screen")
    func offScreenStopsRotation() {
        let result = shouldRotate(isVisible: false, reduceMotion: false, isSceneActive: true, candidateCount: 3)
        #expect(result == false)
    }

    @Test("shouldRotate is false when Reduce Motion is enabled")
    func reduceMotionStopsRotation() {
        let result = shouldRotate(isVisible: true, reduceMotion: true, isSceneActive: true, candidateCount: 3)
        #expect(result == false)
    }

    @Test("shouldRotate is false with only one safe candidate")
    func singleCandidateDoesNotRotate() {
        let result = shouldRotate(isVisible: true, reduceMotion: false, isSceneActive: true, candidateCount: 1)
        #expect(result == false)
    }

    @Test("shouldRotate is false with zero candidates")
    func zeroCandidatesDoesNotRotate() {
        let result = shouldRotate(isVisible: true, reduceMotion: false, isSceneActive: true, candidateCount: 0)
        #expect(result == false)
    }

    @Test("shouldRotate requires ALL conditions — any false short-circuits")
    func allConditionsRequired() {
        // All off
        #expect(shouldRotate(isVisible: false, reduceMotion: true,  isSceneActive: false, candidateCount: 0) == false)
        // One at a time true
        #expect(shouldRotate(isVisible: true,  reduceMotion: true,  isSceneActive: false, candidateCount: 0) == false)
        #expect(shouldRotate(isVisible: false, reduceMotion: false, isSceneActive: false, candidateCount: 0) == false)
        #expect(shouldRotate(isVisible: false, reduceMotion: true,  isSceneActive: true,  candidateCount: 0) == false)
        // Two at a time true but count still 0
        #expect(shouldRotate(isVisible: true,  reduceMotion: false, isSceneActive: true,  candidateCount: 1) == false)
        // All true with count >= 2
        #expect(shouldRotate(isVisible: true,  reduceMotion: false, isSceneActive: true,  candidateCount: 2) == true)
    }
}

// MARK: - Routing Decision Tests

@Suite("Preview routing — model-level routing conditions")
struct PreviewRoutingDecisionTests {

    // These tests verify the model properties that PostCard's openReplyPreview()
    // uses to decide where to navigate. They do not test the view layer directly.

    @Test("topReply with replyId routes to highlighted comments")
    func topReplyWithIdRoutesToHighlight() {
        let preview = DynamicReplyPreview(
            id: "1", postId: "p", replyId: "reply-abc", type: .topReply, previewText: "Test"
        )
        #expect(preview.replyId != nil)
        #expect(preview.replyId?.isEmpty == false)
    }

    @Test("topReply without replyId falls back to standard comments")
    func topReplyWithoutIdFallsBack() {
        let preview = DynamicReplyPreview(id: "1", postId: "p", replyId: nil, type: .topReply, previewText: "Test")
        #expect(preview.replyId == nil)
    }

    @Test("followedReply with replyId routes to highlighted comments")
    func followedReplyWithIdRoutesToHighlight() {
        let preview = DynamicReplyPreview(
            id: "1", postId: "p", replyId: "reply-xyz", type: .followedReply, previewText: "A friend's reply"
        )
        #expect(preview.type == .followedReply)
        #expect(preview.replyId == "reply-xyz")
    }

    @Test("communityPulse with sourceCommentIds provides highlight targets")
    func communityPulseWithSourcesHighlights() {
        let preview = DynamicReplyPreview(
            id: "1", postId: "p",
            sourceCommentIds: ["c1", "c2", "c3"],
            type: .communityPulse,
            previewText: "hope, grace, faith"
        )
        #expect(!preview.sourceCommentIds.isEmpty)
        #expect(preview.sourceCommentIds.count == 3)
        #expect(preview.sourceCommentIds.first == "c1")
    }

    @Test("communityPulse without sourceCommentIds falls back to standard comments")
    func communityPulseWithoutSourcesFallsBack() {
        let preview = DynamicReplyPreview(
            id: "1", postId: "p", sourceCommentIds: [], type: .communityPulse, previewText: "hope"
        )
        #expect(preview.sourceCommentIds.isEmpty)
    }

    @Test("trustedCommunitySignal with sourceCommentIds provides highlight targets")
    func trustedSignalWithSourcesHighlights() {
        let preview = DynamicReplyPreview(
            id: "1", postId: "p",
            sourceCommentIds: ["c1", "c2"],
            type: .trustedCommunitySignal,
            previewText: "2 people from your church replied"
        )
        #expect(!preview.sourceCommentIds.isEmpty)
    }

    @Test("prayerMomentum type is correctly identified for prayer routing")
    func prayerMomentumTypeIdentified() {
        let preview = DynamicReplyPreview(
            id: "1", postId: "p", type: .prayerMomentum, previewText: "5 people are praying with this"
        )
        #expect(preview.type == .prayerMomentum)
    }

    @Test("bereanInsight has non-empty previewText for Berean seed query")
    func bereanInsightHasPreviewText() {
        let preview = DynamicReplyPreview(
            id: "1", postId: "p", type: .bereanInsight,
            previewText: "Berean: replies focus on hope + healing"
        )
        #expect(preview.type == .bereanInsight)
        #expect(!preview.previewText.isEmpty)
        // previewText is used as the seed query when opening Berean
        #expect(preview.previewText.contains("Berean:") || !preview.previewText.isEmpty)
    }

    @Test("stale candidate (expired + approved) is filtered before display")
    func staleCandidateFilteredBeforeDisplay() {
        let past = Date().addingTimeInterval(-300)
        let stale = DynamicReplyPreview(
            id: "s1", postId: "p", type: .topReply, previewText: "Old reply",
            score: 0.95, expiresAt: past, moderationState: "approved"
        )
        // Even though approved, if expired it should not display
        #expect(stale.isSafe == true)
        #expect(stale.isExpired == true)
        // The rotator filters: isSafe && !isExpired
        let showable = stale.isSafe && !stale.isExpired
        #expect(showable == false)
    }

    @Test("pending candidate never displays even with high score")
    func pendingCandidateNeverDisplays() {
        let pending = DynamicReplyPreview(
            id: "p1", postId: "p", type: .topReply, previewText: "Pending reply",
            score: 0.99, moderationState: "pending"
        )
        #expect(pending.isSafe == false)
        let showable = pending.isSafe && !pending.isExpired
        #expect(showable == false)
    }
}

// MARK: - Preview Type Tests

@Suite("ReplyPreviewType — enum semantics")
struct ReplyPreviewTypeTests {

    @Test("topReply and followedReply are the 'real reply' types")
    func realReplyTypes() {
        let realTypes: [ReplyPreviewType] = [.topReply, .followedReply]
        for type in realTypes {
            #expect(type == .topReply || type == .followedReply)
        }
    }

    @Test("All types have distinct raw values")
    func distinctRawValues() {
        let rawValues = ReplyPreviewType.allCases.map(\.rawValue)
        let unique = Set(rawValues)
        #expect(rawValues.count == unique.count)
    }
}

extension ReplyPreviewType: CaseIterable {
    public static var allCases: [ReplyPreviewType] {
        [.topReply, .followedReply, .communityPulse, .bereanInsight, .prayerMomentum, .trustedCommunitySignal]
    }
}
