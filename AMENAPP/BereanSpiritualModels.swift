//
//  BereanSpiritualModels.swift
//  AMENAPP
//
//  Domain models for the Berean Spiritual Intelligence Layers:
//  - SpiritualStateClassification (Spiritual State Discernment Layer)
//  - ResponseMode (how Berean tunes its output to the user's posture)
//  - SensitivityFlag (authority alignment & crisis escalation signals)
//  - BereanStructuredResponse (the unified response contract from the backend)
//  - StudyCard (structured content card within a response)
//  - BereanMessage (unified message model for the chat surface)
//

import Foundation

// MARK: - Spiritual Primary State

/// The detected posture/emotional state of the user at the moment of a query.
/// Used by the Spiritual State Discernment Layer to choose a `ResponseMode`.
enum SpiritualPrimaryState: String, Codable, CaseIterable {
    /// User is in intellectual/curiosity mode — wants facts, context, depth.
    case academic       = "academic"
    /// User is seeking personal encouragement or comfort.
    case devotional     = "devotional"
    /// User is in emotional pain, grief, or sorrow.
    case grieving       = "grieving"
    /// User appears to be in crisis (self-harm signals, extreme distress).
    case crisis         = "crisis"
    /// User is wrestling with doubt or theological questions.
    case wrestling      = "wrestling"
    /// User is in active prayer and wants support staying in that posture.
    case prayerful      = "prayerful"
    /// User is working through a decision or moral question.
    case discerning     = "discerning"
    /// Baseline — no strong signal detected.
    case neutral        = "neutral"

    /// Whether this state should trigger human leader escalation logic.
    var requiresLeaderCheck: Bool {
        switch self {
        case .crisis, .grieving: return true
        default: return false
        }
    }

    /// Human-readable display label.
    var displayLabel: String {
        switch self {
        case .academic:    return "Studying"
        case .devotional:  return "Devotional"
        case .grieving:    return "Grieving"
        case .crisis:      return "In Crisis"
        case .wrestling:   return "Wrestling with Faith"
        case .prayerful:   return "In Prayer"
        case .discerning:  return "Discerning"
        case .neutral:     return "Exploring"
        }
    }
}

// MARK: - Secondary Signals

/// Additional context signals layered on top of the primary state.
struct SpiritualStateSignals: Codable, Equatable {
    /// Detected emotional intensity on a 0–1 scale.
    let emotionalIntensity: Double
    /// Whether the query contains doubt language.
    let containsDoubt: Bool
    /// Whether the query references personal hardship.
    let referencesHardship: Bool
    /// Whether the query contains crisis or self-harm signals.
    let crisisSignalDetected: Bool
    /// Whether the query is asking for doctrinal / theological information.
    let doctrinalQuery: Bool
    /// Whether the user mentioned a pastor, leader, or mentor.
    let mentionedLeader: Bool
    /// Confidence of the primary state classification (0–1).
    let classificationConfidence: Double
}

// MARK: - Spiritual State Classification

/// The full spiritual state classification result produced by the backend engine.
struct SpiritualStateClassification: Codable, Equatable {
    let primaryState: SpiritualPrimaryState
    let signals: SpiritualStateSignals
    /// The response mode the system selected for this state.
    let selectedResponseMode: ResponseMode
    /// Whether a safety escalation was triggered.
    let escalationTriggered: Bool
    /// Reason for escalation, if triggered.
    let escalationReason: String?
    /// Firestore session ID for the discernment session.
    let sessionId: String
    let classifiedAt: Date
}

// MARK: - Response Mode

/// How Berean tunes its language, depth, and tone in response.
enum ResponseMode: String, Codable, CaseIterable {
    /// Deep exegesis with original language, historical context, cross-references.
    case scholarly      = "scholarly"
    /// Warm, encouraging, scripture-centered devotional response.
    case pastoral       = "pastoral"
    /// Gentle, grief-aware support with minimal theological lecturing.
    case comfort        = "comfort"
    /// Immediate resources; scripture anchors; no exposition.
    case crisis         = "crisis"
    /// Balanced exploration of multiple perspectives with humility markers.
    case exploratory    = "exploratory"
    /// Prayer support: scripture-anchored, contemplative.
    case prayerSupport  = "prayer_support"
    /// Standard balanced response for neutral queries.
    case balanced       = "balanced"

    /// Whether this mode should suppress all heavy theological exposition.
    var suppressHeavyExegesis: Bool {
        switch self {
        case .comfort, .crisis, .prayerSupport: return true
        default: return false
        }
    }

    /// Maximum response length hint for this mode (in approximate words).
    var softWordLimit: Int {
        switch self {
        case .crisis:       return 150
        case .comfort:      return 200
        case .prayerSupport: return 180
        case .pastoral:     return 300
        case .balanced:     return 350
        case .exploratory:  return 400
        case .scholarly:    return 600
        }
    }
}

// MARK: - Sensitivity Flag

/// A signal that the Authority Alignment system detected and may act on.
enum SensitivityFlag: String, Codable, CaseIterable {
    /// AI attempted to assert divine authority; escalate.
    case divineAuthorityAssertion = "divine_authority_assertion"
    /// Response contradicts clear scriptural teaching.
    case scriptureContradiction   = "scripture_contradiction"
    /// Topic requires pastoral wisdom beyond AI scope.
    case pastoralEscalation       = "pastoral_escalation"
    /// Crisis signal requiring human support.
    case crisisEscalation         = "crisis_escalation"
    /// Theological controversy where traditions diverge significantly.
    case controversialDoctrine    = "controversial_doctrine"
    /// User is a minor — apply stricter content guidelines.
    case minorUser                = "minor_user"
    /// Potential scrupulosity spiral detected.
    case scrupulosityRisk         = "scrupulosity_risk"

    /// Whether this flag requires an immediate human referral prompt.
    var requiresHumanReferral: Bool {
        switch self {
        case .crisisEscalation, .pastoralEscalation: return true
        default: return false
        }
    }
}

// MARK: - Study Card

/// A structured content card that Berean can embed within a structured response.
/// Cards allow the UI to render rich formatted content beyond plain prose.
struct StudyCard: Codable, Identifiable, Equatable {
    let id: String
    let type: StudyCardType
    let title: String
    let content: String
    /// Optional scripture reference (e.g. "John 3:16 (ESV)").
    let scriptureRef: String?
    /// Optional URL for "Learn more" actions.
    let resourceURL: String?
    /// Display priority — lower number = shown first.
    let sortOrder: Int

    enum StudyCardType: String, Codable {
        /// Plain scripture quotation.
        case scripture          = "scripture"
        /// Original language word study (Greek/Hebrew).
        case wordStudy          = "word_study"
        /// Historical or cultural background.
        case historicalContext  = "historical_context"
        /// Theological commentary or explanation.
        case commentary         = "commentary"
        /// Practical application prompt.
        case application        = "application"
        /// A question for personal reflection.
        case reflection         = "reflection"
        /// Cross-reference to related passages.
        case crossReference     = "cross_reference"
        /// Christ-connection: how this passage points to Jesus.
        case christConnection   = "christ_connection"
        /// Leader or mentor referral prompt.
        case leaderReferral     = "leader_referral"
        /// Crisis resource (hotlines, support links).
        case crisisResource     = "crisis_resource"

        // Backend structured response block types.
        case text = "text"
        case verseCard = "verse_card"
        case crossReferenceCard = "cross_reference_card"
        case historicalContextCard = "historical_context_card"
        case greekHebrewWordCard = "greek_hebrew_word_card"
        case prayerCard = "prayer_card"
        case discernmentFrameworkCard = "discernment_framework_card"
        case summaryCard = "summary_card"
        case cautionCard = "caution_card"
        case actionStepCard = "action_step_card"
        case savedInsightCard = "saved_insight_card"
        case mediaKeyMomentCard = "media_key_moment_card"
        case safetyNoticeCard = "safety_notice_card"
    }
}

// MARK: - Berean Structured Response

/// The full structured response payload returned by the backend for a Spiritual
/// Intelligence query. Contains the prose answer plus any structured cards.
struct BereanStructuredResponse: Codable, Equatable {
    /// Unique ID for this response (used for caching and feedback).
    let responseId: String
    /// The main prose response text.
    let answer: String
    /// The response mode the backend applied.
    let responseMode: ResponseMode
    /// The spiritual state classification that drove this response.
    let spiritualState: SpiritualStateClassification?
    /// Structured study cards to display below the answer.
    let studyCards: [StudyCard]
    /// Any sensitivity flags raised during generation.
    let sensitivityFlags: [SensitivityFlag]
    /// Whether the user should be prompted to connect with a leader.
    let leadershipPromptShown: Bool
    /// A follow-up prompt suggestion to continue the study.
    let followUpSuggestion: String?
    /// The scripture passage that anchored the response (if any).
    let anchorPassage: String?
    /// Confidence score for the doctrinal accuracy check (0–1).
    let doctrinalConfidence: Double
    let generatedAt: Date
}

// MARK: - Berean Message

/// Unified message model for the Berean chat surface. Extends the existing
/// conversation pattern to carry Spiritual Intelligence Layer data.
struct BereanSpiritualMessage: Codable, Identifiable, Equatable {
    let id: String
    let conversationId: String
    let role: MessageRole
    /// The raw text of the message.
    let content: String
    /// Structured response payload, if this is an AI assistant message.
    let structuredResponse: BereanStructuredResponse?
    /// The response mode active when this message was generated.
    let responseMode: ResponseMode?
    /// Whether a leadership prompt was shown with this message.
    let leadershipPromptShown: Bool
    let createdAt: Date
    /// Whether the user has given feedback on this message.
    var feedbackGiven: Bool

    enum MessageRole: String, Codable {
        case user       = "user"
        case assistant  = "assistant"
        case system     = "system"
    }
}

// MARK: - Spiritual State Session

/// A single session record stored in Firestore for longitudinal tracking.
/// Firestore: /users/{uid}/spiritualStateSessions/{sessionId}
struct SpiritualStateSession: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let primaryState: SpiritualPrimaryState
    let responseMode: ResponseMode
    let sensitivityFlags: [SensitivityFlag]
    let escalationTriggered: Bool
    let messageCount: Int
    let sessionStartedAt: Date
    var sessionEndedAt: Date?
}
