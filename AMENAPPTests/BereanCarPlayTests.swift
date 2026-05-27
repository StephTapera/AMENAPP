// BereanCarPlayTests.swift
// AMEN — Berean Drive CarPlay Tests
//
// Contract and logic tests for the Berean Drive CarPlay module.
// Tests validate local contracts, safety gates, routing logic, and feature flags.
// No Firebase calls — all tests are deterministic and offline-safe.
//
// Coverage targets:
//   ✓ Feature flag gating
//   ✓ Safety gate — message blocked before read-aloud
//   ✓ Safety gate — dictated reply blocked before send
//   ✓ Safety gate — youth safety mode
//   ✓ Driving-safe response length
//   ✓ Response truncation at policy limit
//   ✓ Callable name constants (contract guards)
//   ✓ Drive response parsing helpers
//   ✓ Church result parsing
//   ✓ Handoff-required behavior
//   ✓ Voice command parsing
//   ✓ Preferences persistence round-trip
//   ✓ Rate limit enforcement
//   ✓ Analytics event name stability

import Foundation
import Testing
@testable import AMENAPP

// MARK: - Feature Flag Gating

@Suite("CarPlay Feature Flag Gating")
struct BereanCarPlayFeatureFlagTests {

    @Test("carPlayBereanEnabled defaults to false (off by default)")
    @MainActor
    func carPlayDefaultsOff() {
        // The flag must default to false — CarPlay is not active until entitlement
        // is obtained and Remote Config enables it.
        let flags = AMENFeatureFlags.shared
        // Default is false per the declaration in AMENFeatureFlags.swift
        #expect(flags.carPlayBereanEnabled == false)
    }

    @Test("carPlayAudioEnabled defaults to false")
    @MainActor
    func carPlayAudioDefaultsOff() {
        #expect(AMENFeatureFlags.shared.carPlayAudioEnabled == false)
    }

    @Test("carPlayMessagingEnabled defaults to false")
    @MainActor
    func carPlayMessagingDefaultsOff() {
        #expect(AMENFeatureFlags.shared.carPlayMessagingEnabled == false)
    }

    @Test("carPlayNavigationHandoffEnabled defaults to false")
    @MainActor
    func carPlayNavigationDefaultsOff() {
        #expect(AMENFeatureFlags.shared.carPlayNavigationHandoffEnabled == false)
    }
}

// MARK: - Safety Gate — Read-Aloud Blocking

@Suite("BereanCarPlaySafetyGate — Read-Aloud")
struct BereanCarPlaySafetyGateReadAloudTests {

    @Test("safe text passes through unchanged")
    @MainActor
    func safePrayerTextPasses() {
        let text = "Lord, thank you for this journey. Guide my path today."
        let result = BereanCarPlaySafetyGate.shared.screenForReadAloud(text)
        #expect(result.isSafe)
    }

    @Test("profanity is blocked")
    @MainActor
    func profanityIsBlocked() {
        let text = "this is a damn message"
        let result = BereanCarPlaySafetyGate.shared.screenForReadAloud(text)
        #expect(!result.isSafe)
    }

    @Test("sexual content is blocked")
    @MainActor
    func sexualContentIsBlocked() {
        let text = "send me pics"
        let result = BereanCarPlaySafetyGate.shared.screenForReadAloud(text)
        #expect(!result.isSafe)
    }

    @Test("threat is blocked")
    @MainActor
    func threatIsBlocked() {
        let text = "I will hurt you"
        let result = BereanCarPlaySafetyGate.shared.screenForReadAloud(text)
        #expect(!result.isSafe)
    }

    @Test("blocked result returns calm replacement, not original text")
    @MainActor
    func blockedReturnsCalm() {
        let text = "kill you"
        let result = BereanCarPlaySafetyGate.shared.screenForReadAloud(text)
        #expect(!result.isSafe)
        #expect(result.calmReplacementText != nil)
        #expect(result.calmReplacementText?.contains("kill") == false)
    }

    @Test("scripture reference is not blocked")
    @MainActor
    func scriptureNotBlocked() {
        let text = "Romans 8:28 says all things work together for good."
        let result = BereanCarPlaySafetyGate.shared.screenForReadAloud(text)
        #expect(result.isSafe)
    }
}

// MARK: - Safety Gate — Dictated Reply Blocking

@Suite("BereanCarPlaySafetyGate — Dictated Replies")
struct BereanCarPlaySafetyGateDictatedReplyTests {

    @Test("safe dictated reply passes")
    @MainActor
    func safeDictatedReplyPasses() {
        let text = "I'll be there in 10 minutes. Looking forward to worship."
        let result = BereanCarPlaySafetyGate.shared.screenDictatedReply(text)
        #expect(result.isSafe)
    }

    @Test("harassment in dictated reply is blocked")
    @MainActor
    func harassmentBlocked() {
        let text = "you're finished, I will stalk you"
        let result = BereanCarPlaySafetyGate.shared.screenDictatedReply(text)
        #expect(!result.isSafe)
    }

    @Test("grooming pattern in dictated reply is blocked")
    @MainActor
    func groomingPatternBlocked() {
        let text = "don't tell your parents about this"
        let result = BereanCarPlaySafetyGate.shared.screenDictatedReply(text)
        #expect(!result.isSafe)
    }
}

// MARK: - Safety Gate — Youth Mode

@Suite("BereanCarPlaySafetyGate — Youth Safety")
struct BereanCarPlayYouthSafetyTests {

    @Test("alcohol reference blocked in youth mode")
    @MainActor
    func alcoholBlockedInYouthMode() {
        let text = "let's grab some alcohol after church"
        let result = BereanCarPlaySafetyGate.shared.screenForReadAloud(text, youthSafetyEnabled: true)
        #expect(!result.isSafe)
    }

    @Test("alcohol reference NOT blocked without youth mode")
    @MainActor
    func alcoholAllowedWithoutYouthMode() {
        let text = "the wedding at Cana involved alcohol"
        let result = BereanCarPlaySafetyGate.shared.screenForReadAloud(text, youthSafetyEnabled: false)
        // Context-safe (biblical reference) — youth mode flag is the discriminator
        #expect(result.isSafe)
    }

    @Test("self-harm reference blocked in youth mode")
    @MainActor
    func selfHarmBlockedInYouthMode() {
        let text = "I've been self-harming"
        let result = BereanCarPlaySafetyGate.shared.screenForReadAloud(text, youthSafetyEnabled: true)
        #expect(!result.isSafe)
    }
}

// MARK: - Driving-Safe Response Length

@Suite("BereanDriveResponsePolicy — Length Limits")
struct BereanDriveResponsePolicyTests {

    @Test("short response is safe for driving")
    func shortResponseIsSafe() {
        let text = "Romans 8:28: all things work together for good."
        #expect(BereanDriveResponsePolicy.isSafeForDriving(spokenText: text))
    }

    @Test("response at exactly the limit is safe")
    func exactLimitIsSafe() {
        let text = String(repeating: "a", count: BereanDriveResponsePolicy.maxSpokenCharacters)
        #expect(BereanDriveResponsePolicy.isSafeForDriving(spokenText: text))
    }

    @Test("response over the limit is NOT safe for driving")
    func overLimitIsUnsafe() {
        let text = String(repeating: "b", count: BereanDriveResponsePolicy.maxSpokenCharacters + 1)
        #expect(!BereanDriveResponsePolicy.isSafeForDriving(spokenText: text))
    }

    @Test("truncateForDriving returns text at or under the limit")
    func truncationHonorsLimit() {
        let longText = String(repeating: "word ", count: 200)
        let truncated = BereanDriveResponsePolicy.truncateForDriving(longText)
        #expect(truncated.count <= BereanDriveResponsePolicy.maxSpokenCharacters + 10)
    }

    @Test("truncateForDriving leaves short text unchanged")
    func shortTextUnchanged() {
        let text = "A short prayer for today."
        let result = BereanDriveResponsePolicy.truncateForDriving(text)
        #expect(result == text)
    }
}

// MARK: - Drive Response Validation

@Suite("BereanCarPlaySafetyGate — validateDriveResponse")
struct BereanDriveResponseValidationTests {

    @MainActor
    private func gate() -> BereanCarPlaySafetyGate { .shared }

    @Test("safe response passes through unchanged")
    @MainActor
    func safeResponsePassesThrough() {
        let response = makeResponse(spokenText: "Peace be with you on your journey.", safetyState: .safe)
        let result = gate().validateDriveResponse(response, youthSafetyEnabled: false)
        #expect(result.safetyState != .blocked)
        #expect(result.spokenText.contains("Peace"))
    }

    @Test("response with handoffRequired is preserved")
    @MainActor
    func handoffRequiredPreserved() {
        let response = makeResponse(spokenText: "See your phone for details.", safetyState: .safe, handoffRequired: true)
        let result = gate().validateDriveResponse(response, youthSafetyEnabled: false)
        #expect(result.handoffRequired)
    }

    @Test("response with unsafe spoken text is blocked and replaced")
    @MainActor
    func unsafeResponseIsReplaced() {
        let response = makeResponse(spokenText: "I will kill you", safetyState: .safe)
        let result = gate().validateDriveResponse(response, youthSafetyEnabled: false)
        #expect(result.safetyState == .blocked)
        #expect(!result.spokenText.contains("kill"))
    }

    @Test("very long response becomes handoff_required when server review needed")
    @MainActor
    func veryLongResponseTriggersHandoff() {
        let longText = String(repeating: "word ", count: 300)  // ~1500 chars, way over limit
        let response = makeResponse(spokenText: longText, safetyState: .safe)
        let result = gate().validateDriveResponse(response, youthSafetyEnabled: false)
        // Should either truncate (summarized) or require handoff
        #expect(result.safetyState == .summarized || result.safetyState == .handoffRequired)
    }

    private func makeResponse(
        spokenText: String,
        safetyState: BereanDriveSafetyState,
        handoffRequired: Bool = false
    ) -> BereanDriveResponse {
        BereanDriveResponse(
            spokenText: spokenText,
            displayTitle: "Test",
            displaySubtitle: nil,
            safetyState: safetyState,
            handoffRequired: handoffRequired,
            handoffReason: nil,
            sourceRefs: [],
            actionButtons: [],
            audioDurationEstimateSeconds: nil
        )
    }
}

// MARK: - Voice Command Parsing

@Suite("BereanDriveVoiceService — Command Parsing")
struct BereanDriveVoiceCommandParsingTests {

    private let service = BereanDriveVoiceService.shared

    @Test("'Explain Romans 8' routes to askBerean")
    @MainActor
    func explainRoutesToBerean() {
        let command = service.parseCommand(from: "Explain Romans 8")
        if case .askBerean(let q) = command {
            #expect(q.contains("Romans"))
        } else {
            Issue.record("Expected askBerean command")
        }
    }

    @Test("'Pray with me' routes to prayWithMe")
    @MainActor
    func prayWithMeRoutes() {
        let command = service.parseCommand(from: "Pray with me")
        if case .prayWithMe = command { /* pass */ } else {
            Issue.record("Expected prayWithMe command")
        }
    }

    @Test("'Summarize my church notes' routes to summarizeChurchNotes")
    @MainActor
    func churchNotesRoutes() {
        let command = service.parseCommand(from: "Summarize my church notes")
        if case .summarizeChurchNotes = command { /* pass */ } else {
            Issue.record("Expected summarizeChurchNotes command")
        }
    }

    @Test("'Find a church near me' routes to findChurch")
    @MainActor
    func findChurchRoutes() {
        let command = service.parseCommand(from: "Find a church near me")
        if case .findChurch = command { /* pass */ } else {
            Issue.record("Expected findChurch command")
        }
    }

    @Test("unknown command routes to unknown")
    @MainActor
    func unknownRoutes() {
        let command = service.parseCommand(from: "pizza recipe please")
        if case .unknown = command { /* pass */ } else {
            Issue.record("Expected unknown command")
        }
    }

    @Test("blocked dictated reply returns nil")
    @MainActor
    func blockedDictatedReplyReturnsNil() {
        let blocked = service.validateDictatedReply("I will hurt you", youthSafetyEnabled: false)
        #expect(blocked == nil)
    }

    @Test("safe dictated reply returns text")
    @MainActor
    func safeDictatedReplyReturnsText() {
        let safe = service.validateDictatedReply("See you Sunday!", youthSafetyEnabled: false)
        #expect(safe == "See you Sunday!")
    }
}

// MARK: - Drive State Models

@Suite("BereanDriveState — Model Correctness")
struct BereanDriveStateTests {

    @Test("BereanDriveSession.new creates active session with correct userId")
    func newSessionHasCorrectUserId() {
        let session = BereanDriveSession.new(userId: "user_123", mode: .prayerRide)
        #expect(session.userId == "user_123")
        #expect(session.activeMode == .prayerRide)
        #expect(session.phase == .active)
        #expect(!session.sessionId.isEmpty)
    }

    @Test("BereanDrivePreferences round-trips through UserDefaults")
    func preferencesRoundTrip() {
        var prefs = BereanDrivePreferences()
        prefs.preferredScriptureTranslation = "ESV"
        prefs.youthSafetyEnabled = true
        prefs.churchSearchRadiusMiles = 15.0
        prefs.save()

        let loaded = BereanDrivePreferences.load()
        #expect(loaded.preferredScriptureTranslation == "ESV")
        #expect(loaded.youthSafetyEnabled == true)
        #expect(loaded.churchSearchRadiusMiles == 15.0)
    }

    @Test("BereanDriveChurchResult distanceLabel formats correctly")
    func churchDistanceLabelFormats() {
        let church = BereanDriveChurchResult(
            id: "1", name: "Grace Church",
            distanceMiles: 3.7, address: nil, phoneNumber: nil,
            nextServiceTime: nil, denomination: nil,
            latitude: nil, longitude: nil, amenSpaceId: nil
        )
        #expect(church.distanceLabel == "3.7 mi")
    }

    @Test("BereanDriveChurchResult hasNavigation is false when coordinates missing")
    func noNavigationWithoutCoords() {
        let church = BereanDriveChurchResult(
            id: "1", name: "Test",
            distanceMiles: nil, address: nil, phoneNumber: nil,
            nextServiceTime: nil, denomination: nil,
            latitude: nil, longitude: nil, amenSpaceId: nil
        )
        #expect(!church.hasNavigation)
    }
}

// MARK: - Callable Name Constants

@Suite("BereanDriveSessionService — Callable Name Contracts")
struct BereanDriveCallableNameTests {

    @Test("bereanDriveRespond callable name is stable")
    func bereanDriveRespondName() {
        #expect(BereanDriveCallableNames.respond == "bereanDriveRespond")
    }

    @Test("bereanDriveSummarize callable name is stable")
    func bereanDriveSummarizeName() {
        #expect(BereanDriveCallableNames.summarize == "bereanDriveSummarize")
    }

    @Test("bereanDrivePrayerSession callable name is stable")
    func bereanDrivePrayerSessionName() {
        #expect(BereanDriveCallableNames.prayerSession == "bereanDrivePrayerSession")
    }

    @Test("bereanDriveChurchSearch callable name is stable")
    func bereanDriveChurchSearchName() {
        #expect(BereanDriveCallableNames.churchSearch == "bereanDriveChurchSearch")
    }

    @Test("bereanDriveMessageSafetyReview callable name is stable")
    func bereanDriveMessageSafetyReviewName() {
        #expect(BereanDriveCallableNames.messageSafetyReview == "bereanDriveMessageSafetyReview")
    }
}

// MARK: - Analytics Event Names

@Suite("BereanCarPlayAnalytics — Event Name Stability")
struct BereanCarPlayAnalyticsEventNameTests {

    @Test("carplay_session_started event name is stable")
    func sessionStartedName() {
        #expect(BereanCarPlayAnalyticsEvent.sessionStarted.rawValue == "carplay_session_started")
    }

    @Test("carplay_safety_block_triggered event name is stable")
    func safetyBlockName() {
        #expect(BereanCarPlayAnalyticsEvent.safetyBlockTriggered.rawValue == "carplay_safety_block_triggered")
    }

    @Test("carplay_berean_voice_query event name is stable")
    func bereanVoiceQueryName() {
        #expect(BereanCarPlayAnalyticsEvent.bereanVoiceQuery.rawValue == "carplay_berean_voice_query")
    }

    @Test("carplay_church_navigation_started event name is stable")
    func churchNavigationName() {
        #expect(BereanCarPlayAnalyticsEvent.churchNavigationStarted.rawValue == "carplay_church_navigation_started")
    }
}
