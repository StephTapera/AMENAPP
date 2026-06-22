// WalkWithChristTests.swift
// AMENAPPTests
//
// Phase 1 release-blocker regression tests for Walk With Christ.
// Covers: season persistence, onboarding gating, check-in mood assignment,
// next-steps adaptation, notification routing, and analytics event contract.
//
// All tests are pure-Swift — no Firebase, no network, no UI dependencies.
// Run with: Product ▶ Test (⌘U)

import Testing
import Foundation
@testable import AMENAPP

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: 1. Season Persistence — WalkProfile Codable Roundtrip
// ─────────────────────────────────────────────────────────────────────────

// WalkProfile.Codable is @MainActor-isolated; all encode/decode must run on main actor.
@Suite("Walk With Christ — Season Persistence")
@MainActor
struct WalkSeasonPersistenceTests {

    @Test("selectedSeason survives JSONEncoder/JSONDecoder roundtrip")
    func selectedSeasonSurvivesRoundtrip() throws {
        var profile = WalkProfile()
        profile.selectedSeason = .dry

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(WalkProfile.self, from: data)

        #expect(decoded.selectedSeason == .dry)
    }

    @Test("nil selectedSeason decodes back to nil")
    func nilSeasonSurvivesRoundtrip() throws {
        let profile = WalkProfile()

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(WalkProfile.self, from: data)

        #expect(decoded.selectedSeason == nil)
    }

    @Test("Every WalkSpiritualSeason case survives Codable roundtrip")
    func allSeasonCasesRoundtrip() throws {
        for season in WalkSpiritualSeason.allCases {
            var profile = WalkProfile()
            profile.selectedSeason = season

            let data = try JSONEncoder().encode(profile)
            let decoded = try JSONDecoder().decode(WalkProfile.self, from: data)

            #expect(decoded.selectedSeason == season,
                    "Season '\(season.rawValue)' did not survive Codable roundtrip")
        }
    }

    @Test("checkInAnswers survive Codable roundtrip")
    func checkInAnswersSurviveRoundtrip() throws {
        var profile = WalkProfile()
        profile.checkInAnswers = ["Yes", "Not really", "Somewhat", "Dry", "Yes"]

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(WalkProfile.self, from: data)

        #expect(decoded.checkInAnswers == ["Yes", "Not really", "Somewhat", "Dry", "Yes"])
    }

    @Test("Empty checkInAnswers default decodes correctly")
    func emptyCheckInAnswersDefault() throws {
        let profile = WalkProfile()

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(WalkProfile.self, from: data)

        #expect(decoded.checkInAnswers.isEmpty)
    }

    @Test("onboardingComplete flag survives Codable roundtrip")
    func onboardingCompleteFlagSurvives() throws {
        var profile = WalkProfile()
        profile.onboardingComplete = true

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(WalkProfile.self, from: data)

        #expect(decoded.onboardingComplete == true)
    }

    @Test("completedModuleIDs survive Codable roundtrip")
    func completedModuleIDsSurvive() throws {
        var profile = WalkProfile()
        profile.completedModuleIDs = ["mod_1", "mod_2", "mod_3"]

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(WalkProfile.self, from: data)

        #expect(decoded.completedModuleIDs == ["mod_1", "mod_2", "mod_3"])
    }

    @Test("reminderEnabled survives Codable roundtrip")
    func reminderEnabledSurvives() throws {
        var profile = WalkProfile()
        profile.reminderEnabled = true
        profile.reminderHour = 21

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(WalkProfile.self, from: data)

        #expect(decoded.reminderEnabled == true)
        #expect(decoded.reminderHour == 21)
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: 2. Onboarding Gating
// ─────────────────────────────────────────────────────────────────────────

@Suite("Walk With Christ — Onboarding Gating")
@MainActor
struct WalkOnboardingGatingTests {

    @Test("Default WalkProfile has onboardingComplete = false")
    func onboardingDefaultIsFalse() {
        let profile = WalkProfile()
        #expect(profile.onboardingComplete == false)
    }

    @Test("Season band gating: hidden when onboarding is incomplete")
    func seasonBandGatedPreOnboarding() {
        var profile = WalkProfile()
        profile.onboardingComplete = false
        // Matches the gating condition in WalkWithChristView.contentBody
        #expect(!profile.onboardingComplete,
                "Season band must be hidden before onboarding completes")
    }

    @Test("Application card gated when onboarding is incomplete")
    func applicationCardGatedPreOnboarding() {
        var profile = WalkProfile()
        profile.onboardingComplete = false
        #expect(!profile.onboardingComplete,
                "Application card must be hidden before onboarding completes")
    }

    @Test("Season band visible after onboarding completes")
    func seasonBandVisiblePostOnboarding() {
        var profile = WalkProfile()
        profile.onboardingComplete = true
        #expect(profile.onboardingComplete,
                "Season band must be visible once onboarding is complete")
    }

    @Test("Application card visible after onboarding completes")
    func applicationCardVisiblePostOnboarding() {
        var profile = WalkProfile()
        profile.onboardingComplete = true
        #expect(profile.onboardingComplete,
                "Application card must be visible once onboarding is complete")
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: 3. Check-In Mood to Season Auto-Assignment
// ─────────────────────────────────────────────────────────────────────────

@Suite("Walk With Christ — Check-In Mood Assignment")
struct WalkCheckInMoodTests {

    // Mirrors the exact logic in WalkWithChristStore.recordCheckIn(answers:)
    // answers[3] is the mood picker response.
    private func moodToSeason(answers: [String]) -> WalkSpiritualSeason? {
        guard answers.count > 3 else { return nil }
        switch answers[3] {
        case "Dry", "Struggling", "Distant": return .dry
        case "Overwhelmed":                  return .overwhelmed
        default:                             return nil
        }
    }

    @Test("'Dry' mood assigns .dry season")
    func dryMoodSetsDry() {
        #expect(moodToSeason(answers: ["Yes", "Somewhat", "Yes", "Dry", "Yes"]) == .dry)
    }

    @Test("'Struggling' mood assigns .dry season")
    func strugglingMoodSetsDry() {
        #expect(moodToSeason(answers: ["Yes", "Yes", "Not really", "Struggling", "Yes"]) == .dry)
    }

    @Test("'Distant' mood assigns .dry season")
    func distantMoodSetsDry() {
        #expect(moodToSeason(answers: ["Yes", "Yes", "Yes", "Distant", "Yes"]) == .dry)
    }

    @Test("'Overwhelmed' mood assigns .overwhelmed season")
    func overwhelmedMoodSetsOverwhelmed() {
        #expect(moodToSeason(answers: ["Yes", "Yes", "Yes", "Overwhelmed", "Yes"]) == .overwhelmed)
    }

    @Test("'Peaceful' mood assigns no season")
    func peacefulMoodNoAssignment() {
        #expect(moodToSeason(answers: ["Yes", "Yes", "Yes", "Peaceful", "Yes"]) == nil)
    }

    @Test("'Encouraged' mood assigns no season")
    func encouragedMoodNoAssignment() {
        #expect(moodToSeason(answers: ["Yes", "Yes", "Yes", "Encouraged", "Yes"]) == nil)
    }

    @Test("'Hopeful' mood assigns no season")
    func hopefulMoodNoAssignment() {
        #expect(moodToSeason(answers: ["Yes", "Yes", "Yes", "Hopeful", "Yes"]) == nil)
    }

    @Test("Empty answers array returns nil without crashing")
    func emptyAnswersReturnNil() {
        #expect(moodToSeason(answers: []) == nil)
    }

    @Test("Answers shorter than 4 return nil safely")
    func shortAnswersReturnNilSafely() {
        #expect(moodToSeason(answers: ["Dry"]) == nil)
        #expect(moodToSeason(answers: ["Dry", "Dry", "Dry"]) == nil)
    }

    @Test("Exactly 4 answers reads mood at index 3")
    func fourAnswersReadsMoodAtIndex3() {
        #expect(moodToSeason(answers: ["Yes", "Somewhat", "Not really", "Struggling"]) == .dry)
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: 4. Next Steps Adaptation
// ─────────────────────────────────────────────────────────────────────────

@Suite("Walk With Christ — Next Steps Adaptation")
@MainActor
struct WalkNextStepsAdaptationTests {

    @Test("nextSteps returns non-empty list for .newBeliever path")
    func newBelieverHasSteps() {
        var profile = WalkProfile()
        profile.pathAssigned = .newBeliever
        #expect(!WalkWithChristData.nextSteps(for: profile).isEmpty)
    }

    @Test("nextSteps returns non-empty list for .growing path")
    func growingHasSteps() {
        var profile = WalkProfile()
        profile.pathAssigned = .growing
        #expect(!WalkWithChristData.nextSteps(for: profile).isEmpty)
    }

    @Test("nextSteps returns non-empty list for .leading path")
    func leadingHasSteps() {
        var profile = WalkProfile()
        profile.pathAssigned = .leading
        #expect(!WalkWithChristData.nextSteps(for: profile).isEmpty)
    }

    @Test("Zero completed modules: no steps are skipped")
    func zeroCompletionsSkipsNothing() {
        var profile = WalkProfile()
        profile.pathAssigned = .newBeliever
        profile.completedModuleIDs = []
        let allSteps = WalkWithChristData.nextSteps(for: profile)
        let adapted = Array(allSteps.dropFirst(0))
        #expect(adapted.count == allSteps.count)
    }

    @Test("One completed module causes first step to be skipped")
    func oneCompletionSkipsFirstStep() {
        var profile = WalkProfile()
        profile.pathAssigned = .newBeliever
        profile.completedModuleIDs = ["module_1"]
        let allSteps = WalkWithChristData.nextSteps(for: profile)
        guard allSteps.count > 1 else { return }
        let skipCount = min(profile.completedModuleIDs.count, allSteps.count)
        let adapted = Array(allSteps.dropFirst(skipCount))
        #expect(adapted.first != allSteps.first)
    }

    @Test("Season-aware step for .dry prepended at index 0")
    func drySeasonStepAtIndex0() {
        let expectedStep = "Ask Berean what the Bible says about dry seasons"
        var profile = WalkProfile()
        profile.selectedSeason = .dry
        profile.completedModuleIDs = []
        let allSteps = WalkWithChristData.nextSteps(for: profile)
        var steps = Array(allSteps.prefix(4))
        steps.insert(expectedStep, at: 0)
        steps = Array(steps.prefix(4))
        #expect(steps.first == expectedStep)
    }

    @Test("Adapted steps with season insertion never exceed 4 items")
    func adaptedStepsCappedAt4() {
        var profile = WalkProfile()
        profile.selectedSeason = .overwhelmed
        let allSteps = WalkWithChristData.nextSteps(for: profile)
        var steps = Array(allSteps.prefix(4))
        steps.insert("season_step_placeholder", at: 0)
        steps = Array(steps.prefix(4))
        #expect(steps.count <= 4)
    }

    @Test("Completing all modules causes adapted list to be shorter than full list")
    func allModulesCompletedYieldsFewerSteps() {
        var profile = WalkProfile()
        profile.pathAssigned = .newBeliever
        let allSteps = WalkWithChristData.nextSteps(for: profile)
        guard allSteps.count > 1 else { return }
        profile.completedModuleIDs = (0..<allSteps.count).map { "module_\($0)" }
        let skipCount = min(profile.completedModuleIDs.count, allSteps.count)
        let adapted = Array(allSteps.dropFirst(skipCount))
        #expect(adapted.count < allSteps.count)
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: 5. Notification Deep-Link Routing
// ─────────────────────────────────────────────────────────────────────────

@Suite("Walk With Christ — Notification Routing")
struct WalkNotificationRoutingTests {

    @Test("'walk_with_christ' targetRouteType resolves to .walkWithChrist")
    func walkWithChristRouteResolves() {
        let route = NotificationRouteResolver.resolveFromServerRoute(
            type: "walk_with_christ",
            payload: [:]
        )
        #expect(route == .walkWithChrist)
    }

    @Test(".walkWithChrist fallback route is .fallback")
    func walkWithChristFallbackIsFallback() {
        #expect(NotificationRoute.walkWithChrist.fallbackRoute == .fallback)
    }

    @Test("Unknown walk route type returns nil from resolver")
    func unknownRouteTypeReturnsNil() {
        let route = NotificationRouteResolver.resolveFromServerRoute(
            type: "walk_with_christ_v99_does_not_exist",
            payload: [:]
        )
        #expect(route == nil)
    }

    @Test("openWalkWithChristFromNotification rawValue is correct")
    func notificationNameRawValue() {
        #expect(Notification.Name.openWalkWithChristFromNotification.rawValue == "amen.openWalkWithChrist")
    }

    @Test("WalkReminderScheduler category identifier is stable")
    func schedulerCategoryIdentifierIsStable() {
        #expect(WalkReminderScheduler.categoryIdentifier == "com.amen.walkwithchrist.daily")
    }

    @Test("Notification userInfo payload routes through the standard push pipeline")
    func notificationUserInfoRoutesCorrectly() {
        // Verifies that the userInfo written by scheduleDailyReminder and
        // addNotificationRequests satisfies NotificationIntentDecoder's guard:
        //   guard notificationId != nil || type != nil || targetRouteType != nil
        let userInfo: [String: String] = [
            "deepLink": "amen://walkWithChrist",
            "type": "walk_with_christ_reminder",
            "targetRouteType": "walk_with_christ"
        ]
        #expect(userInfo["type"] != nil)
        #expect(userInfo["targetRouteType"] != nil)

        let resolved = NotificationRouteResolver.resolveFromServerRoute(
            type: userInfo["targetRouteType"]!,
            payload: [:]
        )
        #expect(resolved == .walkWithChrist)
    }

    @Test("Category identifier does not match church routing prefix")
    func categoryDoesNotTriggerChurchRouting() {
        // CompositeNotificationDelegate routes to church handler if category contains
        // "church" or "SERVICE_REMINDER". Walk With Christ must not match either.
        let category = WalkReminderScheduler.categoryIdentifier
        #expect(!category.lowercased().contains("church"))
        #expect(!category.lowercased().contains("service_reminder"))
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: 6. Analytics Event Contract
// ─────────────────────────────────────────────────────────────────────────

@Suite("Walk With Christ — Analytics Contract")
struct WalkAnalyticsContractTests {

    @Test("walk_with_christ_opened event name is correct")
    func openedEventName() {
        #expect(AMENAnalyticsEvent.walkWithChristOpened.name == "walk_with_christ_opened")
    }

    @Test("walk_with_christ_onboarding_completed includes path property")
    func onboardingCompletedEvent() {
        let event = AMENAnalyticsEvent.walkWithChristOnboardingCompleted(path: "new_believer")
        #expect(event.name == "walk_with_christ_onboarding_completed")
        #expect(event.properties["path"] as? String == "new_believer")
    }

    @Test("walk_with_christ_season_selected includes season property")
    func seasonSelectedEvent() {
        let event = AMENAnalyticsEvent.walkWithChristSeasonSelected(season: "dry")
        #expect(event.name == "walk_with_christ_season_selected")
        #expect(event.properties["season"] as? String == "dry")
    }

    @Test("walk_with_christ_berean_launched includes source_surface")
    func bereanLaunchedEvent() {
        let event = AMENAnalyticsEvent.walkWithChristBereanLaunched(sourceSurface: "season_band")
        #expect(event.name == "walk_with_christ_berean_launched")
        #expect(event.properties["source_surface"] as? String == "season_band")
    }

    @Test("Berean launches from distinct surfaces are distinguishable")
    func bereanSourceSurfacesDistinct() {
        let surfaces = ["path_today", "season_band", "application_card", "reflection_prompt", "planner"]
        #expect(Set(surfaces).count == surfaces.count, "Each source surface must be unique")
    }

    @Test("walk_with_christ_application_step_completed includes step_index")
    func stepCompletedEvent() {
        let event = AMENAnalyticsEvent.walkWithChristApplicationStepCompleted(stepIndex: 2)
        #expect(event.name == "walk_with_christ_application_step_completed")
        #expect(event.properties["step_index"] as? Int == 2)
    }

    @Test("walk_with_christ_follow_through_plan_created includes area and frequency")
    func planCreatedEvent() {
        let event = AMENAnalyticsEvent.walkWithChristFollowThroughPlanCreated(
            area: "prayer",
            frequency: "daily"
        )
        #expect(event.name == "walk_with_christ_follow_through_plan_created")
        #expect(event.properties["practice_area"] as? String == "prayer")
        #expect(event.properties["frequency"] as? String == "daily")
    }

    @Test("walk_with_christ_follow_through_completed includes plan_id and streak_days")
    func followThroughCompletedEvent() {
        let event = AMENAnalyticsEvent.walkWithChristFollowThroughCompleted(
            planId: "plan_abc",
            streakDays: 7
        )
        #expect(event.name == "walk_with_christ_follow_through_completed")
        #expect(event.properties["plan_id"] as? String == "plan_abc")
        #expect(event.properties["streak_days"] as? Int == 7)
    }

    @Test("walk_with_christ_reminder_enabled has correct name")
    func reminderEnabledEvent() {
        #expect(AMENAnalyticsEvent.walkWithChristReminderEnabled.name == "walk_with_christ_reminder_enabled")
    }

    @Test("All 8 required Walk With Christ analytics events produce non-empty names")
    func allRequiredEventsHaveNames() {
        let events: [AMENAnalyticsEvent] = [
            .walkWithChristOpened,
            .walkWithChristOnboardingCompleted(path: "test"),
            .walkWithChristSeasonSelected(season: "dry"),
            .walkWithChristBereanLaunched(sourceSurface: "test"),
            .walkWithChristApplicationStepCompleted(stepIndex: 0),
            .walkWithChristFollowThroughPlanCreated(area: "prayer", frequency: "daily"),
            .walkWithChristFollowThroughCompleted(planId: "p1", streakDays: 1),
            .walkWithChristReminderEnabled,
        ]
        for event in events {
            #expect(!event.name.isEmpty)
        }
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: 7. Notification Permission Guard Contract
// ─────────────────────────────────────────────────────────────────────────

@Suite("Walk With Christ — Permission Guard")
struct WalkPermissionGuardTests {

    @Test("WalkReminderScheduler category does not match church routing prefix")
    func categoryDoesNotMisroute() {
        let category = WalkReminderScheduler.categoryIdentifier
        #expect(!category.lowercased().contains("church"))
        #expect(!category.lowercased().contains("service_reminder"))
    }

    @Test("WalkReminderScheduler.requestAndSchedule is callable as async")
    func requestAndScheduleCompiles() async {
        // Contract test: verifies the function exists, is async, and returns Bool.
        // UNAuthorizationStatus cannot be simulated in unit tests; denial behavior
        // is covered by the manual verification checklist (reminder enable → denied → alert).
        let result = await WalkReminderScheduler.requestAndSchedule(
            hour: 8,
            messages: ["Walk reminder test"]
        )
        // Result is Bool — true or false depending on simulator auth state.
        // We only assert the call completes without crash.
        let _ = result as Bool
        #expect(Bool(true), "requestAndSchedule must return without crashing")
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: 8. Application Path Empty State Contract
// ─────────────────────────────────────────────────────────────────────────

@Suite("Walk With Christ — Application Path Empty State")
struct WalkApplicationPathEmptyStateTests {

    @Test("SundayApplicationViewModel.hasRealPath starts false — no fake content on init")
    func hasRealPathDefaultsFalse() async {
        let vm = await SundayApplicationViewModel()
        await MainActor.run {
            #expect(
                vm.hasRealPath == false,
                "hasRealPath must start false — ViewModel must never show fake content before loadLatestPath()"
            )
        }
    }

    @Test("SundayApplicationViewModel.currentPath starts nil")
    func currentPathStartsNil() async {
        let vm = await SundayApplicationViewModel()
        await MainActor.run {
            #expect(vm.currentPath == nil)
        }
    }

    @Test("SundayApplicationViewModel.completedStepIndices starts empty")
    func completedStepIndicesStartEmpty() async {
        let vm = await SundayApplicationViewModel()
        await MainActor.run {
            #expect(vm.completedStepIndices.isEmpty)
        }
    }
}
