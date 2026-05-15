// PostCardRenderModel.swift
// AMENAPP
//
// Stable, Equatable render model for PostCard.
//
// Design contract:
//   - Contains only server-confirmed display state derived from Post.
//   - Does NOT carry per-user interaction state (hasSaidAmen, isSaved, etc.).
//     Per-user state lives in PostInteractionsService and PostCard's @State optimistic vars.
//   - Equatable: enables efficient diffing in list rendering.
//   - Created outside the cell (at the feed level) to avoid body-level computation.
//   - Read-only from the card perspective; actions flow through closures/coordinators.
//
// Usage:
//   let model = PostCardRenderModel(post: post, isUserPost: isUserPost,
//                                   feedContextLabel: contextLabel, aiUsage: post.aiUsage)
//   PostCard(renderModel: model, ...)

import Foundation

// MARK: - PostCardRenderModel

struct PostCardRenderModel: Equatable {

    // MARK: - Identity
    let postId: String                  // Post.firestoreId (stable: firebaseId ?? uuid)
    let authorId: String
    let authorDisplayName: String
    let authorUsername: String?
    let authorInitials: String
    let authorAvatarURL: String?
    let authorIsPrivate: Bool           // nil → false (treat as public)

    // MARK: - Timestamp
    let timeAgoDisplay: String          // Pre-formatted "2m", "3h", etc.
    let createdAt: Date

    // MARK: - Content
    let contentText: String
    let category: Post.PostCategory
    let topicTag: String?
    let wasEdited: Bool
    let editVersion: Int
    let hasSensitiveContent: Bool
    let sensitiveContentReason: String?
    let contentSource: String?          // AI disclosure label (e.g. "ChatGPT")

    // MARK: - Media
    let mediaItems: [PostMediaItem]
    let imageURLs: [String]
    let hasWitnessMedia: Bool           // true when witnessMedia is non-nil

    var hasMedia: Bool { !mediaItems.isEmpty || !imageURLs.isEmpty }
    var mediaCount: Int { mediaItems.count + imageURLs.count }

    // MARK: - Server-confirmed engagement counts
    // These are the baseline. PostCard's @State vars hold optimistic deltas.
    let serverAmenCount: Int
    let serverLightbulbCount: Int
    let serverRepostCount: Int
    let serverCommentCount: Int

    // MARK: - Translation
    let detectedLanguage: String?       // ISO 639-1 (nil = language unknown)
    let isAlreadyTranslated: Bool       // Post.isTranslated
    var translationAvailable: Bool { detectedLanguage != nil && detectedLanguage != "en" }

    // MARK: - Thread / Repost
    let isRepost: Bool
    let originalAuthorName: String?
    let originalAuthorId: String?
    let isThreadHead: Bool
    let threadIndex: Int?               // 0 = head, nil = standalone
    let threadPostCount: Int

    // MARK: - Moderation / safety
    let flaggedForReview: Bool
    let isRemoved: Bool
    var moderationDisplayNeeded: Bool { isUserPost && (flaggedForReview || isRemoved) }

    // MARK: - Authorship / visibility
    let isUserPost: Bool
    let visibility: PostVisibility
    let lowTrustAuthor: Bool
    let isPinned: Bool

    // MARK: - Rich content
    let churchNoteId: String?
    let quote: PostQuoteMetadata?
    let poll: PostPoll?
    let linkedPrayerRequestId: String?  // Prayer arc link
    let isAnsweredPrayer: Bool

    // MARK: - Action Thread
    let hasActiveActionThread: Bool
    let actionThreadId: String?

    // MARK: - Church share
    let isChurchShare: Bool
    let sharedChurchId: String?
    let sharedChurchName: String?

    // MARK: - Reply previews (server-denormalised, no extra fetch needed)
    let dynamicReplyPreviewCandidates: [DynamicReplyPreview]

    // MARK: - Feed context (injected by the feed, not stored on Post)
    let feedContextLabel: AmenFeedContextLabel?
    let aiUsage: PostAIUsage?

    // MARK: - Derived action eligibility
    var bereanEntryEligible: Bool { !postId.isEmpty && !isRemoved }
    var mediaDetailEligible: Bool { hasMedia }
    var editEligible: Bool { isUserPost && !isRemoved }
    var tipEligible: Bool { !isUserPost }
    var quoteEligible: Bool { !isRemoved }
}

// MARK: - Init from Post

extension PostCardRenderModel {

    init(post: Post,
         isUserPost: Bool,
         feedContextLabel: AmenFeedContextLabel?,
         aiUsage: PostAIUsage?) {

        self.postId = post.firestoreId
        self.authorId = post.authorId
        self.authorDisplayName = post.authorName
        self.authorUsername = post.authorUsername
        self.authorInitials = post.authorInitials
        self.authorAvatarURL = post.authorProfileImageURL
        self.authorIsPrivate = post.authorIsPrivate ?? false

        self.timeAgoDisplay = post.timeAgo
        self.createdAt = post.createdAt

        self.contentText = post.content
        self.category = post.category
        self.topicTag = post.topicTag
        self.wasEdited = post.wasEdited
        self.editVersion = post.editVersion
        self.hasSensitiveContent = post.hasSensitiveContent
        self.sensitiveContentReason = post.sensitiveContentReason
        self.contentSource = post.contentSource

        self.mediaItems = post.mediaItems ?? []
        self.imageURLs = post.imageURLs ?? []
        self.hasWitnessMedia = post.witnessMedia != nil

        self.serverAmenCount = post.amenCount
        self.serverLightbulbCount = post.lightbulbCount
        self.serverRepostCount = post.repostCount
        self.serverCommentCount = post.commentCount

        self.detectedLanguage = post.detectedLanguage
        self.isAlreadyTranslated = post.isTranslated

        self.isRepost = post.isRepost
        self.originalAuthorName = post.originalAuthorName
        self.originalAuthorId = post.originalAuthorId
        self.isThreadHead = post.isThreadHead
        self.threadIndex = post.threadIndex
        self.threadPostCount = post.threadPostCount

        self.flaggedForReview = post.flaggedForReview
        self.isRemoved = post.removed
        self.isUserPost = isUserPost
        self.visibility = post.visibility
        self.lowTrustAuthor = post.lowTrustAuthor
        self.isPinned = post.isPinned

        self.churchNoteId = post.churchNoteId
        self.quote = post.quote
        self.poll = post.poll
        self.linkedPrayerRequestId = post.linkedPrayerRequestId
        self.isAnsweredPrayer = post.isAnsweredPrayer

        self.hasActiveActionThread = post.hasActiveActionThread
        self.actionThreadId = post.actionThreadId

        self.isChurchShare = post.isChurchShare
        self.sharedChurchId = post.sharedChurchId
        self.sharedChurchName = post.sharedChurchName

        self.dynamicReplyPreviewCandidates = post.dynamicReplyPreviewCandidates ?? []

        // feedContextLabel can come from the feed (override) or from the post itself
        self.feedContextLabel = feedContextLabel ?? post.feedContext
        self.aiUsage = aiUsage ?? post.aiUsage
    }
}

// MARK: - Preview helpers

#if DEBUG
extension PostCardRenderModel {
    static func preview(
        postId: String = "preview-post",
        authorDisplayName: String = "Steph T.",
        contentText: String = "Let all that you do be done in love. — 1 Cor 16:14",
        category: Post.PostCategory = .openTable,
        isUserPost: Bool = false,
        amenCount: Int = 12,
        flaggedForReview: Bool = false,
        isRemoved: Bool = false
    ) -> PostCardRenderModel {
        PostCardRenderModel(
            postId: postId,
            authorId: "uid-preview",
            authorDisplayName: authorDisplayName,
            authorUsername: "@stephtapera",
            authorInitials: "ST",
            authorAvatarURL: nil,
            authorIsPrivate: false,
            timeAgoDisplay: "2m",
            createdAt: Date(),
            contentText: contentText,
            category: category,
            topicTag: nil,
            wasEdited: false,
            editVersion: 0,
            hasSensitiveContent: false,
            sensitiveContentReason: nil,
            contentSource: nil,
            mediaItems: [],
            imageURLs: [],
            hasWitnessMedia: false,
            serverAmenCount: amenCount,
            serverLightbulbCount: 3,
            serverRepostCount: 1,
            serverCommentCount: 5,
            detectedLanguage: nil,
            isAlreadyTranslated: false,
            isRepost: false,
            originalAuthorName: nil,
            originalAuthorId: nil,
            isThreadHead: false,
            threadIndex: nil,
            threadPostCount: 0,
            flaggedForReview: flaggedForReview,
            isRemoved: isRemoved,
            isUserPost: isUserPost,
            visibility: .everyone,
            lowTrustAuthor: false,
            isPinned: false,
            churchNoteId: nil,
            quote: nil,
            poll: nil,
            linkedPrayerRequestId: nil,
            isAnsweredPrayer: false,
            hasActiveActionThread: false,
            actionThreadId: nil,
            isChurchShare: false,
            sharedChurchId: nil,
            sharedChurchName: nil,
            dynamicReplyPreviewCandidates: [],
            feedContextLabel: nil,
            aiUsage: nil
        )
    }
}
#endif
