// CameraOSModels.swift
// AMENAPP — Camera OS v1
// Shared data types for the Camera OS. Single source of truth.

import Foundation
import CoreGraphics
import UIKit

// MARK: - CameraIntent

/// Describes the declared purpose of a capture session.
/// Every session begins with an explicit intent — no silent, ambient recording.
enum CameraIntent: String, CaseIterable, Codable, Identifiable {
    case story
    case tutorial
    case memory
    case review
    case event
    case conversation
    case vlog
    case prayer
    case sermon
    case meeting
    case interview
    case churchNotes
    case testimony
    case prayerRequest

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .story:        return "Story"
        case .tutorial:     return "Tutorial"
        case .memory:       return "Memory"
        case .review:       return "Review"
        case .event:        return "Event"
        case .conversation: return "Conversation"
        case .vlog:         return "Vlog"
        case .prayer:       return "Prayer"
        case .sermon:       return "Sermon"
        case .meeting:      return "Meeting"
        case .interview:    return "Interview"
        case .churchNotes:  return "Church Notes"
        case .testimony:    return "Testimony"
        case .prayerRequest: return "Prayer Request"
        }
    }

    var systemIcon: String {
        switch self {
        case .story:        return "rectangle.stack.person.crop"
        case .tutorial:     return "play.rectangle"
        case .memory:       return "photo.on.rectangle.angled"
        case .review:       return "star.bubble"
        case .event:        return "calendar"
        case .conversation: return "bubble.left.and.bubble.right"
        case .vlog:         return "video.badge.plus"
        case .prayer:       return "hands.and.sparkles"
        case .sermon:       return "book.and.wrench"
        case .meeting:      return "person.3"
        case .interview:    return "mic.and.signal.meter"
        case .churchNotes:  return "note.text"
        case .testimony:    return "quote.bubble"
        case .prayerRequest: return "hand.raised.circle"
        }
    }

    var isFaithIntent: Bool {
        switch self {
        case .prayer, .sermon, .churchNotes, .testimony, .prayerRequest:
            return true
        case .story, .tutorial, .memory, .review, .event,
             .conversation, .vlog, .meeting, .interview:
            return false
        }
    }

    /// Whether this intent requires an Amen+ or Creator Pro subscription.
    /// Free-tier users see an upgrade prompt when they tap these tiles.
    var requiresUpgrade: Bool {
        switch self {
        case .prayer, .sermon, .churchNotes, .testimony, .prayerRequest:
            return true
        case .story, .tutorial, .memory, .review, .event,
             .conversation, .vlog, .meeting, .interview:
            return false
        }
    }

    /// The marketing tier name shown in the upgrade prompt.
    var requiredTierName: String {
        switch self {
        case .sermon, .churchNotes:
            return "Creator Pro"
        case .prayer, .testimony, .prayerRequest:
            return "Amen+"
        default:
            return "Amen+"
        }
    }

    var isPrayerIntent: Bool {
        self == .prayer || self == .prayerRequest
    }

    var defaultSafetyProfile: CameraSafetyProfile {
        switch self {
        case .story:        return .standard
        case .tutorial:     return .creator
        case .memory:       return .standard
        case .review:       return .creator
        case .event:        return .standard
        case .conversation: return .standard
        case .vlog:         return .creator
        case .prayer:       return .standard
        case .sermon:       return .publicFigure
        case .meeting:      return .business
        case .interview:    return .business
        case .churchNotes:  return .standard
        case .testimony:    return .standard
        case .prayerRequest: return .standard
        }
    }

    var suggestedAudience: CameraAudiencePreset {
        switch self {
        case .story:        return .friends
        case .tutorial:     return .public
        case .memory:       return .family
        case .review:       return .public
        case .event:        return .church
        case .conversation: return .friends
        case .vlog:         return .public
        case .prayer:       return .privateOnly
        case .sermon:       return .church
        case .meeting:      return .orgMembers
        case .interview:    return .public
        case .churchNotes:  return .church
        case .testimony:    return .church
        case .prayerRequest: return .smallGroup
        }
    }
}

// MARK: - CameraAudiencePreset

/// Who can see a captured piece of content by default.
enum CameraAudiencePreset: String, CaseIterable, Codable, Identifiable {
    case `public`
    case friends
    case family
    case church
    case smallGroup
    case orgMembers
    case privateOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .public:      return "Public"
        case .friends:     return "Friends"
        case .family:      return "Family"
        case .church:      return "Church"
        case .smallGroup:  return "Small Group"
        case .orgMembers:  return "Org Members"
        case .privateOnly: return "Private"
        }
    }

    var systemIcon: String {
        switch self {
        case .public:      return "globe"
        case .friends:     return "person.2"
        case .family:      return "house"
        case .church:      return "building.columns"
        case .smallGroup:  return "person.3"
        case .orgMembers:  return "building.2"
        case .privateOnly: return "lock.fill"
        }
    }

    /// Restricted presets require explicit entry — they are never auto-expanded.
    var isRestricted: Bool {
        switch self {
        case .privateOnly, .smallGroup, .orgMembers:
            return true
        case .public, .friends, .family, .church:
            return false
        }
    }
}

// MARK: - CameraSafetyProfile

/// A safety configuration applied to a capture session, governing audience ceiling
/// and minor-protection requirements.
enum CameraSafetyProfile: String, CaseIterable, Codable {
    case standard
    case parent
    case teen
    case creator
    case school
    case business
    case publicFigure

    var displayName: String {
        switch self {
        case .standard:      return "Standard"
        case .parent:        return "Parent"
        case .teen:          return "Teen"
        case .creator:       return "Creator"
        case .school:        return "School"
        case .business:      return "Business"
        case .publicFigure:  return "Public Figure"
        }
    }

    /// The broadest audience that this profile may publish to.
    var maxAudienceAllowed: CameraAudiencePreset {
        switch self {
        case .standard:     return .public
        case .parent:       return .friends
        case .teen:         return .friends
        case .creator:      return .public
        case .school:       return .orgMembers
        case .business:     return .public
        case .publicFigure: return .public
        }
    }

    /// Whether the profile automatically strips EXIF location data before publish.
    var requiresLocationStrip: Bool {
        switch self {
        case .parent, .teen, .school:
            return true
        case .standard, .creator, .business, .publicFigure:
            return false
        }
    }

    /// 0 = no special protection, 3 = maximum minor-safety enforcement.
    var minorProtectionLevel: Int {
        switch self {
        case .parent:      return 3
        case .teen:        return 2
        case .school:      return 3
        case .standard:    return 1
        case .creator:     return 1
        case .business:    return 1
        case .publicFigure: return 1
        }
    }
}

// MARK: - CameraContextRiskLevel

/// Aggregate risk level emitted by the pre-publish safety scan.
enum CameraContextRiskLevel: Int, Comparable, CaseIterable, Codable {
    case low      = 0
    case medium   = 1
    case high     = 2
    case severe   = 3
    case critical = 4

    static func < (lhs: CameraContextRiskLevel, rhs: CameraContextRiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Human-readable coaching message surfaced in the pre-publish nudge sheet.
    var nudgeMessage: String {
        switch self {
        case .low:
            return "This content looks good to share."
        case .medium:
            return "We noticed a few items worth reviewing before you post."
        case .high:
            return "Some sensitive details were detected. Consider redacting them before publishing."
        case .severe:
            return "Significant privacy risks found. Publishing is paused until you review and address them."
        case .critical:
            return "Critical safety concerns detected. This content cannot be published until the issues are resolved."
        }
    }

    /// When true, the publish action is disabled until the user resolves flagged items.
    var blocksPublish: Bool {
        switch self {
        case .severe, .critical:
            return true
        case .low, .medium, .high:
            return false
        }
    }

    /// When true, the content is queued for human moderator review before or after publish.
    var requiresReview: Bool {
        switch self {
        case .high, .severe, .critical:
            return true
        case .low, .medium:
            return false
        }
    }
}

// MARK: - CameraSensitiveItemType

/// Categories of sensitive information that the pre-publish scanner can detect.
enum CameraSensitiveItemType: String, CaseIterable, Codable {
    case minorFace
    case adultFace
    case homeAddress
    case streetSign
    case schoolSign
    case schoolUniform
    case busStop
    case licensePlate
    case idDocument
    case badge
    case medicalRecord
    case screenContent
    case phoneNumber

    var displayName: String {
        switch self {
        case .minorFace:     return "Minor's Face"
        case .adultFace:     return "Adult Face"
        case .homeAddress:   return "Home Address"
        case .streetSign:    return "Street Sign"
        case .schoolSign:    return "School Sign"
        case .schoolUniform: return "School Uniform"
        case .busStop:       return "Bus Stop"
        case .licensePlate:  return "License Plate"
        case .idDocument:    return "ID Document"
        case .badge:         return "Badge / Credential"
        case .medicalRecord: return "Medical Record"
        case .screenContent: return "Screen Content"
        case .phoneNumber:   return "Phone Number"
        }
    }

    /// Whether the system can automatically apply a redaction blur without user intervention.
    var autoRedactable: Bool {
        switch self {
        case .minorFace, .adultFace, .licensePlate, .screenContent:
            return true
        case .homeAddress, .streetSign, .schoolSign, .schoolUniform,
             .busStop, .idDocument, .badge, .medicalRecord, .phoneNumber:
            return false
        }
    }

    /// Relative risk weight used to compute aggregate scan risk. Range 1–3.
    var riskWeight: Int {
        switch self {
        case .minorFace:     return 3
        case .adultFace:     return 1
        case .homeAddress:   return 3
        case .streetSign:    return 1
        case .schoolSign:    return 2
        case .schoolUniform: return 2
        case .busStop:       return 1
        case .licensePlate:  return 2
        case .idDocument:    return 3
        case .badge:         return 2
        case .medicalRecord: return 3
        case .screenContent: return 2
        case .phoneNumber:   return 2
        }
    }
}

// MARK: - CameraRedactionSuggestion

/// A single detected sensitive item with its bounding region and redaction state.
struct CameraRedactionSuggestion: Identifiable {
    let id: String
    let itemType: CameraSensitiveItemType
    /// Bounding rectangle in normalized image coordinates (0–1 each axis).
    let normalizedRect: CGRect
    let confidence: Double
    let autoRedactable: Bool
    var isRedacted: Bool

    init(
        id: String = UUID().uuidString,
        itemType: CameraSensitiveItemType,
        normalizedRect: CGRect,
        confidence: Double,
        autoRedactable: Bool,
        isRedacted: Bool = false
    ) {
        self.id = id
        self.itemType = itemType
        self.normalizedRect = normalizedRect
        self.confidence = confidence
        self.autoRedactable = autoRedactable
        self.isRedacted = isRedacted
    }
}

// MARK: - CameraSceneType

/// Contextual scene classification inferred from the captured frame.
enum CameraSceneType: String, CaseIterable, Codable {
    case church
    case classroom
    case school
    case home
    case office
    case hospital
    case government
    case sportingEvent
    case concert
    case outdoors
    case unknown

    var displayName: String {
        switch self {
        case .church:        return "Church"
        case .classroom:     return "Classroom"
        case .school:        return "School"
        case .home:          return "Home"
        case .office:        return "Office"
        case .hospital:      return "Hospital"
        case .government:    return "Government Building"
        case .sportingEvent: return "Sporting Event"
        case .concert:       return "Concert"
        case .outdoors:      return "Outdoors"
        case .unknown:       return "Unknown"
        }
    }
}

// MARK: - CameraPrePublishScanResult

/// Aggregated output of the pre-publish safety scan performed before every post.
struct CameraPrePublishScanResult {
    let riskLevel: CameraContextRiskLevel
    let detectedItems: [CameraSensitiveItemType]
    let redactionSuggestions: [CameraRedactionSuggestion]
    let safetyProfile: CameraSafetyProfile
    let requiresHumanReview: Bool
    let blocksPublish: Bool
    let nudgeMessage: String?
    let recommendedAudience: CameraAudiencePreset?
    let sceneType: CameraSceneType
    let containsMinor: Bool

    /// True when at least one suggestion in `redactionSuggestions` can be auto-applied.
    var hasAutoRedactableItems: Bool {
        redactionSuggestions.contains { $0.autoRedactable && !$0.isRedacted }
    }
}

// MARK: - CameraEditLabel

/// Describes the degree to which a captured asset has been modified.
/// Shown as a content-authenticity chip on every published post.
enum CameraEditLabel: String, CaseIterable, Codable {
    case originalCapture
    case minorEdits
    case aiAssisted
    case aiGenerated
    case uploadedFromLibrary

    var displayName: String {
        switch self {
        case .originalCapture:     return "Original Capture"
        case .minorEdits:          return "Minor Edits"
        case .aiAssisted:          return "AI-Assisted"
        case .aiGenerated:         return "AI-Generated"
        case .uploadedFromLibrary: return "From Library"
        }
    }

    var systemIcon: String {
        switch self {
        case .originalCapture:     return "camera.fill"
        case .minorEdits:          return "pencil.circle"
        case .aiAssisted:          return "sparkles"
        case .aiGenerated:         return "wand.and.stars"
        case .uploadedFromLibrary: return "photo.on.rectangle"
        }
    }
}

// MARK: - CameraContentCredential

/// An append-only record of every editing step applied to a capture.
/// Travels with the asset from capture through publish.
struct CameraContentCredential: Codable {
    let captureId: String
    let capturedAt: Date
    var editHistory: [CameraEditLabel]
    let deviceAttested: Bool
    let isAmenCapture: Bool

    /// The most recent label applied; falls back to `.originalCapture` for untouched captures.
    var currentLabel: CameraEditLabel {
        editHistory.last ?? .originalCapture
    }
}

// MARK: - CameraSafeZone

/// A geo-fenced location that automatically triggers elevated safety review
/// when a capture occurs within its boundary (e.g., schools, hospitals).
struct CameraSafeZone: Identifiable, Codable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    /// Radius in meters within which the safe-zone rules apply.
    let radiusMeters: Double
    /// When true, any capture inside this zone is automatically routed for human review.
    let triggerExtraReview: Bool
    var isActive: Bool
}

// MARK: - CameraLocationDelayOption

/// Controls how long after capture the precise location is withheld from a post.
/// Protects creators from real-time location tracking by bad actors.
enum CameraLocationDelayOption: String, CaseIterable, Identifiable {
    case none
    case thirtyMinutes
    case oneHour
    case afterEvent
    case tomorrow
    case afterTrip

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:          return "No Delay"
        case .thirtyMinutes: return "30 Minutes"
        case .oneHour:       return "1 Hour"
        case .afterEvent:    return "After Event"
        case .tomorrow:      return "Tomorrow"
        case .afterTrip:     return "After Trip"
        }
    }

    /// The delay expressed as seconds, or nil when the delay is event/context-driven.
    var delaySeconds: TimeInterval? {
        switch self {
        case .none:          return 0
        case .thirtyMinutes: return 30 * 60
        case .oneHour:       return 60 * 60
        case .afterEvent:    return nil
        case .tomorrow:      return 24 * 60 * 60
        case .afterTrip:     return nil
        }
    }
}

// MARK: - CreatorCameraSafetyScore

/// A holistic privacy and safety score for a creator's captured content.
/// Computed at review time; displayed in the pre-publish sheet.
struct CreatorCameraSafetyScore {
    /// 0.0 (no privacy protections) → 1.0 (full privacy).
    let privacyScore: Double
    /// 0.0 (unsafe for children) → 1.0 (fully child-safe).
    let childSafetyScore: Double
    /// 0.0 (likely manipulated) → 1.0 (fully authentic).
    let authenticityScore: Double
    /// 0.0 (no disclosure) → 1.0 (all edits disclosed).
    let disclosureScore: Double
    /// 0.0 (high risk to future self) → 1.0 (no future risk).
    let futureImpactScore: Double
    let computedAt: Date

    /// Mean of all five component scores.
    var overallScore: Double {
        (privacyScore + childSafetyScore + authenticityScore + disclosureScore + futureImpactScore) / 5.0
    }

    /// Human-readable tier label for the overall score.
    var overallLabel: String {
        switch overallScore {
        case 0.85...1.0:  return "Excellent"
        case 0.65..<0.85: return "Good"
        case 0.45..<0.65: return "Fair"
        default:          return "Needs Attention"
        }
    }
}

// MARK: - BulletinEventItem

/// A single event extracted from a church bulletin or flyer via OCR.
struct BulletinEventItem: Identifiable {
    let id: String
    let title: String
    let date: String?
    let location: String?
    let notes: String

    init(
        id: String = UUID().uuidString,
        title: String,
        date: String? = nil,
        location: String? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.location = location
        self.notes = notes
    }
}

// MARK: - BereanVisionScanResult

/// Output of the Berean Vision AI pass over a captured image or document.
/// Extracts scriptural references and generates study-ready notes.
struct BereanVisionScanResult {
    let scriptureRefs: [String]
    let summary: String
    let studyNotes: [String]
    let discussionQuestions: [String]
    /// 0.0–1.0 confidence that the scan accurately represents the source material.
    let confidence: Double
}

// MARK: - ContextLensStructuredOutput

/// Typed, structured extraction from a ContextLens OCR + AI pass.
/// Each case represents a distinct document category.
enum ContextLensStructuredOutput {
    case meetingSummary(title: String, keyPoints: [String], actionItems: [String])
    case recipeShoppingList(ingredients: [String])
    case bookNotes(title: String, author: String?, keyThemes: [String])
    case bulletinEvents(events: [BulletinEventItem])
    case sermonNotes(title: String, scripture: [String], summary: String, discussionQuestions: [String])
    case generic(text: String, summary: String)

    /// A short human-readable title identifying the structured output category.
    var displayTitle: String {
        switch self {
        case .meetingSummary(let title, _, _):
            return title.isEmpty ? "Meeting Summary" : title
        case .recipeShoppingList:
            return "Recipe Shopping List"
        case .bookNotes(let title, _, _):
            return title.isEmpty ? "Book Notes" : title
        case .bulletinEvents:
            return "Bulletin Events"
        case .sermonNotes(let title, _, _, _):
            return title.isEmpty ? "Sermon Notes" : title
        case .generic(_, let summary):
            let trimmed = summary.prefix(40)
            return trimmed.isEmpty ? "Extracted Text" : String(trimmed)
        }
    }
}

// MARK: - ContextLensResult

/// Full result of a ContextLens scan, combining scene classification,
/// structured content extraction, and optional Berean scripture analysis.
struct ContextLensResult {
    let sceneType: CameraSceneType
    let structuredOutput: ContextLensStructuredOutput
    let bereanVisionResult: BereanVisionScanResult?
    let rawOCRText: String
    /// 0.0–1.0 confidence across the entire ContextLens pipeline.
    let confidence: Double
}

// MARK: - PrayerCaptureType

/// Classifies the spiritual intent behind a prayer recording session.
enum PrayerCaptureType: String, CaseIterable, Identifiable {
    case personalPrayer
    case prayerRequest
    case intercession
    case thanksgiving
    case worship

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .personalPrayer: return "Personal Prayer"
        case .prayerRequest:  return "Prayer Request"
        case .intercession:   return "Intercession"
        case .thanksgiving:   return "Thanksgiving"
        case .worship:        return "Worship"
        }
    }

    var systemIcon: String {
        switch self {
        case .personalPrayer: return "hands.and.sparkles"
        case .prayerRequest:  return "hand.raised.circle"
        case .intercession:   return "person.2.wave.2"
        case .thanksgiving:   return "heart.circle"
        case .worship:        return "music.note"
        }
    }
}

// MARK: - PrayerCapture

/// A recorded and transcribed prayer session, optionally augmented
/// with an AI-written written prayer and a linked scripture reference.
struct PrayerCapture: Identifiable {
    let id: String
    let transcript: String
    let prayerType: PrayerCaptureType
    let writtenPrayer: String
    let scriptureRef: String?
    let capturedAt: Date

    init(
        id: String = UUID().uuidString,
        transcript: String,
        prayerType: PrayerCaptureType,
        writtenPrayer: String,
        scriptureRef: String? = nil,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.transcript = transcript
        self.prayerType = prayerType
        self.writtenPrayer = writtenPrayer
        self.scriptureRef = scriptureRef
        self.capturedAt = capturedAt
    }
}

// MARK: - ContextBeforeCommentSettings

/// Governs the "Watch Before You Comment" gate on a published video post.
struct ContextBeforeCommentSettings: Codable {
    /// When false the gate is entirely bypassed.
    var isEnabled: Bool
    /// Fraction (0.0–1.0) of the video the viewer must have watched before commenting.
    var minimumWatchFraction: Double
    /// Message shown to viewers who haven't yet met the watch threshold.
    var messageForViewers: String

    static var defaultSettings: ContextBeforeCommentSettings {
        ContextBeforeCommentSettings(
            isEnabled: false,
            minimumWatchFraction: 0.5,
            messageForViewers: "Watch more of this video before sharing your thoughts."
        )
    }
}

// MARK: - CameraOSCaptureState

/// The state machine governing the Camera OS session lifecycle.
/// Each case represents a discrete phase the user moves through.
///
/// `WitnessDraftAttachment` is defined in WitnessCameraModels.swift in the AMENAPP target.
enum CameraOSCaptureState {
    /// The user is choosing what kind of content they want to capture.
    case intentSelection

    /// The camera viewfinder is active and the user is recording or composing.
    case capturing(intent: CameraIntent)

    /// The ContextLens pipeline is analysing the captured frame for structured content.
    case contextLensScanning(intent: CameraIntent)

    /// The pre-publish safety scan has completed; the user is reviewing the results.
    case safetyReview(
        intent: CameraIntent,
        attachment: WitnessDraftAttachment,
        scanResult: CameraPrePublishScanResult
    )

    /// A prayer recording session is in progress.
    case prayerCapture(intent: CameraIntent)

    /// The content is being uploaded and the post is being written to Firestore.
    case publishing(intent: CameraIntent)
}
