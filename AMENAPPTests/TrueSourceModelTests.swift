// TrueSourceModelTests.swift
// AMENAPPTests
//
// Unit tests for TrueSourceBundle, SafetyMetadata, ContextMetadata, and
// Post.isEligibleForFeedDisplay.
// All tests are pure-model: no Firebase, no networking.

import Testing
import Foundation
@testable import AMENAPP

// MARK: - Helpers

private func makeSafety(
    harmRisk: Double = 0,
    misinformationRisk: Double = 0,
    exploitationRisk: Double = 0,
    doomscrollRisk: Double = 0,
    childSafetyRisk: Double = 0,
    selfHarmRisk: Double = 0,
    harassmentRisk: Double = 0,
    violenceRisk: Double = 0,
    sexualSafetyRisk: Double = 0,
    scamRisk: Double = 0,
    religiousAbuseRisk: Double = 0,
    medicalClaimRisk: Double = 0,
    politicalManipulationRisk: Double = 0,
    distributionDecision: DistributionDecision = .allow,
    labels: [String] = [],
    moderationStatus: ContentModerationStatus = .approved
) -> SafetyMetadata {
    SafetyMetadata(
        harmRisk: harmRisk,
        misinformationRisk: misinformationRisk,
        exploitationRisk: exploitationRisk,
        doomscrollRisk: doomscrollRisk,
        childSafetyRisk: childSafetyRisk,
        selfHarmRisk: selfHarmRisk,
        harassmentRisk: harassmentRisk,
        violenceRisk: violenceRisk,
        sexualSafetyRisk: sexualSafetyRisk,
        scamRisk: scamRisk,
        religiousAbuseRisk: religiousAbuseRisk,
        medicalClaimRisk: medicalClaimRisk,
        politicalManipulationRisk: politicalManipulationRisk,
        distributionDecision: distributionDecision,
        labels: labels,
        moderationStatus: moderationStatus,
        reviewedAt: nil,
        reviewerType: nil
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
    removed: Bool = false,
    flaggedForReview: Bool = false,
    trueSource: TrueSourceBundle? = nil,
    amenCount: Int = 0,
    commentCount: Int = 0
) -> Post {
    var post = Post(
        id: UUID(),
        firebaseId: UUID().uuidString,
        authorId: "author-1",
        authorName: "Test Author",
        authorUsername: "testauthor",
        authorInitials: "TA",
        authorProfileImageURL: nil,
        timeAgo: "1m",
        content: "Test post content",
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

// MARK: - SafetyMetadata tests

@Suite("SafetyMetadata")
struct SafetyMetadataTests {

    @Test("shouldBeHidden when moderationStatus is removed")
    func hiddenWhenRemoved() {
        let s = makeSafety(moderationStatus: .removed)
        #expect(s.shouldBeHidden == true)
    }

    @Test("shouldBeHidden when moderationStatus is humanReview")
    func hiddenWhenHumanReview() {
        let s = makeSafety(moderationStatus: .humanReview)
        #expect(s.shouldBeHidden == true)
    }

    @Test("shouldBeHidden when distributionDecision is remove")
    func hiddenWhenDistributionRemove() {
        let s = makeSafety(distributionDecision: .remove)
        #expect(s.shouldBeHidden == true)
    }

    @Test("shouldBeHidden when distributionDecision is humanReview")
    func hiddenWhenDistributionHumanReview() {
        let s = makeSafety(distributionDecision: .humanReview)
        #expect(s.shouldBeHidden == true)
    }

    @Test("shouldBeHidden is false for approved content")
    func notHiddenWhenApproved() {
        let s = makeSafety(distributionDecision: .allow, moderationStatus: .approved)
        #expect(s.shouldBeHidden == false)
    }

    @Test("aggregateHarmScore returns max of key risk signals")
    func aggregateHarmScoreIsMax() {
        let s = makeSafety(harmRisk: 0.3, misinformationRisk: 0.7, childSafetyRisk: 0.5)
        #expect(s.aggregateHarmScore == 0.7)
    }

    @Test("aggregateHarmScore is zero when all risks are zero")
    func aggregateHarmScoreZeroForSafeContent() {
        let s = makeSafety()
        #expect(s.aggregateHarmScore == 0)
    }

    @Test("hasReducedReach is true for reduceReach decision")
    func hasReducedReachForReduceDecision() {
        let s = makeSafety(distributionDecision: .reduceReach)
        #expect(s.hasReducedReach == true)
    }

    @Test("hasReducedReach is false for allow decision")
    func noReducedReachForAllow() {
        let s = makeSafety(distributionDecision: .allow)
        #expect(s.hasReducedReach == false)
    }
}

// MARK: - TrueSourceBundle eligibility

@Suite("TrueSourceBundle.isEligibleForFeedDisplay")
struct TrueSourceBundleEligibilityTests {

    @Test("Eligible when approved and allow decision")
    func eligibleForApprovedContent() {
        let bundle = makeBundle(safety: makeSafety(distributionDecision: .allow, moderationStatus: .approved))
        #expect(bundle.isEligibleForFeedDisplay == true)
    }

    @Test("Not eligible when safety says hidden (remove decision)")
    func notEligibleWhenRemoveDecision() {
        let bundle = makeBundle(safety: makeSafety(distributionDecision: .remove))
        #expect(bundle.isEligibleForFeedDisplay == false)
    }

    @Test("Not eligible when moderationStatus is removed")
    func notEligibleWhenModerationRemoved() {
        let bundle = makeBundle(safety: makeSafety(moderationStatus: .removed))
        #expect(bundle.isEligibleForFeedDisplay == false)
    }

    @Test("Not eligible when moderationStatus is humanReview")
    func notEligibleWhenHumanReview() {
        let bundle = makeBundle(safety: makeSafety(moderationStatus: .humanReview))
        #expect(bundle.isEligibleForFeedDisplay == false)
    }

    @Test("pendingModeration default is not eligible for display")
    func pendingModerationNotEligible() {
        #expect(TrueSourceBundle.pendingModeration.isEligibleForFeedDisplay == false)
    }

    @Test("legacyApproved default IS eligible for display")
    func legacyApprovedIsEligible() {
        #expect(TrueSourceBundle.legacyApproved.isEligibleForFeedDisplay == true)
    }
}

// MARK: - Post.isEligibleForFeedDisplay

@Suite("Post.isEligibleForFeedDisplay")
struct PostEligibilityTests {

    @Test("Removed post is never eligible")
    func removedPostNotEligible() {
        let post = makePost(removed: true)
        #expect(post.isEligibleForFeedDisplay == false)
    }

    @Test("Flagged post is never eligible")
    func flaggedPostNotEligible() {
        let post = makePost(flaggedForReview: true)
        #expect(post.isEligibleForFeedDisplay == false)
    }

    @Test("Removed post with good bundle is still not eligible")
    func removedPostWithGoodBundleStillBlocked() {
        let bundle = makeBundle(safety: makeSafety(distributionDecision: .allow, moderationStatus: .approved))
        let post = makePost(removed: true, trueSource: bundle)
        #expect(post.isEligibleForFeedDisplay == false)
    }

    @Test("Post with remove-decision bundle is not eligible")
    func bundleRemoveDecisionBlocksDisplay() {
        let bundle = makeBundle(safety: makeSafety(distributionDecision: .remove))
        let post = makePost(trueSource: bundle)
        #expect(post.isEligibleForFeedDisplay == false)
    }

    @Test("Post with humanReview bundle is not eligible")
    func bundleHumanReviewBlocksDisplay() {
        let bundle = makeBundle(safety: makeSafety(distributionDecision: .humanReview))
        let post = makePost(trueSource: bundle)
        #expect(post.isEligibleForFeedDisplay == false)
    }

    @Test("Clean approved post is eligible")
    func cleanApprovedPostIsEligible() {
        let bundle = makeBundle(safety: makeSafety(distributionDecision: .allow, moderationStatus: .approved))
        let post = makePost(trueSource: bundle)
        #expect(post.isEligibleForFeedDisplay == true)
    }

    @Test("Legacy post without bundle is eligible (backwards compatibility)")
    func legacyPostWithoutBundleIsEligible() {
        let post = makePost()
        #expect(post.isEligibleForFeedDisplay == true)
    }

    @Test("Post aggregateHarmScore reflects bundle safety")
    func aggregateHarmScoreForwardedFromBundle() {
        let bundle = makeBundle(safety: makeSafety(harmRisk: 0.4, misinformationRisk: 0.6))
        let post = makePost(trueSource: bundle)
        #expect(post.aggregateHarmScore == 0.6)
    }

    @Test("Post aggregateHarmScore is zero without bundle")
    func aggregateHarmScoreZeroWithoutBundle() {
        let post = makePost()
        #expect(post.aggregateHarmScore == 0)
    }

    @Test("hasReducedReach reflects bundle distribution decision")
    func hasReducedReachForwarded() {
        let bundle = makeBundle(safety: makeSafety(distributionDecision: .reduceReach, moderationStatus: .approvedLimited))
        let post = makePost(trueSource: bundle)
        #expect(post.hasReducedReach == true)
    }
}

// MARK: - RankingMetadata.computeFinalScore

@Suite("RankingMetadata.computeFinalScore")
struct RankingScoreComputationTests {

    @Test("High safety risks reduce final distribution score")
    func highSafetyRisksReduceScore() {
        let safeSafety = makeSafety()
        let harmfulSafety = makeSafety(harmRisk: 0.9, misinformationRisk: 0.8, doomscrollRisk: 0.7)

        let safeScore = RankingMetadata.computeFinalScore(
            communityValue: 0.8, sourceIntegrity: 0.8, userRelevance: 0.8,
            conversationHealth: 0.8, originality: 0.8, educationalValue: 0.8,
            safety: safeSafety
        )
        let harmfulScore = RankingMetadata.computeFinalScore(
            communityValue: 0.8, sourceIntegrity: 0.8, userRelevance: 0.8,
            conversationHealth: 0.8, originality: 0.8, educationalValue: 0.8,
            safety: harmfulSafety
        )

        #expect(safeScore > harmfulScore)
    }

    @Test("Perfect safe content scores above zero")
    func perfectSafeContentScoresPositive() {
        let score = RankingMetadata.computeFinalScore(
            communityValue: 1.0, sourceIntegrity: 1.0, userRelevance: 1.0,
            conversationHealth: 1.0, originality: 1.0, educationalValue: 1.0,
            safety: makeSafety()
        )
        #expect(score > 0)
    }

    @Test("Score is clamped to 0..1 range")
    func scoreIsClamped() {
        let score = RankingMetadata.computeFinalScore(
            communityValue: 1.0, sourceIntegrity: 1.0, userRelevance: 1.0,
            conversationHealth: 1.0, originality: 1.0, educationalValue: 1.0,
            safety: makeSafety()
        )
        #expect(score >= 0 && score <= 1)
    }
}
