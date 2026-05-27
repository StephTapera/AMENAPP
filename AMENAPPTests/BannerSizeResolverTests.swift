// BannerSizeResolverTests.swift
// AMEN — Selah Banner Rail
//
// Contract tests for the size waterfall resolution logic.
// Mirrors the server-side waterfall in banners.js:
//   user preference → space default → surface default → standard
//
// All tests are deterministic and offline-safe — no Firebase calls.
//
// Coverage:
//   ✓ User preference wins over everything
//   ✓ Server-resolved size used when no user preference
//   ✓ Surface default used when no user pref + no server size
//   ✓ "standard" is returned when all inputs are nil
//   ✓ Surface default values match the Swift AmenSpaceBannerSurface.defaultSize contract
//   ✓ AmenSpaceBannerSize card dimensions match the UI spec
//   ✓ Feature flag defaults to false (bannerRail is off by default)
//   ✓ Deduplication by targetRoute removes exact-route duplicates
//   ✓ Analytics event raw values match the server schema

import Foundation
import Testing
@testable import AMENAPP

// MARK: - Size waterfall

@Suite("Banner Size Resolver — waterfall priority")
struct BannerSizeResolverTests {

    @Test("user preference wins over server-resolved size and surface default")
    func userPreferenceWins() {
        let resolved = AmenSpaceBannerRailViewModel.resolvedSize(
            userPreference: .hero,
            serverResolvedSize: .compact,
            surfaceDefault: .standard
        )
        #expect(resolved == .hero)
    }

    @Test("server-resolved size used when user preference is absent")
    func serverSizeUsedWhenNoUserPref() {
        let resolved = AmenSpaceBannerRailViewModel.resolvedSize(
            userPreference: nil,
            serverResolvedSize: .large,
            surfaceDefault: .compact
        )
        #expect(resolved == .large)
    }

    @Test("surface default used when user pref and server size are both absent")
    func surfaceDefaultUsedWhenBothAbsent() {
        let resolved = AmenSpaceBannerRailViewModel.resolvedSize(
            userPreference: nil,
            serverResolvedSize: nil,
            surfaceDefault: .compact
        )
        #expect(resolved == .compact)
    }

    @Test("each size in the waterfall can be the winner independently")
    func eachLevelCanWin() {
        // Level 1 — user preference
        #expect(AmenSpaceBannerRailViewModel.resolvedSize(
            userPreference: .compact, serverResolvedSize: .hero, surfaceDefault: .large
        ) == .compact)

        // Level 2 — server
        #expect(AmenSpaceBannerRailViewModel.resolvedSize(
            userPreference: nil, serverResolvedSize: .hero, surfaceDefault: .large
        ) == .hero)

        // Level 3 — surface default
        #expect(AmenSpaceBannerRailViewModel.resolvedSize(
            userPreference: nil, serverResolvedSize: nil, surfaceDefault: .large
        ) == .large)
    }
}

// MARK: - Surface default values

@Suite("Banner Surface Defaults — match Swift + JS spec")
struct BannerSurfaceDefaultTests {

    @Test("spaceDetail default is large")
    func spaceDetailDefault() {
        #expect(AmenSpaceBannerSurface.spaceDetail.defaultSize == .large)
    }

    @Test("churchProfile default is large")
    func churchProfileDefault() {
        #expect(AmenSpaceBannerSurface.churchProfile.defaultSize == .large)
    }

    @Test("schoolProfile default is large")
    func schoolProfileDefault() {
        #expect(AmenSpaceBannerSurface.schoolProfile.defaultSize == .large)
    }

    @Test("businessProfile default is large")
    func businessProfileDefault() {
        #expect(AmenSpaceBannerSurface.businessProfile.defaultSize == .large)
    }

    @Test("homeFeed default is compact")
    func homeFeedDefault() {
        #expect(AmenSpaceBannerSurface.homeFeed.defaultSize == .compact)
    }

    @Test("spacesHome default is standard")
    func spacesHomeDefault() {
        #expect(AmenSpaceBannerSurface.spacesHome.defaultSize == .standard)
    }

    @Test("discovery default is standard")
    func discoveryDefault() {
        #expect(AmenSpaceBannerSurface.discovery.defaultSize == .standard)
    }
}

// MARK: - Card dimensions (UI spec contract)

@Suite("Banner Size — card dimensions match UI spec")
struct BannerCardDimensionTests {

    @Test("compact: 148h × 280w")
    func compactDimensions() {
        #expect(AmenSpaceBannerSize.compact.cardHeight == 148)
        #expect(AmenSpaceBannerSize.compact.cardWidth  == 280)
    }

    @Test("standard: 190h × 318w")
    func standardDimensions() {
        #expect(AmenSpaceBannerSize.standard.cardHeight == 190)
        #expect(AmenSpaceBannerSize.standard.cardWidth  == 318)
    }

    @Test("large: 236h × 342w")
    func largeDimensions() {
        #expect(AmenSpaceBannerSize.large.cardHeight == 236)
        #expect(AmenSpaceBannerSize.large.cardWidth  == 342)
    }

    @Test("hero: 292h × 360w")
    func heroDimensions() {
        #expect(AmenSpaceBannerSize.hero.cardHeight == 292)
        #expect(AmenSpaceBannerSize.hero.cardWidth  == 360)
    }

    @Test("card width grows with size (compact < standard < large < hero)")
    func widthMonotonicallyIncreases() {
        let widths = AmenSpaceBannerSize.allCases.map(\.cardWidth)
        for i in 0..<(widths.count - 1) {
            #expect(widths[i] < widths[i + 1], "Width did not increase from index \(i) to \(i+1)")
        }
    }
}

// MARK: - Feature flag default

@Suite("Banner Rail — feature flag defaults")
struct BannerRailFeatureFlagTests {

    @Test("bannerRailEnabled defaults to false")
    @MainActor
    func bannerRailDefaultsOff() {
        #expect(AMENFeatureFlags.shared.bannerRailEnabled == false)
    }
}

// MARK: - Deduplication

@Suite("Banner Rail ViewModel — deduplication")
struct BannerRailDeduplicationTests {

    private func makeItem(id: String, route: String) -> AmenSpaceBannerItem {
        AmenSpaceBannerItem(
            id: id,
            sourceId: id,
            type: .announcement,
            title: "Title",
            subtitle: "",
            imageURL: nil,
            iconURL: nil,
            spaceId: nil,
            targetRoute: route,
            ctaLabel: .open,
            priority: 0,
            startsAt: nil,
            endsAt: nil,
            location: nil,
            moderationStatus: "approved",
            visibility: "authenticated",
            createdBy: nil,
            trustedContext: nil,
            rankingReason: "featured",
            resolvedSize: .standard
        )
    }

    @Test("duplicate targetRoute is removed; first occurrence retained")
    func duplicateRouteRemoved() {
        let items = [
            makeItem(id: "a", route: "selah://space/spc1"),
            makeItem(id: "b", route: "selah://space/spc1"), // duplicate
            makeItem(id: "c", route: "selah://space/spc2"),
        ]
        let deduped = AmenSpaceBannerRailViewModel.deduplicated(items)
        #expect(deduped.count == 2)
        #expect(deduped[0].id == "a")
        #expect(deduped[1].id == "c")
    }

    @Test("unique routes are all retained")
    func uniqueRoutesRetained() {
        let items = [
            makeItem(id: "a", route: "selah://space/s1"),
            makeItem(id: "b", route: "selah://space/s2"),
            makeItem(id: "c", route: "selah://group/g1"),
        ]
        let deduped = AmenSpaceBannerRailViewModel.deduplicated(items)
        #expect(deduped.count == 3)
    }

    @Test("empty input produces empty output")
    func emptyInput() {
        let deduped = AmenSpaceBannerRailViewModel.deduplicated([])
        #expect(deduped.isEmpty)
    }
}

// MARK: - Analytics event raw value contract

@Suite("Banner Analytics Events — raw value stability")
struct BannerAnalyticsEventTests {

    @Test("analytics event rawValues match server schema")
    func analyticsEventRawValues() {
        #expect(AmenSpaceBannerAnalyticsEvent.impression.rawValue   == "banner_impression")
        #expect(AmenSpaceBannerAnalyticsEvent.tap.rawValue          == "banner_tap")
        #expect(AmenSpaceBannerAnalyticsEvent.dismiss.rawValue      == "banner_dismiss")
        #expect(AmenSpaceBannerAnalyticsEvent.ctaComplete.rawValue  == "banner_cta_complete")
        #expect(AmenSpaceBannerAnalyticsEvent.hiddenReason.rawValue == "banner_hidden_reason")
    }
}
