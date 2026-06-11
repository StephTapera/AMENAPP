// MusicContentLayerTests.swift
// AMENAPPTests — MusicContentLayer
//
// Contract tests for SmartComposerIntentService, RightsMonetizationService,
// FaithMusicGraphService, and CommentSafetyService.
// Pure logic — no Firebase, no UI, no network.

import Testing
@testable import AMENAPP

// MARK: - SmartComposerIntentService Tests

@Suite("SmartComposerIntentService")
struct SmartComposerIntentServiceTests {

    private let svc = SmartComposerIntentService()

    @Test("Prayer keywords classify as prayerRequest")
    func prayerRequest() {
        let result = svc.classify(
            draftText: "Please pray for my healing",
            hasAttachment: false,
            accountType: "standard"
        )
        #expect(result.intent == .prayerRequest)
        #expect(result.confidence >= 0.3)
    }

    @Test("Music emoji + 'listening to' classify as songShare")
    func songShare() {
        let result = svc.classify(
            draftText: "Listening to this worship song today 🎵",
            hasAttachment: false,
            accountType: "standard"
        )
        #expect(result.intent == .songShare)
        #expect(result.confidence >= 0.3)
    }

    @Test("Scripture reference pattern classifies as scriptureQuote")
    func scriptureQuote() {
        let result = svc.classify(
            draftText: "John 3:16 really hit different today",
            hasAttachment: false,
            accountType: "standard"
        )
        #expect(result.intent == .scriptureQuote)
        #expect(result.confidence >= 0.3)
    }

    @Test("Generic short text with no keywords returns low confidence")
    func genericText() {
        let result = svc.classify(
            draftText: "Good morning everyone",
            hasAttachment: false,
            accountType: "standard"
        )
        // Generic text: confidence below threshold (not classified to a strong intent)
        #expect(result.confidence < 0.3)
    }

    @Test("Testimony keywords classify as testimony")
    func testimony() {
        let result = svc.classify(
            draftText: "I just want to share my testimony. God is good and blessed me.",
            hasAttachment: false,
            accountType: "standard"
        )
        #expect(result.intent == .testimony)
        #expect(result.confidence >= 0.3)
    }

    @Test("Sermon keywords classify as sermonNote")
    func sermonNote() {
        let result = svc.classify(
            draftText: "Pastor preached an amazing sermon today",
            hasAttachment: false,
            accountType: "standard"
        )
        #expect(result.intent == .sermonNote)
        #expect(result.confidence >= 0.3)
    }

    @Test("Prayer request suggests worship playlist = false, church note = true")
    func prayerSuggestions() {
        let result = svc.classify(
            draftText: "Pray for my family, Lord God please",
            hasAttachment: false,
            accountType: "standard"
        )
        #expect(result.shouldSuggestChurchNote == true)
        #expect(result.shouldSuggestWorshipPlaylist == false)
    }

    @Test("Song share suggests worship playlist = true")
    func songShareSuggestions() {
        let result = svc.classify(
            draftText: "🎵 Listening to this song on repeat",
            hasAttachment: false,
            accountType: "standard"
        )
        #expect(result.shouldSuggestWorshipPlaylist == true)
    }

    @Test("Suggested tags are non-empty for scripture intent")
    func scriptureTags() {
        let result = svc.classify(
            draftText: "Romans 8:28 is so powerful today",
            hasAttachment: false,
            accountType: "standard"
        )
        #expect(!result.suggestedTags.isEmpty)
    }
}

// MARK: - RightsMonetizationService Tests

@Suite("RightsMonetizationService")
struct RightsMonetizationServiceTests {

    private let svc = RightsMonetizationService()

    // MARK: Blocked

    @Test("Blocked moderation status returns denied(.blocked)")
    func blockedDenied() {
        let input = RightsCheckInput(
            contentID: "c1",
            rightsPolicy: "free",
            visibilityPolicy: "public",
            moderationStatus: "blocked",
            isChildAccount: false,
            hasActiveMembership: false,
            hasPaidAccess: false,
            isAdmin: false
        )
        let result = svc.checkAccess(input)
        if case .denied(let reason) = result {
            #expect(reason == .blocked)
        } else {
            Issue.record("Expected denied(.blocked), got granted")
        }
    }

    // MARK: Paid

    @Test("Paid rights policy without paid access returns denied(.paidRequired)")
    func paidNoPaidAccess() {
        let input = RightsCheckInput(
            contentID: "c2",
            rightsPolicy: "paid",
            visibilityPolicy: "public",
            moderationStatus: "approved",
            isChildAccount: false,
            hasActiveMembership: false,
            hasPaidAccess: false,
            isAdmin: false
        )
        let result = svc.checkAccess(input)
        if case .denied(let reason) = result {
            #expect(reason == .paidRequired)
        } else {
            Issue.record("Expected denied(.paidRequired), got granted")
        }
    }

    // MARK: Members Only

    @Test("MembersOnly visibility with active membership returns granted")
    func membersOnlyWithMembership() {
        let input = RightsCheckInput(
            contentID: "c3",
            rightsPolicy: "free",
            visibilityPolicy: "membersOnly",
            moderationStatus: "approved",
            isChildAccount: false,
            hasActiveMembership: true,
            hasPaidAccess: false,
            isAdmin: false
        )
        let result = svc.checkAccess(input)
        if case .granted = result {
            // pass
        } else {
            Issue.record("Expected granted for members-only content with active membership")
        }
    }

    // MARK: Child Restricted

    @Test("Child-restricted rights policy with child account returns denied(.childRestricted)")
    func childRestrictedAccount() {
        let input = RightsCheckInput(
            contentID: "c4",
            rightsPolicy: "childRestricted",
            visibilityPolicy: "public",
            moderationStatus: "approved",
            isChildAccount: true,
            hasActiveMembership: false,
            hasPaidAccess: false,
            isAdmin: false
        )
        let result = svc.checkAccess(input)
        if case .denied(let reason) = result {
            #expect(reason == .childRestricted)
        } else {
            Issue.record("Expected denied(.childRestricted) for child account + childRestricted policy")
        }
    }

    // MARK: Free + Public + Approved

    @Test("Free + public + approved returns granted")
    func freePublicApproved() {
        let input = RightsCheckInput(
            contentID: "c5",
            rightsPolicy: "free",
            visibilityPolicy: "public",
            moderationStatus: "approved",
            isChildAccount: false,
            hasActiveMembership: false,
            hasPaidAccess: false,
            isAdmin: false
        )
        let result = svc.checkAccess(input)
        if case .granted = result {
            // pass
        } else {
            Issue.record("Expected granted for free public approved content")
        }
    }

    // MARK: Admin Bypass

    @Test("Admin can access admin-only content")
    func adminBypass() {
        let input = RightsCheckInput(
            contentID: "c6",
            rightsPolicy: "adminOnly",
            visibilityPolicy: "public",
            moderationStatus: "approved",
            isChildAccount: false,
            hasActiveMembership: false,
            hasPaidAccess: false,
            isAdmin: true
        )
        let result = svc.checkAccess(input)
        if case .granted = result {
            // pass
        } else {
            Issue.record("Expected granted for admin accessing admin-only content")
        }
    }
}

// MARK: - FaithMusicGraphService Tests

@Suite("FaithMusicGraphService")
struct FaithMusicGraphServiceTests {

    @Test("recommendedNodes is empty after init")
    @MainActor
    func initiallyEmpty() {
        let service = FaithMusicGraphService()
        #expect(service.recommendedNodes.isEmpty)
    }

    @Test("loadRelated with seeded node ID returns non-empty recommendations")
    @MainActor
    func loadRelatedReturnsNodes() async {
        let service = FaithMusicGraphService()
        // "song-1" is seeded and has edges in the mock data
        await service.loadRelated(for: "song-1", type: .song)
        #expect(!service.recommendedNodes.isEmpty)
    }

    @Test("loadRelated for unknown node ID returns empty results")
    @MainActor
    func loadRelatedUnknownNode() async {
        let service = FaithMusicGraphService()
        await service.loadRelated(for: "does-not-exist", type: .song)
        #expect(service.recommendedNodes.isEmpty)
    }

    @Test("isLoading is false before and after loadRelated completes")
    @MainActor
    func isLoadingLifecycle() async {
        let service = FaithMusicGraphService()
        #expect(service.isLoading == false)
        await service.loadRelated(for: "song-2", type: .song)
        #expect(service.isLoading == false)
    }

    @Test("addNode then loadRelated includes the added node in results")
    @MainActor
    func addNodeAndLoadRelated() async {
        let service = FaithMusicGraphService()
        let newNode = FaithGraphNode(
            id: "custom-song-1",
            type: .song,
            title: "New Custom Song",
            subtitle: "Test Artist",
            artworkURL: nil,
            deepLink: "amen://music/custom-1",
            weight: 0.9
        )
        let edge = FaithGraphEdge(
            id: "custom-edge-1",
            fromNodeID: "song-1",
            toNodeID: "custom-song-1",
            relationLabel: "relatedTo",
            strength: 0.95
        )
        service.addNode(newNode)
        service.addEdge(edge)
        await service.loadRelated(for: "song-1", type: .song)
        let ids = service.recommendedNodes.map(\.id)
        #expect(ids.contains("custom-song-1"))
    }
}

// MARK: - CommentSafetyService Tests
// These tests use the MusicContentLayer-scoped lightweight service (pure local).

@Suite("CommentSafetyService")
struct CommentSafetyServiceTests {

    private let svc = MusicContentLayerCommentSafetyService()

    @Test("Clean comment returns isSafe = true")
    func cleanComment() {
        let result = svc.check(comment: "This sermon really spoke to me today!")
        #expect(result.isSafe == true)
        #expect(result.blockedKeyword == nil)
    }

    @Test("Comment with profanity keyword returns isSafe = false")
    func profanityDetected() {
        let result = svc.check(comment: "This is damn stupid")
        #expect(result.isSafe == false)
        #expect(result.blockedKeyword != nil)
    }

    @Test("Empty comment returns isSafe = true (no content to block)")
    func emptyComment() {
        let result = svc.check(comment: "")
        #expect(result.isSafe == true)
    }

    @Test("Comment with harassment keyword returns isSafe = false")
    func harassmentDetected() {
        let result = svc.check(comment: "You are such an idiot")
        #expect(result.isSafe == false)
    }

    @Test("Scripture comment is always safe")
    func scriptureComment() {
        let result = svc.check(comment: "John 3:16 — For God so loved the world. Amen.")
        #expect(result.isSafe == true)
    }
}

// MARK: - MusicContentLayerCommentSafetyService
// Lightweight local-only service used exclusively by MusicContentLayer tests.
// Does NOT replace the app-level CommentSafetySystem (which uses Firebase).

struct CommentSafetyCheckResult: Sendable {
    let isSafe: Bool
    let blockedKeyword: String?
    let safetyScore: Double     // 0.0 (unsafe) – 1.0 (safe)
}

final class MusicContentLayerCommentSafetyService: Sendable {

    // Simple keyword blocklist for local/unit-test use.
    // Production moderation uses the full CommentSafetySystem.
    private static let blockedKeywords: [String] = [
        "damn", "hell", "idiot", "stupid", "hate you", "loser",
        "shut up", "moron", "dumb", "ugly", "worthless"
    ]

    func check(comment: String) -> CommentSafetyCheckResult {
        let lower = comment.lowercased()
        for keyword in Self.blockedKeywords {
            if lower.contains(keyword) {
                return CommentSafetyCheckResult(
                    isSafe: false,
                    blockedKeyword: keyword,
                    safetyScore: 0.0
                )
            }
        }
        return CommentSafetyCheckResult(isSafe: true, blockedKeyword: nil, safetyScore: 1.0)
    }
}
