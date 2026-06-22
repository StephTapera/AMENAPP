import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

/// Contract tests for the Amen Pulse decode seam and model invariants.
/// These exercise pure logic (no Firebase): the Firestore→model boundary, the
/// fail-closed `minorSafe` default, brief-duration gating, and What's New freshness.
@Suite("Amen Pulse Contracts")
struct AmenPulseContractTests {

    // MARK: - Decode: full card round-trips every field

    @Test("Card decode maps every contract field")
    func cardDecodeFull() throws {
        let dict: [String: Any] = [
            "id": "c1",
            "kind": "prayer_followup",
            "score": ["composite": 0.9, "relationship": 0.8, "spiritual": 0.1,
                      "community": 0.2, "urgency": 0.7, "interest": 0.3],
            "hero": ["scrim": "dark", "style": "prayer", "imageUrl": "https://x/y.jpg"],
            "eyebrow": "PRAYER UPDATE",
            "title": "Marcus posted an update",
            "subtitle": "He shared good news this morning.",
            "action": ["kind": "checkIn", "label": "Check In",
                       "deeplink": "amen://prayer/42", "payload": ["id": "42"]],
            "minorSafe": true,
            "provenanceLabel": "Summaries by Berean · cite-or-refuse",
            "facts": [["systemImage": "heart", "text": "a friend is celebrating"]],
            "briefSections": [["heading": "Prayer", "body": "body", "minimumDuration": "30s"]],
            "whatsNewStoryId": "w1"
        ]

        let card = try #require(PulseDecode.card(dict))
        #expect(card.id == "c1")
        #expect(card.kind == .prayerFollowup)
        #expect(card.score.composite == 0.9)
        #expect(card.hero.scrim == .dark)
        #expect(card.hero.style == "prayer")
        #expect(card.hero.imageUrl == "https://x/y.jpg")
        #expect(card.eyebrow == "PRAYER UPDATE")
        #expect(card.action.kind == .checkIn)
        #expect(card.action.deeplink == "amen://prayer/42")
        #expect(card.action.payload["id"] == "42")
        #expect(card.minorSafe == true)
        #expect(card.facts?.count == 1)
        #expect(card.briefSections?.first?.minimumDuration == .thirtySec)
        #expect(card.whatsNewStoryId == "w1")
    }

    // MARK: - Decode: fail-closed safety invariant

    @Test("Absent minorSafe decodes as false (fail-closed)")
    func minorSafeFailsClosed() throws {
        let dict: [String: Any] = [
            "id": "c2", "kind": "church_event",
            "hero": ["scrim": "dark", "style": "event"],
            "eyebrow": "TONIGHT", "title": "Worship Night"
            // no "minorSafe" key
        ]
        let card = try #require(PulseDecode.card(dict))
        #expect(card.minorSafe == false, "Unknown minor-safety must default to unsafe.")
    }

    @Test("Card decode rejects missing id or unknown kind")
    func cardDecodeRejectsInvalid() {
        #expect(PulseDecode.card(["kind": "scripture_hero"]) == nil)        // no id
        #expect(PulseDecode.card(["id": "x", "kind": "totally_bogus"]) == nil) // bad kind
        #expect(PulseDecode.card(["id": "x"]) == nil)                        // no kind
    }

    @Test("Empty facts / briefSections decode to nil, not empty arrays")
    func emptyCollectionsBecomeNil() throws {
        let dict: [String: Any] = [
            "id": "c3", "kind": "scripture_hero",
            "hero": ["scrim": "light", "style": "verse"],
            "eyebrow": "VERSE", "title": "Be still",
            "facts": [[String: Any]](), "briefSections": [[String: Any]]()
        ]
        let card = try #require(PulseDecode.card(dict))
        #expect(card.facts == nil)
        #expect(card.briefSections == nil)
    }

    // MARK: - Decode: digest

    @Test("Digest decode bounds cards and defaults durations + sabbath")
    func digestDecode() {
        let cardDict: [String: Any] = [
            "id": "c1", "kind": "daily_brief_hero",
            "hero": ["scrim": "light", "style": "brief"],
            "eyebrow": "DAILY BRIEF", "title": "Good morning"
        ]
        let digest = PulseDecode.digest(
            ["date": "2026-06-10", "sabbath": true, "cards": [cardDict], "briefDurations": [String]()],
            fallbackDateKey: "fallback"
        )
        #expect(digest.date == "2026-06-10")
        #expect(digest.cards.count == 1)
        #expect(digest.sabbath == true)
        #expect(digest.briefDurations == [.thirtySec, .threeMin, .tenMin])
    }

    @Test("Digest decode falls back to provided date key when absent")
    func digestDateFallback() {
        let digest = PulseDecode.digest([:], fallbackDateKey: "2026-06-10")
        #expect(digest.date == "2026-06-10")
        #expect(digest.cards.isEmpty)
        #expect(digest.sabbath == false)
    }

    // MARK: - Decode: What's New story

    @Test("Story decode maps pages, tryAction, and audience")
    func storyDecode() throws {
        let data: [String: Any] = [
            "version": "2.0",
            "title": "Berean understands sermon context",
            "tagline": "Cites the passage, never invents it.",
            "pages": [["headline": "Listen with you", "body": "b", "layout": "split"]],
            "tryAction": ["deeplink": "amen://berean", "label": "Try It"],
            "audience": "adult_only"
        ]
        let story = try #require(PulseDecode.story(data, id: "w1"))
        #expect(story.id == "w1")
        #expect(story.pages.count == 1)
        #expect(story.pages.first?.layout == .split)
        #expect(story.tryAction?.deeplink == "amen://berean")
        #expect(story.audience == .adultOnly)
    }

    // MARK: - Model invariants

    @Test("WhatsNewStory.isFresh honors the 14-day window")
    func freshnessWindow() {
        func story(_ published: Date?) -> WhatsNewStory {
            WhatsNewStory(id: "x", version: "1", title: "t", tagline: "g",
                          pages: [], publishedAt: published)
        }
        let now = Date()
        #expect(story(now).isFresh(asOf: now) == true)
        #expect(story(now.addingTimeInterval(-13 * 86_400)).isFresh(asOf: now) == true)
        #expect(story(now.addingTimeInterval(-15 * 86_400)).isFresh(asOf: now) == false)
        #expect(story(nil).isFresh(asOf: now) == false)
    }

    @Test("Brief duration ranks order 30s < 3m < 10m and gate sections")
    func briefDurationGating() {
        #expect(PulseBriefDuration.thirtySec.rank < PulseBriefDuration.threeMin.rank)
        #expect(PulseBriefDuration.threeMin.rank < PulseBriefDuration.tenMin.rank)

        let sections = [
            PulseBriefSection(heading: "A", body: "", minimumDuration: .thirtySec),
            PulseBriefSection(heading: "B", body: "", minimumDuration: .threeMin),
            PulseBriefSection(heading: "C", body: "", minimumDuration: .tenMin)
        ]
        // At 30s only the 30s section shows; at 10m all three show.
        let at30 = sections.filter { $0.minimumDuration.rank <= PulseBriefDuration.thirtySec.rank }
        let at10 = sections.filter { $0.minimumDuration.rank <= PulseBriefDuration.tenMin.rank }
        #expect(at30.map(\.heading) == ["A"])
        #expect(at10.map(\.heading) == ["A", "B", "C"])
    }

    @Test("Pulse cap floor never exceeds the default ceiling")
    func capInvariants() {
        #expect(PulseConfig.minUserCards <= PulseConfig.defaultMaxCards)
        #expect(PulseConfig.minUserCards >= 1)
    }

    @Test("Hero style resolves known keys and falls back safely")
    func heroStyleResolve() {
        #expect(PulseHeroStyle.resolve("prayer") == .prayer)
        #expect(PulseHeroStyle.resolve("not_a_style") == .verse)   // safe fallback
        #expect(PulseHeroStyle.prayer.scrim == .dark)
        #expect(PulseHeroStyle.verse.scrim == .light)
    }
}
#endif
