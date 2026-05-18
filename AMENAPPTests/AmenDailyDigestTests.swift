import Testing
import Foundation
@testable import AMENAPP

@Suite("Amen Daily Digest Models")
struct AmenDailyDigestTests {
    @Test("Digest decoding supports backend payload")
    func digestDecodingSupportsBackendPayload() throws {
        let json = """
        {
          "id":"amen-daily-2026-05-10",
          "dateKey":"2026-05-10",
          "greeting":"Good morning",
          "title":"Happy Mother's Day",
          "verseText":"Her children rise up and call her blessed.",
          "verseReference":"Proverbs 31:28",
          "contextText":"Take a moment to honor, remember, or pray for mothers and mother figures.",
          "reflectionText":"Bring the day honestly before God.",
          "prayerPrompt":"Lord, bless mothers and mother figures.",
          "passage":{"reference":"Proverbs 31","title":"A Woman of Noble Character"},
          "holiday":{"name":"Mother's Day","type":"general","message":"Take a moment to honor, remember, or pray for mothers and mother figures.","suggestedVerseReference":"Proverbs 31:28","dateKey":"2026-05-10"},
          "actions":[{"id":"pray","title":"Pray","systemImage":"hands.sparkles","destination":{"type":"prayer","prompt":"Lord, bless mothers."},"analyticsName":"pray"}],
          "priority":"generalHoliday",
          "source":"backend"
        }
        """
        let digest = try JSONDecoder().decode(AmenDailyDigest.self, from: Data(json.utf8))
        #expect(digest.priority == .generalHoliday)
        #expect(digest.holiday?.name == "Mother's Day")
        #expect(digest.collapsedActions.count == 1)
    }

    @Test("Collapsed actions are limited to two")
    func collapsedActionsAreLimitedToTwo() {
        let digest = AmenDailyDigest.fallback()
        #expect(digest.collapsedActions.count <= 2)
    }

    @Test("Fallback digest remains scripture first")
    func fallbackDigestRemainsScriptureFirst() {
        let digest = AmenDailyDigest.fallback()
        #expect(digest.verseReference == "Psalm 23:1")
        #expect(digest.contextText != nil)
        #expect(digest.priority == .defaultVerse)
    }

    @Test("Action destinations map analytics safely")
    func actionDestinationsMapAnalyticsSafely() {
        #expect(AmenDailyDigestDestination.selah.analyticsValue == "selah")
        #expect(AmenDailyDigestDestination.passage(reference: "Luke 24").analyticsValue == "passage")
        #expect(AmenDailyDigestDestination.bereanAI(prompt: "Explain Psalm 23").analyticsValue == "berean_ai")
    }
}
