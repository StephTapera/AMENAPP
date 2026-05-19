import Foundation

enum AmenAttachmentProvider: String, Codable, CaseIterable, Hashable {
    case appleMusic
    case spotify
    case youtube
    case instagram
    case threads
    case tikTok
    case x
    case facebook
    case linkedIn
    case applePodcasts
    case medium
    case substack
    case rss
    case bibleGateway
    case youVersion
    case eventbrite
    case generic
}

enum AmenAttachmentType: String, Codable, CaseIterable, Hashable {
    case song
    case album
    case playlist
    case artist
    case video
    case podcast
    case article
    case profile
    case post
    case reel
    case short
    case channel
    case episode
    case sermon
    case scripture
    case event
    case donation
    case rssFeed
    case genericLink
}

enum AmenAttachmentPlaybackPolicy: String, Codable, CaseIterable, Hashable {
    case externalOnly
    case embeddedAllowed
    case previewAllowed
}

enum AmenAttachmentSafetyStatus: String, Codable, CaseIterable, Hashable {
    case approved
    case limited
    case blocked
    case needsReview
}

enum AmenUniversalLinkState: String, Codable, CaseIterable, Hashable {
    case detecting
    case fetchingMetadata
    case extractingLinks
    case generatingContext
    case ready
    case partial
    case failed
    case restricted
    case unsafe
}

enum AmenExtractedLinkCategory: String, Codable, CaseIterable, Hashable {
    case scripture
    case source
    case guest
    case church
    case event
    case book
    case donation
    case social
    case video
    case podcast
    case music
    case article
    case product
    case unknown
}

struct AmenExtractedLink: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let url: String
    let title: String?
    let category: AmenExtractedLinkCategory
}

enum AmenSmartAttachmentAction: String, Codable, CaseIterable, Hashable {
    case open
    case listen
    case watch
    case saveToSelah
    case addToChurchNotes
    case saveForLater
    case share
    case startGroupDiscussion
    case report
    case hide
}

struct AmenSmartAttachment: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let postId: String?
    let provider: AmenAttachmentProvider
    let type: AmenAttachmentType
    let providerId: String?
    let title: String
    let subtitle: String?
    let creatorName: String?
    let description: String?
    let artworkUrl: String?
    let canonicalUrl: String
    let originalUrl: String?
    let durationMs: Int?
    let previewUrl: String?
    let attributionText: String
    let sourceLogoRequired: Bool
    let playbackPolicy: AmenAttachmentPlaybackPolicy
    let safetyStatus: AmenAttachmentSafetyStatus
    let intelligenceState: AmenUniversalLinkState?
    let sourcePlatformLabel: String?
    let publishedAtISO8601: String?
    let transcriptStatus: String?
    let aiContextStatus: String?
    let summary: String?
    let scriptureReferences: [String]?
    let extractedLinks: [AmenExtractedLink]?
    let smartActions: [AmenSmartAttachmentAction]
    let soundtrackEnabled: Bool
    let createdAt: Date?
    let updatedAt: Date?

    init(
        id: String,
        postId: String?,
        provider: AmenAttachmentProvider,
        type: AmenAttachmentType,
        providerId: String?,
        title: String,
        subtitle: String?,
        creatorName: String?,
        description: String?,
        artworkUrl: String?,
        canonicalUrl: String,
        originalUrl: String? = nil,
        durationMs: Int?,
        previewUrl: String?,
        attributionText: String,
        sourceLogoRequired: Bool,
        playbackPolicy: AmenAttachmentPlaybackPolicy,
        safetyStatus: AmenAttachmentSafetyStatus,
        intelligenceState: AmenUniversalLinkState? = nil,
        sourcePlatformLabel: String? = nil,
        publishedAtISO8601: String? = nil,
        transcriptStatus: String? = nil,
        aiContextStatus: String? = nil,
        summary: String? = nil,
        scriptureReferences: [String]? = nil,
        extractedLinks: [AmenExtractedLink]? = nil,
        smartActions: [AmenSmartAttachmentAction],
        soundtrackEnabled: Bool,
        createdAt: Date?,
        updatedAt: Date?
    ) {
        self.id = id
        self.postId = postId
        self.provider = provider
        self.type = type
        self.providerId = providerId
        self.title = title
        self.subtitle = subtitle
        self.creatorName = creatorName
        self.description = description
        self.artworkUrl = artworkUrl
        self.canonicalUrl = canonicalUrl
        self.originalUrl = originalUrl
        self.durationMs = durationMs
        self.previewUrl = previewUrl
        self.attributionText = attributionText
        self.sourceLogoRequired = sourceLogoRequired
        self.playbackPolicy = playbackPolicy
        self.safetyStatus = safetyStatus
        self.intelligenceState = intelligenceState
        self.sourcePlatformLabel = sourcePlatformLabel
        self.publishedAtISO8601 = publishedAtISO8601
        self.transcriptStatus = transcriptStatus
        self.aiContextStatus = aiContextStatus
        self.summary = summary
        self.scriptureReferences = scriptureReferences
        self.extractedLinks = extractedLinks
        self.smartActions = smartActions
        self.soundtrackEnabled = soundtrackEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum AmenAttachmentError: Error, Equatable {
    case unsupported
    case resolveFailed
    case providerUnavailable
    case blocked
    case network
    case unauthenticated
    case rateLimited
}

enum AmenAttachmentComposerState: Equatable {
    case empty
    case detecting
    case resolving
    case resolved(AmenSmartAttachment)
    case failed(AmenAttachmentError)
    case blocked(String)
}
