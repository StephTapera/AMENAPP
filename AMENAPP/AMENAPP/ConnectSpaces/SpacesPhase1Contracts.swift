// SpacesPhase1Contracts.swift
// AMEN Spaces + Connect — Phase 1–5 shared type contracts
//
// FROZEN after initial write. Do not edit without orchestrator sign-off.
// Extends ConnectSpacesPhase0Contracts.swift with monetization, events,
// livestream, AI catch-up, and trust/safety types.
// Written: 2026-06-02

import Foundation

// MARK: - Host types

enum AmenSpaceHostType: String, Codable, CaseIterable, Hashable {
    case creator
    case church
    case organization
    case nonprofit
}

// MARK: - Subscription / Monetization

/// A paid (or free) membership tier within a Space.
struct AmenSpaceSubscriptionTier: Identifiable, Codable, Hashable {
    let id: String
    var spaceId: String
    var name: String                   // e.g. "Free", "Member", "Founding Member"
    var description: String
    var monthlyPriceCents: Int         // 0 for free tier
    var annualPriceCents: Int?
    var features: [String]             // human-readable bullet list
    var order: Int                     // ascending display order
    var isActive: Bool
    var isFreeTier: Bool
    var storeKitProductId: String?     // App Store product ID for IAP
    var introMonths: Int?              // intro pricing duration
    var introPriceCents: Int?
    var createdAt: Date
}

/// Entitlement source — how did this user get access?
enum AmenEntitlementSource: String, Codable, CaseIterable, Hashable {
    case appStoreSubscription
    case hostComp
    case scholarship
    case freeTier
    case paymentFailed           // in grace period
    case revoked
}

/// Server-authoritative entitlement. Never gate on the client alone.
struct AmenSpaceEntitlement: Identifiable, Codable, Hashable {
    var id: String { userId + "_" + spaceId }
    var userId: String
    var spaceId: String
    var tierId: String
    var source: AmenEntitlementSource
    var grantedAt: Date
    var expiresAt: Date?          // nil = never expires (comp/scholarship)
    var gracePeriodEndsAt: Date?  // for dunning
    var isActive: Bool
}

/// Per-tier access matrix key
enum AmenSpaceGatedFeature: String, Codable, CaseIterable, Hashable {
    case spaceFeed
    case liveRoom
    case replayLibrary
    case chatChannels
    case aiRecap
    case studyCompanion
    case aiTranscriptSearch
    case aiClips
    case directMessage
}

// MARK: - Payout / Revenue

struct AmenSpacePayoutSummary: Identifiable, Codable, Hashable {
    let id: String           // period key, e.g. "2026-05"
    var spaceId: String
    var grossCents: Int
    var platformFeeCents: Int
    var processingFeeCents: Int
    var refundsCents: Int
    var chargebacksCents: Int
    var netPayableCents: Int
    var periodStart: Date
    var periodEnd: Date
    var status: AmenPayoutStatus
}

enum AmenPayoutStatus: String, Codable, CaseIterable, Hashable {
    case pending
    case processing
    case paid
    case failed
    case onHold
}

// MARK: - Events

enum AmenSpaceEventType: String, Codable, CaseIterable, Hashable {
    case livestream
    case audioHuddle
    case communityEvent
    case recurringGathering
    case prayerMeeting
    case studySession
}

struct AmenSpaceEvent: Identifiable, Codable, Hashable {
    let id: String
    var spaceId: String
    var hostUserId: String
    var title: String
    var eventDescription: String
    var type: AmenSpaceEventType
    var scheduledAt: Date
    var durationMinutes: Int
    var isRecurring: Bool
    var recurrenceRule: String?       // iCal RRULE string
    var rsvpUserIds: [String]
    var maxAttendees: Int?
    var requiredTierId: String?       // nil = any member
    var isLive: Bool
    var liveRoomId: String?
    var replayRef: String?
    var calendarInviteSentAt: Date?
    var createdAt: Date
    var updatedAt: Date
}

struct AmenSpaceEventRSVP: Identifiable, Codable, Hashable {
    var id: String { userId + "_" + eventId }
    var userId: String
    var eventId: String
    var spaceId: String
    var rsvpAt: Date
    var calendarAdded: Bool
}

// MARK: - Livestream / Live Rooms

enum AmenLiveRoomState: String, Codable, CaseIterable, Hashable {
    case scheduled
    case greenRoom         // host-only pre-show
    case live
    case ended
    case recordingProcessing
}

enum AmenLiveRoomMode: String, Codable, CaseIterable, Hashable {
    case video
    case audioOnly
}

struct AmenLiveRoomParticipant: Identifiable, Codable, Hashable {
    let id: String        // userId
    var displayName: String
    var isHost: Bool
    var isMod: Bool
    var hasRaisedHand: Bool
    var isMuted: Bool
    var joinedAt: Date
}

struct AmenLiveRoom: Identifiable, Codable, Hashable {
    let id: String
    var spaceId: String
    var eventId: String?
    var hostUserId: String
    var mode: AmenLiveRoomMode
    var state: AmenLiveRoomState
    var participants: [AmenLiveRoomParticipant]
    var captionsEnabled: Bool
    var translationLocale: String?    // BCP 47 e.g. "es"
    var recordingRef: String?
    var chapterMarkers: [AmenReplayChapter]
    var viewerCount: Int
    var startedAt: Date?
    var endedAt: Date?
    var createdAt: Date
}

struct AmenReplayChapter: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var offsetSeconds: TimeInterval
}

// MARK: - AI Catch-up

/// 90-second AI recap card for a replay or live room.
struct AmenAIRecap: Identifiable, Codable, Hashable {
    let id: String
    var spaceId: String
    var sourceRef: String             // liveRoomId or videoId
    var sourceTitle: String
    var keyPoints: [String]           // ≤ 5 bullets
    var scriptureRefs: [AmenConnectSpacesScriptureRefProvenance]
    var actionItems: [String]
    var quotedExcerpt: String?        // ≤ 2 sentences, cited to transcript
    var durationEstimateSecs: Int     // ~90
    var generatedAt: Date
    var aegisReviewedAt: Date?        // must pass Aegis before surfacing
}

struct AmenTranscriptSegment: Identifiable, Codable, Hashable {
    let id: String
    var sourceRef: String             // liveRoomId or videoId
    var text: String
    var startSecs: TimeInterval
    var endSecs: TimeInterval
    var speakerId: String
    var searchScore: Double?          // populated by vector search
}

struct AmenAutoClip: Identifiable, Codable, Hashable {
    let id: String
    var sourceRef: String
    var title: String
    var startSecs: TimeInterval
    var durationSecs: TimeInterval
    var thumbnailRef: String?
    var shareUrl: String?
    var generatedAt: Date
}

// MARK: - Safety / Trust

enum AmenScamFlagType: String, Codable, CaseIterable, Hashable {
    case moneyRequest
    case giftCardRequest
    case cryptoRequest
    case offPlatformPaymentRequest
    case impersonation
    case suspiciousExternalLink
    case financialAdvice
}

struct AmenScamShieldFlag: Identifiable, Codable, Hashable {
    let id: String
    var messageId: String
    var authorId: String
    var flagTypes: [AmenScamFlagType]
    var confidence: Double
    var surfaced: Bool                // shown to user
    var reviewedByHuman: Bool
    var flaggedAt: Date
}

enum AmenHostVerificationStatus: String, Codable, CaseIterable, Hashable {
    case unverified
    case pending
    case verified
    case suspended
}

struct AmenVerifiedHostProfile: Identifiable, Codable, Hashable {
    let id: String                    // spaceId
    var hostType: AmenSpaceHostType
    var verificationStatus: AmenHostVerificationStatus
    var displayName: String
    var ein: String?                  // churches/nonprofits
    var verifiedAt: Date?
    var badgeVariant: AmenHostBadgeVariant
}

enum AmenHostBadgeVariant: String, Codable, CaseIterable, Hashable {
    case individual
    case church
    case organization
    case nonprofit
}

struct AmenModerationAction: Identifiable, Codable, Hashable {
    let id: String
    var targetUserId: String
    var spaceId: String
    var actionType: AmenModerationActionType
    var reason: String
    var performedBy: String           // moderator userId
    var performedAt: Date
}

enum AmenModerationActionType: String, Codable, CaseIterable, Hashable {
    case mute
    case unmute
    case block
    case removePost
    case approveJoin
    case denyJoin
    case assignModRole
    case removeModRole
    case reportToReviewQueue
}

// MARK: - Callable contracts (Phase 1+)

enum AmenSpacesPhase1Callable: String, Codable, CaseIterable, Hashable {
    // Monetization
    case createSpaceTier
    case getSpaceEntitlement
    case processSubscription
    case processRefund
    case getPayoutSummary
    case hostKYCOnboarding

    // Events
    case createSpaceEvent
    case rsvpToEvent
    case sendEventBroadcast        // push + email + .ics
    case listUpcomingEvents

    // Live
    case createLiveRoom
    case joinLiveRoom
    case endLiveRoom
    case raiseHand
    case muteParticipant

    // AI
    case generateRecap
    case searchTranscripts
    case generateClip
    case studyCompanionQuery

    // Safety
    case scanMessageForScam
    case verifyHost
    case submitModerationAction
    case reviewJoinRequest
}
