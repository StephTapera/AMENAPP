import Foundation

// MARK: - Supporting Enums

enum AmenSmartObjectType: String, Codable, CaseIterable, Hashable {
    case mediaTrack
    case album
    case playlist
    case artist
    case video
    case podcast
    case article
    case scripture
    case person
    case place
    case event
    case genericLink
}

enum AmenSmartContentCategory: String, Codable, CaseIterable, Hashable {
    case worship
    case devotional
    case educational
    case entertainment
    case news
    case scripture
    case prayer
    case testimony
    case sermon
    case music
    case podcast
    case article
    case general
}

enum AmenSmartUserIntent: String, Codable, CaseIterable, Hashable {
    case listen
    case watch
    case read
    case share
    case save
    case pray
    case discuss
    case reflect
    case unknown
}

enum AmenSmartMemoryDestination: String, Codable, CaseIterable, Hashable {
    case selah
    case churchNotes
    case savedForLater
    case none
}

enum AmenSmartTranslationState: String, Codable, CaseIterable, Hashable {
    case original
    case translating
    case translated
    case failed
    case notNeeded
}

enum AmenExplicitContentState: String, Codable, CaseIterable, Hashable {
    case clean
    case explicit
    case unknown
    case limited
    case blocked
}

enum AmenSmartRemixPolicy: String, Codable, CaseIterable, Hashable {
    case open
    case restricted
    case none
}

enum AmenSmartSummaryPolicy: String, Codable, CaseIterable, Hashable {
    case allowed
    case restricted
    case none
}

enum AmenSmartSharePolicy: String, Codable, CaseIterable, Hashable {
    case `public`
    case followersOnly
    case none
}

// MARK: - AmenSmartObject

/// Universal Smart Object — wraps AmenSmartAttachment and extends it with
/// context, intent, memory routing, safety, and community hub linkage.
struct AmenSmartObject: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let objectType: AmenSmartObjectType
    let contentCategory: AmenSmartContentCategory
    let userIntent: AmenSmartUserIntent
    let suggestedActions: [AmenSmartAttachmentAction]
    let memoryDestinations: [AmenSmartMemoryDestination]
    let language: String?
    let translationState: AmenSmartTranslationState
    let explicitContentState: AmenExplicitContentState
    let remixPolicy: AmenSmartRemixPolicy
    let summaryPolicy: AmenSmartSummaryPolicy
    let sharePolicy: AmenSmartSharePolicy
    let canonicalObjectId: String?
    let attachment: AmenSmartAttachment?
    let smartLabel: String?
    let contextConfidence: Double

    /// Convenience: the safety status from the underlying attachment or derived from explicit content state.
    var resolvedSafetyStatus: AmenAttachmentSafetyStatus {
        if let status = attachment?.safetyStatus { return status }
        switch explicitContentState {
        case .blocked: return .blocked
        case .limited, .explicit: return .limited
        case .clean, .unknown: return .approved
        }
    }

    /// Convenience: the display title from attachment or a fallback.
    var displayTitle: String {
        attachment?.title ?? smartLabel ?? id
    }

    var displayArtworkUrl: String? {
        attachment?.artworkUrl
    }

    var displayCanonicalUrl: String? {
        attachment?.canonicalUrl
    }
}

// MARK: - AmenSmartObject Factory

extension AmenSmartObject {
    /// Creates a smart object from an existing attachment, inferring additional context.
    static func from(
        attachment: AmenSmartAttachment,
        postText: String = ""
    ) -> AmenSmartObject {
        let decision = AmenContextEngine.analyze(
            attachment: attachment,
            postText: postText,
            surface: .feed
        )

        return AmenSmartObject(
            id: "so_\(attachment.id)",
            objectType: objectType(for: attachment.type),
            contentCategory: decision.contentCategory,
            userIntent: decision.userIntent,
            suggestedActions: decision.primaryAction.map { [$0] + decision.secondaryActions } ?? decision.secondaryActions,
            memoryDestinations: decision.suggestedDestinations,
            language: nil,
            translationState: .notNeeded,
            explicitContentState: explicitState(for: attachment.safetyStatus),
            remixPolicy: .restricted,
            summaryPolicy: .allowed,
            sharePolicy: .public,
            canonicalObjectId: nil,
            attachment: attachment,
            smartLabel: decision.smartLabel,
            contextConfidence: decision.confidence
        )
    }

    private static func objectType(for attachmentType: AmenAttachmentType) -> AmenSmartObjectType {
        switch attachmentType {
        case .song: return .mediaTrack
        case .album: return .album
        case .playlist: return .playlist
        case .artist: return .artist
        case .video: return .video
        case .podcast: return .podcast
        case .article: return .article
        case .genericLink: return .genericLink
        case .profile: return .person
        case .post: return .genericLink
        case .reel: return .video
        case .short: return .video
        case .channel: return .genericLink
        case .episode: return .podcast
        case .sermon: return .article
        case .scripture: return .scripture
        case .event: return .event
        case .donation: return .genericLink
        case .rssFeed: return .article
        }
    }

    private static func explicitState(for safetyStatus: AmenAttachmentSafetyStatus) -> AmenExplicitContentState {
        switch safetyStatus {
        case .approved: return .clean
        case .needsReview: return .unknown
        case .limited: return .limited
        case .blocked: return .blocked
        }
    }
}
