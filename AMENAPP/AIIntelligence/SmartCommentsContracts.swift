// SmartCommentsContracts.swift
// AMENAPP — Smart Comments (enhanced end-to-end)
//
// Wave 0 Swift mirrors of src/comments/smartCommentsContracts.ts.
// TypeScript is source of truth. Keep in sync; add no behavior here.
//
// SCOPE SPLIT:
//   SHIP (flags OFF): text comments + entity detection + previews
//                     + layered moderation (fail-closed) + Berean features + CalmCap
//   DEFER (contracts only): VoiceComment, VoicePaymentTransaction
//   PERMANENTLY REMOVED: pay-for-reach / paid boosts of spiritual content
//
// INVARIANTS:
//   - NO read-before-moderation: a comment is NEVER publicly visible until
//     moderation passes. Fail-closed. This is the spine of the build.
//   - NO UserTrustScore model — route through existing TrustOS signals (internal).
//   - NO pay-for-boost path anywhere in this codebase.
//   - NSPrivacyTracking=false; private user data never exposed to creators.

import Foundation

// MARK: - Moderation

enum CommentModerationStatus: String, Codable, Sendable {
    case allowed       = "allowed"
    case limited       = "limited"
    case pendingReview = "pending_review"
    case blocked       = "blocked"
    case removed       = "removed"
    case appealed      = "appealed"
    case restored      = "restored"
}

enum CommentVisibilityStatus: String, Codable, Sendable {
    case `public`    = "public"
    case `private`   = "private"
    case creatorOnly = "creator_only"
    case hidden      = "hidden"
    case shadowLimited = "shadow_limited"
    case deleted     = "deleted"
}

enum ModerationCategory: String, Codable, CaseIterable, Sendable {
    case harassment             = "harassment"
    case hate                   = "hate"
    case threats                = "threats"
    case sexualContent          = "sexual_content"
    case childSafety            = "child_safety"
    case selfHarm               = "self_harm"          // → supportive resources; no method content
    case violence               = "violence"
    case scam                   = "scam"
    case spam                   = "spam"
    case malwarePhishingLink    = "malware_phishing_link"
    case impersonation          = "impersonation"
    case donationFraud          = "donation_fraud"
    case misinformation         = "misinformation"
    case spiritualAbuse         = "spiritual_abuse"    // Claimed prophetic authority used to harm
    case doxxing                = "doxxing"
    case graphicContent         = "graphic_content"
    case aiGeneratedSpam        = "ai_generated_spam"
}

struct CommentModerationResult: Codable, Identifiable, Sendable {
    let id: String
    let targetId: String
    let targetType: String  // "comment" | "reply"
    let status: CommentModerationStatus
    let category: ModerationCategory?
    let confidence: Double
    let source: ModerationSource
    let reviewedAt: TimeInterval
    let reviewedBy: String?  // Anonymized; never public

    enum ModerationSource: String, Codable, Sendable {
        case onDevice      = "on_device"
        case serverAI      = "server_ai"
        case linkScanner   = "link_scanner"
        case humanReview   = "human_review"
    }
}

struct CommentModerationAuditLog: Codable, Identifiable, Sendable {
    let id: String
    let targetId: String
    let action: AuditAction
    let reason: String?
    let actorType: ActorType
    let actorId: String?  // Internal only; never exposed publicly
    let timestamp: TimeInterval
    /// Sensitive records (crisis, child safety) encrypted at rest
    let encryptedAtRest: Bool

    enum AuditAction: String, Codable, Sendable {
        case flagged   = "flagged"
        case approved  = "approved"
        case removed   = "removed"
        case appealed  = "appealed"
        case restored  = "restored"
        case published = "published"
    }

    enum ActorType: String, Codable, Sendable {
        case system        = "system"
        case humanReviewer = "human_reviewer"
        case creator       = "creator"
        case admin         = "admin"
        case userReporter  = "user_reporter"
    }
}

// MARK: - Entity Detection

enum DetectedEntityKind: String, Codable, Sendable {
    case bibleVerse      = "bible_verse"
    case bibleReference  = "bible_reference"
    case link            = "link"
    case musicMention    = "music_mention"
    case videoLink       = "video_link"
    case prayerRequest   = "prayer_request"
    case testimony       = "testimony"
    case question        = "question"
    /// Safety workflow; never surface method content
    case crisisSignal    = "crisis_signal"
}

struct DetectedEntity: Codable, Sendable {
    let kind: DetectedEntityKind
    let rawText: String
    let startIndex: Int
    let endIndex: Int
    let metadata: [String: String]
}

// MARK: - Preview Cards

struct ScripturePreview: Codable, Sendable {
    let reference: String
    let translation: String
    let text: String
    /// Must pass CitationVerdict before display
    let citationVerified: Bool
    let crossReferenceCount: Int?
    let cachedAt: TimeInterval
}

enum LinkSafetyVerdict: String, Codable, Sendable {
    case safe        = "safe"
    case unknown     = "unknown"      // Show warning interstitial
    case suspicious  = "suspicious"   // Show warning interstitial
    case phishing    = "phishing"     // Block with explanation
    case malware     = "malware"      // Block with explanation
    case adult       = "adult"
    case extremist   = "extremist"
}

struct LinkPreview: Codable, Sendable {
    let originalUrl: String
    /// Server-expanded (shortened links resolved server-side)
    let resolvedUrl: String
    let safetyVerdict: LinkSafetyVerdict
    let title: String?
    let description: String?
    let imageUrl: String?
    let domain: String?
    /// Unknown or risky → show warning interstitial before navigation
    let requiresWarningInterstitial: Bool
    let cachedAt: TimeInterval
}

struct MusicPreview: Codable, Sendable {
    enum Platform: String, Codable, Sendable {
        case appleMusic = "apple_music"
        case spotify    = "spotify"
        case other      = "other"
    }

    let platform: Platform
    let title: String?
    let artist: String?
    let albumArtUrl: String?
    let previewUrl: String
    let safetyVerdict: LinkSafetyVerdict
    // Invariant: never autoplay — preview opens in platform app only
}

// MARK: - Comment Attachment (text/preview only — no user media upload)

enum AttachmentKind: String, Codable, Sendable {
    case scripturePreview = "scripture_preview"
    case linkPreview      = "link_preview"
    case musicPreview     = "music_preview"
    case videoPreview     = "video_preview"
}

struct CommentAttachment: Codable, Identifiable, Sendable {
    let id: String
    let kind: AttachmentKind
    let scripturePreview: ScripturePreview?
    let linkPreview: LinkPreview?
    let musicPreview: MusicPreview?
}

// MARK: - Reactions

enum CommentReactionKind: String, Codable, CaseIterable, Sendable {
    case amen      = "amen"
    case pray      = "pray"
    case testimony = "testimony"
    case save      = "save"
}

struct SmartCommentReaction: Codable, Identifiable, Sendable {
    let id: String
    let commentId: String
    let authorId: String
    let kind: CommentReactionKind
    let createdAt: TimeInterval
}

// MARK: - Comment + Reply

/// SmartComments contract model. Named `SmartComment` to avoid colliding with the
/// app-wide `Comment` type in PostInteractionModels.swift.
struct SmartComment: Codable, Identifiable, Sendable {
    let id: String
    let postId: String
    let parentCommentId: String?
    let userId: String
    let body: String
    let detectedEntities: [DetectedEntity]
    let attachments: [CommentAttachment]
    let moderationStatus: CommentModerationStatus
    /// NEVER public until moderationStatus == .allowed — fail-closed invariant
    let visibilityStatus: CommentVisibilityStatus
    let safetyLabels: [ModerationCategory]
    /// Internal TrustOS snapshot — never displayed, never exposed to creators
    let _trustScoreSnapshot: Double?
    let reactions: [SmartCommentReaction]
    let replyCount: Int
    let createdAt: TimeInterval
    let updatedAt: TimeInterval
}

struct CommentReply: Codable, Identifiable, Sendable {
    let id: String
    let commentId: String
    let userId: String
    let body: String
    let detectedEntities: [DetectedEntity]
    let attachments: [CommentAttachment]
    let moderationStatus: CommentModerationStatus
    let visibilityStatus: CommentVisibilityStatus
    let safetyLabels: [ModerationCategory]
    let reactions: [SmartCommentReaction]
    let createdAt: TimeInterval
    let updatedAt: TimeInterval
}

// MARK: - Report & Appeal

struct CommentReport: Codable, Identifiable, Sendable {
    let id: String
    let reporterId: String
    let targetId: String
    let targetType: String  // "comment" | "reply"
    let category: ModerationCategory
    let detail: String?
    let submittedAt: TimeInterval
}

struct CommentAppeal: Codable, Identifiable, Sendable {
    let id: String
    let reporterId: String
    let targetId: String
    let moderationResultId: String
    let appealText: String?
    let status: AppealStatus
    let submittedAt: TimeInterval
    let resolvedAt: TimeInterval?

    enum AppealStatus: String, Codable, Sendable {
        case pending = "pending"
        case granted = "granted"
        case denied  = "denied"
    }
}

// MARK: - CalmCap Modes

struct CalmCapSettings: Codable, Sendable {
    let slowModeEnabled: Bool
    let slowModeDelaySeconds: Int?
    let sabbathModeEnabled: Bool
    let kindnessNudgeEnabled: Bool
}

// MARK: - Deferred Contracts (no implementation in this build)

/// DEFERRED: behind media-safety gate + founder ruling + App Store policy review.
/// Requires: ESP/NCMEC registration, hash-provider contract, legal sign-off, non-engineer review.
struct SmartVoiceComment: Codable, Identifiable, Sendable {
    let id: String
    let commentId: String
    let audioUrl: String
    let durationSeconds: Int
    let transcript: String?
    let transcriptionStatus: TranscriptionStatus
    let paymentStatus: PaymentStatus?
    let moderationStatus: CommentModerationStatus
    let reviewStatus: ReviewStatus
    let publishStatus: PublishStatus

    enum TranscriptionStatus: String, Codable, Sendable {
        case pending  = "pending"
        case complete = "complete"
        case failed   = "failed"
    }

    enum PaymentStatus: String, Codable, Sendable {
        case none    = "none"
        case pending = "pending"
        case paid    = "paid"
    }

    enum ReviewStatus: String, Codable, Sendable {
        case pending  = "pending"
        case approved = "approved"
        case rejected = "rejected"
    }

    enum PublishStatus: String, Codable, Sendable {
        case draft     = "draft"
        case published = "published"
        case removed   = "removed"
    }
}
