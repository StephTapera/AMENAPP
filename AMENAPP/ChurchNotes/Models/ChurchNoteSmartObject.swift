// FROZEN — Wave 0 contract. Changes require orchestrator approval.
//
// ╔══════════════════════════════════════════════════════════════════╗
// ║  WIRING_CERT — Church Notes Lane                                 ║
// ║  Generated: 2026-06-11 | Branch: safety-hardening               ║
// ╠══════════════════════════════════════════════════════════════════╣
// ║ PIPELINE SURFACES                                                ║
// ║  Audio → uploadAudioAndCreateJob                                 ║
// ║    Gate: churchNotesAudioCaptureEnabled                          ║
// ║          && !churchNotesProcessingKillSwitch                     ║
// ║          && !churchNotesAudioProcessingKillSwitch  ← WIRED       ║
// ║    CF:   createChurchNoteProcessingJob             ✅ WIRED      ║
// ║    CF:   processChurchNoteAudio                    ✅ WIRED      ║
// ║    CF:   generateChurchNoteDraft (auto-chain)      ✅ WIRED      ║
// ║    safetyStatus after audio: "approved" (no image) ✅ WIRED      ║
// ║                                                                  ║
// ║  Image OCR → uploadImageAndCreateJob                             ║
// ║    Gate: churchNotesPhotoOCREnabled                              ║
// ║          && !churchNotesProcessingKillSwitch                     ║
// ║          && !churchNotesImageModerationKillSwitch  ← WIRED       ║
// ║    CF:   createChurchNoteProcessingJob             ✅ WIRED      ║
// ║    CF:   processChurchNoteImageOCR                 ✅ WIRED      ║
// ║    safetyStatus after OCR: "pending_moderation"   ✅ WIRED       ║
// ║    Storage trigger: moderateUploadedImage                        ║
// ║      writes safetyStatus "approved"/"blocked"     ✅ WIRED       ║
// ║      back to churchNoteProcessingJobs via query   ✅ WIRED       ║
// ║    isSafeForDisplay gated on safetyStatus         ✅ CONTRACT     ║
// ║                                                                  ║
// ║  Video → uploadVideoAndCreateJob                                 ║
// ║    Gate: (churchNotesVideoCaptureEnabled                         ║
// ║          || sermonVideoCaptureEnabled)                           ║
// ║          && !churchNotesProcessingKillSwitch                     ║
// ║          && !churchNotesVideoProcessingKillSwitch  ← WIRED       ║
// ║    CF:   processChurchNoteVideo                    ✅ WIRED      ║
// ║    safetyStatus after video: "approved" (no image) ✅ WIRED      ║
// ║                                                                  ║
// ║  Document PDF → uploadDocumentAndCreateJob                       ║
// ║    Gate: churchNotesPhotoOCREnabled                              ║
// ║          && !churchNotesProcessingKillSwitch                     ║
// ║          && !churchNotesImageModerationKillSwitch  ← WIRED       ║
// ║    CF:   processChurchNoteDocumentPDF              ✅ WIRED      ║
// ║    safetyStatus after PDF: "pending_moderation"   ✅ WIRED       ║
// ║    Storage trigger write-back: same as image OCR  ✅ WIRED       ║
// ║                                                                  ║
// ╠══════════════════════════════════════════════════════════════════╣
// ║ GAPS FOUND & RESOLUTION                                          ║
// ║  GAP-1: Image moderation result never fed back into job          ║
// ║    → WIRED: moderateUploadedImage now queries                    ║
// ║      churchNoteProcessingJobs by storagePath and writes          ║
// ║      safetyStatus (approved/blocked/pending_moderation)          ║
// ║    → WIRED: processChurchNoteImageOCR and                        ║
// ║      processChurchNoteDocumentPDF now call                       ║
// ║      markJobCompleted({requiresImageModeration:true}),           ║
// ║      setting safetyStatus="pending_moderation" immediately.      ║
// ║                                                                  ║
// ║  GAP-2: No per-media-type kill switches                          ║
// ║    → WIRED: three new flags in AMENFeatureFlags.swift            ║
// ║      churchNotesAudioProcessingKillSwitch  (default: false)      ║
// ║      churchNotesImageModerationKillSwitch  (default: false)      ║
// ║      churchNotesVideoProcessingKillSwitch  (default: false)      ║
// ║      RC keys: church_notes_audio_processing_kill_switch          ║
// ║               church_notes_image_moderation_kill_switch          ║
// ║               church_notes_video_processing_kill_switch          ║
// ║      Guards wired in ChurchNotesMediaProcessingService.swift.    ║
// ║                                                                  ║
// ║  GAP-3: ChurchNoteSmartObject.safetyStatus lacks server signal   ║
// ║    → CONTRACT: SmartObject.safetyStatus is set by the backend    ║
// ║      CF on the smartObjects subcollection. The processing job    ║
// ║      safetyStatus (above) is a separate field on the job doc.    ║
// ║      ChurchNoteProcessingJob.isSafeForDisplay reads job          ║
// ║      safetyStatus, now always populated by the pipeline.         ║
// ║                                                                  ║
// ║ DECISION-GATED (human approval required before deploy)           ║
// ║  DECISION-GATE-1: Remote Config values for the three new         ║
// ║    per-type kill switches must be set in Firebase Console         ║
// ║    (default false = pipeline active) before next CF deploy.      ║
// ║  DECISION-GATE-2: Firestore index on                             ║
// ║    churchNoteProcessingJobs.storagePath (single-field) must be   ║
// ║    added to firestore.indexes.json and deployed before the       ║
// ║    imageModeration write-back query scales under load.           ║
// ╚══════════════════════════════════════════════════════════════════╝

import Foundation

/// Church Notes Smart Object contract for the `churchNotes/{noteId}/smartObjects/{objectId}` subcollection.
/// This is intentionally separate from the app-wide `AmenSmartObject`, which models generic attachments.
struct ChurchNoteSmartObject: Codable, Identifiable, Hashable, Sendable {
    static let interactiveConfidenceThreshold = 0.75
    static let confidentThreshold = 0.90

    let id: String
    let type: ChurchNoteSmartObjectType
    let source: ChurchNoteSmartObjectSource
    let confidence: Double
    let privacyLevel: ChurchNoteSmartObjectPrivacyLevel
    let actionSet: [ChurchNoteSmartAction]
    let previewState: ChurchNoteSmartPreviewPayload
    let expandedState: ChurchNoteSmartExpandedPayload?
    let fallback: ChurchNotePlainLinkFallback
    let monetizationFlag: ChurchNoteSmartMonetizationTier
    let safetyStatus: ChurchNoteSmartSafetyStatus

    var renderState: ChurchNoteSmartRenderState {
        switch safetyStatus {
        case .pending:
            return .pendingSkeleton
        case .restricted:
            return .fallback
        case .blocked:
            return .removed
        case .approved:
            if confidence < Self.interactiveConfidenceThreshold {
                return .fallback
            }
            if confidence < Self.confidentThreshold {
                return .confirmationRequired
            }
            return .interactive
        }
    }

    var shouldRenderInteractively: Bool {
        renderState == .interactive || renderState == .confirmationRequired
    }

    var needsCorrectionAffordance: Bool {
        renderState == .confirmationRequired
    }

    var shouldRenderFallback: Bool {
        renderState == .fallback
    }

    var shouldRemoveFromRendering: Bool {
        renderState == .removed
    }

    init(
        id: String = UUID().uuidString,
        type: ChurchNoteSmartObjectType,
        source: ChurchNoteSmartObjectSource,
        confidence: Double,
        privacyLevel: ChurchNoteSmartObjectPrivacyLevel,
        actionSet: [ChurchNoteSmartAction],
        previewState: ChurchNoteSmartPreviewPayload,
        expandedState: ChurchNoteSmartExpandedPayload? = nil,
        fallback: ChurchNotePlainLinkFallback,
        monetizationFlag: ChurchNoteSmartMonetizationTier = .free,
        safetyStatus: ChurchNoteSmartSafetyStatus = .pending
    ) {
        self.id = id
        self.type = type
        self.source = source
        self.confidence = min(max(confidence, 0), 1)
        self.privacyLevel = privacyLevel
        self.actionSet = actionSet
        self.previewState = previewState
        self.expandedState = expandedState
        self.fallback = fallback
        self.monetizationFlag = monetizationFlag
        self.safetyStatus = safetyStatus
    }

    func clamped(toParentPrivacy parentPrivacy: ChurchNoteSmartObjectPrivacyLevel) -> ChurchNoteSmartObject {
        ChurchNoteSmartObject(
            id: id,
            type: type,
            source: source,
            confidence: confidence,
            privacyLevel: privacyLevel.clamped(toParentPrivacy: parentPrivacy),
            actionSet: actionSet,
            previewState: previewState,
            expandedState: expandedState,
            fallback: fallback,
            monetizationFlag: monetizationFlag,
            safetyStatus: safetyStatus
        )
    }
}

enum ChurchNoteSmartObjectType: String, Codable, CaseIterable, Hashable, Sendable {
    case church
    case scripture
    case sermonVideo
    case audio
    case event
    case location
    case prayer
    case resource
    case group
    case person
    case song
    case findChurchIntent
    case quote
    case mixed
}

enum ChurchNoteSmartObjectSource: String, Codable, CaseIterable, Hashable, Sendable {
    case urlDetection
    case textDetection
    case attachment
    case userTagged
    case aiInferred
}

enum ChurchNoteSmartObjectPrivacyLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case `public`
    case churchOnly
    case groupOnly
    case `private`
    case anonymousPrayer
    case leaderOnly

    init(notePermission: NotePermission) {
        switch notePermission {
        case .publicNote:
            self = .public
        case .shared:
            self = .groupOnly
        case .privateNote:
            self = .private
        }
    }

    var permitsServerEnrichment: Bool {
        switch self {
        case .public, .churchOnly, .groupOnly, .anonymousPrayer, .leaderOnly:
            return true
        case .private:
            return false
        }
    }

    func clamped(toParentPrivacy parentPrivacy: ChurchNoteSmartObjectPrivacyLevel) -> ChurchNoteSmartObjectPrivacyLevel {
        rank >= parentPrivacy.rank ? self : parentPrivacy
    }

    private var rank: Int {
        switch self {
        case .public:
            return 0
        case .churchOnly:
            return 1
        case .groupOnly:
            return 2
        case .leaderOnly, .anonymousPrayer:
            return 3
        case .private:
            return 4
        }
    }
}

enum ChurchNoteSmartSafetyStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case approved
    case pending
    case restricted
    case blocked
}

enum ChurchNoteSmartRenderState: String, Codable, CaseIterable, Hashable, Sendable {
    case interactive
    case confirmationRequired
    case fallback
    case pendingSkeleton
    case removed
}

enum ChurchNoteSmartMonetizationTier: String, Codable, CaseIterable, Hashable, Sendable {
    case free
    case premiumUser
    case premiumChurch
}

enum ChurchNoteSmartActionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case open
    case readNote
    case save
    case pray
    case discuss
    case share
    case askAmen
    case watch
    case listen
    case rsvp
    case addToCalendar
    case directions
    case follow
    case planVisit
    case join
    case translate
    case createCommitment
    case generateDevotional
    case generateStudy
    case generateQuestions
}

struct ChurchNoteSmartAction: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let kind: ChurchNoteSmartActionKind
    let title: String
    let systemImage: String
    let requiresPremium: Bool

    init(
        id: String? = nil,
        kind: ChurchNoteSmartActionKind,
        title: String,
        systemImage: String,
        requiresPremium: Bool = false
    ) {
        self.id = id ?? kind.rawValue
        self.kind = kind
        self.title = title
        self.systemImage = systemImage
        self.requiresPremium = requiresPremium
    }
}

struct ChurchNoteSmartPreviewPayload: Codable, Hashable, Sendable {
    let title: String
    let subtitle: String?
    let eyebrow: String?
    let summary: String?
    let imageURL: String?
    let accentHex: String?
    let metadata: [ChurchNoteSmartMetadataPill]

    init(
        title: String,
        subtitle: String? = nil,
        eyebrow: String? = nil,
        summary: String? = nil,
        imageURL: String? = nil,
        accentHex: String? = nil,
        metadata: [ChurchNoteSmartMetadataPill] = []
    ) {
        self.title = title
        self.subtitle = subtitle
        self.eyebrow = eyebrow
        self.summary = summary
        self.imageURL = imageURL
        self.accentHex = accentHex
        self.metadata = metadata
    }
}

struct ChurchNoteSmartExpandedPayload: Codable, Hashable, Sendable {
    let title: String
    let sections: [ChurchNoteSmartExpandedSection]
    let heroImageURL: String?
    let canonicalURL: String?

    init(
        title: String,
        sections: [ChurchNoteSmartExpandedSection] = [],
        heroImageURL: String? = nil,
        canonicalURL: String? = nil
    ) {
        self.title = title
        self.sections = sections
        self.heroImageURL = heroImageURL
        self.canonicalURL = canonicalURL
    }
}

struct ChurchNoteSmartExpandedSection: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let body: String

    init(id: String = UUID().uuidString, title: String, body: String) {
        self.id = id
        self.title = title
        self.body = body
    }
}

struct ChurchNoteSmartMetadataPill: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let systemImage: String?

    init(id: String = UUID().uuidString, title: String, systemImage: String? = nil) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
    }
}

struct ChurchNotePlainLinkFallback: Codable, Hashable, Sendable {
    let title: String
    let url: String?
    let reason: ChurchNoteSmartFallbackReason

    init(title: String, url: String? = nil, reason: ChurchNoteSmartFallbackReason = .unsupported) {
        self.title = title
        self.url = url
        self.reason = reason
    }
}

enum ChurchNoteSmartFallbackReason: String, Codable, CaseIterable, Hashable, Sendable {
    case lowConfidence
    case pendingSafety
    case restrictedSafety
    case blockedSafety
    case unsupported

    init(object: ChurchNoteSmartObject) {
        switch object.safetyStatus {
        case .pending:
            self = .pendingSafety
        case .restricted:
            self = .restrictedSafety
        case .blocked:
            self = .blockedSafety
        case .approved:
            self = object.confidence < ChurchNoteSmartObject.interactiveConfidenceThreshold ? .lowConfidence : .unsupported
        }
    }
}

extension ChurchNoteSmartAction {
    static let readNote = ChurchNoteSmartAction(kind: .readNote, title: "Read", systemImage: "doc.text")
    static let save = ChurchNoteSmartAction(kind: .save, title: "Save", systemImage: "bookmark")
    static let pray = ChurchNoteSmartAction(kind: .pray, title: "Pray", systemImage: "hands.sparkles")
    static let discuss = ChurchNoteSmartAction(kind: .discuss, title: "Discuss", systemImage: "bubble.left.and.bubble.right")
    static let askAmen = ChurchNoteSmartAction(kind: .askAmen, title: "Ask", systemImage: "sparkles")
}
