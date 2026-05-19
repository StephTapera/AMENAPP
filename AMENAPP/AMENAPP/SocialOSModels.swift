// SocialOSModels.swift
// AMENAPP
//
// Core data models for the Social OS: provenance, spatial post layers,
// authenticity labels, discovery preferences, and finite media sessions.

import Foundation
import FirebaseFirestore

// MARK: - Media Provenance

struct MediaProvenance: Codable, Identifiable {
    @DocumentID var id: String?
    let postId: String
    let mediaId: String
    let ownerUid: String
    let capturedOnDevice: Bool
    let sourceType: MediaSourceType
    let uploadedAt: Date
    var editEvents: [ProvenanceEditEvent]
    var aiEvents: [ProvenanceAIEvent]
    var authenticityConfidence: Double   // 0–1
    var contentCredentialsStatus: ContentCredentialsStatus
    var syntheticMediaStatus: SyntheticMediaStatus
    var disclosureRequired: Bool
    var disclosureSatisfied: Bool
    var moderationStatus: String
    @ServerTimestamp var createdAt: Date?
    @ServerTimestamp var updatedAt: Date?

    init(
        id: String? = nil,
        postId: String,
        mediaId: String,
        ownerUid: String,
        capturedOnDevice: Bool,
        sourceType: MediaSourceType,
        uploadedAt: Date = Date(),
        editEvents: [ProvenanceEditEvent],
        aiEvents: [ProvenanceAIEvent],
        authenticityConfidence: Double,
        contentCredentialsStatus: ContentCredentialsStatus,
        syntheticMediaStatus: SyntheticMediaStatus,
        disclosureRequired: Bool,
        disclosureSatisfied: Bool,
        moderationStatus: String,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.postId = postId
        self.mediaId = mediaId
        self.ownerUid = ownerUid
        self.capturedOnDevice = capturedOnDevice
        self.sourceType = sourceType
        self.uploadedAt = uploadedAt
        self.editEvents = editEvents
        self.aiEvents = aiEvents
        self.authenticityConfidence = authenticityConfidence
        self.contentCredentialsStatus = contentCredentialsStatus
        self.syntheticMediaStatus = syntheticMediaStatus
        self.disclosureRequired = disclosureRequired
        self.disclosureSatisfied = disclosureSatisfied
        self.moderationStatus = moderationStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum MediaSourceType: String, Codable {
        case deviceCamera = "device_camera"
        case deviceLibrary = "device_library"
        case screenRecording = "screen_recording"
        case externalImport = "external_import"
        case aiGenerated = "ai_generated"
        case aiAssisted = "ai_assisted"
        case unknown = "unknown"
    }

    enum ContentCredentialsStatus: String, Codable {
        case verified = "verified"
        case pending = "pending"
        case notApplicable = "not_applicable"
        case failed = "failed"
    }

    enum SyntheticMediaStatus: String, Codable {
        case clean = "clean"
        case aiAssistedMetadata = "ai_assisted_metadata"
        case aiEditedMedia = "ai_edited_media"
        case aiGeneratedMedia = "ai_generated_media"
        case deepfakeRisk = "deepfake_risk"
        case unknown = "unknown"
    }
}

struct ProvenanceEditEvent: Codable {
    let editType: String
    let tool: String?
    let aiAssisted: Bool
    let timestamp: Date
}

struct ProvenanceAIEvent: Codable {
    let actionType: String
    let provider: String?
    let purpose: String
    let userApproved: Bool
    let timestamp: Date
}

// MARK: - Authenticity Label

struct AuthenticityLabel: Identifiable {
    let id = UUID()
    let kind: AuthenticityKind
    let title: String
    let detail: String
    let confident: Bool

    enum AuthenticityKind: String, CaseIterable {
        case realMedia = "real_media"
        case creatorVerified = "creator_verified"
        case communityVerified = "community_verified"
        case churchMedia = "church_media"
        case editedRealFootage = "edited_real_footage"
        case aiAssistedCaptions = "ai_assisted_captions"
        case aiAssistedTranslation = "ai_assisted_translation"
        case transcriptApproved = "transcript_approved"
        case pendingReview = "pending_review"
        case syntheticWarning = "synthetic_warning"
    }
}

// MARK: - Spatial Post Layer Context

struct SpatialPostContext {
    let postId: String
    let presenceCount: Int
    let activeViewers: [String]      // uids (max 3 shown)
    let contextChips: [ContextChip]
    let trustSignals: [TrustSignal]

    struct ContextChip: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        let isActive: Bool
    }

    struct TrustSignal: Identifiable {
        let id = UUID()
        let kind: TrustKind
        let label: String

        enum TrustKind { case verified, community, church, creator }
    }
}

// MARK: - Discovery Preference

struct DiscoveryPreference: Codable {
    var topicInterests: [String]
    var mutedTopics: [String]
    var preferCommunityFirst: Bool
    var preferLocalContent: Bool
    var reduceSensational: Bool
    var showWhyExplanations: Bool
    var safetyMode: SafetyDiscoveryMode
    @ServerTimestamp var updatedAt: Date?

    enum SafetyDiscoveryMode: String, Codable {
        case off, gentle, strict, familySafe
    }
}

// MARK: - Finite Media Session

struct AmenMediaSession: Identifiable, Codable {
    @DocumentID var id: String?
    let ownerUid: String
    let sessionType: SessionType
    let intent: String
    let communityIds: [String]
    let itemIds: [String]
    var currentIndex: Int
    var status: SessionStatus
    var finiteQueue: Bool
    var maxItems: Int
    var maxDurationSeconds: Int
    var reflectionPromptShown: Bool
    var sourceSurface: String
    @ServerTimestamp var createdAt: Date?
    @ServerTimestamp var startedAt: Date?
    @ServerTimestamp var completedAt: Date?

    enum SessionType: String, Codable {
        case morningInspiration = "morning_inspiration"
        case friendsAndFamily = "friends_and_family"
        case creativeDiscovery = "creative_discovery"
        case worshipAndMusic = "worship_and_music"
        case learningSession = "learning_session"
        case sermonHighlights = "sermon_highlights"
        case selahReflection = "selah_reflection"
        case testimonies = "testimonies"
        case churchMoments = "church_moments"
        case encouragement = "encouragement"
        case custom = "custom"
    }

    enum SessionStatus: String, Codable {
        case active, paused, completed, abandoned
    }
}

// MARK: - Safety Warning

struct SafetyWarning: Identifiable {
    let id = UUID()
    let warningType: WarningType
    let title: String
    let message: String
    let actions: [SafetyAction]

    enum WarningType {
        case sensitiveContent, harassment, ageRestricted, deceptiveMedia, crisisContent
    }

    struct SafetyAction: Identifiable {
        let id = UUID()
        let label: String
        let icon: String
        let isDestructive: Bool
    }
}

// MARK: - Discovery Feed Item

struct DiscoveryFeedItem: Identifiable {
    let id: String
    let postId: String
    let reasonForShowing: DiscoveryReason
    let trustScore: Double
    let safetyScore: Double
    let communityContext: String?
    let canReset: Bool

    enum DiscoveryReason: String {
        case followedTopic = "followed_topic"
        case friendInteraction = "friend_interaction"
        case localCommunity = "local_community"
        case churchContent = "church_content"
        case trustedCreator = "trusted_creator"
        case youMightKnow = "you_might_know"
        case slowFeed = "slow_feed"
    }

    var whyShownExplanation: String {
        switch reasonForShowing {
        case .followedTopic:      return "From a topic you follow"
        case .friendInteraction:  return "Someone you follow interacted with this"
        case .localCommunity:     return "From your local community"
        case .churchContent:      return "From a church you follow"
        case .trustedCreator:     return "From a creator you trust"
        case .youMightKnow:       return "From someone you might know"
        case .slowFeed:           return "Curated for mindful viewing"
        }
    }

    var whyShownIcon: String {
        switch reasonForShowing {
        case .followedTopic: return "tag"
        case .friendInteraction: return "person.2"
        case .localCommunity: return "mappin.and.ellipse"
        case .churchContent: return "building.columns"
        case .trustedCreator: return "checkmark.seal"
        case .youMightKnow: return "person.crop.circle.badge.questionmark"
        case .slowFeed: return "leaf"
        }
    }
}
