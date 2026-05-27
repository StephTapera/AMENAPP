// BannerRouteTests.swift
// AMEN — Selah Banner Rail
//
// Contract tests for AmenSpaceBannerRoute parsing.
// All tests are deterministic and offline-safe — no Firebase calls.
//
// Coverage:
//   ✓ All 6 valid route patterns parse to the correct typed case
//   ✓ Mismatched CTA + host combinations return nil
//   ✓ Wrong scheme (non-selah://) returns nil
//   ✓ Invalid identifier characters are rejected
//   ✓ Query strings and fragments are rejected
//   ✓ Bare host (no path id) returns nil
//   ✓ Open-variant bare routes (selah://group/id without CTA suffix)
//   ✓ entityId extraction is correct for every case
//   ✓ completionSource strings match the server analytics schema

import Foundation
import Testing
@testable import AMENAPP

// MARK: - Valid routes

@Suite("Banner Route — valid parses")
struct BannerRouteValidParseTests {

    @Test("selah://group/{id} + .join → .joinGroup(id:)")
    func joinGroup() {
        let r = AmenSpaceBannerRoute(route: "selah://group/abc123", cta: .join)
        #expect(r == .joinGroup(id: "abc123"))
    }

    @Test("selah://event/{id}/rsvp + .rsvp → .rsvpEvent(id:)")
    func rsvpEvent() {
        let r = AmenSpaceBannerRoute(route: "selah://event/evt-456/rsvp", cta: .rsvp)
        #expect(r == .rsvpEvent(id: "evt-456"))
    }

    @Test("selah://job/{id}/apply + .apply → .applyJob(id:)")
    func applyJob() {
        let r = AmenSpaceBannerRoute(route: "selah://job/job_789/apply", cta: .apply)
        #expect(r == .applyJob(id: "job_789"))
    }

    @Test("selah://space/{id} + .open → .openSpace(id:)")
    func openSpace() {
        let r = AmenSpaceBannerRoute(route: "selah://space/space-001", cta: .open)
        #expect(r == .openSpace(id: "space-001"))
    }

    @Test("selah://prayer/{id} + .pray → .pray(id:)")
    func prayRoute() {
        let r = AmenSpaceBannerRoute(route: "selah://prayer/prayer-abc", cta: .pray)
        #expect(r == .pray(id: "prayer-abc"))
    }

    @Test("selah://sermon/{id} + .watch → .watchSermon(id:)")
    func watchSermon() {
        let r = AmenSpaceBannerRoute(route: "selah://sermon/s-999", cta: .watch)
        #expect(r == .watchSermon(id: "s-999"))
    }
}

// MARK: - Invalid: mismatched CTA + host

@Suite("Banner Route — CTA / host mismatches return nil")
struct BannerRouteMismatchTests {

    @Test("join CTA on event host → nil")
    func joinOnEvent() {
        #expect(AmenSpaceBannerRoute(route: "selah://event/abc", cta: .join) == nil)
    }

    @Test("rsvp CTA without /rsvp suffix → nil")
    func rsvpMissingSuffix() {
        #expect(AmenSpaceBannerRoute(route: "selah://event/abc", cta: .rsvp) == nil)
    }

    @Test("apply CTA without /apply suffix → nil")
    func applyMissingSuffix() {
        #expect(AmenSpaceBannerRoute(route: "selah://job/abc", cta: .apply) == nil)
    }

    @Test("open CTA on group host → nil")
    func openOnGroup() {
        #expect(AmenSpaceBannerRoute(route: "selah://group/abc", cta: .open) == nil)
    }

    @Test("pray CTA on space host → nil")
    func prayOnSpace() {
        #expect(AmenSpaceBannerRoute(route: "selah://space/abc", cta: .pray) == nil)
    }

    @Test("watch CTA on prayer host → nil")
    func watchOnPrayer() {
        #expect(AmenSpaceBannerRoute(route: "selah://prayer/abc", cta: .watch) == nil)
    }
}

// MARK: - Invalid: structural problems

@Suite("Banner Route — structural rejections")
struct BannerRouteStructuralTests {

    @Test("wrong scheme returns nil")
    func wrongScheme() {
        #expect(AmenSpaceBannerRoute(route: "amen://group/abc", cta: .join) == nil)
        #expect(AmenSpaceBannerRoute(route: "https://example.com/group/abc", cta: .join) == nil)
        #expect(AmenSpaceBannerRoute(route: "group/abc", cta: .join) == nil)
    }

    @Test("empty route returns nil")
    func emptyRoute() {
        #expect(AmenSpaceBannerRoute(route: "", cta: .join) == nil)
    }

    @Test("query string is rejected")
    func queryStringRejected() {
        #expect(AmenSpaceBannerRoute(route: "selah://group/abc?foo=bar", cta: .join) == nil)
    }

    @Test("fragment is rejected")
    func fragmentRejected() {
        #expect(AmenSpaceBannerRoute(route: "selah://group/abc#section", cta: .join) == nil)
    }

    @Test("empty id segment is rejected")
    func emptyId() {
        #expect(AmenSpaceBannerRoute(route: "selah://group/", cta: .join) == nil)
    }

    @Test("id with forbidden characters is rejected")
    func badIdCharacters() {
        // Spaces and slashes in id should not parse
        #expect(AmenSpaceBannerRoute(route: "selah://group/abc def", cta: .join) == nil)
        #expect(AmenSpaceBannerRoute(route: "selah://group/abc/def/extra", cta: .join) == nil)
    }

    @Test("host-only URL with no id is rejected")
    func noId() {
        #expect(AmenSpaceBannerRoute(route: "selah://group", cta: .join) == nil)
    }
}

// MARK: - entityId extraction

@Suite("Banner Route — entityId")
struct BannerRouteEntityIdTests {

    @Test("entityId matches parsed id for all 6 route types")
    func entityIdAllCases() {
        let cases: [(String, AmenSpaceBannerCTA, String)] = [
            ("selah://group/grp1",       .join,  "grp1"),
            ("selah://event/evt1/rsvp",  .rsvp,  "evt1"),
            ("selah://job/job1/apply",   .apply, "job1"),
            ("selah://space/spc1",       .open,  "spc1"),
            ("selah://prayer/pry1",      .pray,  "pry1"),
            ("selah://sermon/ser1",      .watch, "ser1"),
        ]
        for (route, cta, expected) in cases {
            let parsed = AmenSpaceBannerRoute(route: route, cta: cta)
            #expect(parsed?.entityId == expected, "entityId mismatch for route \(route)")
        }
    }
}

// MARK: - completionSource strings (analytics schema contract)

@Suite("Banner Route — completionSource analytics contract")
struct BannerRouteCompletionSourceTests {

    @Test("completionSource values match server analytics schema")
    func completionSources() {
        #expect(AmenSpaceBannerRoute.joinGroup(id: "x").completionSource  == "group_join")
        #expect(AmenSpaceBannerRoute.rsvpEvent(id: "x").completionSource  == "event_rsvp")
        #expect(AmenSpaceBannerRoute.applyJob(id: "x").completionSource   == "job_apply")
        #expect(AmenSpaceBannerRoute.openSpace(id: "x").completionSource  == "space_open")
        #expect(AmenSpaceBannerRoute.pray(id: "x").completionSource       == "prayer")
        #expect(AmenSpaceBannerRoute.watchSermon(id: "x").completionSource == "sermon_watch")
    }
}

// MARK: - Callable name contract

@Suite("Banner Callable Names — contract stability")
struct BannerCallableNameTests {

    @Test("callable rawValues match functions/banners.js exports exactly")
    func callableNames() {
        #expect(AmenSpaceBannerCallable.resolveBannerRail.rawValue                   == "resolveBannerRail")
        #expect(AmenSpaceBannerCallable.logAmenSpaceBannerEvent.rawValue             == "logAmenSpaceBannerEvent")
        #expect(AmenSpaceBannerCallable.validateAmenSpaceBannerCTA.rawValue          == "validateAmenSpaceBannerCTA")
        #expect(AmenSpaceBannerCallable.setAmenSpaceBannerDisplayPreference.rawValue == "setAmenSpaceBannerDisplayPreference")
        #expect(AmenSpaceBannerCallable.setAmenSpaceDefaultBannerSize.rawValue       == "setAmenSpaceDefaultBannerSize")
    }
}
