// ThresholdRankerTests.swift
// AMEN — THRESHOLD Smart Profile / Identity Switcher
//
// W2 TESTS — 2026-06-16
// Pure/deterministic — all dates are fixed. No `Date()` calls.
// All tests use SignalCollector.collect(now:entryContext:deepLinkHint:)
// so the same path exercised in production is exercised in tests.

import Testing
import Foundation
@testable import AMENAPP

// MARK: - Test Fixtures

/// A fixed "Sunday 9am" Date for service-window tests.
/// 2026-06-07 is a Sunday (confirmed via Calendar).
private let fixedSundayNineAM: Date = {
    var comps = DateComponents()
    comps.year = 2026; comps.month = 6; comps.day = 7
    comps.hour = 9; comps.minute = 0; comps.second = 0
    return Calendar.current.date(from: comps)!
}()

/// A fixed "Tuesday 3pm" Date for weekday-afternoon tests.
private let fixedTuesdayThreePM: Date = {
    var comps = DateComponents()
    comps.year = 2026; comps.month = 6; comps.day = 9
    comps.hour = 15; comps.minute = 0; comps.second = 0
    return Calendar.current.date(from: comps)!
}()

/// A fixed "Tuesday 8pm" Date for personal/evening tests.
private let fixedTuesdayEightPM: Date = {
    var comps = DateComponents()
    comps.year = 2026; comps.month = 6; comps.day = 9
    comps.hour = 20; comps.minute = 0; comps.second = 0
    return Calendar.current.date(from: comps)!
}()

// MARK: - Profile Builders

private func makeProfile(
    id: String,
    type: ProfileType,
    handle: String? = nil
) -> ProfileDescriptor {
    ProfileDescriptor(
        id: id,
        identityId: "identity-1",
        type: type,
        handle: handle ?? id,
        displayName: handle ?? id,
        avatarRef: nil,
        trustTier: .established,
        capabilities: [.post, .dm],
        e2eeKeyRef: nil
    )
}

// MARK: - ThresholdRankerTests

struct ThresholdRankerTests {

    private let ranker = DefaultThresholdRanker()

    // MARK: - testDeepLinkMatchTopsRanking

    /// A profile whose id matches deepLinkProfileHint must rank first,
    /// regardless of profile type or time of day.
    @Test func testDeepLinkMatchTopsRanking() {
        let profiles: [ProfileDescriptor] = [
            makeProfile(id: "ministry-1", type: .ministry),
            makeProfile(id: "personal-1", type: .personal),
            makeProfile(id: "creator-1",  type: .creator),
        ]

        // Deep link targets the personal profile — the "weakest" type for Sunday morning.
        let signal = SignalCollector.collect(
            now: fixedSundayNineAM,
            entryContext: .deepLink,
            deepLinkHint: "personal-1"
        )

        let prediction = ranker.rank(profiles, signal)

        #expect(prediction.ranked.first?.profileId == "personal-1",
                "Deep-link-hinted profile must be ranked first regardless of type or time")
        #expect(prediction.confidence > 0.0,
                "Confidence must be positive when a deep-link match fires")
    }

    // MARK: - testMinistryTopsSundayMorning

    /// A ministry profile must rank first on Sunday at 9am (the service window),
    /// when there is no deep-link hint.
    @Test func testMinistryTopsSundayMorning() {
        let profiles: [ProfileDescriptor] = [
            makeProfile(id: "personal-1", type: .personal),
            makeProfile(id: "ministry-1", type: .ministry),
            makeProfile(id: "creator-1",  type: .creator),
        ]

        // No deep-link hint — service-window + time-of-day signals should elevate ministry.
        let signal = SignalCollector.collect(
            now: fixedSundayNineAM,
            entryContext: .coldLaunch,
            deepLinkHint: nil
        )

        let prediction = ranker.rank(profiles, signal)

        #expect(prediction.ranked.first?.profileId == "ministry-1",
                "Ministry profile must rank first on Sunday morning service window")
        #expect(prediction.ranked.first?.score ?? 0 > (prediction.ranked.dropFirst().first?.score ?? 0),
                "Ministry score must strictly exceed runner-up on Sunday morning")
    }

    // MARK: - testDeterminism

    /// Identical input → identical output, every single call.
    @Test func testDeterminism() {
        let profiles: [ProfileDescriptor] = [
            makeProfile(id: "personal-1", type: .personal),
            makeProfile(id: "ministry-1", type: .ministry),
            makeProfile(id: "creator-1",  type: .creator),
            makeProfile(id: "org-1",      type: .org),
        ]

        let signal = SignalCollector.collect(
            now: fixedTuesdayThreePM,
            entryContext: .inAppSwitch,
            deepLinkHint: nil
        )

        let first  = ranker.rank(profiles, signal)
        let second = ranker.rank(profiles, signal)

        #expect(first.ranked.map(\.profileId) == second.ranked.map(\.profileId),
                "Ranked order must be identical for identical inputs")
        #expect(first.ranked.map(\.score) == second.ranked.map(\.score),
                "Scores must be identical for identical inputs")
        #expect(first.ranked.map(\.reason) == second.ranked.map(\.reason),
                "Reasons must be identical for identical inputs")
        #expect(first.confidence == second.confidence,
                "Confidence must be identical for identical inputs")
    }

    // MARK: - testAntiEngagement_noSessionLengthSignal

    /// Calling rank() twice with identical input must produce identical output.
    /// This verifies: no hidden mutation, no incrementing internal counter,
    /// no time-sensitive side effect, no engagement-proxy state accumulation.
    ///
    /// The only way output can differ across calls is if the ALLOWED signals
    /// (time, season, deepLink, recency) differ — and here they are identical.
    @Test func testAntiEngagement_noSessionLengthSignal() {
        let profiles: [ProfileDescriptor] = [
            makeProfile(id: "ministry-A", type: .ministry),
            makeProfile(id: "personal-B", type: .personal),
        ]

        // Fixed, non-service-window moment — no ambiguity in scoring.
        let signal = SignalCollector.collect(
            now: fixedTuesdayEightPM,
            entryContext: .coldLaunch,
            deepLinkHint: nil
        )

        // Call rank() many times; output must never change.
        let results = (0..<10).map { _ in ranker.rank(profiles, signal) }

        let referenceIds     = results[0].ranked.map(\.profileId)
        let referenceScores  = results[0].ranked.map(\.score)
        let referenceReasons = results[0].ranked.map(\.reason)

        for (index, result) in results.enumerated() {
            #expect(result.ranked.map(\.profileId) == referenceIds,
                    "Call \(index): ranked IDs must not change across calls (no hidden state)")
            #expect(result.ranked.map(\.score) == referenceScores,
                    "Call \(index): scores must not change across calls (anti-engagement)")
            #expect(result.ranked.map(\.reason) == referenceReasons,
                    "Call \(index): reasons must not change across calls (no side effects)")
        }
    }

    // MARK: - testReasonStringNotEmpty

    /// Every RankedProfile returned by the ranker must have a non-empty reason
    /// string of at most 60 characters.
    @Test func testReasonStringNotEmpty() {
        // Exercise a variety of profile types and signals to maximise coverage.
        let profileSets: [[ProfileDescriptor]] = [
            [makeProfile(id: "p1", type: .personal),
             makeProfile(id: "m1", type: .ministry),
             makeProfile(id: "c1", type: .creator),
             makeProfile(id: "o1", type: .org)],
            [makeProfile(id: "solo", type: .personal)],
        ]

        let signals: [SwitchSignal] = [
            SignalCollector.collect(now: fixedSundayNineAM,    entryContext: .coldLaunch,       deepLinkHint: nil),
            SignalCollector.collect(now: fixedTuesdayThreePM,  entryContext: .deepLink,          deepLinkHint: "m1"),
            SignalCollector.collect(now: fixedTuesdayEightPM,  entryContext: .notificationTap,   deepLinkHint: nil),
            SignalCollector.collect(now: fixedSundayNineAM,    entryContext: .shareSheet,        deepLinkHint: "o1"),
        ]

        for profiles in profileSets {
            for signal in signals {
                let prediction = ranker.rank(profiles, signal)
                for ranked in prediction.ranked {
                    #expect(!ranked.reason.isEmpty,
                            "Reason must not be empty for profileId: \(ranked.profileId)")
                    #expect(ranked.reason.count <= 60,
                            "Reason '\(ranked.reason)' exceeds 60 chars for profileId: \(ranked.profileId)")
                }
            }
        }
    }
}
