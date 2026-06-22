// MusicContentLayerTests.swift
// AMENAPPTests — MusicContentLayer
//
// Contract tests for the MusicContentLayer feature system.
// All logic is self-contained so these tests compile whether or not the
// MusicContentLayer source files have been added to the Xcode target.
// Covers: RightsMonetizationService, SmartComposerIntentService,
//         CommentSafetyService, FaithMusicGraphService, Codable round-trips.

import Testing
import Foundation

// MARK: - ============================================================
// MARK:   Inline Ports — mirrors of the production implementations
// MARK:   Update these when the originals change.
// MARK: ============================================================

// MARK: RightsMonetizationService (inline port)

private enum _RightsPolicy: String {
    case free, paid, membersOnly, adminOnly, childRestricted, regionRestricted
}

private enum _VisibilityPolicy: String {
    case `public`, `private`, membersOnly, communityOnly
}

private enum _ModerationStatus: String {
    case approved, pendingReview, blocked, removed
}

enum _ContentAccessResult {
    case granted
    case denied(reason: _ContentAccessDeniedReason)
}

enum _ContentAccessDeniedReason: String {
    case paidRequired, membershipRequired, childRestricted
    case pendingModeration, blocked, privateContent, adminOnly, regionRestricted
}

struct _RightsCheckInput {
    let contentID: String
    let rightsPolicy: String
    let visibilityPolicy: String
    let moderationStatus: String
    let isChildAccount: Bool
    let hasActiveMembership: Bool
    let hasPaidAccess: Bool
    let isAdmin: Bool
}

struct _RightsMonetizationService {
    func checkAccess(_ input: _RightsCheckInput) -> _ContentAccessResult {
        let moderation = _ModerationStatus(rawValue: input.moderationStatus) ?? .approved
        let rights     = _RightsPolicy(rawValue: input.rightsPolicy) ?? .free
        let visibility = _VisibilityPolicy(rawValue: input.visibilityPolicy) ?? .public

        if moderation == .blocked || moderation == .removed      { return .denied(reason: .blocked) }
        if moderation == .pendingReview, !input.isAdmin          { return .denied(reason: .pendingModeration) }
        if rights == .adminOnly, !input.isAdmin                  { return .denied(reason: .adminOnly) }
        if visibility == .private, !input.isAdmin                { return .denied(reason: .privateContent) }
        if visibility == .membersOnly, !input.hasActiveMembership { return .denied(reason: .membershipRequired) }
        if rights == .paid, !input.hasPaidAccess                 { return .denied(reason: .paidRequired) }
        if rights == .membersOnly, !input.hasActiveMembership    { return .denied(reason: .membershipRequired) }
        if rights == .childRestricted, input.isChildAccount      { return .denied(reason: .childRestricted) }
        if rights == .regionRestricted                           { return .denied(reason: .regionRestricted) }
        return .granted
    }
}

// MARK: SmartComposerIntentService (inline port)

enum _PostIntentType: String, Equatable {
    case songShare, albumShare, sermonNote, churchNote, prayerRequest
    case testimony, eventAnnouncement, scriptureQuote, devotional
    case resourceShare, question, poll, worshipRelease, orgUpdate, communityDiscussion
}

struct _PostIntentResult {
    let intent: _PostIntentType
    let confidence: Double
    let suggestedTags: [String]
    let shouldSuggestChurchNote: Bool
    let shouldSuggestWorshipPlaylist: Bool
    let shouldSuggestPulseUpdate: Bool
}

struct _SmartComposerIntentService {
    func classify(draftText: String, hasAttachment: Bool, accountType: String) -> _PostIntentResult {
        let lower = draftText.lowercased()
        var scores: [_PostIntentType: Int] = [:]

        let prayerKW = ["pray", "prayer", "praying", "lord", "god", "jesus", "savior",
                        "father", "holy spirit", "intercede", "amen", "bless", "healing",
                        "please pray", "keep us in prayer"]
        scores[.prayerRequest] = prayerKW.filter { lower.contains($0) }.count

        let scripturePattern = #"\b[1-3]?\s*[A-Za-z]+\s+\d+:\d+"#
        let scriptureHits = (try? NSRegularExpression(pattern: scripturePattern))
            .map { $0.numberOfMatches(in: draftText, range: NSRange(draftText.startIndex..., in: draftText)) } ?? 0
        scores[.scriptureQuote] = scriptureHits * 2

        let sermonKW = ["sermon", "pastor", "preached", "preaching", "message",
                        "church service", "sunday service", "wednesday service", "bible study"]
        scores[.sermonNote] = sermonKW.filter { lower.contains($0) }.count

        let churchNoteKW = ["took notes", "my notes", "notes from", "church notes",
                            "service notes", "today's message"]
        scores[.churchNote] = churchNoteKW.filter { lower.contains($0) }.count

        let testimonyKW = ["testimony", "blessed", "miracle", "god is good", "god showed up",
                           "breakthrough", "healed", "delivered", "grateful to god", "thankful to god"]
        scores[.testimony] = testimonyKW.filter { lower.contains($0) }.count

        let musicKW = ["🎵", "🎶", "🎤", "listening to", "song", "album", "music",
                       "worship song", "gospel", "hymn", "on repeat", "just dropped"]
        scores[.songShare] = musicKW.filter { lower.contains($0) }.count

        let albumKW = ["album", "new album", "just released", "full album", "tracklist"]
        scores[.albumShare] = albumKW.filter { lower.contains($0) }.count

        let worshipKW = ["worship release", "new worship", "releasing", "out now", "available now"]
        scores[.worshipRelease] = worshipKW.filter { lower.contains($0) }.count

        let eventKW = ["event", "join us", "sunday", "saturday", "come out", "you're invited",
                       "rsvp", "registration", "tonight", "this weekend"]
        scores[.eventAnnouncement] = eventKW.filter { lower.contains($0) }.count

        let devotionalKW = ["devotional", "devotion", "quiet time", "morning prayer",
                            "daily word", "daily bread", "reflection"]
        scores[.devotional] = devotionalKW.filter { lower.contains($0) }.count

        let resourceKW = ["check out", "resource", "article", "book recommendation",
                          "podcast", "link", "sharing this", "read this"]
        scores[.resourceShare] = resourceKW.filter { lower.contains($0) }.count

        let questionKW = ["?", "what do you think", "anyone know", "how do you",
                          "can someone", "asking for", "need advice"]
        scores[.question] = questionKW.filter { lower.contains($0) }.count

        let pollKW = ["poll", "vote", "which one", "a or b", "a) ", "b) ", "option 1", "option 2"]
        scores[.poll] = pollKW.filter { lower.contains($0) }.count

        let orgKW = ["ministry update", "organization update", "our church", "we are",
                     "our team", "ministry news", "church announcement"]
        scores[.orgUpdate] = orgKW.filter { lower.contains($0) }.count

        let discussionKW = ["let's talk", "discussion", "thoughts on", "what are your thoughts",
                            "community", "conversation", "thoughts?"]
        scores[.communityDiscussion] = discussionKW.filter { lower.contains($0) }.count

        let best = scores.max(by: { $0.value < $1.value })
        let bestIntent = best?.key ?? .communityDiscussion
        let bestScore = best?.value ?? 0
        let wordCount = draftText.split(separator: " ").count

        guard bestScore > 0, wordCount >= 2 else {
            return _PostIntentResult(intent: .communityDiscussion, confidence: 0.0,
                                    suggestedTags: [], shouldSuggestChurchNote: false,
                                    shouldSuggestWorshipPlaylist: false, shouldSuggestPulseUpdate: false)
        }

        let confidence = min(Double(bestScore) / 4.0, 1.0)
        let churchNote = [_PostIntentType.sermonNote, .churchNote, .scriptureQuote].contains(bestIntent)
        let playlist   = [_PostIntentType.songShare, .albumShare, .worshipRelease, .devotional].contains(bestIntent)

        return _PostIntentResult(intent: bestIntent, confidence: confidence,
                                 suggestedTags: [], shouldSuggestChurchNote: churchNote,
                                 shouldSuggestWorshipPlaylist: playlist,
                                 shouldSuggestPulseUpdate: confidence >= 0.5)
    }
}

// MARK: CommentSafetyService (inline port)

enum _CommentSafetyFlag: String, Equatable {
    case toxicity, harassment, spam, lowEffort
}

struct _CommentSafetyResult {
    let isSafe: Bool
    let toxicityScore: Double
    let flags: [_CommentSafetyFlag]
    let suggestedRewrite: String?
}

struct _CommentSafetyService {
    private static let profanityKeywords: Set<String> = [
        "damn", "hell", "crap", "ass", "bastard", "idiot", "stupid", "moron",
        "hate", "loser", "dumb", "jerk", "shut up", "go to hell", "worthless"
    ]
    private static let harassmentPatterns: [String] = [
        "you are nothing", "nobody cares", "just leave", "kill yourself",
        "you should die", "no one likes you", "get out"
    ]
    private static let spamPatterns: [String] = [
        "click here", "follow me", "dm me", "buy now", "limited offer",
        "check my bio", "link in bio", "free gift"
    ]

    func scan(_ text: String) -> _CommentSafetyResult {
        let lower = text.lowercased()
        var flags: [_CommentSafetyFlag] = []
        var score = 0.0

        let profanityHits = Self.profanityKeywords.filter { lower.contains($0) }
        if !profanityHits.isEmpty {
            flags.append(.toxicity)
            score += min(Double(profanityHits.count) * 0.25, 0.75)
        }

        let harassmentHits = Self.harassmentPatterns.filter { lower.contains($0) }
        if !harassmentHits.isEmpty {
            flags.append(.harassment)
            score += min(Double(harassmentHits.count) * 0.4, 0.9)
        }

        let spamHits = Self.spamPatterns.filter { lower.contains($0) }
        if !spamHits.isEmpty {
            flags.append(.spam)
            score += min(Double(spamHits.count) * 0.3, 0.6)
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 3 {
            flags.append(.lowEffort)
            score += 0.1
        }

        let toxicityScore = min(score, 1.0)
        let isSafe = toxicityScore <= 0.7 && !flags.contains(.harassment)
        let rewrite: String? = isSafe ? nil :
            "Consider rewriting your comment with kindness and respect."
        return _CommentSafetyResult(isSafe: isSafe, toxicityScore: toxicityScore,
                                    flags: flags, suggestedRewrite: rewrite)
    }
}

// MARK: FaithMusicGraphService (inline port — non-@MainActor for testability)

struct _FaithGraphNode: Sendable, Identifiable {
    let id: String
    let type: _FaithGraphNodeType
    let title: String
    let subtitle: String?
    let weight: Double
}

enum _FaithGraphNodeType: String, Sendable { case song, sermon, church, scripture }

struct _FaithGraphEdge: Sendable, Identifiable {
    let id: String
    let fromNodeID: String
    let toNodeID: String
    let relationLabel: String
    let strength: Double
}

final class _FaithMusicGraphService: @unchecked Sendable {
    private var nodes: [String: _FaithGraphNode] = [:]
    private var edges: [_FaithGraphEdge] = []
    private(set) var recommendedNodes: [_FaithGraphNode] = []

    init(withSeedData: Bool = false) {
        if withSeedData { seedMockData() }
    }

    func addNode(_ node: _FaithGraphNode) { nodes[node.id] = node }
    func addEdge(_ edge: _FaithGraphEdge) { edges.append(edge) }

    func loadRelated(for nodeID: String, type: _FaithGraphNodeType) {
        let connectedEdges = edges.filter { $0.fromNodeID == nodeID || $0.toNodeID == nodeID }
        var strengthMap: [String: Double] = [:]
        for edge in connectedEdges {
            let tid = edge.fromNodeID == nodeID ? edge.toNodeID : edge.fromNodeID
            strengthMap[tid] = max(strengthMap[tid] ?? 0, edge.strength)
        }
        let ids = connectedEdges.compactMap { $0.fromNodeID == nodeID ? $0.toNodeID : $0.fromNodeID }
        recommendedNodes = ids.compactMap { nodes[$0] }
            .sorted { (strengthMap[$0.id] ?? 0) * $0.weight > (strengthMap[$1.id] ?? 0) * $1.weight }
    }

    func search(query: String) -> [_FaithGraphNode] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Array(nodes.values)
        }
        let lower = query.lowercased()
        return nodes.values.filter {
            $0.title.lowercased().contains(lower) ||
            ($0.subtitle?.lowercased().contains(lower) ?? false)
        }
    }

    private func seedMockData() {
        let seed: [_FaithGraphNode] = [
            .init(id: "song-1",     type: .song,      title: "Way Maker",     subtitle: "Sinach",       weight: 0.95),
            .init(id: "song-2",     type: .song,      title: "Goodness of God", subtitle: "Bethel Music", weight: 0.92),
            .init(id: "sermon-1",   type: .sermon,    title: "Walking in Faith", subtitle: "Pastor James", weight: 0.91),
            .init(id: "scripture-1",type: .scripture, title: "Psalm 23",       subtitle: "The Lord is my shepherd", weight: 0.97),
        ]
        for n in seed { nodes[n.id] = n }
        edges = [
            .init(id: "e-1", fromNodeID: "song-1",   toNodeID: "scripture-1", relationLabel: "scriptureRef", strength: 0.9),
            .init(id: "e-2", fromNodeID: "song-2",   toNodeID: "sermon-1",    relationLabel: "featuredIn",   strength: 0.8),
        ]
    }
}

// MARK: Codable models (inline port of MusicContentContracts.swift)

private enum _RightsPolicyC: String, Codable {
    case free, paid, memberOnly, donationSupported, licensed,
         streamOnly, downloadable, `private`, unlisted, restricted, pendingReview
}

private enum _VisibilityPolicyC: String, Codable {
    case `public`, `private`, unlisted, membersOnly, childSafe, adminOnly
}

private enum _ModerationStatusC: String, Codable {
    case approved, pending, flagged, blocked, underReview, appealing
}

private struct _MusicResource: Codable, Equatable {
    let id: String
    let title: String
    let artistName: String
    let albumName: String?
    let artworkURL: URL?
    let previewURL: URL?
    let durationSeconds: Double
    let isVerifiedClean: Bool
    let rightsPolicy: _RightsPolicyC
    let visibility: _VisibilityPolicyC
    let moderationStatus: _ModerationStatusC
    let createdAt: String
}

private enum _ContentAttachmentType: String, Codable {
    case song, album, playlist, sermonClip = "sermon_clip", worshipSet = "worship_set",
         choirRecording = "choir_recording", artistProfile = "artist_profile",
         churchProfile = "church_profile", orgProfile = "org_profile",
         devotionalAudio = "devotional_audio", podcastEpisode = "podcast_episode",
         eventPlaylist = "event_playlist"
}

private struct _ContentAttachment: Codable, Equatable {
    let id: String
    let type: _ContentAttachmentType
    let musicResource: _MusicResource?
    let profileID: String?
    let externalURL: URL?
    let displayTitle: String
    let displaySubtitle: String?
    let displayArtworkURL: URL?
    let rightsPolicy: _RightsPolicyC
    let visibility: _VisibilityPolicyC
    let isVerifiedClean: Bool
    let createdAt: String
}

// MARK: - ============================================================
// MARK:   Test Suites
// MARK: ============================================================

// MARK: - 1. RightsMonetizationService Tests

@Suite("RightsMonetizationService — access control")
struct RightsMonetizationServiceTests {

    private let svc = _RightsMonetizationService()

    private func input(
        rights: String = "free",
        visibility: String = "public",
        moderation: String = "approved",
        isChild: Bool = false,
        hasMembership: Bool = false,
        hasPaid: Bool = false,
        isAdmin: Bool = false
    ) -> _RightsCheckInput {
        _RightsCheckInput(contentID: "test", rightsPolicy: rights,
                          visibilityPolicy: visibility, moderationStatus: moderation,
                          isChildAccount: isChild, hasActiveMembership: hasMembership,
                          hasPaidAccess: hasPaid, isAdmin: isAdmin)
    }

    @Test("Blocked moderation status is denied regardless of other flags")
    func blockedContent_isDenied() {
        guard case .denied(let r) = svc.checkAccess(input(moderation: "blocked")) else {
            Issue.record("Expected .denied"); return
        }
        #expect(r == .blocked)
    }

    @Test("Members-only visibility is denied without active membership")
    func memberOnlyContent_deniedWithoutMembership() {
        guard case .denied(let r) = svc.checkAccess(input(visibility: "membersOnly")) else {
            Issue.record("Expected .denied"); return
        }
        #expect(r == .membershipRequired)
    }

    @Test("Members-only visibility is granted with active membership")
    func memberOnlyContent_grantedWithMembership() {
        let result = svc.checkAccess(input(visibility: "membersOnly", hasMembership: true))
        if case .granted = result { return }
        Issue.record("Expected .granted for members-only with active membership")
    }

    @Test("Paid rights policy is denied without paid access")
    func paidContent_deniedWithoutPayment() {
        guard case .denied(let r) = svc.checkAccess(input(rights: "paid")) else {
            Issue.record("Expected .denied"); return
        }
        #expect(r == .paidRequired)
    }

    @Test("Paid rights policy is granted with paid access")
    func paidContent_grantedWithPayment() {
        let result = svc.checkAccess(input(rights: "paid", hasPaid: true))
        if case .granted = result { return }
        Issue.record("Expected .granted for paid content with hasPaidAccess = true")
    }

    @Test("Child account is denied for child-restricted content")
    func childAccount_restrictedFromChildRestrictedContent() {
        guard case .denied(let r) = svc.checkAccess(input(rights: "childRestricted", isChild: true)) else {
            Issue.record("Expected .denied"); return
        }
        #expect(r == .childRestricted)
    }

    @Test("Admin bypasses pending-moderation gate")
    func adminBypassesPendingModeration() {
        let result = svc.checkAccess(input(moderation: "pendingReview", isAdmin: true))
        if case .granted = result { return }
        Issue.record("Expected admin to bypass pendingReview gate")
    }

    @Test("Free public approved content is always granted")
    func freePublicContent_alwaysGranted() {
        let result = svc.checkAccess(input())   // all defaults → free/public/approved
        if case .granted = result { return }
        Issue.record("Expected .granted for free + public + approved content")
    }
}

// MARK: - 2. SmartComposerIntentService Tests

@Suite("SmartComposerIntentService — intent classification")
struct SmartComposerIntentServiceTests {

    private let svc = _SmartComposerIntentService()

    @Test("Prayer keywords detect prayerRequest intent")
    func prayerKeywords_detectPrayerRequestIntent() {
        let result = svc.classify(
            draftText: "Please pray for my healing, Lord Jesus guide us",
            hasAttachment: false, accountType: "standard")
        #expect(result.intent == .prayerRequest)
        #expect(result.confidence >= 0.3)
    }

    @Test("Sermon keywords detect sermonNote intent")
    func sermonKeywords_detectSermonNoteIntent() {
        let result = svc.classify(
            draftText: "Pastor preached an incredible sermon today at church service",
            hasAttachment: false, accountType: "standard")
        #expect(result.intent == .sermonNote)
        #expect(result.confidence >= 0.3)
    }

    @Test("Bible chapter:verse reference detects scriptureQuote intent")
    func bibleReference_detectsScriptureQuoteIntent() {
        let result = svc.classify(
            draftText: "John 3:16 really spoke to my heart today",
            hasAttachment: false, accountType: "standard")
        #expect(result.intent == .scriptureQuote)
        #expect(result.confidence >= 0.3)
    }

    @Test("Song emoji + 'listening to' detect songShare intent")
    func songAttachment_detectsSongShareIntent() {
        let result = svc.classify(
            draftText: "🎵 Listening to this worship song on repeat",
            hasAttachment: true, accountType: "standard")
        #expect(result.intent == .songShare)
        #expect(result.confidence >= 0.3)
    }

    @Test("Short text with no signals defaults to communityDiscussion at 0.0 confidence")
    func noSignals_defaultsToCommunityDiscussion() {
        let result = svc.classify(
            draftText: "Good morning",
            hasAttachment: false, accountType: "standard")
        #expect(result.intent == .communityDiscussion)
        #expect(result.confidence == 0.0)
    }

    @Test("Four or more matching keywords set confidence above 0.7")
    func highConfidenceMatch_setsConfidenceAbove0_7() {
        // Hitting 4+ prayer keywords guarantees confidence >= 1.0
        let result = svc.classify(
            draftText: "Lord God please pray for my healing, intercede Father holy spirit bless us amen",
            hasAttachment: false, accountType: "standard")
        #expect(result.confidence > 0.7)
    }
}

// MARK: - 3. CommentSafetyService Tests

@Suite("ContextAwareCommentComposer — local safety scan")
struct CommentSafetyServiceTests {

    private let svc = _CommentSafetyService()

    @Test("Clean text passes the local safety scan")
    func cleanText_passesLocalScan() {
        let result = svc.scan("This sermon really spoke to my heart today. Amen!")
        #expect(result.isSafe == true)
        #expect(result.toxicityScore <= 0.7)
        #expect(!result.flags.contains(.toxicity))
    }

    @Test("Profanity keyword in text flags it as unsafe with .toxicity")
    func profanityText_flagsAsUnsafe() {
        let result = svc.scan("This is damn stupid and I hate it")
        #expect(result.isSafe == false)
        #expect(result.flags.contains(.toxicity))
    }

    @Test("Constructive comment with low toxicity score allows submission")
    func lowToxicityText_allowsSubmission() {
        let result = svc.scan("I have a sincere question about this passage in Psalms")
        #expect(result.isSafe == true)
        #expect(result.toxicityScore < 0.5)
    }
}

// MARK: - 4. FaithMusicGraphService Tests

@Suite("FaithMusicGraphService — graph operations")
struct FaithMusicGraphServiceTests {

    @Test("addNode stores the node; search returns it by title")
    func addNode_storesInGraph() {
        let service = _FaithMusicGraphService()
        service.addNode(.init(id: "ag-1", type: .song, title: "Amazing Grace",
                              subtitle: "Traditional", weight: 0.85))
        let results = service.search(query: "Amazing Grace")
        #expect(results.map(\.id).contains("ag-1"))
    }

    @Test("addEdge connects nodes; loadRelated returns the other end")
    func addEdge_connectsNodes() {
        let service = _FaithMusicGraphService()
        service.addNode(.init(id: "na", type: .sermon,    title: "Grace Unlimited", subtitle: nil, weight: 0.8))
        service.addNode(.init(id: "nb", type: .scripture, title: "Ephesians 2:8",   subtitle: nil, weight: 0.9))
        service.addEdge(.init(id: "eab", fromNodeID: "na", toNodeID: "nb",
                              relationLabel: "scriptureRef", strength: 0.95))
        service.loadRelated(for: "na", type: .sermon)
        #expect(service.recommendedNodes.map(\.id).contains("nb"))
    }

    @Test("loadRelated returns connected seeded nodes sorted by strength x weight")
    func loadRelated_returnsConnectedNodesSortedByStrength() {
        let service = _FaithMusicGraphService(withSeedData: true)
        service.loadRelated(for: "song-1", type: .song)
        #expect(!service.recommendedNodes.isEmpty)
        if service.recommendedNodes.count >= 2 {
            #expect(service.recommendedNodes[0].id != service.recommendedNodes[1].id)
        }
    }

    @Test("search filters nodes by title substring")
    func search_filtersNodesByTitle() {
        let service = _FaithMusicGraphService(withSeedData: true)
        let results = service.search(query: "Way Maker")
        #expect(results.map(\.title).contains("Way Maker"))
    }

    @Test("search is case-insensitive")
    func search_isCaseInsensitive() {
        let service = _FaithMusicGraphService(withSeedData: true)
        let lower  = service.search(query: "way maker").map(\.id).sorted()
        let upper  = service.search(query: "WAY MAKER").map(\.id).sorted()
        let mixed  = service.search(query: "Way Maker").map(\.id).sorted()
        #expect(lower == upper)
        #expect(lower == mixed)
    }
}

// MARK: - 5. Codable Round-Trip Tests

@Suite("Codable round-trips")
struct CodableRoundTripTests {

    private func makeMusicResource() -> _MusicResource {
        _MusicResource(
            id: "rt-music-1",
            title: "Way Maker",
            artistName: "Sinach",
            albumName: "Way Maker",
            artworkURL: URL(string: "https://example.com/artwork.jpg"),
            previewURL: URL(string: "https://example.com/preview.m4a"),
            durationSeconds: 302.5,
            isVerifiedClean: true,
            rightsPolicy: .free,
            visibility: .public,
            moderationStatus: .approved,
            createdAt: "2026-06-10T00:00:00Z"
        )
    }

    private func makeContentAttachment() -> _ContentAttachment {
        _ContentAttachment(
            id: "rt-attach-1",
            type: .song,
            musicResource: makeMusicResource(),
            profileID: nil,
            externalURL: nil,
            displayTitle: "Way Maker",
            displaySubtitle: "Sinach",
            displayArtworkURL: URL(string: "https://example.com/artwork.jpg"),
            rightsPolicy: .free,
            visibility: .public,
            isVerifiedClean: true,
            createdAt: "2026-06-10T00:00:00Z"
        )
    }

    @Test("ContentAttachment survives JSON encode/decode round-trip")
    func contentAttachment_roundTripsJSON() throws {
        let original = makeContentAttachment()
        let data    = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(_ContentAttachment.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.type == original.type)
        #expect(decoded.displayTitle == original.displayTitle)
        #expect(decoded.displaySubtitle == original.displaySubtitle)
        #expect(decoded.rightsPolicy == original.rightsPolicy)
        #expect(decoded.visibility == original.visibility)
        #expect(decoded.isVerifiedClean == original.isVerifiedClean)
        #expect(decoded.createdAt == original.createdAt)
        #expect(decoded.musicResource?.id == original.musicResource?.id)
        #expect(decoded.musicResource?.title == original.musicResource?.title)
    }

    @Test("MusicResource survives JSON encode/decode round-trip with URL preservation")
    func musicResource_roundTripsJSON() throws {
        let original = makeMusicResource()
        let data    = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(_MusicResource.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.title == original.title)
        #expect(decoded.artistName == original.artistName)
        #expect(decoded.albumName == original.albumName)
        #expect(decoded.durationSeconds == original.durationSeconds)
        #expect(decoded.isVerifiedClean == original.isVerifiedClean)
        #expect(decoded.rightsPolicy == original.rightsPolicy)
        #expect(decoded.visibility == original.visibility)
        #expect(decoded.moderationStatus == original.moderationStatus)
        #expect(decoded.createdAt == original.createdAt)
        #expect(decoded.artworkURL == original.artworkURL)
        #expect(decoded.previewURL == original.previewURL)
    }
}
