import Foundation

// MARK: - Reply Preview Type

enum ReplyPreviewType: String, Codable, Equatable, Hashable {
    case topReply              = "topReply"
    case followedReply         = "followedReply"
    case communityPulse        = "communityPulse"
    case bereanInsight         = "bereanInsight"
    case prayerMomentum        = "prayerMomentum"
    case trustedCommunitySignal = "trustedCommunitySignal"
}

// MARK: - Dynamic Reply Preview

/// A server-ranked, moderation-approved preview candidate for inline display in PostCard.
/// Clients rotate between candidates; clients never generate preview text locally.
///
/// Firestore path: posts/{postId}/dynamicReplyPreviews/{previewId}
struct DynamicReplyPreview: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let postId: String
    let replyId: String?
    let type: ReplyPreviewType
    let previewText: String
    let authorId: String?
    let authorDisplayName: String?
    let avatarURLs: [String]
    let participantUserIds: [String]
    let score: Double
    let generatedAt: Date
    let expiresAt: Date?
    /// "approved" | "pending" | "rejected" — only "approved" is shown in the UI
    let moderationState: String
    let source: String?

    var isSafe: Bool {
        moderationState == "approved"
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() > expiresAt
    }

    // MARK: Firestore Codable

    enum CodingKeys: String, CodingKey {
        case id, postId, replyId, type, previewText
        case authorId, authorDisplayName, avatarURLs, participantUserIds
        case score, generatedAt, expiresAt, moderationState, source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                  = try c.decode(String.self, forKey: .id)
        postId              = try c.decode(String.self, forKey: .postId)
        replyId             = try c.decodeIfPresent(String.self, forKey: .replyId)
        type                = try c.decode(ReplyPreviewType.self, forKey: .type)
        previewText         = try c.decode(String.self, forKey: .previewText)
        authorId            = try c.decodeIfPresent(String.self, forKey: .authorId)
        authorDisplayName   = try c.decodeIfPresent(String.self, forKey: .authorDisplayName)
        avatarURLs          = (try? c.decode([String].self, forKey: .avatarURLs)) ?? []
        participantUserIds  = (try? c.decode([String].self, forKey: .participantUserIds)) ?? []
        score               = (try? c.decode(Double.self, forKey: .score)) ?? 0
        moderationState     = (try? c.decode(String.self, forKey: .moderationState)) ?? "pending"
        source              = try c.decodeIfPresent(String.self, forKey: .source)

        // Firestore Timestamps arrive as seconds-since-epoch doubles
        if let ts = try? c.decode(Double.self, forKey: .generatedAt) {
            generatedAt = Date(timeIntervalSince1970: ts)
        } else {
            generatedAt = (try? c.decode(Date.self, forKey: .generatedAt)) ?? Date()
        }
        if let ts = try? c.decode(Double.self, forKey: .expiresAt) {
            expiresAt = Date(timeIntervalSince1970: ts)
        } else {
            expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        }
    }

    // MARK: Memberwise init (for previews / tests only)
    init(
        id: String,
        postId: String,
        replyId: String? = nil,
        type: ReplyPreviewType,
        previewText: String,
        authorId: String? = nil,
        authorDisplayName: String? = nil,
        avatarURLs: [String] = [],
        participantUserIds: [String] = [],
        score: Double = 0.5,
        generatedAt: Date = Date(),
        expiresAt: Date? = nil,
        moderationState: String = "approved",
        source: String? = nil
    ) {
        self.id                 = id
        self.postId             = postId
        self.replyId            = replyId
        self.type               = type
        self.previewText        = previewText
        self.authorId           = authorId
        self.authorDisplayName  = authorDisplayName
        self.avatarURLs         = avatarURLs
        self.participantUserIds = participantUserIds
        self.score              = score
        self.generatedAt        = generatedAt
        self.expiresAt          = expiresAt
        self.moderationState    = moderationState
        self.source             = source
    }
}

// MARK: - ReplyCandidate

struct ReplyCandidate {
    let id: String
    let authorUID: String
    let authorDisplayName: String
    let text: String
    let createdAt: Date
    let relevanceScore: Double
    let spiritualUsefulness: Double
    let engagementScore: Double
    let safetyPassed: Bool
}

// MARK: - ResolvedReplyPreview

struct ResolvedReplyPreview {
    let postId: String
    let type: ReplyPreviewType
    let displayName: String
    let text: String
    let authorUID: String
    let avatarURL: String?
    let contentHash: String
}

// MARK: - Preview Helpers (SwiftUI preview use only, never in production feed)

#if DEBUG
extension DynamicReplyPreview {
    static let previewTopReply = DynamicReplyPreview(
        id: "prev-1",
        postId: "post-1",
        replyId: "reply-1",
        type: .topReply,
        previewText: "This reminds me of Romans 8",
        authorDisplayName: "mariah",
        avatarURLs: [],
        score: 0.91
    )

    static let previewPrayer = DynamicReplyPreview(
        id: "prev-2",
        postId: "post-1",
        type: .prayerMomentum,
        previewText: "5 people are praying with this",
        avatarURLs: [],
        score: 0.78
    )

    static let previewBerean = DynamicReplyPreview(
        id: "prev-3",
        postId: "post-1",
        type: .bereanInsight,
        previewText: "replies focused on hope + healing",
        avatarURLs: [],
        score: 0.72
    )

    static let previewPulse = DynamicReplyPreview(
        id: "prev-4",
        postId: "post-1",
        type: .communityPulse,
        previewText: "grief, hope, faith",
        avatarURLs: [],
        score: 0.65
    )
}
#endif
