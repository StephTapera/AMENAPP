// AdaptiveComposerUnitTests.swift
// AMEN — Unit tests for the Adaptive Composer system.
// Uses Swift Testing framework (not XCTest).

import Testing
import Foundation
@testable import AMENAPP

// MARK: - Scripture Detector Tests

@Suite("Scripture Detector")
struct ScriptureDetectorTests {
    let engine = OnDeviceIntentEngine()
    let ctx = ComposerContext(
        surface: .post,
        churchContext: nil,
        spaceContext: nil,
        audience: nil,
        conversationParticipants: [],
        recentBehavior: [],
        pastedContent: nil
    )

    @Test("John 3:16 triggers bible tool")
    func johnRef() async {
        let s = await engine.detect(in: "Just read John 3:16 amazing", context: ctx)
        #expect(s.contains { $0.primaryTool == .bible })
    }

    @Test("1 Cor 13 triggers bible tool")
    func corRef() async {
        let s = await engine.detect(in: "1 Cor 13:4 love is patient", context: ctx)
        #expect(s.contains { $0.primaryTool == .bible })
    }

    @Test("Psalm 23 triggers bible tool")
    func psalmRef() async {
        let s = await engine.detect(in: "Psalm 23 is my favorite", context: ctx)
        #expect(s.contains { $0.primaryTool == .bible })
    }

    @Test("Genesis 1:1 triggers bible tool")
    func genesisRef() async {
        let s = await engine.detect(in: "Genesis 1:1 in the beginning", context: ctx)
        #expect(s.contains { $0.primaryTool == .bible })
    }

    @Test("Rev 22 triggers bible tool")
    func revRef() async {
        let s = await engine.detect(in: "Check Rev 22:20 maranatha", context: ctx)
        #expect(s.contains { $0.primaryTool == .bible })
    }

    @Test("Random text no scripture match")
    func noMatch1() async {
        let s = await engine.detect(in: "Let's grab coffee tomorrow", context: ctx)
        #expect(!s.contains { $0.primaryTool == .bible })
    }

    @Test("Birthday message no scripture")
    func noMatch2() async {
        let s = await engine.detect(in: "Happy birthday friend!", context: ctx)
        #expect(!s.contains { $0.primaryTool == .bible })
    }

    @Test("Weather text no scripture")
    func noMatch3() async {
        let s = await engine.detect(in: "Great weather today in Chicago", context: ctx)
        #expect(!s.contains { $0.primaryTool == .bible })
    }

    @Test("Pizza text no scripture")
    func noMatch4() async {
        let s = await engine.detect(in: "I love pepperoni pizza", context: ctx)
        #expect(!s.contains { $0.primaryTool == .bible })
    }

    @Test("Greeting no scripture")
    func noMatch5() async {
        let s = await engine.detect(in: "See you at the game!", context: ctx)
        #expect(!s.contains { $0.primaryTool == .bible })
    }
}

// MARK: - Prayer Detector Tests

@Suite("Prayer Detector")
struct PrayerDetectorTests {
    let engine = OnDeviceIntentEngine()
    let ctx = ComposerContext(
        surface: .post,
        churchContext: nil,
        spaceContext: nil,
        audience: nil,
        conversationParticipants: [],
        recentBehavior: [],
        pastedContent: nil
    )

    @Test("Please pray fires prayer")
    func pleasePray() async {
        let s = await engine.detect(in: "Please pray for my mom", context: ctx)
        #expect(s.contains { $0.primaryTool == .prayerRequest })
    }

    @Test("Prayer word fires prayerRequest")
    func prayerWord() async {
        let s = await engine.detect(in: "Sending prayer your way", context: ctx)
        #expect(s.contains { $0.primaryTool == .prayerRequest })
    }

    @Test("Intercession fires prayer")
    func intercession() async {
        let s = await engine.detect(in: "Need intercession for this situation", context: ctx)
        #expect(s.contains { $0.primaryTool == .prayerRequest })
    }

    @Test("Lift up fires prayer")
    func liftUp() async {
        let s = await engine.detect(in: "Lift up the Johnson family today", context: ctx)
        #expect(s.contains { $0.primaryTool == .prayerRequest })
    }

    @Test("Keep in prayer fires")
    func keepInPrayer() async {
        let s = await engine.detect(in: "Keep my friend in prayer this week", context: ctx)
        #expect(s.contains { $0.primaryTool == .prayerRequest })
    }

    @Test("Dinner text no prayer")
    func noPrayer1() async {
        let s = await engine.detect(in: "What should we eat for dinner?", context: ctx)
        #expect(!s.contains { $0.primaryTool == .prayerRequest })
    }

    @Test("Game result no prayer")
    func noPrayer2() async {
        let s = await engine.detect(in: "The game was incredible last night", context: ctx)
        #expect(!s.contains { $0.primaryTool == .prayerRequest })
    }

    @Test("Shopping no prayer")
    func noPrayer3() async {
        let s = await engine.detect(in: "Got a new phone yesterday", context: ctx)
        #expect(!s.contains { $0.primaryTool == .prayerRequest })
    }

    @Test("Compliment no prayer")
    func noPrayer4() async {
        let s = await engine.detect(in: "She is so talented on stage", context: ctx)
        #expect(!s.contains { $0.primaryTool == .prayerRequest })
    }

    @Test("Movie review no prayer")
    func noPrayer5() async {
        let s = await engine.detect(in: "That movie was incredible", context: ctx)
        #expect(!s.contains { $0.primaryTool == .prayerRequest })
    }
}

// MARK: - Date/Event Detector Tests

@Suite("Date/Event Detector")
struct EventDetectorTests {
    let engine = OnDeviceIntentEngine()
    let ctx = ComposerContext(
        surface: .post,
        churchContext: nil,
        spaceContext: nil,
        audience: nil,
        conversationParticipants: [],
        recentBehavior: [],
        pastedContent: nil
    )

    @Test("Sunday at 10am fires event")
    func sundayTime() async {
        let s = await engine.detect(in: "Sunday at 10am everyone come", context: ctx)
        #expect(s.contains { $0.primaryTool == .event })
    }

    @Test("Meeting Thursday fires event")
    func thursdayMeeting() async {
        let s = await engine.detect(in: "Meeting is Thursday at 7pm", context: ctx)
        #expect(s.contains { $0.primaryTool == .event })
    }

    @Test("Specific date fires event")
    func specificDate() async {
        let s = await engine.detect(in: "Conference starts December 15th", context: ctx)
        #expect(s.contains { $0.primaryTool == .event })
    }

    @Test("Random text no event")
    func noEvent1() async {
        let s = await engine.detect(in: "I love this worship song", context: ctx)
        #expect(!s.contains { $0.primaryTool == .event })
    }

    @Test("Scripture no event")
    func noEvent2() async {
        let s = await engine.detect(in: "God is faithful in all things", context: ctx)
        #expect(!s.contains { $0.primaryTool == .event })
    }
}

// MARK: - Tool Registry Tests

@Suite("Tool Registry Tests")
struct ToolRegistryTests {

    @Test("Bible tool present on post surface")
    func bibleOnPost() {
        let tools = CreationTool.registry.filter { $0.surfaces.contains(.post) }
        #expect(tools.contains { $0.id == .bible })
    }

    @Test("Photo tool present on all surfaces")
    func photoAllSurfaces() {
        let photo = CreationTool.registry.first { $0.id == .photo }
        #expect(photo != nil)
        #expect((photo?.surfaces.count ?? 0) == ComposerSurface.allCases.count)
    }

    @Test("Sermon is churchOnly tier")
    func sermonChurchOnly() {
        let sermon = CreationTool.registry.first { $0.id == .sermon }
        #expect(sermon?.tier == .churchOnly)
    }

    @Test("Sermon not on post surface")
    func sermonNotOnPost() {
        let sermon = CreationTool.registry.first { $0.id == .sermon }
        #expect(!(sermon?.surfaces.contains(.post) ?? false))
    }

    @Test("More tool on all surfaces")
    func moreAllSurfaces() {
        let more = CreationTool.registry.first { $0.id == .more }
        #expect((more?.surfaces.count ?? 0) >= ComposerSurface.allCases.count)
    }

    @Test("All tools have non-empty icon")
    func allToolsHaveIcons() {
        let emptyIcons = CreationTool.registry.filter { $0.icon.isEmpty }
        #expect(emptyIcons.isEmpty)
    }

    @Test("Poll not on comment surface")
    func pollNotOnComment() {
        let poll = CreationTool.registry.first { $0.id == .poll }
        #expect(!(poll?.surfaces.contains(.comment) ?? true))
    }
}

// MARK: - ComposerAttachment Codable Round-Trip Tests

@Suite("ComposerAttachment Codable Round-Trips")
struct AttachmentCodableTests {

    @Test("ScripturePayload round-trip")
    func scriptureRoundTrip() throws {
        let p = ScripturePayload(
            schemaVersion: 1,
            reference: "John 3:16",
            text: "For God so loved the world",
            translation: "NIV",
            bookChapter: "John 3"
        )
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(ScripturePayload.self, from: data)
        #expect(decoded == p)
    }

    @Test("PrayerPayload anonymous round-trip")
    func prayerRoundTrip() throws {
        let p = PrayerPayload(schemaVersion: 1, text: "Please pray", isAnonymous: true, prayCount: 5, circleId: nil)
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(PrayerPayload.self, from: data)
        #expect(decoded == p)
        #expect(decoded.isAnonymous == true)
    }

    @Test("PollPayload round-trip")
    func pollRoundTrip() throws {
        let p = PollPayload(
            schemaVersion: 1,
            question: "Best book?",
            options: ["Genesis", "Psalms"],
            votesByOption: ["Genesis": 10, "Psalms": 20],
            totalVotes: 30
        )
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(PollPayload.self, from: data)
        #expect(decoded == p)
    }

    @Test("DonationPayload round-trip")
    func donationRoundTrip() throws {
        let p = DonationPayload(
            schemaVersion: 1,
            campaignId: "c1",
            title: "Building Fund",
            goalAmount: 50000,
            raisedAmount: 12345,
            currency: "USD"
        )
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(DonationPayload.self, from: data)
        #expect(decoded == p)
    }

    @Test("LinkPayload round-trip")
    func linkRoundTrip() throws {
        let p = LinkPayload(
            schemaVersion: 1,
            url: "https://example.com",
            title: "Example",
            description: "A page",
            imageURL: nil,
            domain: "example.com"
        )
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(LinkPayload.self, from: data)
        #expect(decoded == p)
    }

    @Test("YouTubePayload round-trip")
    func youtubeRoundTrip() throws {
        let p = YouTubePayload(
            schemaVersion: 1,
            videoId: "abc123",
            title: "Sermon",
            thumbnailURL: "https://img.youtube.com/vi/abc123/0.jpg",
            duration: "42:00"
        )
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(YouTubePayload.self, from: data)
        #expect(decoded == p)
    }

    @Test("EventPayload round-trip")
    func eventRoundTrip() throws {
        let p = EventPayload(
            schemaVersion: 1,
            title: "Sunday Service",
            startDate: Date(timeIntervalSince1970: 1_000_000),
            endDate: nil,
            location: "Main Sanctuary",
            rsvpCount: 0
        )
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(EventPayload.self, from: data)
        #expect(decoded == p)
    }

    @Test("MusicPayload round-trip")
    func musicRoundTrip() throws {
        let p = MusicPayload(
            schemaVersion: 1,
            title: "Amazing Grace",
            artist: "Chris Tomlin",
            artworkURL: nil,
            previewURL: nil,
            source: "Apple Music"
        )
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(MusicPayload.self, from: data)
        #expect(decoded == p)
    }

    @Test("VoicePayload round-trip")
    func voiceRoundTrip() throws {
        let p = VoicePayload(
            schemaVersion: 1,
            durationSeconds: 42.5,
            waveformData: [0.1, 0.5, 0.3],
            downloadURL: "https://storage.example.com/voice.m4a"
        )
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(VoicePayload.self, from: data)
        #expect(decoded == p)
    }

    @Test("AdaptiveComposerChecklistPayload round-trip")
    func checklistRoundTrip() throws {
        let item = AdaptiveComposerChecklistItem(id: "1", text: "Buy milk", isChecked: false, assigneeUID: nil)
        let p = AdaptiveComposerChecklistPayload(schemaVersion: 1, title: "Shopping", items: [item])
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(AdaptiveComposerChecklistPayload.self, from: data)
        #expect(decoded == p)
    }
}

// MARK: - RailState Filtering Tests

@Suite("RailState Filtering")
@MainActor
struct RailStateTests {

    @Test("Church-only tools excluded when not in church mode")
    func churchOnlyFiltered() {
        let vm = CreationRailViewModel.makeForSurface(.post)
        let tools = vm.availableTools(for: .post, isChurchMode: false)
        #expect(!tools.contains { $0.tier == .churchOnly })
    }

    @Test("Church-only tools included in church mode")
    func churchOnlyIncluded() {
        let ctx = ChurchComposerContext(churchId: "c1", churchName: "Grace", userRole: "member")
        let vm = CreationRailViewModel.makeForSurface(.churchSpace, churchContext: ctx)
        let tools = vm.availableTools(for: .churchSpace, isChurchMode: true)
        #expect(tools.contains { $0.tier == .churchOnly })
    }

    @Test("More tool always included")
    func moreAlwaysPresent() {
        for surface in ComposerSurface.allCases {
            let vm = CreationRailViewModel.makeForSurface(surface)
            let tools = vm.availableTools(for: surface, isChurchMode: false)
            #expect(tools.contains { $0.id == .more }, "More tool missing for \(surface.rawValue)")
        }
    }
}
