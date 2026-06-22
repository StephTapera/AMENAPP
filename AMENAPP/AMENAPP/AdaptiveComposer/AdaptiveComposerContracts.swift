// AdaptiveComposerContracts.swift
// AMEN — Adaptive Composer frozen contracts. Do not change existing types.
import SwiftUI
import Foundation

// MARK: - ToolID
enum ToolID: String, CaseIterable, Codable, Hashable {
    case photo, camera, bible, link, poll, event, music, podcast
    case prayerRequest, anonymousPrayer, prayerCircle
    case voice, video, location, file, checklist, task
    case donation, announcement, churchNote, sermon, worshipSong
    case teachingSeries, volunteerSignup, ministryInterestForm
    case rsvpCard, directionsCard, reminder, bibleStudy
    case discussionThread, more
}

// MARK: - ComposerToolTier
enum ComposerToolTier { case primary, extended, churchOnly }

// MARK: - ComposerSurface
enum ComposerSurface: String, CaseIterable, Codable, Hashable {
    case post, comment, message, groupChat, space, churchSpace, churchNote, prayerRequest, event, bibleStudy

    var defaultPresentationMode: ComposerPresentationMode {
        switch self {
        case .comment, .message, .groupChat: return .floatingPill
        default: return .dockedRail
        }
    }

    var defaultToolSet: Set<ToolID> {
        switch self {
        case .post: return [.photo, .camera, .bible, .link, .poll, .event, .music, .voice, .location, .more]
        case .comment: return [.bible, .photo, .prayerRequest, .voice, .more]
        case .message: return [.photo, .bible, .prayerRequest, .voice, .file, .more]
        case .groupChat: return [.photo, .bible, .prayerRequest, .poll, .event, .file, .task, .more]
        case .space: return [.bible, .prayerRequest, .event, .poll, .file, .task, .video, .more]
        case .churchSpace: return [.bible, .prayerRequest, .event, .announcement, .churchNote, .donation, .volunteerSignup, .sermon, .more]
        case .churchNote: return [.bible, .photo, .worshipSong, .sermon, .teachingSeries, .more]
        case .prayerRequest: return [.bible, .photo, .prayerCircle, .anonymousPrayer, .voice, .more]
        case .event: return [.photo, .rsvpCard, .directionsCard, .reminder, .announcement, .more]
        case .bibleStudy: return [.bible, .checklist, .discussionThread, .voice, .more]
        }
    }

    var isChurchAware: Bool {
        switch self {
        case .churchSpace, .churchNote, .bibleStudy: return true
        default: return false
        }
    }
}

// MARK: - ComposerPresentationMode
enum ComposerPresentationMode: String, Codable, Hashable {
    case dockedRail, floatingPill, orb
}

// MARK: - Attachment Payloads

struct ScripturePayload: Codable, Hashable {
    var schemaVersion: Int = 1
    var reference: String
    var text: String
    var translation: String
    var bookChapter: String
}

struct PrayerPayload: Codable, Hashable {
    var schemaVersion: Int = 1
    var text: String
    var isAnonymous: Bool
    var prayCount: Int
    var circleId: String?
}

struct AdaptiveComposerEventPayload: Codable, Hashable {
    var schemaVersion: Int = 1
    var title: String
    var startDate: Date
    var endDate: Date?
    var location: String?
    var rsvpCount: Int
}

struct ChurchNotePayload: Codable, Hashable {
    var schemaVersion: Int = 1
    var title: String
    var churchId: String
    var content: String
}

struct PollPayload: Codable, Hashable {
    var schemaVersion: Int = 1
    var question: String
    var options: [String]
    var votesByOption: [String: Int]
    var totalVotes: Int
}

struct MusicPayload: Codable, Hashable {
    var schemaVersion: Int = 1
    var title: String
    var artist: String
    var artworkURL: String?
    var previewURL: String?
    var source: String
}

struct PodcastPayload: Codable, Hashable {
    var schemaVersion: Int = 1
    var title: String
    var episodeTitle: String
    var artworkURL: String?
    var feedURL: String
}

struct YouTubePayload: Codable, Hashable {
    var schemaVersion: Int = 1
    var videoId: String
    var title: String
    var thumbnailURL: String
    var duration: String
}

struct LocationPayload: Codable, Hashable {
    var schemaVersion: Int = 1
    var name: String
    var latitude: Double
    var longitude: Double
    var address: String?
}

struct FilePayload: Codable, Hashable {
    var schemaVersion: Int = 1
    var name: String
    var mimeType: String
    var sizeBytes: Int
    var downloadURL: String
}

struct AdaptiveComposerChecklistItem: Codable, Hashable, Identifiable {
    var id: String
    var text: String
    var isChecked: Bool
    var assigneeUID: String?
}

struct AdaptiveComposerChecklistPayload: Codable, Hashable {
    var schemaVersion: Int = 1
    var title: String
    var items: [AdaptiveComposerChecklistItem]
}

struct DonationPayload: Codable, Hashable {
    var schemaVersion: Int = 1
    var campaignId: String
    var title: String
    var goalAmount: Double
    var raisedAmount: Double
    var currency: String
}

struct VolunteerPayload: Codable, Hashable {
    var schemaVersion: Int = 1
    var title: String
    var description: String
    var slotsTotal: Int
    var slotsFilled: Int
    var signupURL: String?
}

struct VoicePayload: Codable, Hashable {
    var schemaVersion: Int = 1
    var durationSeconds: Double
    var waveformData: [Float]
    var downloadURL: String
}

struct AdaptiveComposerVideoPayload: Codable, Hashable {
    var schemaVersion: Int = 1
    var durationSeconds: Double
    var thumbnailURL: String?
    var downloadURL: String
}

struct AnnouncementPayload: Codable, Hashable {
    var schemaVersion: Int = 1
    var title: String
    var body: String
    var churchId: String?
    var priority: Int
}

struct RSVPPayload: Codable, Hashable {
    var schemaVersion: Int = 1
    var eventId: String
    var title: String
    var yesCount: Int
    var noCount: Int
    var maybeCount: Int
}

struct DirectionsPayload: Codable, Hashable {
    var schemaVersion: Int = 1
    var name: String
    var latitude: Double
    var longitude: Double
    var address: String
}

struct TaskPayload: Codable, Hashable {
    var schemaVersion: Int = 1
    var title: String
    var dueDate: Date?
    var assigneeUID: String?
    var isCompleted: Bool
    var spaceId: String?
}

struct AdaptiveComposerReminderPayload: Codable, Hashable {
    var schemaVersion: Int = 1
    var title: String
    var triggerDate: Date
    var recurrence: String?
}

struct LinkPayload: Codable, Hashable {
    var schemaVersion: Int = 1
    var url: String
    var title: String?
    var description: String?
    var imageURL: String?
    var domain: String
}

struct BibleStudyPayload: Codable, Hashable {
    var schemaVersion: Int = 1
    var title: String
    var passages: [String]
    var studyNotes: String
    var groupId: String?
}

struct DiscussionThreadPayload: Codable, Hashable {
    var schemaVersion: Int = 1
    var title: String
    var prompt: String
    var postCount: Int
    var communityId: String?
}

struct SermonPayload: Codable, Hashable {
    var schemaVersion: Int = 1
    var title: String
    var speakerName: String
    var churchId: String
    var audioURL: String?
    var videoURL: String?
    var scriptureReferences: [String]
}

struct WorshipSongPayload: Codable, Hashable {
    var schemaVersion: Int = 1
    var title: String
    var artist: String
    var ccliNumber: String?
    var lyricsURL: String?
}

struct TeachingSeriesPayload: Codable, Hashable {
    var schemaVersion: Int = 1
    var seriesTitle: String
    var episodeTitle: String
    var churchId: String
    var episodeNumber: Int
}

struct MinistryFormPayload: Codable, Hashable {
    var schemaVersion: Int = 1
    var title: String
    var ministryName: String
    var formURL: String
    var churchId: String
}

// MARK: - ComposerAttachment
enum ComposerAttachment: Codable, Hashable {
    case scripture(ScripturePayload)
    case prayer(PrayerPayload)
    case event(AdaptiveComposerEventPayload)
    case churchNote(ChurchNotePayload)
    case poll(PollPayload)
    case music(MusicPayload)
    case podcast(PodcastPayload)
    case youtube(YouTubePayload)
    case location(LocationPayload)
    case file(FilePayload)
    case checklist(AdaptiveComposerChecklistPayload)
    case donation(DonationPayload)
    case volunteer(VolunteerPayload)
    case voice(VoicePayload)
    case video(AdaptiveComposerVideoPayload)
    case announcement(AnnouncementPayload)
    case rsvp(RSVPPayload)
    case directions(DirectionsPayload)
    case task(TaskPayload)
    case reminder(AdaptiveComposerReminderPayload)
    case link(LinkPayload)
    case bibleStudy(BibleStudyPayload)
    case discussionThread(DiscussionThreadPayload)
    case sermon(SermonPayload)
    case worshipSong(WorshipSongPayload)
    case teachingSeries(TeachingSeriesPayload)
    case ministryForm(MinistryFormPayload)

    var typeKey: String {
        switch self {
        case .scripture: return "scripture"
        case .prayer: return "prayer"
        case .event: return "event"
        case .churchNote: return "churchNote"
        case .poll: return "poll"
        case .music: return "music"
        case .podcast: return "podcast"
        case .youtube: return "youtube"
        case .location: return "location"
        case .file: return "file"
        case .checklist: return "checklist"
        case .donation: return "donation"
        case .volunteer: return "volunteer"
        case .voice: return "voice"
        case .video: return "video"
        case .announcement: return "announcement"
        case .rsvp: return "rsvp"
        case .directions: return "directions"
        case .task: return "task"
        case .reminder: return "reminder"
        case .link: return "link"
        case .bibleStudy: return "bibleStudy"
        case .discussionThread: return "discussionThread"
        case .sermon: return "sermon"
        case .worshipSong: return "worshipSong"
        case .teachingSeries: return "teachingSeries"
        case .ministryForm: return "ministryForm"
        }
    }
}

// MARK: - CreationTool
struct CreationTool: Identifiable {
    let id: ToolID
    let icon: String
    let title: String
    let tier: ComposerToolTier
    let surfaces: Set<ComposerSurface>
    let makeAttachment: (() -> ComposerAttachment)?
}

// MARK: - Context
struct ChurchComposerContext {
    let churchId: String
    let churchName: String
    let userRole: String
}

struct SpaceComposerContext {
    let spaceId: String
    let spaceName: String
}

struct ComposerContext {
    let surface: ComposerSurface
    var churchContext: ChurchComposerContext?
    var spaceContext: SpaceComposerContext?
    var audience: String?
    var conversationParticipants: [String]
    var recentBehavior: [String]
    var pastedContent: String?

    var isChurchMode: Bool { churchContext != nil }
}

// MARK: - Intent
struct IntentSuggestion: Identifiable, Equatable {
    let id: UUID
    let primaryTool: ToolID
    let alternativeTools: [ToolID]
    let label: String
    let confidence: Double
    let triggerText: String
}

protocol IntentEngine: AnyObject {
    func detect(in text: String, context: ComposerContext) async -> [IntentSuggestion]
}

// MARK: - Rail State
enum RailState: Equatable {
    case compact
    case expanded
    case predictive([IntentSuggestion])
}
