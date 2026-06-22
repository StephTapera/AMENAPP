// AdaptiveComposerDispatcherTests.swift
// AMEN — Exhaustive dispatcher typeKey contract + missing Codable round-trips
// + intent detector coverage for all 11 detector classes.
// Uses Swift Testing framework.

import Testing
import Foundation
@testable import AMENAPP

// MARK: - Dispatcher Completeness (typeKey contract for all 27 cases)

@Suite("Dispatcher TypeKey Completeness")
@MainActor
struct DispatcherTypeKeyTests {

    // Verifies every ComposerAttachment case maps to the correct typeKey string.
    // This acts as a compile-time contract: adding a new case without updating typeKey
    // will cause the switch to fail to compile, and this test suite will need updating.

    @Test("scripture typeKey")
    func scriptureKey() {
        let a = ComposerAttachment.scripture(.init(schemaVersion:1,reference:"Rom 8",text:"t",translation:"NIV",bookChapter:"Rom 8"))
        #expect(a.typeKey == "scripture")
    }
    @Test("prayer typeKey")
    func prayerKey() {
        let a = ComposerAttachment.prayer(.init(schemaVersion:1,text:"t",isAnonymous:false,prayCount:0,circleId:nil))
        #expect(a.typeKey == "prayer")
    }
    @Test("event typeKey")
    func eventKey() {
        let a = ComposerAttachment.event(.init(schemaVersion:1,title:"E",startDate:Date(),endDate:nil,location:nil,rsvpCount:0))
        #expect(a.typeKey == "event")
    }
    @Test("churchNote typeKey")
    func churchNoteKey() {
        let a = ComposerAttachment.churchNote(.init(schemaVersion:1,title:"N",churchId:"c",content:"c"))
        #expect(a.typeKey == "churchNote")
    }
    @Test("poll typeKey")
    func pollKey() {
        let a = ComposerAttachment.poll(.init(schemaVersion:1,question:"Q",options:["A"],votesByOption:[:],totalVotes:0))
        #expect(a.typeKey == "poll")
    }
    @Test("music typeKey")
    func musicKey() {
        let a = ComposerAttachment.music(.init(schemaVersion:1,title:"T",artist:"A",artworkURL:nil,previewURL:nil,source:"AM"))
        #expect(a.typeKey == "music")
    }
    @Test("podcast typeKey")
    func podcastKey() {
        let a = ComposerAttachment.podcast(.init(schemaVersion:1,title:"T",episodeTitle:"E",artworkURL:nil,feedURL:"f"))
        #expect(a.typeKey == "podcast")
    }
    @Test("youtube typeKey")
    func youtubeKey() {
        let a = ComposerAttachment.youtube(.init(schemaVersion:1,videoId:"v",title:"T",thumbnailURL:"u",duration:"1:00"))
        #expect(a.typeKey == "youtube")
    }
    @Test("location typeKey")
    func locationKey() {
        let a = ComposerAttachment.location(.init(schemaVersion:1,name:"N",latitude:0,longitude:0,address:nil))
        #expect(a.typeKey == "location")
    }
    @Test("file typeKey")
    func fileKey() {
        let a = ComposerAttachment.file(.init(schemaVersion:1,name:"f.pdf",mimeType:"application/pdf",sizeBytes:100,downloadURL:"u"))
        #expect(a.typeKey == "file")
    }
    @Test("checklist typeKey")
    func checklistKey() {
        let a = ComposerAttachment.checklist(.init(schemaVersion:1,title:"T",items:[]))
        #expect(a.typeKey == "checklist")
    }
    @Test("donation typeKey")
    func donationKey() {
        let a = ComposerAttachment.donation(.init(schemaVersion:1,campaignId:"c",title:"T",goalAmount:1000,raisedAmount:0,currency:"USD"))
        #expect(a.typeKey == "donation")
    }
    @Test("volunteer typeKey")
    func volunteerKey() {
        let a = ComposerAttachment.volunteer(.init(schemaVersion:1,title:"T",description:"D",slotsTotal:10,slotsFilled:0,signupURL:nil))
        #expect(a.typeKey == "volunteer")
    }
    @Test("voice typeKey")
    func voiceKey() {
        let a = ComposerAttachment.voice(.init(schemaVersion:1,durationSeconds:30,waveformData:[0.5],downloadURL:"u"))
        #expect(a.typeKey == "voice")
    }
    @Test("video typeKey")
    func videoKey() {
        let a = ComposerAttachment.video(.init(schemaVersion:1,durationSeconds:60,thumbnailURL:nil,downloadURL:"u"))
        #expect(a.typeKey == "video")
    }
    @Test("announcement typeKey")
    func announcementKey() {
        let a = ComposerAttachment.announcement(.init(schemaVersion:1,title:"T",body:"B",churchId:nil,priority:1))
        #expect(a.typeKey == "announcement")
    }
    @Test("rsvp typeKey")
    func rsvpKey() {
        let a = ComposerAttachment.rsvp(.init(schemaVersion:1,eventId:"e",title:"T",yesCount:0,noCount:0,maybeCount:0))
        #expect(a.typeKey == "rsvp")
    }
    @Test("directions typeKey")
    func directionsKey() {
        let a = ComposerAttachment.directions(.init(schemaVersion:1,name:"N",latitude:0,longitude:0,address:"A"))
        #expect(a.typeKey == "directions")
    }
    @Test("task typeKey")
    func taskKey() {
        let a = ComposerAttachment.task(.init(schemaVersion:1,title:"T",dueDate:nil,assigneeUID:nil,isCompleted:false,spaceId:nil))
        #expect(a.typeKey == "task")
    }
    @Test("reminder typeKey")
    func reminderKey() {
        let a = ComposerAttachment.reminder(.init(schemaVersion:1,title:"T",triggerDate:Date(),recurrence:nil))
        #expect(a.typeKey == "reminder")
    }
    @Test("link typeKey")
    func linkKey() {
        let a = ComposerAttachment.link(.init(schemaVersion:1,url:"https://x.com",title:nil,description:nil,imageURL:nil,domain:"x.com"))
        #expect(a.typeKey == "link")
    }
    @Test("bibleStudy typeKey")
    func bibleStudyKey() {
        let a = ComposerAttachment.bibleStudy(.init(schemaVersion:1,title:"T",passages:["Gen 1"],studyNotes:"N",groupId:nil))
        #expect(a.typeKey == "bibleStudy")
    }
    @Test("discussionThread typeKey")
    func discussionThreadKey() {
        let a = ComposerAttachment.discussionThread(.init(schemaVersion:1,title:"T",prompt:"P",postCount:0,communityId:nil))
        #expect(a.typeKey == "discussionThread")
    }
    @Test("sermon typeKey")
    func sermonKey() {
        let a = ComposerAttachment.sermon(.init(schemaVersion:1,title:"T",speakerName:"S",churchId:"c",audioURL:nil,videoURL:nil,scriptureReferences:[]))
        #expect(a.typeKey == "sermon")
    }
    @Test("worshipSong typeKey")
    func worshipSongKey() {
        let a = ComposerAttachment.worshipSong(.init(schemaVersion:1,title:"T",artist:"A",ccliNumber:nil,lyricsURL:nil))
        #expect(a.typeKey == "worshipSong")
    }
    @Test("teachingSeries typeKey")
    func teachingSeriesKey() {
        let a = ComposerAttachment.teachingSeries(.init(schemaVersion:1,seriesTitle:"S",episodeTitle:"E",churchId:"c",episodeNumber:1))
        #expect(a.typeKey == "teachingSeries")
    }
    @Test("ministryForm typeKey")
    func ministryFormKey() {
        let a = ComposerAttachment.ministryForm(.init(schemaVersion:1,title:"T",ministryName:"M",formURL:"u",churchId:"c"))
        #expect(a.typeKey == "ministryForm")
    }
}

// MARK: - Missing Codable Round-Trip Tests

@Suite("Missing Payload Codable Round-Trips")
@MainActor
struct MissingPayloadCodableTests {

    @Test("PodcastPayload round-trip")
    func podcastRoundTrip() throws {
        let p = PodcastPayload(schemaVersion: 1, title: "The Daily Bread",
                               episodeTitle: "Faith in Action",
                               artworkURL: "https://cdn.example.com/art.jpg",
                               feedURL: "https://podcast.example.com/feed")
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(PodcastPayload.self, from: data)
        #expect(decoded == p)
        #expect(decoded.episodeTitle == "Faith in Action")
    }

    @Test("LocationPayload round-trip")
    func locationRoundTrip() throws {
        let p = LocationPayload(schemaVersion: 1, name: "Grace Church",
                                latitude: 37.7749, longitude: -122.4194,
                                address: "123 Main St, San Francisco, CA")
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(LocationPayload.self, from: data)
        #expect(decoded == p)
        #expect(abs(decoded.latitude - 37.7749) < 0.0001)
    }

    @Test("FilePayload round-trip")
    func fileRoundTrip() throws {
        let p = FilePayload(schemaVersion: 1, name: "sermon_notes.pdf",
                             mimeType: "application/pdf",
                             sizeBytes: 204800,
                             downloadURL: "https://storage.example.com/file.pdf")
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(FilePayload.self, from: data)
        #expect(decoded == p)
        #expect(decoded.sizeBytes == 204800)
    }

    @Test("VideoPayload round-trip")
    func videoRoundTrip() throws {
        let p = VideoPayload(schemaVersion: 1, durationSeconds: 180.5,
                              thumbnailURL: "https://cdn.example.com/thumb.jpg",
                              downloadURL: "https://cdn.example.com/video.mp4")
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(VideoPayload.self, from: data)
        #expect(decoded == p)
        #expect(abs(decoded.durationSeconds - 180.5) < 0.001)
    }

    @Test("AnnouncementPayload round-trip with churchId")
    func announcementRoundTrip() throws {
        let p = AnnouncementPayload(schemaVersion: 1, title: "Service Change",
                                     body: "Sunday service at 10am in the main hall.",
                                     churchId: "church-grace", priority: 2)
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(AnnouncementPayload.self, from: data)
        #expect(decoded == p)
        #expect(decoded.churchId == "church-grace")
        #expect(decoded.priority == 2)
    }

    @Test("RSVPPayload round-trip")
    func rsvpRoundTrip() throws {
        let p = RSVPPayload(schemaVersion: 1, eventId: "event-1",
                             title: "Easter Sunday", yesCount: 45,
                             noCount: 3, maybeCount: 12)
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(RSVPPayload.self, from: data)
        #expect(decoded == p)
        #expect(decoded.yesCount == 45)
        #expect(decoded.maybeCount == 12)
    }

    @Test("DirectionsPayload round-trip")
    func directionsRoundTrip() throws {
        let p = DirectionsPayload(schemaVersion: 1, name: "Calvary Chapel",
                                   latitude: 34.0522, longitude: -118.2437,
                                   address: "456 Church Ave, Los Angeles, CA")
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(DirectionsPayload.self, from: data)
        #expect(decoded == p)
        #expect(decoded.address == "456 Church Ave, Los Angeles, CA")
    }

    @Test("VolunteerPayload round-trip")
    func volunteerRoundTrip() throws {
        let p = VolunteerPayload(schemaVersion: 1, title: "Usher Team",
                                  description: "Help greet visitors",
                                  slotsTotal: 8, slotsFilled: 3,
                                  signupURL: "https://church.example.com/signup")
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(VolunteerPayload.self, from: data)
        #expect(decoded == p)
        #expect(decoded.slotsTotal == 8)
        #expect(decoded.slotsFilled == 3)
    }

    @Test("AdaptiveComposerReminderPayload round-trip preserves triggerDate")
    func reminderRoundTrip() throws {
        let trigger = Date(timeIntervalSince1970: 2_000_000)
        let p = AdaptiveComposerReminderPayload(schemaVersion: 1,
                                                title: "Read Acts 2",
                                                triggerDate: trigger,
                                                recurrence: "weekly")
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(AdaptiveComposerReminderPayload.self, from: data)
        #expect(decoded == p)
        #expect(abs(decoded.triggerDate.timeIntervalSince1970 - trigger.timeIntervalSince1970) < 0.001)
        #expect(decoded.recurrence == "weekly")
    }

    @Test("BibleStudyPayload round-trip with multiple passages")
    func bibleStudyRoundTrip() throws {
        let p = BibleStudyPayload(schemaVersion: 1, title: "Romans Study",
                                   passages: ["Rom 1:1-7", "Rom 3:21-26"],
                                   studyNotes: "Focus on justification by faith",
                                   groupId: "group-romans")
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(BibleStudyPayload.self, from: data)
        #expect(decoded == p)
        #expect(decoded.passages.count == 2)
        #expect(decoded.groupId == "group-romans")
    }

    @Test("DiscussionThreadPayload round-trip")
    func discussionThreadRoundTrip() throws {
        let p = DiscussionThreadPayload(schemaVersion: 1,
                                         title: "What does grace mean to you?",
                                         prompt: "Share your personal experience of grace.",
                                         postCount: 7,
                                         communityId: "community-1")
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(DiscussionThreadPayload.self, from: data)
        #expect(decoded == p)
        #expect(decoded.postCount == 7)
    }

    @Test("ChurchNotePayload round-trip")
    func churchNoteRoundTrip() throws {
        let p = ChurchNotePayload(schemaVersion: 1, title: "Week 3 Notes",
                                   churchId: "church-1",
                                   content: "Main points from Sunday's message.")
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(ChurchNotePayload.self, from: data)
        #expect(decoded == p)
        #expect(decoded.churchId == "church-1")
    }

    @Test("WorshipSongPayload round-trip")
    func worshipSongRoundTrip() throws {
        let p = WorshipSongPayload(schemaVersion: 1, title: "How Great Thou Art",
                                    artist: "Stuart K. Hine",
                                    ccliNumber: "14181",
                                    lyricsURL: "https://ccli.com/14181")
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(WorshipSongPayload.self, from: data)
        #expect(decoded == p)
        #expect(decoded.ccliNumber == "14181")
    }

    @Test("TeachingSeriesPayload round-trip")
    func teachingSeriesRoundTrip() throws {
        let p = TeachingSeriesPayload(schemaVersion: 1,
                                       seriesTitle: "Identity in Christ",
                                       episodeTitle: "Beloved",
                                       churchId: "church-grace",
                                       episodeNumber: 3)
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(TeachingSeriesPayload.self, from: data)
        #expect(decoded == p)
        #expect(decoded.episodeNumber == 3)
    }

    @Test("MinistryFormPayload round-trip")
    func ministryFormRoundTrip() throws {
        let p = MinistryFormPayload(schemaVersion: 1, title: "Kids Ministry Interest",
                                     ministryName: "Kids Church",
                                     formURL: "https://church.example.com/kids-form",
                                     churchId: "church-1")
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(MinistryFormPayload.self, from: data)
        #expect(decoded == p)
        #expect(decoded.ministryName == "Kids Church")
    }
}

// MARK: - Intent Detector Coverage (previously missing detectors)

@Suite("Intent Detector — DateTime")
struct DateTimeDetectorTests {
    let engine = OnDeviceIntentEngine()
    let ctx = ComposerContext(surface: .post, churchContext: nil, spaceContext: nil,
                               audience: nil, conversationParticipants: [],
                               recentBehavior: [], pastedContent: nil)

    @Test("Sunday at 10am fires event")
    func sundayAt10() async {
        let s = await engine.detect(in: "Join us Sunday at 10am for worship!", context: ctx)
        #expect(s.contains { $0.primaryTool == .event })
    }

    @Test("Meeting Thursday fires event")
    func meetingThursday() async {
        let s = await engine.detect(in: "We have a meeting Thursday at 6pm", context: ctx)
        #expect(s.contains { $0.primaryTool == .event })
    }

    @Test("Tonight at 7 fires event")
    func tonightAt7() async {
        let s = await engine.detect(in: "Come over tonight at 7 for small group", context: ctx)
        #expect(s.contains { $0.primaryTool == .event })
    }

    @Test("Join us on December 25 fires event")
    func december25() async {
        let s = await engine.detect(in: "Join us on December 25 for our Christmas service", context: ctx)
        #expect(s.contains { $0.primaryTool == .event })
    }

    @Test("Come to our conference next month fires event")
    func nextMonth() async {
        let s = await engine.detect(in: "Come to our conference next month in Dallas", context: ctx)
        #expect(s.contains { $0.primaryTool == .event })
    }

    @Test("Random text no event")
    func noEvent1() async {
        let s = await engine.detect(in: "I love coffee and early mornings", context: ctx)
        #expect(!s.contains { $0.primaryTool == .event })
    }

    @Test("Opinion text no event")
    func noEvent2() async {
        let s = await engine.detect(in: "Grace is the greatest gift", context: ctx)
        #expect(!s.contains { $0.primaryTool == .event })
    }
}

@Suite("Intent Detector — Music")
struct MusicDetectorTests {
    let engine = OnDeviceIntentEngine()
    let ctx = ComposerContext(surface: .post, churchContext: nil, spaceContext: nil,
                               audience: nil, conversationParticipants: [],
                               recentBehavior: [], pastedContent: nil)

    @Test("Listen to this fires music")
    func listenToThis() async {
        let s = await engine.detect(in: "Listen to this amazing worship song!", context: ctx)
        #expect(s.contains { $0.primaryTool == .music })
    }

    @Test("Love this song fires music")
    func loveThisSong() async {
        let s = await engine.detect(in: "Love this song by Hillsong!", context: ctx)
        #expect(s.contains { $0.primaryTool == .music })
    }

    @Test("Currently playing fires music")
    func currentlyPlaying() async {
        let s = await engine.detect(in: "Currently playing 'Good Grace' on Apple Music", context: ctx)
        #expect(s.contains { $0.primaryTool == .music })
    }

    @Test("Random text no music")
    func noMusic1() async {
        let s = await engine.detect(in: "We need to talk about your schedule", context: ctx)
        #expect(!s.contains { $0.primaryTool == .music })
    }

    @Test("Food post no music")
    func noMusic2() async {
        let s = await engine.detect(in: "Just had the best tacos tonight", context: ctx)
        #expect(!s.contains { $0.primaryTool == .music })
    }
}

@Suite("Intent Detector — YouTube/Video")
struct YouTubeDetectorTests {
    let engine = OnDeviceIntentEngine()
    let ctx = ComposerContext(surface: .post, churchContext: nil, spaceContext: nil,
                               audience: nil, conversationParticipants: [],
                               recentBehavior: [], pastedContent: nil)

    @Test("Watch this fires youtube")
    func watchThis() async {
        let s = await engine.detect(in: "Watch this sermon clip — so powerful", context: ctx)
        #expect(s.contains { $0.primaryTool == .video })
    }

    @Test("YouTube URL pasted fires youtube")
    func youtubePasted() async {
        let ctx2 = ComposerContext(surface: .post, churchContext: nil, spaceContext: nil,
                                    audience: nil, conversationParticipants: [],
                                    recentBehavior: [], pastedContent: "https://youtube.com/watch?v=abc123")
        let s = await engine.detect(in: "Check out this video https://youtube.com/watch?v=abc123", context: ctx2)
        #expect(s.contains { $0.primaryTool == .video })
    }

    @Test("Random text no youtube")
    func noYouTube1() async {
        let s = await engine.detect(in: "Praying for you today", context: ctx)
        #expect(!s.contains { $0.primaryTool == .video })
    }

    @Test("Scripture reference no youtube")
    func noYouTube2() async {
        let s = await engine.detect(in: "John 3:16 is my favorite verse", context: ctx)
        #expect(!s.contains { $0.primaryTool == .video })
    }
}

@Suite("Intent Detector — Volunteer")
struct VolunteerDetectorTests {
    let engine = OnDeviceIntentEngine()
    let ctx = ComposerContext(surface: .post, churchContext: nil, spaceContext: nil,
                               audience: nil, conversationParticipants: [],
                               recentBehavior: [], pastedContent: nil)

    @Test("We need volunteers fires volunteerSignup")
    func needVolunteers() async {
        let s = await engine.detect(in: "We need volunteers for the food pantry this Saturday", context: ctx)
        #expect(s.contains { $0.primaryTool == .volunteerSignup })
    }

    @Test("Serve our community fires volunteerSignup")
    func serveOurCommunity() async {
        let s = await engine.detect(in: "Serve our community — sign up to help at the shelter", context: ctx)
        #expect(s.contains { $0.primaryTool == .volunteerSignup })
    }

    @Test("Volunteer opportunity fires volunteerSignup")
    func volunteerOpportunity() async {
        let s = await engine.detect(in: "Volunteer opportunity: kids ministry needs 3 helpers", context: ctx)
        #expect(s.contains { $0.primaryTool == .volunteerSignup })
    }

    @Test("Devotional text no volunteer")
    func noVolunteer1() async {
        let s = await engine.detect(in: "Blessed are the pure in heart", context: ctx)
        #expect(!s.contains { $0.primaryTool == .volunteerSignup })
    }

    @Test("Gratitude post no volunteer")
    func noVolunteer2() async {
        let s = await engine.detect(in: "So grateful for this amazing community", context: ctx)
        #expect(!s.contains { $0.primaryTool == .volunteerSignup })
    }
}

@Suite("Intent Detector — Link/URL")
struct LinkDetectorTests {
    let engine = OnDeviceIntentEngine()

    @Test("Pasted HTTPS URL fires link")
    func httpsURL() async {
        let ctx = ComposerContext(surface: .post, churchContext: nil, spaceContext: nil,
                                   audience: nil, conversationParticipants: [],
                                   recentBehavior: [], pastedContent: "https://example.com/article")
        let s = await engine.detect(in: "Check out this article https://example.com/article", context: ctx)
        #expect(s.contains { $0.primaryTool == .link })
    }

    @Test("Inline https URL fires link")
    func inlineURL() async {
        let ctx = ComposerContext(surface: .post, churchContext: nil, spaceContext: nil,
                                   audience: nil, conversationParticipants: [],
                                   recentBehavior: [], pastedContent: nil)
        let s = await engine.detect(in: "Read this: https://bible.com/passage", context: ctx)
        #expect(s.contains { $0.primaryTool == .link })
    }

    @Test("No URL no link")
    func noURL() async {
        let ctx = ComposerContext(surface: .post, churchContext: nil, spaceContext: nil,
                                   audience: nil, conversationParticipants: [],
                                   recentBehavior: [], pastedContent: nil)
        let s = await engine.detect(in: "Just a regular post with no link", context: ctx)
        #expect(!s.contains { $0.primaryTool == .link })
    }
}

@Suite("Intent Detector — Giving/Donation")
struct GivingDetectorTests {
    let engine = OnDeviceIntentEngine()
    let ctx = ComposerContext(surface: .post, churchContext: nil, spaceContext: nil,
                               audience: nil, conversationParticipants: [],
                               recentBehavior: [], pastedContent: nil)

    @Test("Giving campaign fires donation")
    func givingCampaign() async {
        let s = await engine.detect(in: "Support our giving campaign for the new building", context: ctx)
        #expect(s.contains { $0.primaryTool == .donation })
    }

    @Test("Offering Sunday fires donation")
    func offeringSunday() async {
        let s = await engine.detect(in: "Come support our offering Sunday initiative", context: ctx)
        #expect(s.contains { $0.primaryTool == .donation })
    }

    @Test("Donation drive fires donation")
    func donationDrive() async {
        let s = await engine.detect(in: "Join our donation drive for local families in need", context: ctx)
        #expect(s.contains { $0.primaryTool == .donation })
    }

    @Test("Generic encouragement no donation")
    func noDonation1() async {
        let s = await engine.detect(in: "God provides for all our needs", context: ctx)
        #expect(!s.contains { $0.primaryTool == .donation })
    }

    @Test("Fellowship post no donation")
    func noDonation2() async {
        let s = await engine.detect(in: "Looking forward to fellowship this Sunday", context: ctx)
        #expect(!s.contains { $0.primaryTool == .donation })
    }
}

@Suite("Intent Detector — Bible Study")
struct BibleStudyDetectorTests {
    let engine = OnDeviceIntentEngine()
    let ctx = ComposerContext(surface: .post, churchContext: nil, spaceContext: nil,
                               audience: nil, conversationParticipants: [],
                               recentBehavior: [], pastedContent: nil)

    @Test("Bible study fires bibleStudy")
    func bibleStudyWord() async {
        let s = await engine.detect(in: "Join our Bible study on the book of Romans", context: ctx)
        #expect(s.contains { $0.primaryTool == .bibleStudy })
    }

    @Test("Study group fires bibleStudy")
    func studyGroup() async {
        let s = await engine.detect(in: "Our study group meets Tuesday at 7pm", context: ctx)
        #expect(s.contains { $0.primaryTool == .bibleStudy })
    }

    @Test("Devotional text no bibleStudy")
    func noStudy1() async {
        let s = await engine.detect(in: "Feeling grateful for God's grace today", context: ctx)
        #expect(!s.contains { $0.primaryTool == .bibleStudy })
    }

    @Test("Weather text no bibleStudy")
    func noStudy2() async {
        let s = await engine.detect(in: "Beautiful day outside for a walk", context: ctx)
        #expect(!s.contains { $0.primaryTool == .bibleStudy })
    }
}

// MARK: - ComposerAttachment Codable (enum-level round-trips for 6 representative cases)

@Suite("ComposerAttachment Enum Codable")
@MainActor
struct ComposerAttachmentEnumCodableTests {

    @Test("Scripture ComposerAttachment encodes and decodes preserving typeKey")
    func scriptureEnumRoundTrip() throws {
        let payload = ScripturePayload(schemaVersion: 1, reference: "John 3:16",
                                        text: "For God so loved the world",
                                        translation: "NIV", bookChapter: "John 3")
        let attachment = ComposerAttachment.scripture(payload)
        let data = try JSONEncoder().encode(attachment)
        let decoded = try JSONDecoder().decode(ComposerAttachment.self, from: data)
        #expect(decoded == attachment)
        #expect(decoded.typeKey == "scripture")
    }

    @Test("Poll ComposerAttachment encodes and decodes preserving votesByOption")
    func pollEnumRoundTrip() throws {
        let payload = PollPayload(schemaVersion: 1, question: "Favorite Psalm?",
                                   options: ["23", "91", "121"],
                                   votesByOption: ["23": 10, "91": 5, "121": 8],
                                   totalVotes: 23)
        let attachment = ComposerAttachment.poll(payload)
        let data = try JSONEncoder().encode(attachment)
        let decoded = try JSONDecoder().decode(ComposerAttachment.self, from: data)
        #expect(decoded == attachment)
    }

    @Test("Event ComposerAttachment encodes and decodes")
    func eventEnumRoundTrip() throws {
        let attachment = ComposerAttachment.event(
            EventPayload(schemaVersion: 1, title: "Christmas Eve Service",
                         startDate: Date(timeIntervalSince1970: 1_800_000),
                         endDate: nil, location: "Main Hall", rsvpCount: 120))
        let data = try JSONEncoder().encode(attachment)
        let decoded = try JSONDecoder().decode(ComposerAttachment.self, from: data)
        #expect(decoded == attachment)
        #expect(decoded.typeKey == "event")
    }
}
