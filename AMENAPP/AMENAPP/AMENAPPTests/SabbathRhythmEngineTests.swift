// SabbathRhythmEngineTests.swift
// AMENAPP — Sabbath Mode v2 (Rhythm) engine contracts.
//
// Pure-logic tests over the subtraction engine: trigger arbitration, per-state removal
// policies, the weekly schedule window (including the midnight wrap), the Wave 1 ambient
// trigger thresholds, config persistence round-trips, and the three Sabbath invariants.
// No UIHostingController / accessibility-tree walking — the engine is deliberately pure.

#if canImport(Testing)
import Foundation
import Testing
@testable import AMENAPP

@Suite("Sabbath rhythm engine")
struct SabbathRhythmEngineTests {

    // A fixed reference date — Sunday, 1 Jan 2023, 10:00 local — for deterministic windows.
    private func date(weekday: Int, hour: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2023
        comps.month = 1
        comps.day = 1 + ((weekday - 1) % 7)   // 2023-01-01 is a Sunday (weekday 1)
        comps.hour = hour
        return Calendar.current.date(from: comps) ?? Date(timeIntervalSince1970: 0)
    }

    private let now = Date(timeIntervalSince1970: 0)

    // MARK: - Policies per state

    @Test("normal removes nothing")
    func normalRemovesNothing() {
        let p = SabbathSubtractionPolicy.policy(for: .normal)
        for field in [SabbathSubtractionField.feeds, .metrics, .badges, .streaks, .navigation, .inAppNotifications] {
            #expect(field.isRemoved(by: p) == false)
        }
    }

    @Test("every quiet state removes the full social layer")
    func quietStatesRemoveSocial() {
        for state in [SabbathRhythmState.rest, .presence, .holyGround] {
            let p = SabbathSubtractionPolicy.policy(for: state)
            for field in [SabbathSubtractionField.feeds, .metrics, .badges, .streaks] {
                #expect(field.isRemoved(by: p), "\(state) should remove \(field)")
            }
        }
    }

    @Test("presence keeps navigation; rest and holy ground remove it")
    func navigationDistinction() {
        #expect(SabbathSubtractionField.navigation.isRemoved(by: .policy(for: .presence)) == false)
        #expect(SabbathSubtractionField.navigation.isRemoved(by: .policy(for: .rest)))
        #expect(SabbathSubtractionField.navigation.isRemoved(by: .policy(for: .holyGround)))
    }

    // MARK: - Resolver arbitration

    @Test("resolver stays normal when all triggers are silent or disabled")
    func resolverSilentByDefault() {
        let triggers: [SabbathTriggerSource] = [
            SabbathManualTrigger(isEnabled: false, manualState: .rest),
            SabbathScheduleTrigger(isEnabled: true, schedule: nil),
            SabbathUsageTrigger(isEnabled: false, dwellSeconds: 99_999),
        ]
        #expect(SabbathTriggerResolver().resolve(triggers: triggers, now: now) == .normal)
    }

    @Test("sub-threshold confidence never takes effect")
    func subThresholdStaysNormal() {
        // Usage at 10 minutes is below the 25-minute onset → silent.
        let triggers: [SabbathTriggerSource] = [
            SabbathUsageTrigger(isEnabled: true, dwellSeconds: 10 * 60),
        ]
        #expect(SabbathTriggerResolver().resolve(triggers: triggers, now: now) == .normal)
    }

    @Test("highest-confidence proposal wins")
    func highestConfidenceWins() {
        // Location proposes .presence @0.8; motion proposes .rest @0.6 → presence wins.
        let triggers: [SabbathTriggerSource] = [
            SabbathLocationTrigger(isEnabled: true, isAtPlaceOfWorship: true),
            SabbathMotionTrigger(isEnabled: true, isWalking: true),
        ]
        #expect(SabbathTriggerResolver().resolve(triggers: triggers, now: now) == .presence)
    }

    @Test("a deliberate manual choice (1.0) beats any ambient guess")
    func manualBeatsAmbient() {
        let triggers: [SabbathTriggerSource] = [
            SabbathManualTrigger(isEnabled: true, manualState: .holyGround),
            SabbathLocationTrigger(isEnabled: true, isAtPlaceOfWorship: true),
        ]
        #expect(SabbathTriggerResolver().resolve(triggers: triggers, now: now) == .holyGround)
    }

    // MARK: - Manual trigger

    @Test("manual trigger is silent when not resting or disabled or normal")
    func manualSilences() {
        #expect(SabbathManualTrigger(isEnabled: true, manualState: nil).proposal(now: now) == .silent)
        #expect(SabbathManualTrigger(isEnabled: false, manualState: .rest).proposal(now: now) == .silent)
        #expect(SabbathManualTrigger(isEnabled: true, manualState: .normal).proposal(now: now) == .silent)
    }

    @Test("manual trigger proposes the exact chosen state at full confidence")
    func manualProposesChosenState() {
        let p = SabbathManualTrigger(isEnabled: true, manualState: .holyGround).proposal(now: now)
        #expect(p.proposedState == .holyGround)
        #expect(p.confidence == 1.0)
    }

    // MARK: - Schedule window (incl. midnight wrap)

    @Test("schedule fires only inside its weekday window")
    func scheduleWindow() {
        let schedule = SabbathSchedule(weekday: 1, startHour: 9, endHour: 12)   // Sun 9–12
        #expect(schedule.contains(date(weekday: 1, hour: 10)))                  // inside
        #expect(schedule.contains(date(weekday: 1, hour: 12)) == false)         // end-exclusive
        #expect(schedule.contains(date(weekday: 2, hour: 10)) == false)         // wrong day
    }

    @Test("schedule window wraps past midnight when end <= start")
    func scheduleWrap() {
        let schedule = SabbathSchedule(weekday: 1, startHour: 22, endHour: 6)   // Sun 22:00–06:00
        #expect(schedule.contains(date(weekday: 1, hour: 23)))                  // late night
        #expect(schedule.contains(date(weekday: 1, hour: 3)))                   // early morning
        #expect(schedule.contains(date(weekday: 1, hour: 12)) == false)         // midday excluded
    }

    // MARK: - Ambient trigger thresholds

    @Test("usage trigger fires at onset and saturates at full confidence")
    func usageThresholds() {
        #expect(SabbathUsageTrigger(isEnabled: true, dwellSeconds: 24 * 60).proposal(now: now) == .silent)

        let onset = SabbathUsageTrigger(isEnabled: true, dwellSeconds: 25 * 60).proposal(now: now)
        #expect(onset.proposedState == .rest)
        #expect(onset.confidence == 0.5)        // exactly the resolver threshold

        let saturated = SabbathUsageTrigger(isEnabled: true, dwellSeconds: 60 * 60).proposal(now: now)
        #expect(saturated.confidence == 1.0)
    }

    @Test("location and motion triggers respect their enable flag and signal")
    func locationAndMotion() {
        #expect(SabbathLocationTrigger(isEnabled: true, isAtPlaceOfWorship: false).proposal(now: now) == .silent)
        #expect(SabbathLocationTrigger(isEnabled: false, isAtPlaceOfWorship: true).proposal(now: now) == .silent)
        #expect(SabbathLocationTrigger(isEnabled: true, isAtPlaceOfWorship: true).proposal(now: now).proposedState == .presence)

        #expect(SabbathMotionTrigger(isEnabled: true, isWalking: false).proposal(now: now) == .silent)
        #expect(SabbathMotionTrigger(isEnabled: true, isWalking: true).proposal(now: now).proposedState == .rest)
    }

    // MARK: - Config persistence

    @Test("config store round-trips through UserDefaults")
    func configRoundTrip() throws {
        let suite = try #require(UserDefaults(suiteName: "sabbath-rhythm-test-\(UUID().uuidString)"))
        let store = SabbathRhythmConfigStore(defaults: suite)

        #expect(store.load() == .disabled)   // nothing saved yet

        let config = SabbathRhythmConfig(
            schedule: SabbathSchedule(weekday: 7, startHour: 18, endHour: 21),
            usageTriggerEnabled: true,
            locationTriggerEnabled: false,
            motionTriggerEnabled: true
        )
        store.save(config)
        #expect(store.load() == config)
        #expect(config.hasAnyActiveTrigger)
    }

    // MARK: - Safety + invariants

    @Test("safety routes can never be suppressed, even under the deepest policy")
    func emergencyNeverSuppressed() {
        let deepest = SabbathSubtractionPolicy.policy(for: .holyGround)
        for route in SabbathSafetyInvariant.alwaysAllowed {
            #expect(SabbathSafetyInvariant.maySuppressNotification(route: route, policy: deepest) == false)
        }
        // A normal social route is suppressible under a quiet policy.
        #expect(SabbathSafetyInvariant.maySuppressNotification(route: "social", policy: deepest))
    }

    @Test("the three Sabbath invariants hold")
    func invariantsHold() {
        #expect(SabbathRhythmInvariants.i1_exitAlwaysAvailable())
        #expect(SabbathRhythmInvariants.i2_noComparativeMetric())
        #expect(SabbathRhythmInvariants.i3_policyIsSoleHideMechanism())
    }
}
#endif
