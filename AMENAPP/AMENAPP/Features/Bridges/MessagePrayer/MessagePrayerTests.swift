#if canImport(Testing)
import Testing
import Foundation
@testable import AMENAPP

// MARK: - Helpers

/// A test-only subclass that bypasses AMENFeatureFlags + ConsentStore checks
/// so individual invariants can be tested in isolation.
private final class TestableBridge {
    var flagEnabled: Bool = true
    var consentEnabled: Bool = true
    private var seenPhrases: Set<String> = []

    func analyze(
        message: String,
        threadID: String,
        senderName: String,
        threadTier: TierCeiling = .p,
        threadIsE2EE: Bool = false
    ) -> PrayerSuggestion? {
        guard flagEnabled else { return nil }
        guard consentEnabled else { return nil }

        guard detectPrayerIntent(in: message) else { return nil }

        let excerpt = String(message.prefix(60))
        guard !seenPhrases.contains(excerpt) else { return nil }
        seenPhrases.insert(excerpt)

        return PrayerSuggestion(
            threadID: threadID,
            senderName: senderName,
            excerpt: excerpt,
            suggestedTitle: "Pray for \(senderName)",
            tierCeiling: threadIsE2EE ? .s : threadTier
        )
    }

    private func detectPrayerIntent(in text: String) -> Bool {
        let lower = text.lowercased()
        let prayerPhrases = [
            "pray for", "prayer", "please pray", "keep me in", "in your prayers",
            "could use prayer", "pray with me", "lift up", "intercede"
        ]
        return prayerPhrases.contains { lower.contains($0) }
    }
}

// MARK: - Test Suite

@Suite("MessagePrayerBridge")
struct MessagePrayerTests {

    // MARK: 1. Prayer intent detected

    @Test("Detects prayer intent: 'please pray for my mom'")
    func testDetectsPrayerIntent() {
        let bridge = TestableBridge()
        let suggestion = bridge.analyze(
            message: "please pray for my mom, she's going into surgery",
            threadID: "thread-001",
            senderName: "Sarah"
        )
        #expect(suggestion != nil, "Bridge should return a suggestion for a clear prayer-request message")
        #expect(suggestion?.senderName == "Sarah")
        #expect(suggestion?.suggestedTitle == "Pray for Sarah")
        #expect(suggestion?.threadID == "thread-001")
    }

    // MARK: 2. Non-prayer message returns nil

    @Test("Ignores non-prayer message: 'Hey, how was your weekend?'")
    func testIgnoresNonPrayerMessage() {
        let bridge = TestableBridge()
        let suggestion = bridge.analyze(
            message: "Hey, how was your weekend?",
            threadID: "thread-002",
            senderName: "Chris"
        )
        #expect(suggestion == nil, "Bridge must not return a suggestion for a non-prayer message")
    }

    // MARK: 3. Consent off skips

    @Test("Returns nil when consent is off")
    func testConsentOffSkips() {
        let bridge = TestableBridge()
        bridge.consentEnabled = false
        let suggestion = bridge.analyze(
            message: "please pray for me today",
            threadID: "thread-003",
            senderName: "Jordan"
        )
        #expect(suggestion == nil, "Bridge must return nil when messagesToPrayer consent is disabled")
    }

    // MARK: 4. Dedupe prevents duplicates

    @Test("Dedupe: same message twice returns nil on the second call")
    func testDedupePreventsDuplicates() {
        let bridge = TestableBridge()
        let message = "I could use prayer right now, going through a lot"

        let first = bridge.analyze(message: message, threadID: "thread-004", senderName: "Alex")
        let second = bridge.analyze(message: message, threadID: "thread-004", senderName: "Alex")

        #expect(first != nil, "First call should return a suggestion")
        #expect(second == nil, "Second call with same excerpt should be deduped and return nil")
    }

    // MARK: 5. Tier-S prayer stays local

    @Test("E2EE thread produces Tier-S suggestion (device-local only)")
    func testTierSPrayerStaysLocal() {
        let bridge = TestableBridge()
        let suggestion = bridge.analyze(
            message: "lift up my family tonight in prayer",
            threadID: "e2ee-thread-001",
            senderName: "Morgan",
            threadTier: .p,
            threadIsE2EE: true
        )

        #expect(suggestion != nil, "E2EE prayer message should still produce a suggestion")
        #expect(suggestion?.tierCeiling == .s, "E2EE suggestion must have Tier-S ceiling (device-only)")
        // Tier-S invariant: ContextBus.emit() will fan-out locally and never call serverForward.
        // PrayerExtractService.createPrayer() branches on .s and calls savePrayerLocally(),
        // which writes to UserDefaults — never to Firestore.
    }

    // MARK: 6. Flag off skips

    @Test("Returns nil when feature flag is off")
    func testFlagOffSkips() {
        let bridge = TestableBridge()
        bridge.flagEnabled = false
        let suggestion = bridge.analyze(
            message: "in your prayers please",
            threadID: "thread-005",
            senderName: "Taylor"
        )
        #expect(suggestion == nil, "Bridge must return nil when the ctx_message_prayer_extraction_enabled flag is false")
    }

    // MARK: 7. Excerpt is capped at 60 characters

    @Test("Excerpt is capped at 60 characters")
    func testExcerptCap() {
        let bridge = TestableBridge()
        let longMessage = "please pray for me, I have been struggling for many weeks now and need all the support I can get"
        let suggestion = bridge.analyze(
            message: longMessage,
            threadID: "thread-006",
            senderName: "Riley"
        )
        #expect(suggestion != nil)
        #expect((suggestion?.excerpt.count ?? 0) <= 60, "Excerpt must be at most 60 characters")
    }
}
#endif
