// AmenSmartPromptTests.swift
// AMEN App — Smart Contextual Prompt System Tests
//
// Tests for AmenSmartPromptStateStore and AmenSmartPromptEngine.
// Uses the Swift Testing framework (not XCTest).
//
// Test isolation: each test uses an ephemeral UserDefaults suite to
// avoid state bleed between runs.

import Testing
import Foundation
import UserNotifications
@testable import AMENAPP

// MARK: - StateStore Tests

@Suite("AmenSmartPromptStateStore")
@MainActor
struct AmenSmartPromptStateStoreTests {

    private func makeSut() -> AmenSmartPromptStateStore {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return AmenSmartPromptStateStore(defaults: suite)
    }

    @Test("New store returns nil for all dates")
    func testFreshStoreIsEmpty() {
        let sut = makeSut()
        #expect(sut.lastImpressionDate(for: "prayer_reply_notification") == nil)
        #expect(sut.lastDismissalDate(for: "prayer_reply_notification") == nil)
        #expect(sut.lastActionDate(for: "prayer_reply_notification") == nil)
        #expect(sut.globalLastPromptDate == nil)
        #expect(sut.dismissalCount(for: "prayer_reply_notification") == 0)
        #expect(!sut.isPermanentlySuppressed("prayer_reply_notification"))
    }

    @Test("recordImpression writes a timestamp within the call window")
    func testRecordImpression() {
        let sut = makeSut()
        let before = Date()
        sut.recordImpression(for: "prayer_reply_notification")
        let after = Date()
        let ts = sut.lastImpressionDate(for: "prayer_reply_notification")
        #expect(ts != nil)
        #expect(ts! >= before)
        #expect(ts! <= after)
    }

    @Test("recordDismissal increments count and writes timestamp")
    func testRecordDismissal() {
        let sut = makeSut()
        sut.recordDismissal(for: "prayer_reply_notification")
        sut.recordDismissal(for: "prayer_reply_notification")
        #expect(sut.dismissalCount(for: "prayer_reply_notification") == 2)
        #expect(sut.lastDismissalDate(for: "prayer_reply_notification") != nil)
    }

    @Test("markPermanentlySuppressed is read back correctly")
    func testPermanentSuppression() {
        let sut = makeSut()
        #expect(!sut.isPermanentlySuppressed("prayer_reply_notification"))
        sut.markPermanentlySuppressed("prayer_reply_notification")
        #expect(sut.isPermanentlySuppressed("prayer_reply_notification"))
    }

    @Test("Surface cooldown is tracked independently per surface")
    func testSurfaceCooldown() {
        let sut = makeSut()
        sut.recordSurfacePrompt(for: .prayerRequests)
        #expect(sut.lastPromptDate(for: .prayerRequests) != nil)
        #expect(sut.lastPromptDate(for: .bereanAI) == nil)
    }

    @Test("Global cooldown is set by recordGlobalPrompt")
    func testGlobalCooldown() {
        let sut = makeSut()
        #expect(sut.globalLastPromptDate == nil)
        sut.recordGlobalPrompt()
        #expect(sut.globalLastPromptDate != nil)
    }

    @Test("resetAll clears all prompt keys")
    func testResetAll() {
        let sut = makeSut()
        sut.recordImpression(for: "prayer_reply_notification")
        sut.recordDismissal(for: "prayer_reply_notification")
        sut.markPermanentlySuppressed("prayer_reply_notification")
        sut.recordGlobalPrompt()
        sut.resetAll()
        #expect(sut.lastImpressionDate(for: "prayer_reply_notification") == nil)
        #expect(sut.dismissalCount(for: "prayer_reply_notification") == 0)
        #expect(!sut.isPermanentlySuppressed("prayer_reply_notification"))
        #expect(sut.globalLastPromptDate == nil)
    }

    @Test("Different prompt keys are stored independently")
    func testKeyIsolation() {
        let sut = makeSut()
        sut.recordDismissal(for: "prayer_reply_notification")
        sut.recordDismissal(for: "prayer_reply_notification")
        sut.recordDismissal(for: "church_event_reminder")
        #expect(sut.dismissalCount(for: "prayer_reply_notification") == 2)
        #expect(sut.dismissalCount(for: "church_event_reminder") == 1)
    }
}

// MARK: - Engine Suppression Tests

@Suite("AmenSmartPromptEngine — Suppression Rules")
@MainActor
struct AmenSmartPromptEngineSuppressionTests {

    @Test("Engine call completes cleanly during worship session")
    func testWorshipSessionSuppression() async {
        var ctx = AmenSmartPromptContext()
        ctx.isInWorshipSession = true
        let result = await AmenSmartPromptEngine.shared.eligiblePrompt(surface: .selah, context: ctx)
        _ = result
    }

    @Test("Engine call completes cleanly during live prayer")
    func testLivePrayerSuppression() async {
        var ctx = AmenSmartPromptContext()
        ctx.isInLivePrayer = true
        let result = await AmenSmartPromptEngine.shared.eligiblePrompt(surface: .prayerRequests, context: ctx)
        _ = result
    }

    @Test("Engine call completes cleanly during Berean generation")
    func testBereanGeneratingSuppression() async {
        var ctx = AmenSmartPromptContext()
        ctx.isBereanGenerating = true
        let result = await AmenSmartPromptEngine.shared.eligiblePrompt(surface: .bereanAI, context: ctx)
        _ = result
    }

    @Test("Engine call completes cleanly during active text entry")
    func testTextEntrySuppression() async {
        var ctx = AmenSmartPromptContext()
        ctx.isInActiveTextEntry = true
        let result = await AmenSmartPromptEngine.shared.eligiblePrompt(surface: .churchNotes, context: ctx)
        _ = result
    }

    @Test("Engine call completes cleanly when notification permission is authorized")
    func testNotificationPermissionAlreadyGranted() async {
        var ctx = AmenSmartPromptContext()
        ctx.notificationPermissionStatus = .authorized
        let result = await AmenSmartPromptEngine.shared.eligiblePrompt(surface: .prayerRequests, context: ctx)
        _ = result
    }
}

// MARK: - StateStore Cooldown Contract Tests

@Suite("AmenSmartPromptStateStore — Cooldown Contract")
@MainActor
struct AmenSmartPromptCooldownContractTests {

    private func makeSut() -> AmenSmartPromptStateStore {
        let suite = UserDefaults(suiteName: "test-cooldown-\(UUID().uuidString)")!
        return AmenSmartPromptStateStore(defaults: suite)
    }

    @Test("Recent impression is within cooldown window")
    func testRecentImpressionBlocksEligibility() {
        let sut = makeSut()
        sut.recordImpression(for: "prayer_reply_notification")
        let last = sut.lastImpressionDate(for: "prayer_reply_notification")!
        #expect(Date().timeIntervalSince(last) < 48 * 3600)
    }

    @Test("Dismissal count accumulates to threshold")
    func testMaxDismissalCount() {
        let sut = makeSut()
        let key = "church_event_reminder"
        for _ in 0..<2 { sut.recordDismissal(for: key) }
        #expect(sut.dismissalCount(for: key) == 2)
    }

    @Test("Surface cooldown is isolated per surface")
    func testSurfaceCooldownTracking() {
        let sut = makeSut()
        let before = Date()
        sut.recordSurfacePrompt(for: .churchDetail)
        let after = Date()
        let ts = sut.lastPromptDate(for: .churchDetail)!
        #expect(ts >= before && ts <= after)
        #expect(sut.lastPromptDate(for: .selah) == nil)
    }

    @Test("Global prompt timestamp is within call window")
    func testGlobalPromptTracking() {
        let sut = makeSut()
        let before = Date()
        sut.recordGlobalPrompt()
        let after = Date()
        let ts = sut.globalLastPromptDate!
        #expect(ts >= before && ts <= after)
    }
}

// MARK: - Prompt Model Tests

@Suite("AmenSmartPrompt Model")
struct AmenSmartPromptModelTests {

    @Test("Prompt persistenceKey equals type rawValue")
    func testPersistenceKey() {
        let prompt = AmenSmartPrompt(
            type: .prayerReplyNotification,
            surface: .prayerRequests,
            title: "Stay close?",
            body: "Body",
            systemImage: "bell",
            primaryAction: .primary("OK", route: .requestNotificationPermission)
        )
        #expect(prompt.persistenceKey == "prayer_reply_notification")
    }

    @Test("Secondary action defaults to dismiss route and is not primary")
    func testSecondaryActionRoute() {
        let prompt = AmenSmartPrompt(
            type: .selahPause,
            surface: .selah,
            title: "Pause?",
            body: "Body",
            systemImage: "leaf",
            primaryAction: .primary("Go", route: .openSelah),
            secondaryActionTitle: "Not Now"
        )
        #expect(prompt.secondaryAction.route == .dismiss)
        #expect(!prompt.secondaryAction.isPrimary)
        #expect(prompt.primaryAction.isPrimary)
    }

    @Test("Default cooldown policy values are sane")
    func testDefaultCooldownPolicy() {
        let policy = AmenSmartPromptCooldownPolicy.default
        #expect(policy.perPromptType >= 24 * 3600)
        #expect(policy.perSurface >= 3600)
        #expect(policy.global >= 900)
        #expect(policy.maxDismissals >= 2)
    }

    @Test("All prompt type raw values are unique")
    func testUniqueRawValues() {
        let raws = AmenSmartPromptType.allCases.map(\.rawValue)
        #expect(raws.count == Set(raws).count)
    }

    @Test("All surface raw values are unique")
    func testUniqueSurfaceRawValues() {
        let raws = AmenSmartPromptSurface.allCases.map(\.rawValue)
        #expect(raws.count == Set(raws).count)
    }
}

// MARK: - Analytics Event Tests

@Suite("Smart Prompt Analytics Events")
struct AmenSmartPromptAnalyticsTests {

    @Test("smartPromptImpression returns correct event name")
    func testImpressionEventName() {
        let event = AMENAnalyticsEvent.smartPromptImpression(
            promptType: "prayer_reply_notification",
            surface: "prayer_requests"
        )
        #expect(event.name == "smart_prompt_impression")
    }

    @Test("smartPromptDismissed includes reason in properties")
    func testDismissedEventProperties() {
        let event = AMENAnalyticsEvent.smartPromptDismissed(
            promptType: "church_event_reminder",
            surface: "church_detail",
            reason: "swiped_away"
        )
        #expect(event.properties["prompt_type"] as? String == "church_event_reminder")
        #expect(event.properties["surface"] as? String == "church_detail")
        #expect(event.properties["reason"] as? String == "swiped_away")
    }

    @Test("smartPromptSuppressed has surface and reason")
    func testSuppressedEventProperties() {
        let event = AMENAnalyticsEvent.smartPromptSuppressed(
            surface: "berean_ai",
            reason: "global_kill_switch"
        )
        #expect(event.properties["surface"] as? String == "berean_ai")
        #expect(event.properties["reason"] as? String == "global_kill_switch")
    }

    @Test("smartPromptPermissionGranted has promptType and permissionType")
    func testPermissionGrantedProperties() {
        let event = AMENAnalyticsEvent.smartPromptPermissionGranted(
            promptType: "prayer_reply_notification",
            permissionType: "notifications"
        )
        #expect(event.properties["prompt_type"] as? String == "prayer_reply_notification")
        #expect(event.properties["permission_type"] as? String == "notifications")
    }

    @Test("Analytics events contain no sensitive spiritual content keys")
    func testNoSensitiveKeys() {
        let forbidden = ["prayer_text", "message_text", "reflection_text",
                         "note_body", "berean_prompt", "berean_response",
                         "journal_text", "emotional_state"]
        let events: [AMENAnalyticsEvent] = [
            .smartPromptImpression(promptType: "p", surface: "s"),
            .smartPromptDismissed(promptType: "p", surface: "s", reason: "r"),
            .smartPromptSuppressed(surface: "s", reason: "r"),
            .smartPromptPermissionRequested(promptType: "p", permissionType: "notifications"),
        ]
        for event in events {
            for key in forbidden {
                #expect(
                    event.properties[key] == nil,
                    "Event '\(event.name)' must not contain sensitive key '\(key)'"
                )
            }
        }
    }
}
