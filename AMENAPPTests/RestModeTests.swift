import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

// MARK: - RestMode Tests

@Suite("Lord's Day Rest Mode")
@MainActor
struct RestModeTests {

    // MARK: - Policy activation: Sunday

    @Test("Activates on Sunday within window")
    func activatesOnSundayInWindow() {
        let policy = makePolicy(activeDay: .sunday, startTime: "00:00", endTime: "23:59")
        let sunday = makeSunday(hour: 10, minute: 30)
        let active = RestModeGate.isPolicyActive(policy, now: sunday)
        #expect(active == true)
    }

    @Test("Does not activate on Saturday for Sunday-only policy")
    func doesNotActivateOnSaturday() {
        let policy = makePolicy(activeDay: .sunday)
        let saturday = makeSaturday(hour: 10, minute: 0)
        let active = RestModeGate.isPolicyActive(policy, now: saturday)
        #expect(active == false)
    }

    @Test("Activates on Saturday for Saturday-configured policy")
    func activatesOnSaturdayPolicy() {
        let policy = makePolicy(activeDay: .saturday)
        let saturday = makeSaturday(hour: 10, minute: 0)
        let active = RestModeGate.isPolicyActive(policy, now: saturday)
        #expect(active == true)
    }

    @Test("Does not activate when enabled is false")
    func doesNotActivateWhenDisabled() {
        var policy = makePolicy(activeDay: .sunday)
        policy.enabled = false
        let sunday = makeSunday(hour: 10, minute: 0)
        let active = RestModeGate.isPolicyActive(policy, now: sunday)
        #expect(active == false)
    }

    // MARK: - Time window

    @Test("Activates within custom time window")
    func activatesWithinTimeWindow() {
        let policy = makePolicy(startTime: "08:00", endTime: "20:00")
        let sunday = makeSunday(hour: 14, minute: 0)
        let active = RestModeGate.isPolicyActive(policy, now: sunday)
        #expect(active == true)
    }

    @Test("Does not activate outside time window")
    func doesNotActivateOutsideWindow() {
        let policy = makePolicy(startTime: "08:00", endTime: "20:00")
        let sunday = makeSunday(hour: 21, minute: 0)
        let active = RestModeGate.isPolicyActive(policy, now: sunday)
        #expect(active == false)
    }

    // MARK: - Custom rest day

    @Test("Activates on custom day matching schedule")
    func activatesOnCustomDayMatch() {
        var policy = makePolicy(activeDay: .custom)
        policy.customSchedule = RestCustomSchedule(days: [4], startTime: "00:00", endTime: "23:59")
        let thursday = makeWeekday(4, hour: 9, minute: 0)
        let active = RestModeGate.isPolicyActive(policy, now: thursday)
        #expect(active == true)
    }

    @Test("Does not activate on non-scheduled custom day")
    func doesNotActivateOnNonScheduledDay() {
        var policy = makePolicy(activeDay: .custom)
        policy.customSchedule = RestCustomSchedule(days: [4], startTime: "00:00", endTime: "23:59")
        let sunday = makeSunday(hour: 9, minute: 0)
        let active = RestModeGate.isPolicyActive(policy, now: sunday)
        #expect(active == false)
    }

    // MARK: - Route guard

    @Test("Allowed routes return true when mode is inactive")
    func allowedWhenModeInactive() {
        let gate = RestModeGate.shared
        // When inactive, all routes should be allowed
        #expect(gate.canOpen(.feed) == true)
        #expect(gate.canOpen(.createPost) == true)
    }

    // MARK: - isWithinWindow helper

    @Test("isWithinWindow normal case (no midnight wrap)")
    func withinWindowNormal() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let active = RestModeGate.isWithinWindow(
            now: makeDate(hour: 10, minute: 0, in: cal),
            cal: cal,
            start: "08:00",
            end: "20:00"
        )
        #expect(active == true)
    }

    @Test("isWithinWindow boundary: exactly at start")
    func withinWindowAtStart() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let active = RestModeGate.isWithinWindow(
            now: makeDate(hour: 8, minute: 0, in: cal),
            cal: cal,
            start: "08:00",
            end: "20:00"
        )
        #expect(active == true)
    }

    @Test("isWithinWindow boundary: exactly at end")
    func withinWindowAtEnd() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let active = RestModeGate.isWithinWindow(
            now: makeDate(hour: 20, minute: 0, in: cal),
            cal: cal,
            start: "08:00",
            end: "20:00"
        )
        #expect(active == true)
    }

    // MARK: - parseMins

    @Test("parseMins parses HH:mm correctly")
    func parseMinsCorrect() {
        #expect(RestModeGate.parseMins("08:30") == 510)
        #expect(RestModeGate.parseMins("00:00") == 0)
        #expect(RestModeGate.parseMins("23:59") == 1439)
    }

    // MARK: - Helpers

    private func makePolicy(
        activeDay: RestActiveDay = .sunday,
        startTime: String = "00:00",
        endTime: String = "23:59"
    ) -> RestModePolicy {
        RestModePolicy(
            id: nil,
            userId: "test-uid",
            enabled: true,
            modeName: .lordsDay,
            modeLevel: .worship,
            timezone: "UTC",
            activeDay: activeDay,
            customSchedule: nil,
            startTime: startTime,
            endTime: endTime,
            allowedRoutes: RestModeRoutes.allowed,
            restrictedRoutes: RestModeRoutes.restricted,
            reflectionFeedEnabled: true,
            postingPolicy: .limitedTypes,
            commentPolicy: .toneGated,
            notificationPolicy: RestNotificationPolicy(
                allowedTypes: RestModeNotifications.allowed,
                mutedTypes: RestModeNotifications.muted
            ),
            allowTemporaryOverride: true,
            overrideDurationMinutes: 15
        )
    }

    private func makeSunday(hour: Int, minute: Int) -> Date {
        makeWeekday(1, hour: hour, minute: minute)
    }

    private func makeSaturday(hour: Int, minute: Int) -> Date {
        makeWeekday(7, hour: hour, minute: minute)
    }

    // weekday: 1=Sunday … 7=Saturday (Calendar weekday)
    private func makeWeekday(_ weekday: Int, hour: Int, minute: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.weekday = weekday
        comps.hour = hour
        comps.minute = minute
        comps.year = 2026
        comps.weekOfYear = 18
        return cal.date(from: comps) ?? Date()
    }

    private func makeDate(hour: Int, minute: Int, in cal: Calendar) -> Date {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        comps.year = 2026
        comps.month = 5
        comps.day = 1
        return cal.date(from: comps) ?? Date()
    }
}

// MARK: - Notification filter tests

@Suite("Rest Mode Notifications")
struct RestModeNotificationTests {

    @Test("Mutes social notification types during rest mode")
    func mutesSocialNotifications() {
        for muted in RestModeNotifications.muted {
            #expect(muted != "church_reminder", "church_reminder should not be muted")
            #expect(muted != "prayer_support", "prayer_support should not be muted")
        }
    }

    @Test("Allows church and prayer notification types")
    func allowsWorshipNotifications() {
        let allowed = RestModeNotifications.allowed
        #expect(allowed.contains("church_reminder"))
        #expect(allowed.contains("prayer_support"))
        #expect(allowed.contains("daily_verse"))
        #expect(allowed.contains("sermon_notes_reminder"))
    }
}

// MARK: - Route guard tests

@Suite("Rest Mode Route Constants")
struct RestModeRouteTests {

    @Test("main_feed is in restricted routes")
    func feedIsRestricted() {
        #expect(RestModeRoutes.restricted.contains("main_feed"))
    }

    @Test("find_church is in allowed routes")
    func findChurchIsAllowed() {
        #expect(RestModeRoutes.allowed.contains("find_church"))
    }

    @Test("emergency_support is in allowed routes")
    func emergencySupportIsAllowed() {
        #expect(RestModeRoutes.allowed.contains("emergency_support"))
    }

    @Test("prayer_request is in allowed routes")
    func prayerRequestIsAllowed() {
        #expect(RestModeRoutes.allowed.contains("prayer_request"))
    }

    @Test("create_post is in restricted routes")
    func createPostIsRestricted() {
        #expect(RestModeRoutes.restricted.contains("create_post"))
    }
}

#endif

// MARK: - isPolicyActive testable override
// Adds a testable version that accepts an injected 'now' date.

extension RestModeGate {
    static func isPolicyActive(_ policy: RestModePolicy, now: Date) -> Bool {
        guard policy.enabled else { return false }
        let tz = TimeZone(identifier: policy.timezone) ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let weekday = cal.component(.weekday, from: now)

        switch policy.activeDay {
        case .sunday:
            guard weekday == 1 else { return false }
        case .saturday:
            guard weekday == 7 else { return false }
        case .custom:
            guard let sched = policy.customSchedule,
                  sched.days.contains(weekday) else { return false }
            return isWithinWindow(now: now, cal: cal, start: sched.startTime, end: sched.endTime)
        }
        return isWithinWindow(now: now, cal: cal, start: policy.startTime, end: policy.endTime)
    }
}
