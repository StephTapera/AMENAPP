// AmenSocialSafetyModels.swift
// AMENAPP — Social Safety OS core data models (Phase 2)
// Covers all 5 major social-media harm categories.

import Foundation

// Compatibility helper for legacy call sites that compare `TrustedContact.id` to String IDs.
func == (lhs: UUID, rhs: String) -> Bool { lhs.uuidString == rhs }
func == (lhs: String, rhs: UUID) -> Bool { lhs == rhs.uuidString }

// MARK: - Risk Category

enum SafetyRiskCategory: String, Codable, CaseIterable {
    case mentalHealth           = "mental_health"
    case exploitation           = "exploitation"
    case grooming               = "grooming"
    case sextortion             = "sextortion"
    case trafficking            = "trafficking"
    case harassment             = "harassment"
    case hate                   = "hate"
    case dogpile                = "dogpile"
    case misinformation         = "misinformation"
    case deepfake               = "deepfake"
    case addictiveUse           = "addictive_use"
    case unsafeRecommendation   = "unsafe_recommendation"
    case theologicalClaim       = "theological_claim"
    case medicalClaim           = "medical_claim"
    case financialClaim         = "financial_claim"
    case politicalClaim         = "political_claim"
    case selfHarm               = "self_harm"
    case sexualContent          = "sexual_content"
    case minorSafety            = "minor_safety"
    case unknown                = "unknown"
}

// MARK: - Severity

enum SafetySeverity: String, Codable, CaseIterable, Comparable {
    case none     = "none"
    case low      = "low"
    case medium   = "medium"
    case high     = "high"
    case critical = "critical"

    private var order: Int {
        switch self {
        case .none: return 0; case .low: return 1
        case .medium: return 2; case .high: return 3; case .critical: return 4
        }
    }
    static func < (lhs: SafetySeverity, rhs: SafetySeverity) -> Bool {
        lhs.order < rhs.order
    }
}

// MARK: - Action Types

enum SafetyActionType: String, Codable, CaseIterable {
    case allow                   = "allow"
    case allowWithContext         = "allow_with_context"
    case promptBeforePost         = "prompt_before_post"
    case requireRewrite           = "require_rewrite"
    case limitReach               = "limit_reach"
    case hideFromFeed             = "hide_from_feed"
    case holdForReview            = "hold_for_review"
    case blockSend                = "block_send"
    case disableDM                = "disable_dm"
    case preserveEvidence         = "preserve_evidence"
    case notifyTrustedContact     = "notify_trusted_contact"
    case showCrisisResources      = "show_crisis_resources"
    case escalateToHumanReview    = "escalate_to_human_review"
    case suspendActor             = "suspend_actor"
    case requireSource            = "require_source"
    case labelAIContent           = "label_ai_content"
    case labelUnverified          = "label_unverified"
    case downrank                 = "downrank"
    case sessionPause             = "session_pause"
    case feedBoundary             = "feed_boundary"
    case algorithmReset           = "algorithm_reset"
}

// MARK: - Safety Decision

struct SafetyDecision: Codable, Identifiable {
    var id: String
    var actorUid: String
    var targetUid: String?
    var contentId: String?
    var conversationId: String?
    var contentType: String
    var riskCategories: [SafetyRiskCategory]
    var severity: SafetySeverity
    var actions: [SafetyActionType]
    /// User-facing reason (safe to display; no internal scoring exposed).
    var userFacingReason: String?
    var confidence: Double
    var modelVersion: String?
    var policyVersion: String?
    var createdAt: Date
    var expiresAt: Date?
    var reviewStatus: SafetyReviewStatus
    var reviewerUid: String?
    var source: String

    init(
        id: String = UUID().uuidString,
        actorUid: String,
        targetUid: String? = nil,
        contentId: String? = nil,
        conversationId: String? = nil,
        contentType: String,
        riskCategories: [SafetyRiskCategory] = [],
        severity: SafetySeverity = .none,
        actions: [SafetyActionType] = [.allow],
        userFacingReason: String? = nil,
        confidence: Double = 1.0,
        modelVersion: String? = nil,
        policyVersion: String? = nil,
        createdAt: Date = .now,
        expiresAt: Date? = nil,
        reviewStatus: SafetyReviewStatus = .notRequired,
        reviewerUid: String? = nil,
        source: String = "client"
    ) {
        self.id = id; self.actorUid = actorUid; self.targetUid = targetUid
        self.contentId = contentId; self.conversationId = conversationId
        self.contentType = contentType; self.riskCategories = riskCategories
        self.severity = severity; self.actions = actions
        self.userFacingReason = userFacingReason; self.confidence = confidence
        self.modelVersion = modelVersion; self.policyVersion = policyVersion
        self.createdAt = createdAt; self.expiresAt = expiresAt
        self.reviewStatus = reviewStatus; self.reviewerUid = reviewerUid
        self.source = source
    }
}

extension SafetyDecision {
    // Backward-compatible API expected by existing message safety call sites.
    var action: SafetyActionType { actions.first ?? .allow }
    var riskCategory: SafetyRiskCategory? { riskCategories.first }
    var reason: String? { userFacingReason }
    var userFacingMessage: String? { userFacingReason }
    var requiresHumanReview: Bool { actions.contains(.escalateToHumanReview) || reviewStatus == .pending || reviewStatus == .inReview }
    var appealEligible: Bool { !actions.contains(.suspendActor) && !actions.contains(.blockSend) }
    var decidedAt: Date { createdAt }

    init(
        action: SafetyActionType,
        riskCategory: SafetyRiskCategory?,
        severity: SafetySeverity,
        reason: String?,
        userFacingMessage: String?,
        requiresHumanReview: Bool,
        appealEligible: Bool,
        decidedAt: Date
    ) {
        var finalActions: [SafetyActionType] = [action]
        if requiresHumanReview {
            finalActions.append(.escalateToHumanReview)
        }
        self.init(
            actorUid: "",
            contentType: "unknown",
            riskCategories: riskCategory.map { [$0] } ?? [],
            severity: severity,
            actions: finalActions,
            userFacingReason: reason ?? userFacingMessage,
            createdAt: decidedAt,
            reviewStatus: requiresHumanReview ? .pending : .notRequired
        )
    }
}

enum SafetyReviewStatus: String, Codable {
    case notRequired = "not_required"
    case pending     = "pending"
    case inReview    = "in_review"
    case resolved    = "resolved"
    case appealed    = "appealed"
    case escalated   = "escalated"
}

// MARK: - Wellbeing Signal

struct WellbeingSignal: Codable, Identifiable {
    var id: String
    var uid: String
    var signalType: WellbeingSignalType
    var value: Double
    var confidence: Double
    var createdAt: Date
    var expiresAt: Date?
    var source: String
    /// Whether this signal is surfaced to the user (not all are).
    var isClientVisible: Bool

    init(
        id: String = UUID().uuidString,
        uid: String,
        signalType: WellbeingSignalType,
        value: Double,
        confidence: Double = 1.0,
        createdAt: Date = .now,
        expiresAt: Date? = nil,
        source: String = "client",
        isClientVisible: Bool = false
    ) {
        self.id = id; self.uid = uid; self.signalType = signalType
        self.value = value; self.confidence = confidence
        self.createdAt = createdAt; self.expiresAt = expiresAt
        self.source = source; self.isClientVisible = isClientVisible
    }
}

enum WellbeingSignalType: String, Codable {
    case rapidScroll            = "rapid_scroll"
    case lateNightUse           = "late_night_use"
    case negativeEngagement     = "negative_engagement"
    case repeatedAppOpen        = "repeated_app_open"
    case highEmotionalDraft     = "high_emotional_draft"
    case sessionLength          = "session_length"
    case postsViewed            = "posts_viewed"
    case deletedDrafts          = "deleted_drafts"
}

// MARK: - Trusted Contact Compatibility

extension TrustedContact {
    init(
        id: String = UUID().uuidString,
        contactUserId: String,
        displayName: String,
        avatarURL: String? = nil,
        relationshipType: TrustedContactRelationshipType = .friend,
        notificationLevel: TrustedContactNotificationLevel = .alerts,
        addedAt: Date = .now
    ) {
        self.init(
            id: UUID(uuidString: id) ?? UUID(),
            name: displayName,
            phone: contactUserId,
            relationship: relationshipType.rawValue
        )
    }

    var contactUserId: String { phone }
    var displayName: String { name }
    var avatarURL: String? { nil }
    var relationshipType: TrustedContactRelationshipType {
        TrustedContactRelationshipType(rawValue: relationship.lowercased()) ?? .friend
    }
    var notificationLevel: TrustedContactNotificationLevel { .alerts }
    var addedAt: Date { .now }
}

enum TrustedContactRelationshipType: String, Codable, CaseIterable {
    case parent   = "parent"
    case guardian = "guardian"
    case sibling  = "sibling"
    case mentor   = "mentor"
    case pastor   = "pastor"
    case counselor = "counselor"
    case friend   = "friend"
    case spouse   = "spouse"
    case other    = "other"
}

enum TrustedContactNotificationLevel: String, Codable, CaseIterable {
    case all           = "all"
    case alerts        = "alerts"
    case emergencyOnly = "emergency_only"
}

// MARK: - Report Record

struct SafetyReportRecord: Codable, Identifiable {
    var id: String
    var reporterUid: String
    var reportedUid: String?
    var contentId: String?
    var conversationId: String?
    var category: SafetyRiskCategory
    var severity: SafetySeverity
    var description: String?
    var evidenceRefs: [String]
    var status: ReportStatus
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        reporterUid: String,
        reportedUid: String? = nil,
        contentId: String? = nil,
        conversationId: String? = nil,
        category: SafetyRiskCategory,
        severity: SafetySeverity = .medium,
        description: String? = nil,
        evidenceRefs: [String] = [],
        status: ReportStatus = .pending,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id; self.reporterUid = reporterUid; self.reportedUid = reportedUid
        self.contentId = contentId; self.conversationId = conversationId
        self.category = category; self.severity = severity
        self.description = description; self.evidenceRefs = evidenceRefs
        self.status = status; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

enum ReportStatus: String, Codable {
    case pending    = "pending"
    case inReview   = "in_review"
    case resolved   = "resolved"
    case dismissed  = "dismissed"
    case escalated  = "escalated"
}

// MARK: - Feed Control State

struct FeedControlState: Codable {
    var activeMode: FeedMode
    var blockedCategories: Set<SafetyRiskCategory>
    var sessionDurationLimitMinutes: Int?
    var quietHoursStart: String?
    var quietHoursEnd: String?

    init(
        activeMode: FeedMode = .balanced,
        blockedCategories: Set<SafetyRiskCategory> = [],
        sessionDurationLimitMinutes: Int? = nil,
        quietHoursStart: String? = nil,
        quietHoursEnd: String? = nil
    ) {
        self.activeMode = activeMode
        self.blockedCategories = blockedCategories
        self.sessionDurationLimitMinutes = sessionDurationLimitMinutes
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case categories
        case sessionDurationLimitMinutes = "sessionDurationMinutes"
        case quietHoursStart
        case quietHoursEnd
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawMode = try container.decodeIfPresent(String.self, forKey: .mode) ?? FeedMode.balanced.rawValue
        activeMode = FeedMode(rawValue: rawMode) ?? .balanced
        let rawCategories = try container.decodeIfPresent([String].self, forKey: .categories) ?? []
        blockedCategories = Set(rawCategories.compactMap(SafetyRiskCategory.init(rawValue:)))
        sessionDurationLimitMinutes = try container.decodeIfPresent(Int.self, forKey: .sessionDurationLimitMinutes)
        quietHoursStart = try container.decodeIfPresent(String.self, forKey: .quietHoursStart)
        quietHoursEnd = try container.decodeIfPresent(String.self, forKey: .quietHoursEnd)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(activeMode.rawValue, forKey: .mode)
        try container.encode(blockedCategories.map(\.rawValue), forKey: .categories)
        try container.encodeIfPresent(sessionDurationLimitMinutes, forKey: .sessionDurationLimitMinutes)
        try container.encodeIfPresent(quietHoursStart, forKey: .quietHoursStart)
        try container.encodeIfPresent(quietHoursEnd, forKey: .quietHoursEnd)
    }
}

// MARK: - Content Integrity Label

struct ContentIntegrityLabel: Codable, Identifiable {
    var id: String
    var contentId: String
    var contentType: String
    var labelType: IntegrityLabelType
    var confidence: Double
    var source: String
    var explanation: String?
    var createdAt: Date
    var expiresAt: Date?

    init(
        id: String = UUID().uuidString,
        contentId: String,
        contentType: String,
        labelType: IntegrityLabelType,
        confidence: Double,
        source: String = "system",
        explanation: String? = nil,
        createdAt: Date = .now,
        expiresAt: Date? = nil
    ) {
        self.id = id; self.contentId = contentId; self.contentType = contentType
        self.labelType = labelType; self.confidence = confidence
        self.source = source; self.explanation = explanation
        self.createdAt = createdAt; self.expiresAt = expiresAt
    }
}

enum IntegrityLabelType: String, Codable, CaseIterable {
    case aiGenerated        = "ai_generated"
    case aiEdited           = "ai_edited"
    case unverifiedClaim    = "unverified_claim"
    case disputedClaim      = "disputed_claim"
    case needsContext       = "needs_context"
    case partiallyTrue      = "partially_true"
    case sourceUnclear      = "source_unclear"
    case personalOpinion    = "personal_opinion"
    case theologicalInterp  = "theological_interpretation"

    var userFacingLabel: String {
        switch self {
        case .aiGenerated:       return "May be AI-generated"
        case .aiEdited:          return "May be AI-edited"
        case .unverifiedClaim:   return "Unverified claim"
        case .disputedClaim:     return "Disputed"
        case .needsContext:      return "Needs context"
        case .partiallyTrue:     return "Partially accurate"
        case .sourceUnclear:     return "Source unclear"
        case .personalOpinion:   return "Personal opinion"
        case .theologicalInterp: return "One interpretation"
        }
    }

    var icon: String {
        switch self {
        case .aiGenerated, .aiEdited: return "cpu"
        case .unverifiedClaim, .disputedClaim: return "exclamationmark.triangle"
        case .needsContext, .partiallyTrue: return "info.circle"
        case .sourceUnclear: return "questionmark.circle"
        case .personalOpinion, .theologicalInterp: return "bubble.left"
        }
    }
}

// MARK: - Session Boundary

struct SessionBoundary: Codable, Identifiable {
    var id: String
    var uid: String
    var sessionId: String
    var postsViewed: Int
    var scrollVelocityScore: Double
    var timeSpentSeconds: Int
    var lateNightUse: Bool
    var negativeEngagementScore: Double
    var pauseShown: Bool
    var actionTaken: SessionBoundaryAction?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        uid: String,
        sessionId: String,
        postsViewed: Int = 0,
        scrollVelocityScore: Double = 0,
        timeSpentSeconds: Int = 0,
        lateNightUse: Bool = false,
        negativeEngagementScore: Double = 0,
        pauseShown: Bool = false,
        actionTaken: SessionBoundaryAction? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id; self.uid = uid; self.sessionId = sessionId
        self.postsViewed = postsViewed; self.scrollVelocityScore = scrollVelocityScore
        self.timeSpentSeconds = timeSpentSeconds; self.lateNightUse = lateNightUse
        self.negativeEngagementScore = negativeEngagementScore
        self.pauseShown = pauseShown; self.actionTaken = actionTaken
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

enum SessionBoundaryAction: String, Codable {
    case breathe          = "breathe"
    case pray             = "pray"
    case journal          = "journal"
    case reflectPrivately = "reflect_privately"
    case talkToSomeone    = "talk_to_someone"
    case continueIntentn  = "continue_intentionally"
    case closeSession     = "close_session"
}

// MARK: - Claim Context

struct ClaimContext: Codable, Identifiable {
    var id: String
    var contentId: String
    var claimText: String
    var claimType: ClaimType
    var sourceUrls: [String]
    var scriptureRefs: [String]
    var confidence: Double
    var verificationStatus: ClaimVerificationStatus
    var contextSummary: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        contentId: String,
        claimText: String,
        claimType: ClaimType,
        sourceUrls: [String] = [],
        scriptureRefs: [String] = [],
        confidence: Double = 0.5,
        verificationStatus: ClaimVerificationStatus = .pending,
        contextSummary: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id; self.contentId = contentId; self.claimText = claimText
        self.claimType = claimType; self.sourceUrls = sourceUrls
        self.scriptureRefs = scriptureRefs; self.confidence = confidence
        self.verificationStatus = verificationStatus
        self.contextSummary = contextSummary; self.createdAt = createdAt
    }
}

enum ClaimType: String, Codable, CaseIterable {
    case personalOpinion  = "personal_opinion"
    case interpretation   = "interpretation"
    case factualClaim     = "factual_claim"
    case medicalClaim     = "medical_claim"
    case politicalClaim   = "political_claim"
    case financialClaim   = "financial_claim"
    case theologicalClaim = "theological_claim"
    case prophecy         = "prophecy"
    case newsEvent        = "news_event"
    case crisisAlert      = "crisis_alert"
    case allegation       = "allegation"
}

enum ClaimVerificationStatus: String, Codable {
    case pending    = "pending"
    case verified   = "verified"
    case disputed   = "disputed"
    case unverified = "unverified"
    case needsCtx   = "needs_context"
}
