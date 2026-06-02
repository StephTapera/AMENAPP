// TrueSourceRankingTests.swift
// AMENAPPTests
//
// Verifies that the True Source safety penalty signals correctly reduce feed
// distribution scores, and that high-harm content cannot outrank safe content
// through engagement alone.

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
    harassmentRisk: Double = 0
) -> SafetyMetadata {
    SafetyMetadata(
        harmRisk: harmRisk, manipulationRisk: 0, misinformationRisk: misinformationRisk,
        exploitationRisk: exploitationRisk, doomscrollRisk: doomscrollRisk,
        childSafetyRisk: childSafetyRisk, selfHarmRisk: selfHarmRisk,
        harassmentRisk: harassmentRisk, violenceRisk: 0, sexualSafetyRisk: 0,
        scamRisk: 0, religiousAbuseRisk: 0, medicalClaimRisk: 0,
        politicalManipulationRisk: 0,
        distributionDecision: .allow, labels: [],
        moderationStatus: .approved, reviewedAt: nil, reviewerType: nil
    )
}

// MARK: - RankingMetadata.computeFinalScore Safety Signal Tests

@Suite("True Source Ranking — Safety Penalties")
struct TrueSourceRankingTests {

    // MARK: Penalty stacking

    @Test("High harm risk reduces final distribution score")
    func highHarmRiskReducesScore() {
        let baseScore = RankingMetadata.computeFinalScore(
            communityValue: 0.8, sourceIntegrity: 0.9, userRelevance: 0.8,
            conversationHealth: 0.8, originality: 0.7, educationalValue: 0.6,
            safety: makeSafety()
        )
        let harmfulScore = RankingMetadata.computeFinalScore(
            communityValue: 0.8, sourceIntegrity: 0.9, userRelevance: 0.8,
            conversationHealth: 0.8, originality: 0.7, educationalValue: 0.6,
            safety: makeSafety(harmRisk: 0.9)
        )
        #expect(harmfulScore < baseScore,
                "High harmRisk must reduce the final distribution score")
    }

    @Test("High misinformation risk reduces final score")
    func misinformationRiskReducesScore() {
        let safe = RankingMetadata.computeFinalScore(
            communityValue: 0.8, sourceIntegrity: 0.9, userRelevance: 0.8,
            conversationHealth: 0.8, originality: 0.7, educationalValue: 0.6,
            safety: makeSafety()
        )
        let misinfo = RankingMetadata.computeFinalScore(
            communityValue: 0.8, sourceIntegrity: 0.9, userRelevance: 0.8,
            conversationHealth: 0.8, originality: 0.7, educationalValue: 0.6,
            safety: makeSafety(misinformationRisk: 0.8)
        )
        #expect(misinfo < safe)
    }

    @Test("High doomscroll risk reduces final score")
    func doomscrollRiskReducesScore() {
        let safe = RankingMetadata.computeFinalScore(
            communityValue: 0.8, sourceIntegrity: 0.9, userRelevance: 0.8,
            conversationHealth: 0.8, originality: 0.7, educationalValue: 0.6,
            safety: makeSafety()
        )
        let doomscroll = RankingMetadata.computeFinalScore(
            communityValue: 0.8, sourceIntegrity: 0.9, userRelevance: 0.8,
            conversationHealth: 0.8, originality: 0.7, educationalValue: 0.6,
            safety: makeSafety(doomscrollRisk: 0.9)
        )
        #expect(doomscroll < safe)
    }

    @Test("Multiple stacked risks lower score more than a single risk")
    func stackedRisksCompound() {
        let singleRisk = RankingMetadata.computeFinalScore(
            communityValue: 0.8, sourceIntegrity: 0.9, userRelevance: 0.8,
            conversationHealth: 0.8, originality: 0.7, educationalValue: 0.6,
            safety: makeSafety(harmRisk: 0.5)
        )
        let stackedRisks = RankingMetadata.computeFinalScore(
            communityValue: 0.8, sourceIntegrity: 0.9, userRelevance: 0.8,
            conversationHealth: 0.8, originality: 0.7, educationalValue: 0.6,
            safety: makeSafety(harmRisk: 0.5, misinformationRisk: 0.5, doomscrollRisk: 0.5)
        )
        #expect(stackedRisks < singleRisk,
                "Multiple risk signals must compound to produce lower score")
    }

    // MARK: The critical invariant: harm > engagement

    @Test("High-engagement harmful content scores lower than low-engagement safe content")
    func highEngagementHarmfulLosesToLowEngagementSafe() {
        // Safe content with moderate community value
        let safeScore = RankingMetadata.computeFinalScore(
            communityValue: 0.4, sourceIntegrity: 0.6, userRelevance: 0.5,
            conversationHealth: 0.5, originality: 0.4, educationalValue: 0.4,
            safety: makeSafety()
        )
        // High "community value" (engagement bait) but extreme harm risk
        let harmfulViralScore = RankingMetadata.computeFinalScore(
            communityValue: 1.0, sourceIntegrity: 0.6, userRelevance: 1.0,
            conversationHealth: 0.5, originality: 0.4, educationalValue: 0.4,
            safety: makeSafety(harmRisk: 0.9, misinformationRisk: 0.9, exploitationRisk: 0.9)
        )
        #expect(harmfulViralScore <= safeScore,
                "Viral but harmful content must not outrank safe content in True Source scoring")
    }

    // MARK: Safe content properties

    @Test("Perfectly safe content with high positive signals scores above zero")
    func safePerfectContentScoresHigh() {
        let score = RankingMetadata.computeFinalScore(
            communityValue: 1.0, sourceIntegrity: 1.0, userRelevance: 1.0,
            conversationHealth: 1.0, originality: 1.0, educationalValue: 1.0,
            safety: makeSafety()
        )
        #expect(score > 0.5, "Perfect safe content should score above 0.5")
    }

    @Test("Score is always within 0..1 range")
    func scoreIsAlwaysClamped() {
        let scores = [
            RankingMetadata.computeFinalScore(
                communityValue: 0, sourceIntegrity: 0, userRelevance: 0,
                conversationHealth: 0, originality: 0, educationalValue: 0,
                safety: makeSafety(harmRisk: 1.0, misinformationRisk: 1.0, exploitationRisk: 1.0,
                                   doomscrollRisk: 1.0, childSafetyRisk: 1.0)
            ),
            RankingMetadata.computeFinalScore(
                communityValue: 1, sourceIntegrity: 1, userRelevance: 1,
                conversationHealth: 1, originality: 1, educationalValue: 1,
                safety: makeSafety()
            ),
        ]
        for score in scores {
            #expect(score >= 0 && score <= 1, "Score \(score) is out of [0,1] range")
        }
    }
}

// MARK: - aggregateHarmScore used by autoplay gate

@Suite("aggregateHarmScore — autoplay eligibility gate")
struct AggregateHarmScoreTests {

    @Test("aggregateHarmScore of 0 means safe (all risks zero)")
    func zeroAggregateHarmScoreIsSafe() {
        let s = makeSafety()
        #expect(s.aggregateHarmScore == 0)
    }

    @Test("aggregateHarmScore reflects the maximum across all key signals")
    func aggregateHarmScoreIsMaxNotSum() {
        // Even if only one signal is high, aggregate should reflect it
        let s = makeSafety(harmRisk: 0.1, childSafetyRisk: 0.95)
        #expect(s.aggregateHarmScore == 0.95,
                "Child safety risk (0.95) should dominate aggregate harm score")
    }

    @Test("High childSafetyRisk yields high aggregate harm score")
    func childSafetyRiskYieldsHighAggregate() {
        let s = makeSafety(childSafetyRisk: 0.9)
        #expect(s.aggregateHarmScore >= 0.9)
    }

    @Test("High selfHarmRisk yields high aggregate harm score")
    func selfHarmRiskYieldsHighAggregate() {
        let s = makeSafety(selfHarmRisk: 0.85)
        #expect(s.aggregateHarmScore >= 0.85)
    }
}

// MARK: - ProvenanceStatus enum coverage

@Suite("TrueSourceProvenanceStatus")
struct TrueSourceProvenanceStatusTests {

    @Test("All provenance status cases have non-empty raw values")
    func allCasesHaveRawValues() {
        for status in ProvenanceStatus.allCases {
            #expect(!status.rawValue.isEmpty)
        }
    }

    @Test("ProvenanceStatus has expected cases")
    func expectedCasesExist() {
        let all = Set(ProvenanceStatus.allCases.map(\.rawValue))
        #expect(all.contains("original"))
        #expect(all.contains("repost"))
        #expect(all.contains("edited"))
        #expect(all.contains("ai_generated"))
        #expect(all.contains("unknown"))
    }
}
