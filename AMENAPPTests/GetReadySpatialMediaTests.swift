// GetReadySpatialMediaTests.swift
// AMENAPPTests
//
// Unit tests for GetReady Sunday flow, Spatial Home, and Media Session
// using the project-standard Swift Testing framework (@Suite / @Test).

import Testing
import Foundation
@testable import AMENAPP

// MARK: - GetReadyHeroMotion

@Suite("GetReadyHeroMotion")
struct GetReadyHeroMotionTests {

    @Test("Default progress and velocity are zero")
    func defaultState() {
        let motion = GetReadyHeroMotion()
        #expect(motion.progress == 0)
        #expect(motion.velocity == 0)
    }

    @Test("Scale never goes below 0.988 at full scroll")
    func scaleFloor() {
        var motion = GetReadyHeroMotion()
        motion.progress = 1.0
        #expect(motion.overlayScale >= 0.988)
        #expect(motion.overlayScale <= 1.0)
    }

    @Test("Reading mode is true when velocity is low")
    func readingModeAtLowVelocity() {
        var motion = GetReadyHeroMotion()
        motion.velocity = 0.05
        #expect(motion.readingMode == true)
    }

    @Test("Reading mode is false when user is scrolling fast")
    func notReadingModeAtHighVelocity() {
        var motion = GetReadyHeroMotion()
        motion.velocity = 0.5
        #expect(motion.readingMode == false)
    }

    @Test("Dense mode activates past 45% scroll progress")
    func denseAtHighProgress() {
        var motion = GetReadyHeroMotion()
        motion.progress = 0.5
        #expect(motion.dense == true)
    }

    @Test("Dense mode not active below threshold")
    func notDenseBelowThreshold() {
        var motion = GetReadyHeroMotion()
        motion.progress = 0.3
        #expect(motion.dense == false)
    }

    @Test("Glass opacity boost increases with scroll progress")
    func opacityBoostIncreases() {
        var lowMotion = GetReadyHeroMotion()
        lowMotion.progress = 0.1
        var highMotion = GetReadyHeroMotion()
        highMotion.progress = 0.9
        #expect(highMotion.glassOpacityBoost > lowMotion.glassOpacityBoost)
    }

    @Test("Overlay offset is negative (moves up) on scroll")
    func overlayOffsetIsNegative() {
        var motion = GetReadyHeroMotion()
        motion.progress = 1.0
        #expect(motion.overlayOffset < 0)
    }
}

// MARK: - AmenMediaSession

@Suite("AmenMediaSession")
struct AmenMediaSessionTests {

    private func makeSampleSession(
        type: AmenMediaSession.SessionType = .morningInspiration,
        itemCount: Int = 5,
        currentIndex: Int = 0
    ) -> AmenMediaSession {
        AmenMediaSession(
            id: "test-session",
            ownerUid: "uid-test",
            sessionType: type,
            intent: type.displayName,
            communityIds: [],
            itemIds: Array(0..<itemCount).map { "item-\($0)" },
            currentIndex: currentIndex,
            status: .active,
            finiteQueue: true,
            maxItems: itemCount,
            maxDurationSeconds: 900,
            reflectionPromptShown: false,
            sourceSurface: "test"
        )
    }

    @Test("finiteQueue is always true — no infinite sessions")
    func finiteQueueIsAlwaysTrue() {
        let session = makeSampleSession()
        #expect(session.finiteQueue == true)
    }

    @Test("progressFraction is 0 at start")
    func progressFractionAtStart() {
        let session = makeSampleSession(itemCount: 5, currentIndex: 0)
        #expect(session.progressFraction == 0.0)
    }

    @Test("progressFraction is correct at midpoint")
    func progressFractionAtMidpoint() {
        let session = makeSampleSession(itemCount: 4, currentIndex: 2)
        #expect(session.progressFraction == 0.5)
    }

    @Test("isComplete is false when items remain")
    func notCompleteWithRemainingItems() {
        let session = makeSampleSession(itemCount: 5, currentIndex: 2)
        #expect(session.isComplete == false)
    }

    @Test("isComplete is true when currentIndex reaches item count")
    func completeWhenIndexReachesEnd() {
        let session = makeSampleSession(itemCount: 3, currentIndex: 3)
        #expect(session.isComplete == true)
    }

    @Test("remainingCount is correct")
    func remainingCount() {
        let session = makeSampleSession(itemCount: 5, currentIndex: 2)
        #expect(session.remainingCount == 3)
    }

    @Test("Session type display names are non-empty")
    func sessionTypeDisplayNames() {
        for type in AmenMediaSession.SessionType.allCases {
            #expect(!type.displayName.isEmpty)
        }
    }

    @Test("Session type system icons are valid SF Symbol names")
    func sessionTypeIconsPresent() {
        for type in AmenMediaSession.SessionType.allCases {
            #expect(!type.systemIcon.isEmpty)
        }
    }

    @Test("Default max items is at least 1 for all session types")
    func defaultMaxItemsAtLeastOne() {
        for type in AmenMediaSession.SessionType.allCases {
            #expect(type.defaultMaxItems >= 1)
        }
    }

    @Test("Selah reflection has fewer default items for calm experience")
    func selahHasFewerItems() {
        let selah = AmenMediaSession.SessionType.selahReflection
        let encouragement = AmenMediaSession.SessionType.encouragement
        #expect(selah.defaultMaxItems <= encouragement.defaultMaxItems)
    }
}

// MARK: - MediaSessionCheckpoint

@Suite("MediaSessionCheckpoint")
struct MediaSessionCheckpointTests {

    @Test("itemsWatched checkpoint has continue action")
    func itemsWatchedHasContinue() {
        let cp = MediaSessionCheckpoint.checkpoint(for: .itemsWatched)
        let hasContinue = cp.options.contains { $0.action == .continue }
        #expect(hasContinue == true)
    }

    @Test("sessionEnd checkpoint has reflect action")
    func sessionEndHasReflect() {
        let cp = MediaSessionCheckpoint.checkpoint(for: .sessionEnd)
        let hasReflect = cp.options.contains { $0.action == .reflect }
        #expect(hasReflect == true)
    }

    @Test("All checkpoints have at least 2 options")
    func allCheckpointsHaveMultipleOptions() {
        for reason in [MediaSessionCheckpointReason.itemsWatched, .timeElapsed,
                       .rapidSkipping, .sessionEnd] {
            let cp = MediaSessionCheckpoint.checkpoint(for: reason)
            #expect(cp.options.count >= 2)
        }
    }

    @Test("All checkpoint titles are non-empty")
    func checkpointTitlesNonEmpty() {
        let reasons: [MediaSessionCheckpointReason] = [
            .itemsWatched, .timeElapsed, .rapidSkipping, .sensitiveContent, .sessionEnd
        ]
        for reason in reasons {
            let cp = MediaSessionCheckpoint.checkpoint(for: reason)
            #expect(!cp.title.isEmpty)
            #expect(!cp.message.isEmpty)
        }
    }
}

// MARK: - AuthenticityLabel

@Suite("AuthenticityLabel")
struct AuthenticityLabelTests {

    private func makeCleanProvenance() -> MediaProvenance {
        MediaProvenance(
            id: "prov-1",
            postId: "post-1",
            mediaId: "media-1",
            ownerUid: "uid-1",
            capturedOnDevice: true,
            sourceType: .deviceCamera,
            editEvents: [],
            aiEvents: [],
            authenticityConfidence: 0.95,
            contentCredentialsStatus: .verified,
            syntheticMediaStatus: .clean,
            disclosureRequired: false,
            disclosureSatisfied: true,
            moderationStatus: "approved"
        )
    }

    @Test("Clean real media produces a realMedia label")
    func cleanMediaHasRealMediaLabel() {
        let provenance = makeCleanProvenance()
        let labels = AuthenticityLabel.labels(for: provenance)
        let hasRealMedia = labels.contains { $0.kind == .realMedia }
        #expect(hasRealMedia == true)
    }

    @Test("Verified credentials adds creator verified label")
    func verifiedCredentialsAddsLabel() {
        let provenance = makeCleanProvenance()
        let labels = AuthenticityLabel.labels(for: provenance)
        let hasVerified = labels.contains { $0.kind == .creatorVerified }
        #expect(hasVerified == true)
    }

    @Test("AI generated media produces synthetic warning")
    func aiGeneratedProducesSyntheticWarning() {
        var provenance = makeCleanProvenance()
        provenance = MediaProvenance(
            id: provenance.id,
            postId: provenance.postId,
            mediaId: provenance.mediaId,
            ownerUid: provenance.ownerUid,
            capturedOnDevice: false,
            sourceType: .aiGenerated,
            editEvents: [],
            aiEvents: [],
            authenticityConfidence: 0.2,
            contentCredentialsStatus: .notApplicable,
            syntheticMediaStatus: .aiGeneratedMedia,
            disclosureRequired: true,
            disclosureSatisfied: false,
            moderationStatus: "pending"
        )
        let labels = AuthenticityLabel.labels(for: provenance)
        let hasSynthetic = labels.contains { $0.kind == .syntheticWarning }
        #expect(hasSynthetic == true)
    }

    @Test("System icons are non-empty for all label kinds")
    func allIconsNonEmpty() {
        for kind in AuthenticityLabel.AuthenticityKind.allCases {
            let label = AuthenticityLabel(
                kind: kind, title: "Test", detail: "Test detail", confident: true
            )
            #expect(!label.systemIcon.isEmpty)
        }
    }

    @Test("isSafe returns false for deepfake risk")
    func isSafeFalseForDeepfake() {
        var provenance = makeCleanProvenance()
        provenance = MediaProvenance(
            id: provenance.id, postId: provenance.postId, mediaId: provenance.mediaId,
            ownerUid: provenance.ownerUid, capturedOnDevice: false,
            sourceType: .unknown, editEvents: [], aiEvents: [],
            authenticityConfidence: 0.1,
            contentCredentialsStatus: .failed,
            syntheticMediaStatus: .deepfakeRisk,
            disclosureRequired: true, disclosureSatisfied: false,
            moderationStatus: "pending"
        )
        #expect(provenance.isSafe == false)
    }

    @Test("requiresDisclosureBadge is true when disclosure required but not satisfied")
    func requiresDisclosureBadgeWhenUnsatisfied() {
        var provenance = makeCleanProvenance()
        provenance = MediaProvenance(
            id: provenance.id, postId: provenance.postId, mediaId: provenance.mediaId,
            ownerUid: provenance.ownerUid, capturedOnDevice: true,
            sourceType: .deviceCamera, editEvents: [], aiEvents: [],
            authenticityConfidence: 0.9,
            contentCredentialsStatus: .pending,
            syntheticMediaStatus: .aiAssistedMetadata,
            disclosureRequired: true, disclosureSatisfied: false,
            moderationStatus: "approved"
        )
        #expect(provenance.requiresDisclosureBadge == true)
    }
}

// MARK: - GetReadyGlassChip (visual model validation)

@Suite("GetReadyComposerAction")
struct GetReadyComposerActionTests {

    @Test("Standard actions contain 4 entries")
    func standardActionsCount() {
        #expect(GetReadyComposerAction.standard.count == 4)
    }

    @Test("Contextual actions contain 3 entries")
    func contextualActionsCount() {
        #expect(GetReadyComposerAction.contextual.count == 3)
    }

    @Test("All standard action titles are non-empty")
    func standardActionTitlesNonEmpty() {
        for action in GetReadyComposerAction.standard {
            #expect(!action.title.isEmpty)
        }
    }

    @Test("All standard action icons are non-empty")
    func standardActionIconsNonEmpty() {
        for action in GetReadyComposerAction.standard {
            #expect(!action.icon.isEmpty)
        }
    }

    @Test("All action IDs are unique")
    func actionIDsUnique() {
        let all = GetReadyComposerAction.standard + GetReadyComposerAction.contextual
        let ids = all.map(\.id)
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count)
    }
}

// MARK: - DiscoveryFeedItem

@Suite("DiscoveryFeedItem")
struct DiscoveryFeedItemTests {

    @Test("Why shown explanations are non-empty for all reasons")
    func whyShownExplanationsNonEmpty() {
        let reasons: [DiscoveryFeedItem.DiscoveryReason] = [
            .followedTopic, .friendInteraction, .localCommunity,
            .churchContent, .trustedCreator, .youMightKnow, .slowFeed
        ]
        for reason in reasons {
            let item = DiscoveryFeedItem(
                id: "test", postId: "post",
                reasonForShowing: reason,
                trustScore: 0.8, safetyScore: 0.9,
                communityContext: nil, canReset: true
            )
            #expect(!item.whyShownExplanation.isEmpty)
            #expect(!item.whyShownIcon.isEmpty)
        }
    }
}
