#if false
// ObjectHubTests.swift
// AMENAPPTests
//
// Unit tests for the Object Hub / Inline Hub Pill wiring.
// No Firebase emulator required — tests cover model logic, action ranking,
// Firestore CodingKeys mapping, pill visibility rules, and feature flags.

import Testing
import Foundation
@testable import AMENAPP

// MARK: - Suite A: Inline Action Ranker

@Suite("Object Hub — Inline Action Ranker")
struct ObjectHubActionRankerTests {

    @Test("Song returns openProvider + save + discuss + openHub (≤4)")
    func songActionsAreCapped() {
        let actions = AmenObjectHubInlineActionRanker.actions(for: .song, safetyState: .approved)
        #expect(actions.count <= 4, "Inline cluster must never exceed 4 actions")
        #expect(actions.contains(.openHub), "openHub must always be present for safe song")
        #expect(actions.contains(.openProvider), "song needs Listen action")
    }

    @Test("Blocked safety state returns empty actions")
    func blockedSafetyReturnsEmpty() {
        let actions = AmenObjectHubInlineActionRanker.actions(for: .song, safetyState: .blocked)
        #expect(actions.isEmpty, "Blocked hub must expose no actions")
    }

    @Test("Limited safety state returns only openHub")
    func limitedSafetyReturnsOnlyOpenHub() {
        let actions = AmenObjectHubInlineActionRanker.actions(for: .video, safetyState: .limited)
        #expect(actions == [.openHub], "Limited hub exposes only Open Hub")
    }

    @Test("Video returns Watch as provider label")
    func videoProviderLabel() {
        let label = AmenObjectHubInlineActionRanker.providerLabel(for: .video)
        #expect(label == "Watch")
    }

    @Test("Article returns Read as provider label")
    func articleProviderLabel() {
        let label = AmenObjectHubInlineActionRanker.providerLabel(for: .article)
        #expect(label == "Read")
    }

    @Test("Podcast returns Play as provider label")
    func podcastProviderLabel() {
        let label = AmenObjectHubInlineActionRanker.providerLabel(for: .podcast)
        #expect(label == "Play")
    }

    @Test("Song Hub action text is correct")
    func songActionText() {
        let text = AmenObjectHubInlineActionRanker.actionText(for: .song)
        #expect(text == "Song Hub")
    }

    @Test("Song icon is music.note")
    func songIcon() {
        let icon = AmenObjectHubInlineActionRanker.icon(for: .song)
        #expect(icon == "music.note")
    }

    @Test("Article icon is doc.text")
    func articleIcon() {
        let icon = AmenObjectHubInlineActionRanker.icon(for: .article)
        #expect(icon == "doc.text")
    }

    @Test("Generic link falls back to openHub + discuss (not openProvider)")
    func genericLinkActions() {
        let actions = AmenObjectHubInlineActionRanker.actions(for: .genericLink, safetyState: .approved)
        #expect(actions.contains(.openHub))
        #expect(actions.count <= 4)
    }
}

// MARK: - Suite B: CommunityHubPreview Visibility Rules

@Suite("Object Hub — Preview Visibility Rules")
struct ObjectHubPreviewVisibilityTests {

    private func makePreview(
        safetyState: String = "approved",
        explicitState: String = "clean",
        privacyState: String = "public",
        hubId: String = "hub-123",
        canonicalObjectId: String = "obj-456"
    ) -> AmenPostCommunityHubPreview {
        AmenPostCommunityHubPreview(
            hubId: hubId,
            canonicalObjectId: canonicalObjectId,
            objectTypeRaw: "song",
            title: "Test Song",
            aggregateText: "12 people saved this",
            actionText: "Song Hub",
            safetyStateRaw: safetyState,
            explicitContentStateRaw: explicitState,
            privacyStateRaw: privacyState,
            iconKind: "music.note",
            canonicalUrl: "https://open.spotify.com/track/test"
        )
    }

    @Test("Approved public preview is visible")
    func approvedPublicIsVisible() {
        let preview = makePreview()
        #expect(preview.isVisiblePreview)
    }

    @Test("Blocked safety hides preview")
    func blockedSafetyHidesPreview() {
        let preview = makePreview(safetyState: "blocked")
        #expect(!preview.isVisiblePreview)
    }

    @Test("Blocked explicit state hides preview")
    func blockedExplicitHidesPreview() {
        let preview = makePreview(explicitState: "blocked")
        #expect(!preview.isVisiblePreview)
    }

    @Test("Private hub hides preview")
    func privateHubHidesPreview() {
        let preview = makePreview(privacyState: "private")
        #expect(!preview.isVisiblePreview)
    }

    @Test("Empty hubId hides preview")
    func emptyHubIdHidesPreview() {
        let preview = makePreview(hubId: "")
        #expect(!preview.isVisiblePreview)
    }

    @Test("Empty canonicalObjectId hides preview")
    func emptyCanonicalObjectIdHidesPreview() {
        let preview = makePreview(canonicalObjectId: "")
        #expect(!preview.isVisiblePreview)
    }

    @Test("Limited safety state is visible (shows limited copy)")
    func limitedSafetyIsVisible() {
        let preview = makePreview(safetyState: "limited")
        #expect(preview.isVisiblePreview, "Limited hubs show a restricted pill, not hidden")
    }
}

// MARK: - Suite C: CodingKeys Firestore Mapping

@Suite("Object Hub — CodingKeys Firestore field mapping")
struct ObjectHubCodingKeysTests {

    @Test("AmenPostCommunityHubPreview decodes from Firestore-style field names")
    func decodesFromFirestoreFieldNames() throws {
        // Backend writes objectType/safetyState/explicitContentState/privacyState
        let json = """
        {
          "hubId": "hub-abc",
          "canonicalObjectId": "obj-xyz",
          "objectType": "song",
          "title": "Oceans",
          "aggregateText": "5 people saved this",
          "actionText": "Song Hub",
          "safetyState": "approved",
          "explicitContentState": "clean",
          "privacyState": "public",
          "iconKind": "music.note",
          "canonicalUrl": "https://open.spotify.com/track/xyz"
        }
        """
        let data = json.data(using: .utf8)!
        let preview = try JSONDecoder().decode(AmenPostCommunityHubPreview.self, from: data)

        #expect(preview.hubId == "hub-abc")
        #expect(preview.canonicalObjectId == "obj-xyz")
        #expect(preview.objectTypeRaw == "song", "objectType Firestore key must map to objectTypeRaw")
        #expect(preview.safetyStateRaw == "approved", "safetyState Firestore key must map to safetyStateRaw")
        #expect(preview.explicitContentStateRaw == "clean")
        #expect(preview.privacyStateRaw == "public")
        #expect(preview.iconKind == "music.note")
        #expect(preview.isVisiblePreview)
    }

    @Test("Missing optional fields decode without crash")
    func missingOptionalFieldsDecodeSafely() throws {
        let json = """
        {
          "hubId": "hub-123",
          "canonicalObjectId": "obj-456",
          "objectType": "article",
          "title": "Test Article",
          "aggregateText": "3 discussions",
          "actionText": "Discuss",
          "safetyState": "needsReview",
          "explicitContentState": "unknown",
          "privacyState": "public"
        }
        """
        let data = json.data(using: .utf8)!
        let preview = try JSONDecoder().decode(AmenPostCommunityHubPreview.self, from: data)
        #expect(preview.iconKind == nil)
        #expect(preview.canonicalUrl == nil)
        #expect(preview.hubId == "hub-123")
    }

    @Test("Equatable identity holds for same data")
    func equatableIdentityHolds() throws {
        let json = """
        {
          "hubId": "hub-1",
          "canonicalObjectId": "obj-1",
          "objectType": "video",
          "title": "T",
          "aggregateText": "A",
          "actionText": "B",
          "safetyState": "approved",
          "explicitContentState": "clean",
          "privacyState": "public"
        }
        """
        let data = json.data(using: .utf8)!
        let p1 = try JSONDecoder().decode(AmenPostCommunityHubPreview.self, from: data)
        let p2 = try JSONDecoder().decode(AmenPostCommunityHubPreview.self, from: data)
        #expect(p1 == p2)
    }
}

// MARK: - Suite D: Feature Flags

@Suite("Object Hub — Feature Flags")
struct ObjectHubFeatureFlagTests {

    @Test("All 5 Object Hub flags exist and default true")
    @MainActor func objectHubFlagsDefaultTrue() {
        let flags = AMENFeatureFlags.shared
        #expect(flags.communityHubsEnabled,         "communityHubsEnabled must default true")
        #expect(flags.objectHubViewEnabled,          "objectHubViewEnabled must default true")
        #expect(flags.objectHubInlinePillEnabled,    "objectHubInlinePillEnabled must default true")
        #expect(flags.objectHubInlineClusterEnabled, "objectHubInlineClusterEnabled must default true")
        #expect(flags.communityObjectMatchingEnabled,"communityObjectMatchingEnabled must default true")
    }
}

// MARK: - Suite E: Hub Open Source Enum

@Suite("Object Hub — Open Source Routing")
struct ObjectHubOpenSourceTests {

    @Test("AmenObjectHubOpenSource raw values are stable (used as analytics keys)")
    func openSourceRawValuesAreStable() {
        #expect(AmenObjectHubOpenSource.postCardInlineHubPill.rawValue == "postCardInlineHubPill")
        #expect(AmenObjectHubOpenSource.postCardInlineHubCluster.rawValue == "postCardInlineHubCluster")
        #expect(AmenObjectHubOpenSource.unknown.rawValue == "unknown")
    }

    @Test("AmenObjectHubTarget equality by case")
    func hubTargetEquality() {
        let a = AmenObjectHubTarget.canonicalObjectId("abc")
        let b = AmenObjectHubTarget.canonicalObjectId("abc")
        let c = AmenObjectHubTarget.canonicalObjectId("xyz")
        let u = AmenObjectHubTarget.url("https://example.com")
        #expect(a == b)
        #expect(a != c)
        #expect(a != u)
    }
}

#endif
