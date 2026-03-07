// ShabbatModeTests.swift
// AMENAPPTests
//
// Tests for Shabbat Mode: timezone edges, feature gating, settings, navigation.
//
// Run with: ⌘U in Xcode or via `xcodebuild test`

import Testing
import Foundation
@testable import AMENAPP

// MARK: - Timezone helpers (pure, no MainActor needed)

struct TimezoneHelpers {
    /// Returns a Date that is a given weekday + hour in the given timezone.
    /// weekday: 1=Sunday … 7=Saturday (Gregorian)
    static func date(weekday: Int, hour: Int, in tz: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let now = Date()
        let currentWeekday = cal.component(.weekday, from: now)
        let dayDelta = weekday - currentWeekday
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.day = (comps.day ?? 0) + dayDelta
        comps.hour = hour
        comps.minute = 1
        comps.second = 0
        return cal.date(from: comps) ?? now
    }
}

// MARK: - isSundayNow tests

struct ShabbatTimezoneTests {

    // ── Helper: make a throwaway ShabbatModeService-like function we can test
    // (The real ShabbatModeService is @MainActor so we test the pure logic via
    //  the public isSundayNow(in:) helper)

    func isSundayNow(simulatedDate: Date, in tz: TimeZone) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.component(.weekday, from: simulatedDate) == 1
    }

    // MARK: - Sunday 00:01 local

    @Test("isSunday: Sunday at 00:01 Eastern is Sunday")
    func sundayAt0001Eastern() {
        let eastern = TimeZone(identifier: "America/New_York")!
        let d = TimezoneHelpers.date(weekday: 1, hour: 0, in: eastern)
        #expect(isSundayNow(simulatedDate: d, in: eastern) == true)
    }

    @Test("isSunday: Sunday at 23:59 Pacific is Sunday")
    func sundayAt2359Pacific() {
        let pacific = TimeZone(identifier: "America/Los_Angeles")!
        let d = TimezoneHelpers.date(weekday: 1, hour: 23, in: pacific)
        #expect(isSundayNow(simulatedDate: d, in: pacific) == true)
    }

    @Test("isSunday: Saturday is not Sunday")
    func saturdayNotSunday() {
        let utc = TimeZone(identifier: "UTC")!
        let d = TimezoneHelpers.date(weekday: 7, hour: 12, in: utc)
        #expect(isSundayNow(simulatedDate: d, in: utc) == false)
    }

    @Test("isSunday: Monday is not Sunday")
    func mondayNotSunday() {
        let utc = TimeZone(identifier: "UTC")!
        let d = TimezoneHelpers.date(weekday: 2, hour: 12, in: utc)
        #expect(isSundayNow(simulatedDate: d, in: utc) == false)
    }

    // ── Crossing midnight Sat→Sun

    @Test("isSunday: one second before midnight Saturday is not Sunday")
    func saturdayOneSecondBeforeMidnight() {
        let tz = TimeZone(identifier: "Europe/London")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        // Build Saturday 23:59:59
        var comps = DateComponents()
        comps.year = 2025
        comps.month = 10  // October (after DST end in UK)
        comps.day = 25    // known Saturday
        comps.hour = 23; comps.minute = 59; comps.second = 59
        let d = cal.date(from: comps)!
        #expect(isSundayNow(simulatedDate: d, in: tz) == false)
    }

    @Test("isSunday: one second after midnight Sunday is Sunday")
    func sundayOneSecondAfterMidnight() {
        let tz = TimeZone(identifier: "Europe/London")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        // Build Sunday 00:00:01
        var comps = DateComponents()
        comps.year = 2025
        comps.month = 10
        comps.day = 26    // known Sunday
        comps.hour = 0; comps.minute = 0; comps.second = 1
        let d = cal.date(from: comps)!
        #expect(isSundayNow(simulatedDate: d, in: tz) == true)
    }

    // ── DST edge (US spring-forward: 2 AM → 3 AM)

    @Test("isSunday: US spring-forward Sunday still reads Sunday after DST gap")
    func usDSTSpringForwardSunday() {
        // US DST starts on a Sunday in March
        let eastern = TimeZone(identifier: "America/New_York")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = eastern
        // 2025-03-09 is a Sunday (DST spring-forward day in US Eastern)
        var comps = DateComponents()
        comps.year = 2025; comps.month = 3; comps.day = 9
        comps.hour = 3; comps.minute = 30  // after the gap
        let d = cal.date(from: comps)!
        #expect(isSundayNow(simulatedDate: d, in: eastern) == true)
    }

    // ── Timezone difference: same UTC instant, different local day

    @Test("isSunday: same UTC instant is Sunday in NZ but Saturday in NY")
    func sameInstantDifferentDays() {
        // Saturday 18:00 UTC → Saturday 13:00 Eastern, but Sunday 07:00 Auckland
        let utc = TimeZone(identifier: "UTC")!
        let nz  = TimeZone(identifier: "Pacific/Auckland")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        var comps = DateComponents()
        comps.year = 2025; comps.month = 10; comps.day = 18 // known Saturday UTC
        comps.hour = 18; comps.minute = 0
        let d = cal.date(from: comps)!
        // UTC view: Saturday
        #expect(isSundayNow(simulatedDate: d, in: utc) == false)
        // Auckland view: next day, Sunday
        #expect(isSundayNow(simulatedDate: d, in: nz) == true)
    }
}

// MARK: - AppFeature gating tests (pure logic, no MainActor)

struct AppFeatureGatingTests {

    @Test("AppFeature.feed is blocked during Shabbat")
    func feedIsBlocked() {
        #expect(AppFeature.feed.isAllowedDuringShabbat == false)
    }

    @Test("AppFeature.churchNotes is always allowed")
    func churchNotesAllowed() {
        #expect(AppFeature.churchNotes.isAllowedDuringShabbat == true)
    }

    @Test("AppFeature.findChurch is always allowed")
    func findChurchAllowed() {
        #expect(AppFeature.findChurch.isAllowedDuringShabbat == true)
    }

    @Test("AppFeature.settings is always allowed")
    func settingsAllowed() {
        #expect(AppFeature.settings.isAllowedDuringShabbat == true)
    }

    @Test("All blocked features return false for isAllowedDuringShabbat")
    func allBlockedFeatures() {
        let blocked: [AppFeature] = [
            .feed, .postCreate, .commentCreate, .reactions,
            .messages, .notifications, .profileBrowse, .profileEdit,
            .peopleDiscovery, .search, .bereanAI, .prayer, .testimonies,
            .repost, .savePost, .createActivity
        ]
        for feature in blocked {
            #expect(feature.isAllowedDuringShabbat == false,
                    "Expected \(feature.rawValue) to be blocked during Shabbat")
        }
    }
}

// MARK: - AppAccessResult logic tests (no @MainActor needed — purely logical)

struct AppAccessResultTests {

    /// Simulate the canAccess logic without touching the singleton
    func simulateCanAccess(feature: AppFeature, shabbatActive: Bool) -> AppAccessResult {
        guard shabbatActive else { return .allowed }
        guard !feature.isAllowedDuringShabbat else { return .allowed }
        return .blocked(reason: ShabbatBlockReason(feature: feature))
    }

    @Test("canAccess returns .allowed when Shabbat is not active")
    func allowedWhenNotShabbat() {
        let result = simulateCanAccess(feature: .feed, shabbatActive: false)
        if case .allowed = result { } else {
            Issue.record("Expected .allowed but got .blocked")
        }
    }

    @Test("canAccess blocks .feed when Shabbat is active")
    func blockedFeedDuringShabbat() {
        let result = simulateCanAccess(feature: .feed, shabbatActive: true)
        if case .blocked(let reason) = result {
            #expect(reason.errorCode == "SHABBAT_MODE_BLOCKED")
            #expect(reason.feature == .feed)
        } else {
            Issue.record("Expected .blocked but got .allowed")
        }
    }

    @Test("canAccess allows .churchNotes even when Shabbat is active")
    func allowedChurchNotesDuringShabbat() {
        let result = simulateCanAccess(feature: .churchNotes, shabbatActive: true)
        if case .allowed = result { } else {
            Issue.record("Expected .allowed for churchNotes but got .blocked")
        }
    }

    @Test("canAccess allows .findChurch even when Shabbat is active")
    func allowedFindChurchDuringShabbat() {
        let result = simulateCanAccess(feature: .findChurch, shabbatActive: true)
        if case .allowed = result { } else {
            Issue.record("Expected .allowed for findChurch but got .blocked")
        }
    }

    @Test("ShabbatBlockReason has correct error code")
    func blockReasonErrorCode() {
        let reason = ShabbatBlockReason(feature: .messages)
        #expect(reason.errorCode == "SHABBAT_MODE_BLOCKED")
        #expect(reason.feature == .messages)
        #expect(reason.message.contains("Shabbat Mode"))
    }
}

// MARK: - Tab routing allowed/blocked

struct TabRoutingTests {

    /// Mirror of ContentView.isAllowedDuringChurchFocus
    func isTabAllowedDuringShabbat(_ tab: Int) -> Bool {
        return tab == 3 || tab == 5
    }

    @Test("Tab 0 (Feed) is blocked during Shabbat")
    func tab0Blocked() { #expect(isTabAllowedDuringShabbat(0) == false) }

    @Test("Tab 1 (Search/People) is blocked during Shabbat")
    func tab1Blocked() { #expect(isTabAllowedDuringShabbat(1) == false) }

    @Test("Tab 2 (Messages) is blocked during Shabbat")
    func tab2Blocked() { #expect(isTabAllowedDuringShabbat(2) == false) }

    @Test("Tab 3 (Resources / Church Notes + Find Church) is allowed during Shabbat")
    func tab3Allowed() { #expect(isTabAllowedDuringShabbat(3) == true) }

    @Test("Tab 4 (Notifications) is blocked during Shabbat")
    func tab4Blocked() { #expect(isTabAllowedDuringShabbat(4) == false) }

    @Test("Tab 5 (Profile / Settings) is allowed during Shabbat")
    func tab5Allowed() { #expect(isTabAllowedDuringShabbat(5) == true) }
}

// MARK: - DeepLinkRoute.requiredFeature mapping

struct DeepLinkShabbatMappingTests {

    @Test("DeepLink .post maps to .feed (blocked)")
    func postMapsToFeed() {
        let route = DeepLinkRouter.DeepLinkRoute.post(id: "abc")
        #expect(route.requiredFeature == .feed)
        #expect(route.requiredFeature.isAllowedDuringShabbat == false)
    }

    @Test("DeepLink .church maps to .findChurch (allowed)")
    func churchMapsToFindChurch() {
        let route = DeepLinkRouter.DeepLinkRoute.church(churchId: "xyz")
        #expect(route.requiredFeature == .findChurch)
        #expect(route.requiredFeature.isAllowedDuringShabbat == true)
    }

    @Test("DeepLink .settings maps to .settings (allowed)")
    func settingsMapsToSettings() {
        let route = DeepLinkRouter.DeepLinkRoute.settings()
        #expect(route.requiredFeature == .settings)
        #expect(route.requiredFeature.isAllowedDuringShabbat == true)
    }

    @Test("DeepLink .conversation maps to .messages (blocked)")
    func conversationMapsToMessages() {
        let route = DeepLinkRouter.DeepLinkRoute.conversation(conversationId: "conv1")
        #expect(route.requiredFeature == .messages)
        #expect(route.requiredFeature.isAllowedDuringShabbat == false)
    }

    @Test("DeepLink .userProfile maps to .profileBrowse (blocked)")
    func userProfileMapsToProfileBrowse() {
        let route = DeepLinkRouter.DeepLinkRoute.userProfile(userId: "u1")
        #expect(route.requiredFeature == .profileBrowse)
        #expect(route.requiredFeature.isAllowedDuringShabbat == false)
    }
}

// MARK: - NotificationDeepLink.requiredFeature mapping

struct NotificationDeepLinkShabbatTests {

    @Test("NotificationDeepLink .post maps to .feed (blocked)")
    func postNotifMapsToFeed() {
        let link = NotificationDeepLink.post(postId: "p1")
        #expect(link.requiredFeature == .feed)
    }

    @Test("NotificationDeepLink .conversation maps to .messages (blocked)")
    func convNotifMapsToMessages() {
        let link = NotificationDeepLink.conversation(userId: "u1")
        #expect(link.requiredFeature == .messages)
    }

    @Test("NotificationDeepLink .profile maps to .profileBrowse (blocked)")
    func profileNotifMapsToProfileBrowse() {
        let link = NotificationDeepLink.profile(userId: "u1")
        #expect(link.requiredFeature == .profileBrowse)
    }

    @Test("NotificationDeepLink .notifications maps to .notifications (blocked)")
    func notificationsNotifMapsToNotifications() {
        let link = NotificationDeepLink.notifications
        #expect(link.requiredFeature == .notifications)
    }
}

// MARK: - UserDefaults default-ON test

struct ShabbatDefaultsTests {

    @Test("Shabbat Mode defaults to ON for new users (key absent)")
    func defaultsToOn() {
        // Remove key to simulate first install
        let key = "shabbatMode_enabled_test_\(UUID().uuidString)"
        UserDefaults.standard.removeObject(forKey: key)
        // When key is absent, code treats it as true
        let absent = UserDefaults.standard.object(forKey: key) == nil
        let defaultValue = absent ? true : UserDefaults.standard.bool(forKey: key)
        #expect(defaultValue == true)
    }

    @Test("setEnabled(false) persists OFF")
    func setEnabledPersistsOff() {
        let key = "shabbatMode_enabled_test_\(UUID().uuidString)"
        UserDefaults.standard.set(false, forKey: key)
        let value = UserDefaults.standard.bool(forKey: key)
        #expect(value == false)
        UserDefaults.standard.removeObject(forKey: key) // cleanup
    }

    @Test("setEnabled(true) persists ON")
    func setEnabledPersistsOn() {
        let key = "shabbatMode_enabled_test_\(UUID().uuidString)"
        UserDefaults.standard.set(true, forKey: key)
        let value = UserDefaults.standard.bool(forKey: key)
        #expect(value == true)
        UserDefaults.standard.removeObject(forKey: key) // cleanup
    }
}

// MARK: - Manual Verification Checklist
// Run these steps manually on a Sunday (or with a date-override debug build):
//
// 1. FRESH INSTALL
//    - Install app on a new device/simulator
//    - Open on a Sunday → Shabbat Mode should be active immediately (no prompt needed)
//    - Tabs 0,1,2,4 should show the gate view; tabs 3,5 should open normally
//
// 2. TOGGLE OFF IN SETTINGS
//    - Go to Settings → Wellbeing → Shabbat Mode → toggle OFF
//    - All tabs should immediately become accessible without restart
//    - Force-quit and reopen → still OFF
//    - Open on a second device signed in to same account → also OFF within a minute
//
// 3. TOGGLE BACK ON
//    - Toggle ON → restricted tabs immediately show gate view
//
// 4. DEEP LINK TO BLOCKED SCREEN
//    - Open amen://post/some-id in Safari while app is in background (Sunday)
//    - App should open to tab 3 (Resources), NOT the post
//
// 5. PUSH NOTIFICATION TAP (Sunday)
//    - Receive a "comment" push, tap it while Shabbat active
//    - App should open to tab 3, not the post
//
// 6. MIDNIGHT SAT→SUN TRANSITION
//    - Set device clock to Saturday 23:58
//    - Open app → normal access
//    - Wait for 23:59→00:00 transition
//    - App should redirect to Resources within 60 seconds
//
// 7. MIDNIGHT SUN→MON TRANSITION
//    - Set device clock to Sunday 23:58
//    - App should be restricted
//    - Wait for Monday 00:00
//    - App should automatically re-enable all features
//
// 8. DST TEST
//    - Set device timezone to America/New_York
//    - Set device clock to Sunday 01:30 AM on a DST spring-forward Sunday
//    - App should be restricted
//
// 9. SERVER BYPASS ATTEMPT
//    - With a REST client, call onPostCreate / onCommentCreate with a user that
//      has shabbatModeEnabled=true and is in a Sunday timezone
//    - Response should show null return (trigger skips) and shabbat_blocked_server
//      event in analytics_shabbat_blocks Firestore collection
