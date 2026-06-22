// FeedSafetyFilterTests.swift
// AMENAPPTests
//
// Verifies that removed, flagged, and safety-hidden posts never appear on
// any feed surface, and that safe content is eligible.
// Tests the Post-level eligibility gate (used by both HomeFeedAlgorithm
// and HeyFeedAlgorithm.rank()).

import Testing
import Foundation
@testable import AMENAPP

// MARK: - Helpers

private func makeApprovedSafety() -> SafetyMetadata {
    SafetyMetadata(
        harmRisk: 0, misinformationRisk: 0, exploitationRisk: 0,
        doomscrollRisk: 0, childSafetyRisk: 0, selfHarmRisk: 0,
        harassmentRisk: 0, violenceRisk: 0, sexualSafetyRisk: 0,
        scamRisk: 0, religiousAbuseRisk: 0, medicalClaimRisk: 0,
        politicalManipulationRisk: 0,
        distributionDecision: .allow,
        labels: [],
        moderationStatus: .approved,
        reviewedAt: nil, reviewerType: nil
    )
}

private func makeSafetyWithDecision(_ decision: DistributionDecision,
                                     status: ContentModerationStatus = .approved) -> SafetyMetadata {
    SafetyMetadata(
        harmRisk: 0.9, misinformationRisk: 0, exploitationRisk: 0,
        doomscrollRisk: 0, childSafetyRisk: 0, selfHarmRisk: 0,
        harassmentRisk: 0, violenceRisk: 0, sexualSafetyRisk: 0,
        scamRisk: 0, religiousAbuseRisk: 0, medicalClaimRisk: 0,
        politicalManipulationRisk: 0,
        distributionDecision: decision,
        labels: [],
        moderationStatus: status,
        reviewedAt: nil, reviewerType: nil
    )
}

private func makeBundle(safety: SafetyMetadata) -> TrueSourceBundle {
    TrueSourceBundle(
        source: TrueSourceMetadata(
            sourceIntegrityScore: 0.9, originalityScore: 0.9, authenticityScore: 0.9,
            manipulationRisk: 0, contextConfidence: 0.9, accountTrustScore: 0.9,
            repostLineage: [], provenanceStatus: .original, mediaType: "text",
            aiGenerated: false, aiAssisted: false, editedMedia: false,
            sourceUnclear: false, humanReviewed: false, communityReviewed: false,
            createdAt: nil, updatedAt: nil
        ),
        safety: safety,
        context: ContextMetadata(
            contentType: .personalStory, captionMatchesMedia: true,
            clippedContextRisk: 0, outOfContextRisk: 0, consentRisk: 0,
            locationExposureRisk: 0
        ),
        ranking: RankingMetadata(
            communityValueScore: 0.8, conversationHealthScore: 0.8,
            originalityBoost: 0.8, educationalCreativeValue: 0.5,
            userRelevanceScore: 0.7, safetyPenalty: 0,
            finalDistributionScore: 0.8, eligibleForRecommendation: true,
            eligibleForTrending: false, eligibleForAutoplay: true
        )
    )
}

private func makePost(
    id: String = UUID().uuidString,
    authorId: String = "author-1",
    removed: Bool = false,
    flaggedForReview: Bool = false,
    trueSource: TrueSourceBundle? = nil,
    amenCount: Int = 0,
    commentCount: Int = 0
) -> Post {
    var post = Post(
        id: UUID(),
        firebaseId: id,
        authorId: authorId,
        authorName: "Test Author",
        authorUsername: "testauthor",
        authorInitials: "TA",
        authorProfileImageURL: nil,
        timeAgo: "1m",
        content: "Test post content about faith and community",
        category: .openTable,
        topicTag: nil,
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
        createdAt: Date(),
        amenCount: amenCount,
        lightbulbCount: 0,
        commentCount: commentCount,
        repostCount: 0
    )
    post.removed = removed
    post.flaggedForReview = flaggedForReview
    post.trueSource = trueSource
    return post
}

// MARK: - Feed Eligibility Tests

@Suite("Feed Safety Filter — Post Eligibility Gate")
struct FeedSafetyFilterTests {

    // MARK: Legacy flag gates

    @Test("Removed post must never appear in any feed")
    func removedPostFilteredFromFeed() {
        let post = makePost(removed: true)
        #expect(post.isEligibleForFeedDisplay == false,
                "A removed post must be blocked at the eligibility gate")
    }

    @Test("Flagged post must never appear in any feed")
    func flaggedPostFilteredFromFeed() {
        let post = makePost(flaggedForReview: true)
        #expect(post.isEligibleForFeedDisplay == false,
                "A post under review must not appear in feeds")
    }

    @Test("Removed+flagged post must never appear in any feed")
    func removedAndFlaggedPostFiltered() {
        let post = makePost(removed: true, flaggedForReview: true)
        #expect(post.isEligibleForFeedDisplay == false)
    }

    // MARK: True Source bundle gates

    @Test("Post with remove distribution decision is blocked")
    func removeDecisionBlocksFeedDisplay() {
        let bundle = makeBundle(safety: makeSafetyWithDecision(.remove))
        let post = makePost(trueSource: bundle)
        #expect(post.isEligibleForFeedDisplay == false)
    }

    @Test("Post pending human review is blocked")
    func humanReviewBlocksFeedDisplay() {
        let bundle = makeBundle(safety: makeSafetyWithDecision(.humanReview))
        let post = makePost(trueSource: bundle)
        #expect(post.isEligibleForFeedDisplay == false)
    }

    @Test("Post with removed moderation status is blocked")
    func removedModerationStatusBlocksDisplay() {
        let bundle = makeBundle(safety: makeSafetyWithDecision(.allow, status: .removed))
        let post = makePost(trueSource: bundle)
        #expect(post.isEligibleForFeedDisplay == false)
    }

    @Test("Post with humanReview moderation status is blocked")
    func humanReviewModerationStatusBlocksDisplay() {
        let bundle = makeBundle(safety: makeSafetyWithDecision(.allow, status: .humanReview))
        let post = makePost(trueSource: bundle)
        #expect(post.isEligibleForFeedDisplay == false)
    }

    // MARK: Eligible posts

    @Test("Safe approved post is eligible for feed")
    func safeApprovedPostIsEligible() {
        let bundle = makeBundle(safety: makeApprovedSafety())
        let post = makePost(trueSource: bundle)
        #expect(post.isEligibleForFeedDisplay == true)
    }

    @Test("Post with reduceReach decision is still visible (just reduced)")
    func reduceReachPostIsStillVisible() {
        let safety = makeSafetyWithDecision(.reduceReach, status: .approvedLimited)
        let bundle = makeBundle(safety: safety)
        let post = makePost(trueSource: bundle)
        #expect(post.isEligibleForFeedDisplay == true,
                "reduceReach should reduce score but not fully hide the post")
    }

    @Test("Legacy post without TrueSourceBundle is eligible")
    func legacyPostIsEligible() {
        let post = makePost()
        #expect(post.isEligibleForFeedDisplay == true)
    }

    // MARK: P0 SAFETY: high-engagement harmful content is never promoted

    @Test("Removed post with extremely high engagement is still blocked")
    func removedHighEngagementPostIsBlocked() {
        // This tests the critical invariant: safety > engagement in ranking.
        // A viral post that has been removed must NEVER return to the feed
        // regardless of how many amen/comments it has.
        let post = makePost(removed: true, amenCount: 9999, commentCount: 5000)
        #expect(post.isEligibleForFeedDisplay == false,
                "Viral engagement must not override a removal decision")
    }

    @Test("Post with child safety risk in bundle is blocked when decision is remove")
    func childSafetyRiskWithRemoveDecisionIsBlocked() {
        var safety = makeApprovedSafety()
        // Simulate pipeline detecting CSAM-risk and setting remove decision
        var mutable = safety
        mutable = SafetyMetadata(
            harmRisk: 0, misinformationRisk: 0, exploitationRisk: 0,
            doomscrollRisk: 0, childSafetyRisk: 0.9, selfHarmRisk: 0,
            harassmentRisk: 0, violenceRisk: 0, sexualSafetyRisk: 0.8,
            scamRisk: 0, religiousAbuseRisk: 0, medicalClaimRisk: 0,
            politicalManipulationRisk: 0,
            distributionDecision: .remove, labels: ["child_safety"],
            moderationStatus: .removed, reviewedAt: nil, reviewerType: nil
        )
        let bundle = makeBundle(safety: mutable)
        let post = makePost(trueSource: bundle)
        #expect(post.isEligibleForFeedDisplay == false)
    }

    // MARK: DistributionDecision.isVisible contract

    @Test("DistributionDecision.remove is not visible")
    func removeDecisionIsNotVisible() {
        #expect(DistributionDecision.remove.isVisible == false)
    }

    @Test("DistributionDecision.humanReview is not visible")
    func humanReviewDecisionIsNotVisible() {
        #expect(DistributionDecision.humanReview.isVisible == false)
    }

    @Test("DistributionDecision.allow is visible")
    func allowDecisionIsVisible() {
        #expect(DistributionDecision.allow.isVisible == true)
    }

    @Test("DistributionDecision.reduceReach reduces reach but remains visible")
    func reduceReachIsVisibleButReduces() {
        #expect(DistributionDecision.reduceReach.isVisible == true)
        #expect(DistributionDecision.reduceReach.reducesReach == true)
    }

    @Test("DistributionDecision.allowWithLabel is visible and does not reduce reach")
    func allowWithLabelIsVisible() {
        #expect(DistributionDecision.allowWithLabel.isVisible == true)
        #expect(DistributionDecision.allowWithLabel.reducesReach == false)
    }
}
