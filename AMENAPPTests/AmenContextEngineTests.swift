import Foundation
import Testing
@testable import AMENAPP

struct AmenContextEngineTests {

    // MARK: - Category Detection

    @Test("Worship song → worship category")
    func worshipSongCategory() {
        let attachment = makeAttachment(type: .song, title: "Great Worship Song", description: "praise and glory")
        let decision = AmenContextEngine.analyze(attachment: attachment, postText: "worship", surface: .feed)
        #expect(decision.contentCategory == .worship)
    }

    @Test("Neutral song → music category")
    func neutralSongCategory() {
        let attachment = makeAttachment(type: .song, title: "Sunday Drive", description: nil)
        let decision = AmenContextEngine.analyze(attachment: attachment, postText: "good vibes", surface: .feed)
        #expect(decision.contentCategory == .music)
    }

    @Test("Sermon video → sermon category + Church Notes destination")
    func sermonVideoChurchNotes() {
        let attachment = makeAttachment(type: .video, title: "Sunday Sermon", description: "Great teaching on John 3")
        let decision = AmenContextEngine.analyze(attachment: attachment, postText: "amazing message", surface: .feed)
        #expect(decision.contentCategory == .sermon)
        #expect(decision.suggestedDestinations.contains(.churchNotes))
    }

    @Test("Reflection song → Selah destination")
    func reflectionSongSelah() {
        let attachment = makeAttachment(type: .song, title: "Still Waters", description: "quiet time reflection")
        let decision = AmenContextEngine.analyze(attachment: attachment, postText: "prayer music", surface: .feed)
        #expect(decision.suggestedDestinations.contains(.selah))
    }

    @Test("Podcast → savedForLater destination")
    func podcastSavedForLater() {
        let attachment = makeAttachment(type: .podcast, title: "Daily Bible Podcast", description: "Christian podcast")
        let decision = AmenContextEngine.analyze(attachment: attachment, postText: "", surface: .feed)
        #expect(decision.suggestedDestinations.contains(.savedForLater))
    }

    @Test("Blocked attachment → empty actions")
    func blockedAttachmentEmpty() {
        let attachment = makeAttachment(type: .song, title: "Blocked", description: nil, safetyStatus: .blocked)
        let decision = AmenContextEngine.analyze(attachment: attachment, postText: "", surface: .feed)
        #expect(decision.primaryAction == nil)
        #expect(decision.secondaryActions.isEmpty)
        #expect(decision.safetyTreatment == .blocked)
    }

    @Test("Limited attachment → only open + report")
    func limitedAttachmentOpenReport() {
        let attachment = makeAttachment(type: .song, title: "Limited", description: nil, safetyStatus: .limited)
        let decision = AmenContextEngine.analyze(attachment: attachment, postText: "", surface: .feed)
        #expect(decision.primaryAction == .open)
        #expect(decision.safetyTreatment == .limited)
    }

    // MARK: - Intent Detection

    @Test("Song with prayer text → pray intent")
    func songWithPrayerTextPrayIntent() {
        let attachment = makeAttachment(type: .song, title: "Intercession", description: "worship")
        let decision = AmenContextEngine.analyze(attachment: attachment, postText: "for prayer and worship", surface: .feed)
        #expect(decision.userIntent == .pray)
    }

    @Test("Video → watch intent")
    func videoWatchIntent() {
        let attachment = makeAttachment(type: .video, title: "Sunday message", description: nil)
        let decision = AmenContextEngine.analyze(attachment: attachment, postText: "", surface: .feed)
        #expect(decision.userIntent == .watch)
    }

    @Test("Article → read intent")
    func articleReadIntent() {
        let attachment = makeAttachment(type: .article, title: "Faith Today", description: "Christian living")
        let decision = AmenContextEngine.analyze(attachment: attachment, postText: "", surface: .feed)
        #expect(decision.userIntent == .read)
    }

    // MARK: - Action Ranker

    @Test("Feed surface → max 2 compact actions")
    func feedSurfaceMaxTwoCompact() {
        let attachment = makeAttachment(type: .song, title: "Worship Song", description: "praise")
        let decision = AmenContextEngine.analyze(attachment: attachment, postText: "", surface: .feed)
        let ranked = AmenSmartActionRanker.rank(decision: decision, surface: .feed)
        #expect(ranked.compactActions.count <= 2)
    }

    @Test("Expanded sheet surface → includes share")
    func expandedSheetIncludesShare() {
        let attachment = makeAttachment(type: .song, title: "Song", description: nil)
        let decision = AmenContextEngine.analyze(attachment: attachment, postText: "", surface: .expandedSheet)
        let ranked = AmenSmartActionRanker.rank(decision: decision, surface: .expandedSheet)
        #expect(ranked.expandedActions.contains(.share))
    }

    @Test("Blocked decision → empty ranked set")
    func blockedDecisionEmptyRanked() {
        let attachment = makeAttachment(type: .song, title: "X", description: nil, safetyStatus: .blocked)
        let decision = AmenContextEngine.analyze(attachment: attachment, postText: "", surface: .feed)
        let ranked = AmenSmartActionRanker.rank(decision: decision, surface: .feed)
        #expect(ranked.compactActions.isEmpty)
        #expect(ranked.primaryAction == nil)
    }

    // MARK: - AmenSmartObject Factory

    @Test("Smart object from worship attachment has selah destination")
    func smartObjectFromWorshipAttachment() {
        let attachment = makeAttachment(type: .song, title: "Agnus Dei", description: "worship")
        let obj = AmenSmartObject.from(attachment: attachment, postText: "worship")
        #expect(obj.memoryDestinations.contains(.selah))
        #expect(obj.objectType == .mediaTrack)
        #expect(obj.resolvedSafetyStatus == .approved)
    }

    @Test("Smart object from sermon video has church notes destination")
    func smartObjectFromSermonVideo() {
        let attachment = makeAttachment(type: .video, title: "Sunday Sermon", description: "sermon message")
        let obj = AmenSmartObject.from(attachment: attachment, postText: "sermon today")
        #expect(obj.memoryDestinations.contains(.churchNotes))
    }

    // MARK: - Community Hub Models

    @Test("AmenCommunityHub activity cards generated correctly")
    func hubActivityCardsGenerated() {
        let summary = AmenHubActivitySummary(
            recentPosterCount: 14,
            totalPrayerCount: 82,
            weeklyPostCount: 23,
            weeklyGrowthPercent: 0.15,
            lastActivityAt: nil
        )
        let hub = makeHub(activitySummary: summary)
        let cards = hub.activityCards()
        #expect(!cards.isEmpty)
        #expect(cards.contains(where: { $0.iconName == "hands.sparkles" }))
        #expect(cards.contains(where: { $0.count == 82 }))
    }

    @Test("AmenCommunityHub with blocked safety status is not discoverable")
    func blockedHubNotDiscoverable() {
        let hub = makeHub(safetyStatus: .blocked)
        #expect(!hub.isDiscoverable)
    }

    @Test("AmenCommunityHub with public privacy is discoverable")
    func publicHubDiscoverable() {
        let hub = makeHub(safetyStatus: .approved, privacy: .public)
        #expect(hub.isDiscoverable)
    }

    @Test("AmenObjectHubMembership primaryInteraction ranks posted first")
    func membershipPrimaryInteractionPostedFirst() {
        let membership = AmenObjectHubMembership(
            hubId: "h1",
            userId: "u1",
            interactionTypes: [.saved, .listened, .posted],
            lastInteractedAt: nil,
            isMuted: false,
            joinedAt: Date()
        )
        #expect(membership.primaryInteraction == .posted)
    }

    // MARK: - Helpers

    private func makeAttachment(
        type: AmenAttachmentType,
        title: String,
        description: String?,
        safetyStatus: AmenAttachmentSafetyStatus = .approved
    ) -> AmenSmartAttachment {
        AmenSmartAttachment(
            id: "test_\(title.hashValue)",
            postId: nil,
            provider: .youtube,
            type: type,
            providerId: nil,
            title: title,
            subtitle: nil,
            creatorName: nil,
            description: description,
            artworkUrl: nil,
            canonicalUrl: "https://example.com/\(title)",
            durationMs: nil,
            previewUrl: nil,
            attributionText: "Test",
            sourceLogoRequired: false,
            playbackPolicy: .externalOnly,
            safetyStatus: safetyStatus,
            smartActions: [.open, .saveForLater],
            soundtrackEnabled: false,
            createdAt: nil,
            updatedAt: nil
        )
    }

    private func makeHub(
        safetyStatus: AmenAttachmentSafetyStatus = .approved,
        privacy: AmenHubPrivacyLevel = .public,
        activitySummary: AmenHubActivitySummary? = nil
    ) -> AmenCommunityHub {
        AmenCommunityHub(
            id: "hub_test",
            canonicalObjectId: "co_test",
            title: "Test Hub",
            subtitle: nil,
            artworkUrl: nil,
            totalMembers: 100,
            weeklyPostCount: 10,
            totalPostCount: 200,
            safetyStatus: safetyStatus,
            privacyLevel: privacy,
            topicChips: [],
            relatedObjectIds: [],
            discussionPrompts: [],
            activitySummary: activitySummary,
            contentCategory: .worship,
            explicitContentState: .clean,
            createdAt: nil,
            updatedAt: nil
        )
    }
}
