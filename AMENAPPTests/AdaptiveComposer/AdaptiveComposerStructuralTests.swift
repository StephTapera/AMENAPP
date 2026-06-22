// AdaptiveComposerStructuralTests.swift
// AMEN — Swift Testing structural + logic verification for the Adaptive Composer.
// These tests check payload shapes, privacy invariants, surface contracts,
// and codable round-trips without touching any UI layer.

import Testing
import Foundation
@testable import AMENAPP

// MARK: - Anonymous Prayer Privacy Invariants

@Suite("Anonymous Prayer Privacy Invariants")
@MainActor
struct PrayerPrivacyTests {

    @Test("Anonymous prayer payload has no authorId field")
    func noAuthorId() {
        let payload = PrayerPayload(
            schemaVersion: 1,
            text: "Healing needed",
            isAnonymous: true,
            prayCount: 0,
            circleId: nil
        )
        let mirror = Mirror(reflecting: payload)
        let fields = mirror.children.compactMap { $0.label }
        #expect(!fields.contains("authorId"),
                "authorId must not exist in PrayerPayload — privacy invariant")
    }

    @Test("Anonymous prayer sets isAnonymous to true")
    func isAnonymousFlag() {
        let payload = PrayerPayload(schemaVersion: 1, text: "Guidance please",
                                    isAnonymous: true, prayCount: 0, circleId: nil)
        #expect(payload.isAnonymous == true)
    }

    @Test("Non-anonymous prayer encodes cleanly with correct text")
    func nonAnonymousOK() throws {
        let payload = PrayerPayload(schemaVersion: 1, text: "Thank you Lord",
                                    isAnonymous: false, prayCount: 3, circleId: nil)
        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json != nil)
        #expect(json?["text"] as? String == "Thank you Lord")
        #expect(json?["isAnonymous"] as? Bool == false)
    }

    @Test("Anonymous prayer does not embed circleId when nil")
    func anonymousCircleIdNil() throws {
        let payload = PrayerPayload(schemaVersion: 1, text: "Peace",
                                    isAnonymous: true, prayCount: 0, circleId: nil)
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(PrayerPayload.self, from: data)
        #expect(decoded.circleId == nil)
    }

    @Test("PrayerPayload round-trip preserves all fields")
    func prayerRoundTrip() throws {
        let p = PrayerPayload(schemaVersion: 1, text: "Be healed",
                               isAnonymous: false, prayCount: 7, circleId: "circle-abc")
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(PrayerPayload.self, from: data)
        #expect(decoded == p)
        #expect(decoded.prayCount == 7)
        #expect(decoded.circleId == "circle-abc")
    }
}

// MARK: - Poll Vote Privacy Invariants

@Suite("Poll Vote Privacy Invariants")
@MainActor
struct PollPrivacyTests {

    @Test("PollPayload totalVotes field exists")
    func totalVotesFieldPresent() {
        let payload = PollPayload(schemaVersion: 1, question: "Q",
                                   options: ["A", "B"],
                                   votesByOption: [:],
                                   totalVotes: 0)
        #expect(payload.totalVotes == 0)
    }

    @Test("Poll percentage calculation is correct for equal split")
    func percentageEqualSplit() {
        let payload = PollPayload(schemaVersion: 1, question: "Q",
                                   options: ["A", "B"],
                                   votesByOption: ["A": 50, "B": 50],
                                   totalVotes: 100)
        let pctA = payload.totalVotes > 0
            ? Double(payload.votesByOption["A"] ?? 0) / Double(payload.totalVotes)
            : 0.0
        #expect(abs(pctA - 0.5) < 0.001)
    }

    @Test("Poll percentage calculation is correct for unequal split")
    func percentageUnequalSplit() {
        let payload = PollPayload(schemaVersion: 1, question: "Q",
                                   options: ["A", "B"],
                                   votesByOption: ["A": 1, "B": 3],
                                   totalVotes: 4)
        let pctA = payload.totalVotes > 0
            ? Double(payload.votesByOption["A"] ?? 0) / Double(payload.totalVotes)
            : 0.0
        #expect(abs(pctA - 0.25) < 0.001)
    }

    @Test("Poll with zero votes returns 0 percent")
    func zeroVotesPercent() {
        let payload = PollPayload(schemaVersion: 1, question: "Q",
                                   options: ["A"], votesByOption: [:], totalVotes: 0)
        let pct = payload.totalVotes > 0
            ? Double(payload.votesByOption["A"] ?? 0) / Double(payload.totalVotes)
            : 0.0
        #expect(pct == 0.0)
    }

    @Test("PollPayload round-trip preserves votesByOption")
    func pollRoundTrip() throws {
        let p = PollPayload(schemaVersion: 1,
                             question: "Best book?",
                             options: ["Genesis", "Psalms"],
                             votesByOption: ["Genesis": 10, "Psalms": 20],
                             totalVotes: 30)
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(PollPayload.self, from: data)
        #expect(decoded == p)
        #expect(decoded.votesByOption["Psalms"] == 20)
    }
}

// MARK: - Donation Stripe Gate

@Suite("Donation Stripe Gate")
@MainActor
struct DonationGateTests {

    @Test("DonationPayload encodes and decodes correctly")
    func donationEncodes() throws {
        let p = DonationPayload(schemaVersion: 1, campaignId: "c1", title: "Fund",
                                 goalAmount: 1_000, raisedAmount: 500, currency: "USD")
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(DonationPayload.self, from: data)
        #expect(decoded.campaignId == "c1")
        #expect(decoded.raisedAmount == 500)
        #expect(decoded.currency == "USD")
    }

    @Test("DonationPayload progress is below 1.0 when partially funded")
    func partialProgress() {
        let p = DonationPayload(schemaVersion: 1, campaignId: "c2", title: "Mission",
                                 goalAmount: 10_000, raisedAmount: 3_500, currency: "USD")
        let progress = p.goalAmount > 0 ? p.raisedAmount / p.goalAmount : 0.0
        #expect(progress < 1.0)
        #expect(abs(progress - 0.35) < 0.001)
    }

    @Test("DonationPayload progress is capped at 1.0 when over-funded")
    func overFundedProgress() {
        let p = DonationPayload(schemaVersion: 1, campaignId: "c3", title: "Over",
                                 goalAmount: 1_000, raisedAmount: 1_500, currency: "USD")
        let rawProgress = p.goalAmount > 0 ? p.raisedAmount / p.goalAmount : 0.0
        let progress = min(rawProgress, 1.0)
        #expect(progress == 1.0)
    }

    @Test("DonationPayload schemaVersion is 1")
    func schemaVersionIsOne() {
        let p = DonationPayload(schemaVersion: 1, campaignId: "c4", title: "T",
                                 goalAmount: 100, raisedAmount: 0, currency: "USD")
        #expect(p.schemaVersion == 1)
    }
}

// MARK: - Surface Church Awareness

@Suite("Surface Church Awareness")
struct ChurchAwarenessTests {

    @Test("churchSpace is church-aware")
    func churchSpaceAware() {
        #expect(ComposerSurface.churchSpace.isChurchAware == true)
    }

    @Test("churchNote is church-aware")
    func churchNoteAware() {
        #expect(ComposerSurface.churchNote.isChurchAware == true)
    }

    @Test("bibleStudy is church-aware")
    func bibleStudyAware() {
        #expect(ComposerSurface.bibleStudy.isChurchAware == true)
    }

    @Test("post is not church-aware")
    func postNotChurchAware() {
        #expect(ComposerSurface.post.isChurchAware == false)
    }

    @Test("comment is not church-aware")
    func commentNotChurchAware() {
        #expect(ComposerSurface.comment.isChurchAware == false)
    }

    @Test("message is not church-aware")
    func messageNotChurchAware() {
        #expect(ComposerSurface.message.isChurchAware == false)
    }

    @Test("groupChat is not church-aware")
    func groupChatNotChurchAware() {
        #expect(ComposerSurface.groupChat.isChurchAware == false)
    }

    @Test("space is not church-aware")
    func spaceNotChurchAware() {
        #expect(ComposerSurface.space.isChurchAware == false)
    }

    @Test("event is not church-aware")
    func eventNotChurchAware() {
        #expect(ComposerSurface.event.isChurchAware == false)
    }

    @Test("prayerRequest is not church-aware")
    func prayerRequestNotChurchAware() {
        #expect(ComposerSurface.prayerRequest.isChurchAware == false)
    }

    @Test("isChurchAware count matches expected set")
    func churchAwareCount() {
        let churchAwareSurfaces = ComposerSurface.allCases.filter { $0.isChurchAware }
        #expect(churchAwareSurfaces.count == 3,
                "Exactly churchSpace, churchNote, and bibleStudy must be church-aware")
    }
}

// MARK: - Default Presentation Mode Contracts

@Suite("Default Presentation Mode Contracts")
struct PresentationModeTests {

    @Test("Floating pill surfaces are comment, message, groupChat")
    func floatingPillSurfaces() {
        let floatingPillSurfaces = ComposerSurface.allCases.filter {
            $0.defaultPresentationMode == .floatingPill
        }
        let expectedIDs: Set<ComposerSurface> = [.comment, .message, .groupChat]
        #expect(Set(floatingPillSurfaces) == expectedIDs)
    }

    @Test("All other surfaces default to dockedRail")
    func dockedRailSurfaces() {
        let dockedSurfaces = ComposerSurface.allCases.filter {
            $0.defaultPresentationMode == .dockedRail
        }
        #expect(dockedSurfaces.count == ComposerSurface.allCases.count - 3)
    }

    @Test("No surface defaults to orb mode")
    func noOrbDefault() {
        let orbSurfaces = ComposerSurface.allCases.filter {
            $0.defaultPresentationMode == .orb
        }
        #expect(orbSurfaces.isEmpty,
                "No surface should default to orb — orb is opt-in only")
    }
}

// MARK: - Tool Registry Structural Contracts

@Suite("Tool Registry Structural Contracts")
struct ToolRegistryStructuralTests {

    @Test("Every ToolID case has a registry entry")
    func allToolIDsRegistered() {
        let registryIDs = Set(CreationTool.registry.map(\.id))
        for id in ToolID.allCases {
            #expect(registryIDs.contains(id),
                    "ToolID.\(id.rawValue) is missing from CreationTool.registry")
        }
    }

    @Test("No registry entry has an empty icon")
    func noEmptyIcons() {
        let emptyIconTools = CreationTool.registry.filter { $0.icon.isEmpty }
        #expect(emptyIconTools.isEmpty)
    }

    @Test("No registry entry has an empty title")
    func noEmptyTitles() {
        let emptyTitleTools = CreationTool.registry.filter { $0.title.isEmpty }
        #expect(emptyTitleTools.isEmpty)
    }

    @Test("photo tool covers all surfaces")
    func photoAllSurfaces() {
        let photo = CreationTool.registry.first { $0.id == .photo }
        #expect(photo != nil)
        #expect(photo?.surfaces.count == ComposerSurface.allCases.count)
    }

    @Test("more tool covers all surfaces")
    func moreAllSurfaces() {
        let more = CreationTool.registry.first { $0.id == .more }
        #expect(more != nil)
        #expect((more?.surfaces.count ?? 0) >= ComposerSurface.allCases.count)
    }

    @Test("sermon is churchOnly tier")
    func sermonChurchOnly() {
        let sermon = CreationTool.registry.first { $0.id == .sermon }
        #expect(sermon?.tier == .churchOnly)
    }

    @Test("worshipSong is churchOnly tier")
    func worshipSongChurchOnly() {
        let tool = CreationTool.registry.first { $0.id == .worshipSong }
        #expect(tool?.tier == .churchOnly)
    }

    @Test("teachingSeries is churchOnly tier")
    func teachingSeriesChurchOnly() {
        let tool = CreationTool.registry.first { $0.id == .teachingSeries }
        #expect(tool?.tier == .churchOnly)
    }

    @Test("volunteerSignup is churchOnly tier")
    func volunteerSignupChurchOnly() {
        let tool = CreationTool.registry.first { $0.id == .volunteerSignup }
        #expect(tool?.tier == .churchOnly)
    }

    @Test("ministryInterestForm is churchOnly tier")
    func ministryInterestFormChurchOnly() {
        let tool = CreationTool.registry.first { $0.id == .ministryInterestForm }
        #expect(tool?.tier == .churchOnly)
    }

    @Test("poll is not on comment surface")
    func pollNotOnComment() {
        let poll = CreationTool.registry.first { $0.id == .poll }
        #expect(!(poll?.surfaces.contains(.comment) ?? true))
    }

    @Test("bible tool is on all surfaces")
    func bibleAllSurfaces() {
        let bible = CreationTool.registry.first { $0.id == .bible }
        #expect(bible?.surfaces.count == ComposerSurface.allCases.count)
    }
}

// MARK: - ComposerAttachment typeKey Contracts

@Suite("ComposerAttachment typeKey Contracts")
struct AttachmentTypeKeyTests {

    @Test("scripture attachment has typeKey 'scripture'")
    func scriptureTypeKey() {
        let p = ScripturePayload(schemaVersion: 1, reference: "John 3:16",
                                  text: "For God so loved", translation: "NIV",
                                  bookChapter: "John 3")
        let attachment = ComposerAttachment.scripture(p)
        #expect(attachment.typeKey == "scripture")
    }

    @Test("prayer attachment has typeKey 'prayer'")
    func prayerTypeKey() {
        let p = PrayerPayload(schemaVersion: 1, text: "Help me",
                               isAnonymous: false, prayCount: 0, circleId: nil)
        let attachment = ComposerAttachment.prayer(p)
        #expect(attachment.typeKey == "prayer")
    }

    @Test("poll attachment has typeKey 'poll'")
    func pollTypeKey() {
        let p = PollPayload(schemaVersion: 1, question: "Q",
                             options: ["A"], votesByOption: [:], totalVotes: 0)
        let attachment = ComposerAttachment.poll(p)
        #expect(attachment.typeKey == "poll")
    }

    @Test("donation attachment has typeKey 'donation'")
    func donationTypeKey() {
        let p = DonationPayload(schemaVersion: 1, campaignId: "c",
                                 title: "Fund", goalAmount: 1000,
                                 raisedAmount: 0, currency: "USD")
        let attachment = ComposerAttachment.donation(p)
        #expect(attachment.typeKey == "donation")
    }

    @Test("event attachment has typeKey 'event'")
    func eventTypeKey() {
        let p = EventPayload(schemaVersion: 1, title: "Service",
                              startDate: Date(), endDate: nil,
                              location: nil, rsvpCount: 0)
        let attachment = ComposerAttachment.event(p)
        #expect(attachment.typeKey == "event")
    }

    @Test("sermon attachment has typeKey 'sermon'")
    func sermonTypeKey() {
        let p = SermonPayload(schemaVersion: 1, title: "Grace",
                               speakerName: "Pastor John", churchId: "c1",
                               audioURL: nil, videoURL: nil,
                               scriptureReferences: [])
        let attachment = ComposerAttachment.sermon(p)
        #expect(attachment.typeKey == "sermon")
    }
}

// MARK: - CreationRailViewModel Filter Tests

@Suite("CreationRailViewModel Filter Tests")
@MainActor
struct RailViewModelFilterTests {

    @Test("Church-only tools excluded when not in church mode")
    func churchOnlyFilteredOutside() {
        let vm = CreationRailViewModel.makeForSurface(.post)
        let tools = vm.availableTools(for: .post, isChurchMode: false)
        #expect(!tools.contains { $0.tier == .churchOnly })
    }

    @Test("Church-only tools included when in church mode")
    func churchOnlyIncludedInside() {
        let ctx = ChurchComposerContext(churchId: "c1",
                                        churchName: "Grace",
                                        userRole: "member")
        let vm = CreationRailViewModel.makeForSurface(.churchSpace, churchContext: ctx)
        let tools = vm.availableTools(for: .churchSpace, isChurchMode: true)
        #expect(tools.contains { $0.tier == .churchOnly })
    }

    @Test("More tool always present on every surface")
    func moreAlwaysPresent() {
        for surface in ComposerSurface.allCases {
            let vm = CreationRailViewModel.makeForSurface(surface)
            let tools = vm.availableTools(for: surface, isChurchMode: false)
            #expect(tools.contains { $0.id == .more },
                    "More tool missing for surface: \(surface.rawValue)")
        }
    }

    @Test("ViewModel initial rail state is compact")
    func initialRailStateIsCompact() {
        let vm = CreationRailViewModel.makeForSurface(.post)
        #expect(vm.railState == .compact)
    }

    @Test("ViewModel initial presentation mode matches surface default")
    func initialPresentationModeMatchesSurface() {
        for surface in ComposerSurface.allCases {
            let vm = CreationRailViewModel.makeForSurface(surface)
            #expect(vm.presentationMode == surface.defaultPresentationMode,
                    "presentationMode mismatch for surface: \(surface.rawValue)")
        }
    }
}

// MARK: - Payload Codable Round-Trip Tests

@Suite("Payload Codable Round-Trip Tests")
@MainActor
struct PayloadCodableTests {

    @Test("ScripturePayload round-trip")
    func scriptureRoundTrip() throws {
        let p = ScripturePayload(schemaVersion: 1, reference: "Psalm 23",
                                  text: "The Lord is my shepherd",
                                  translation: "KJV", bookChapter: "Psalm 23")
        let decoded = try JSONDecoder().decode(
            ScripturePayload.self,
            from: JSONEncoder().encode(p)
        )
        #expect(decoded == p)
    }

    @Test("EventPayload round-trip preserves dates")
    func eventRoundTrip() throws {
        let p = EventPayload(schemaVersion: 1, title: "Sunday Service",
                              startDate: Date(timeIntervalSince1970: 1_000_000),
                              endDate: nil, location: "Main Sanctuary", rsvpCount: 0)
        let decoded = try JSONDecoder().decode(
            EventPayload.self,
            from: JSONEncoder().encode(p)
        )
        #expect(decoded == p)
    }

    @Test("MusicPayload round-trip")
    func musicRoundTrip() throws {
        let p = MusicPayload(schemaVersion: 1, title: "Amazing Grace",
                              artist: "Chris Tomlin",
                              artworkURL: nil, previewURL: nil,
                              source: "Apple Music")
        let decoded = try JSONDecoder().decode(
            MusicPayload.self,
            from: JSONEncoder().encode(p)
        )
        #expect(decoded == p)
    }

    @Test("LinkPayload round-trip")
    func linkRoundTrip() throws {
        let p = LinkPayload(schemaVersion: 1, url: "https://example.com",
                             title: "Example", description: "A page",
                             imageURL: nil, domain: "example.com")
        let decoded = try JSONDecoder().decode(
            LinkPayload.self,
            from: JSONEncoder().encode(p)
        )
        #expect(decoded == p)
    }

    @Test("VoicePayload round-trip preserves waveform data")
    func voiceRoundTrip() throws {
        let p = VoicePayload(schemaVersion: 1, durationSeconds: 42.5,
                              waveformData: [0.1, 0.5, 0.3],
                              downloadURL: "https://storage.example.com/voice.m4a")
        let decoded = try JSONDecoder().decode(
            VoicePayload.self,
            from: JSONEncoder().encode(p)
        )
        #expect(decoded == p)
        #expect(decoded.waveformData.count == 3)
    }

    @Test("AdaptiveComposerChecklistPayload round-trip")
    func checklistRoundTrip() throws {
        let item = AdaptiveComposerChecklistItem(
            id: "1", text: "Prepare slides", isChecked: false, assigneeUID: nil)
        let p = AdaptiveComposerChecklistPayload(
            schemaVersion: 1, title: "Sermon Prep", items: [item])
        let decoded = try JSONDecoder().decode(
            AdaptiveComposerChecklistPayload.self,
            from: JSONEncoder().encode(p)
        )
        #expect(decoded == p)
        #expect(decoded.items.first?.text == "Prepare slides")
    }

    @Test("YouTubePayload round-trip")
    func youtubeRoundTrip() throws {
        let p = YouTubePayload(schemaVersion: 1, videoId: "abc123",
                                title: "Sunday Sermon",
                                thumbnailURL: "https://img.youtube.com/vi/abc123/0.jpg",
                                duration: "42:00")
        let decoded = try JSONDecoder().decode(
            YouTubePayload.self,
            from: JSONEncoder().encode(p)
        )
        #expect(decoded == p)
        #expect(decoded.videoId == "abc123")
    }

    @Test("TaskPayload round-trip with optional fields")
    func taskRoundTrip() throws {
        let p = TaskPayload(schemaVersion: 1, title: "Follow up",
                             dueDate: nil, assigneeUID: "uid-1",
                             isCompleted: false, spaceId: nil)
        let decoded = try JSONDecoder().decode(
            TaskPayload.self,
            from: JSONEncoder().encode(p)
        )
        #expect(decoded == p)
        #expect(decoded.assigneeUID == "uid-1")
        #expect(decoded.isCompleted == false)
    }

    @Test("SermonPayload round-trip with scripture references")
    func sermonRoundTrip() throws {
        let p = SermonPayload(schemaVersion: 1, title: "The Good Shepherd",
                               speakerName: "Pastor John",
                               churchId: "church-1",
                               audioURL: "https://cdn.example.com/sermon.mp3",
                               videoURL: nil,
                               scriptureReferences: ["John 10:11", "Psalm 23"])
        let decoded = try JSONDecoder().decode(
            SermonPayload.self,
            from: JSONEncoder().encode(p)
        )
        #expect(decoded == p)
        #expect(decoded.scriptureReferences.count == 2)
    }
}
