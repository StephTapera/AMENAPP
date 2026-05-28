// ContentNode.swift
// AMENAPP
// Universal content node model (Phase 1).

import Foundation

struct ContentAuthorMetadata: Codable, Equatable {
    var displayName: String
    var username: String?
    var avatarURL: String?
    var initials: String?
    var isVerified: Bool?

    init(
        displayName: String,
        username: String? = nil,
        avatarURL: String? = nil,
        initials: String? = nil,
        isVerified: Bool? = nil
    ) {
        self.displayName = displayName
        self.username = username
        self.avatarURL = avatarURL
        self.initials = initials
        self.isVerified = isVerified
    }
}

struct ContentSourceReference: Codable, Equatable, Hashable {
    var sourceId: String?
    var sourceType: String
    var title: String?
    var url: String?
    var attribution: String?

    init(
        sourceId: String? = nil,
        sourceType: String,
        title: String? = nil,
        url: String? = nil,
        attribution: String? = nil
    ) {
        self.sourceId = sourceId
        self.sourceType = sourceType
        self.title = title
        self.url = url
        self.attribution = attribution
    }
}

struct ContentAccessibilityMetadata: Codable, Equatable {
    var altText: String?
    var transcript: String?
    var captionsAvailable: Bool
    var readingLevel: String?
    var highContrastPreferred: Bool?

    init(
        altText: String? = nil,
        transcript: String? = nil,
        captionsAvailable: Bool = false,
        readingLevel: String? = nil,
        highContrastPreferred: Bool? = nil
    ) {
        self.altText = altText
        self.transcript = transcript
        self.captionsAvailable = captionsAvailable
        self.readingLevel = readingLevel
        self.highContrastPreferred = highContrastPreferred
    }
}

struct ContentLanguageMetadata: Codable, Equatable {
    var primaryLanguage: String?
    var detectedLanguages: [String]
    var locale: String?
    var isRightToLeft: Bool?

    init(
        primaryLanguage: String? = nil,
        detectedLanguages: [String] = [],
        locale: String? = nil,
        isRightToLeft: Bool? = nil
    ) {
        self.primaryLanguage = primaryLanguage
        self.detectedLanguages = detectedLanguages
        self.locale = locale
        self.isRightToLeft = isRightToLeft
    }
}

struct ContentTranslationMetadata: Codable, Equatable {
    var isTranslated: Bool
    var originalLanguage: String?
    var translatedLanguage: String?
    var availableLanguages: [String]
    var provider: String?
    var translatedAt: Date?

    init(
        isTranslated: Bool = false,
        originalLanguage: String? = nil,
        translatedLanguage: String? = nil,
        availableLanguages: [String] = [],
        provider: String? = nil,
        translatedAt: Date? = nil
    ) {
        self.isTranslated = isTranslated
        self.originalLanguage = originalLanguage
        self.translatedLanguage = translatedLanguage
        self.availableLanguages = availableLanguages
        self.provider = provider
        self.translatedAt = translatedAt
    }
}

enum ContentPublishState: String, Codable, CaseIterable {
    case draft
    case published
    case archived
}

struct ContentNode: Identifiable, Codable, Equatable {
    var id: String
    var ownerId: String
    var author: ContentAuthorMetadata
    var type: AmenContentType
    var visibility: AmenVisibility
    var title: String?
    var text: String?
    var blocks: [ContentBlock]
    var mediaRefs: [MediaRef]
    var collaborators: [String]
    var moderationState: ModerationState
    var aiMetadata: AIMetadata
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var sourceReferences: [ContentSourceReference]
    var parentContentId: String?
    var remixSourceId: String?
    var saveEligible: Bool
    var shareEligible: Bool
    var accessibility: ContentAccessibilityMetadata?
    var language: ContentLanguageMetadata?
    var translation: ContentTranslationMetadata?
    var publishState: ContentPublishState?

    init(
        id: String = UUID().uuidString,
        ownerId: String,
        author: ContentAuthorMetadata,
        type: AmenContentType,
        visibility: AmenVisibility,
        title: String? = nil,
        text: String? = nil,
        blocks: [ContentBlock] = [],
        mediaRefs: [MediaRef] = [],
        collaborators: [String] = [],
        moderationState: ModerationState = .pending,
        aiMetadata: AIMetadata = .none,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        sourceReferences: [ContentSourceReference] = [],
        parentContentId: String? = nil,
        remixSourceId: String? = nil,
        saveEligible: Bool = true,
        shareEligible: Bool = true,
        accessibility: ContentAccessibilityMetadata? = nil,
        language: ContentLanguageMetadata? = nil,
        translation: ContentTranslationMetadata? = nil,
        publishState: ContentPublishState? = nil
    ) {
        self.id = id
        self.ownerId = ownerId
        self.author = author
        self.type = type
        self.visibility = visibility
        self.title = title
        self.text = text
        self.blocks = blocks
        self.mediaRefs = mediaRefs
        self.collaborators = collaborators
        self.moderationState = moderationState
        self.aiMetadata = aiMetadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.sourceReferences = sourceReferences
        self.parentContentId = parentContentId
        self.remixSourceId = remixSourceId
        self.saveEligible = saveEligible
        self.shareEligible = shareEligible
        self.accessibility = accessibility
        self.language = language
        self.translation = translation
        self.publishState = publishState
    }

    var displayText: String {
        if let text, !text.isEmpty {
            return text
        }
        let textBlocks = blocks.filter { $0.type == .text || $0.type == .heading || $0.type == .quote }
        return textBlocks.compactMap { $0.text }.joined(separator: "\n")
    }
}

// MARK: - Compatibility Mapping

extension Post {
    func toContentNode() -> ContentNode {
        let authorMeta = ContentAuthorMetadata(
            displayName: authorName,
            username: authorUsername,
            avatarURL: authorProfileImageURL,
            initials: authorInitials,
            isVerified: nil
        )

        let visibilityMap = visibility.toAmenVisibility
        let type: AmenContentType = churchNoteId != nil ? .churchNote : .post

        var mediaRefs: [MediaRef] = []
        if let imageURLs = imageURLs {
            mediaRefs.append(contentsOf: imageURLs.map {
                MediaRef(type: .image, url: $0, processingState: .ready)
            })
        }
        if let items = mediaItems {
            mediaRefs.append(contentsOf: items.map { item in
                MediaRef(
                    mediaId: item.id,
                    type: item.type == .video ? .video : .image,
                    url: item.url,
                    thumbnailURL: item.thumbnailURL,
                    width: item.width,
                    height: item.height,
                    duration: item.duration,
                    caption: item.frameCaption,
                    processingState: item.generationStatus.mediaProcessing
                )
            })
        }

        let moderationState: ModerationState = {
            if removed { return ModerationState.rejected }
            if flaggedForReview { return ModerationState.flagged }
            return ModerationState.approved
        }()

        let aiMeta: AIMetadata = {
            guard let usage = aiUsage else { return .none }
            return AIMetadata(
                usedAI: usage.usedAI,
                provider: nil,
                model: usage.modelVersion,
                disclosureLabel: usage.primaryLabel.displayText,
                promptSummary: usage.secondaryDetail,
                confidence: usage.aiGeneratedPercentageEstimate.map { Double($0) / 100.0 },
                generatedAt: usage.createdAt,
                safetyLabels: usage.aiUseTypes.map { $0.rawValue }
            )
        }()

        let blocks = [
            ContentBlock(type: .text, text: content, order: 0)
        ]

        return ContentNode(
            id: firebaseId ?? id.uuidString,
            ownerId: authorId,
            author: authorMeta,
            type: type,
            visibility: visibilityMap,
            title: nil,
            text: content,
            blocks: blocks,
            mediaRefs: mediaRefs,
            collaborators: [],
            moderationState: moderationState,
            aiMetadata: aiMeta,
            createdAt: createdAt,
            updatedAt: updatedAt ?? createdAt,
            deletedAt: nil,
            sourceReferences: [],
            parentContentId: nil,
            remixSourceId: nil,
            saveEligible: true,
            shareEligible: true,
            accessibility: ContentAccessibilityMetadata(altText: nil),
            language: ContentLanguageMetadata(primaryLanguage: detectedLanguage, detectedLanguages: detectedLanguage.map { [$0] } ?? []),
            translation: ContentTranslationMetadata(
                isTranslated: isTranslated,
                originalLanguage: detectedLanguage,
                translatedLanguage: isTranslated ? "en" : nil,
                availableLanguages: detectedLanguage.map { [$0, "en"] } ?? [],
                provider: nil,
                translatedAt: nil
            ),
            publishState: .published
        )
    }
}

extension ContentNode {
    func toPostPreview() -> Post {
        let initials: String = {
            if let initials = author.initials, !initials.isEmpty {
                return initials
            }
            return author.displayName
                .components(separatedBy: " ")
                .compactMap { $0.first }
                .map { String($0) }
                .joined()
                .prefix(2)
                .uppercased()
        }()

        let category = type.toPostCategory

        let postMediaItems: [PostMediaItem] = mediaRefs.enumerated().compactMap { index, ref in
            guard let url = ref.url else { return nil }
            let mediaType: PostMediaType = ref.type == .video ? .video : .image
            return PostMediaItem(
                id: ref.mediaId ?? ref.id,
                type: mediaType,
                url: url,
                thumbnailURL: ref.thumbnailURL,
                aspectRatio: ref.width.flatMap { w in
                    ref.height.map { h in h > 0 ? CGFloat(w) / CGFloat(h) : nil }
                } ?? nil,
                order: index,
                duration: ref.duration,
                width: ref.width,
                height: ref.height
            )
        }

        let imageURLs = mediaRefs.filter { $0.type == .image }.compactMap { $0.url }
        let timeAgo = createdAt.timeAgoDisplay()

        return Post(
            firebaseId: id,
            authorId: ownerId,
            authorName: author.displayName,
            authorUsername: author.username,
            authorInitials: initials,
            authorProfileImageURL: author.avatarURL,
            timeAgo: timeAgo,
            content: displayText,
            category: category,
            topicTag: nil,
            visibility: visibility.toPostVisibility,
            imageURLs: imageURLs.isEmpty ? nil : imageURLs,
            createdAt: createdAt,
            updatedAt: updatedAt,
            wasEdited: updatedAt > createdAt,
            amenCount: 0,
            lightbulbCount: 0,
            commentCount: 0,
            repostCount: 0,
            contentSource: aiMetadata.usedAI ? aiMetadata.disclosureLabel : nil,
            mediaItems: postMediaItems.isEmpty ? nil : postMediaItems
        )
    }
}

// MARK: - Mapping Helpers

extension Post.PostVisibility {
    var toAmenVisibility: AmenVisibility {
        switch self {
        case .everyone: return .public
        case .followers: return .followers
        case .community: return .church
        }
    }
}

extension AmenVisibility {
    var toPostVisibility: Post.PostVisibility {
        switch self {
        case .public: return .everyone
        case .followers: return .followers
        case .group, .church, .private: return .community
        }
    }
}

extension AmenContentType {
    var toPostCategory: Post.PostCategory {
        switch self {
        case .post, .discussion, .aiSession, .note, .design, .selah, .churchNote,
             .video, .comment, .reply, .mediaPost, .prayerPost, .testimonyPost, .scripturePost:
            return .openTable
        }
    }
}
