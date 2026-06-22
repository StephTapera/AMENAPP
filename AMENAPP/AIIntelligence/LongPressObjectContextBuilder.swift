// LongPressObjectContextBuilder.swift
// AMENAPP — Long-Press Intelligence Layer (Wave 1)
//
// Defines the LongPressPayload union (per-object type carry) and the
// LongPressObjectContextBuilder factory that flattens it into a
// BereanObjectContext at press time.  Pure local computation; zero network calls.

import Foundation

// MARK: - Per-Object Payload Types

struct VersePayload: Sendable {
    let text: String
    let reference: String
    let translation: String?
}

struct PostPayload: Sendable {
    let text: String?
    let authorId: String
    let communityId: String?
}

struct CommentPayload: Sendable {
    let text: String?
    let authorId: String
    let threadId: String?
}

struct CreatorPayload: Sendable {
    let creatorId: String
    let displayName: String?
}

struct CommunityPayload: Sendable {
    let communityId: String
    let displayName: String?
}

struct VideoPayload: Sendable {
    let videoId: String
    let title: String?
    let creatorId: String?
    let durationSeconds: Int?
}

struct EventPayload: Sendable {
    let eventId: String
    let title: String?
    let communityId: String?
}

struct ResourcePayload: Sendable {
    let resourceId: String
    let title: String?
    let format: String?
}

struct ProfileAvatarPayload: Sendable {
    let userId: String
    let displayName: String?
}

struct MessagePayload: Sendable {
    let messageId: String
    let text: String?
    let authorId: String
    let threadId: String?
}

struct TextSelectionPayload: Sendable {
    let selectedText: String
    let sourceObjectId: String?
    let sourceObjectType: String?
}

// MARK: - Payload Union

enum LongPressPayload: Sendable {
    case verse(VersePayload)
    case post(PostPayload)
    case comment(CommentPayload)
    case creator(CreatorPayload)
    case community(CommunityPayload)
    case video(VideoPayload)
    case event(EventPayload)
    case resource(ResourcePayload)
    case profileAvatar(ProfileAvatarPayload)
    case message(MessagePayload)
    case textSelection(TextSelectionPayload)
}

// MARK: - Context Builder

struct LongPressObjectContextBuilder {

    static func build(
        objectType: LongPressObjectType,
        objectId: String,
        surface: LongPressSourceSurface,
        payload: LongPressPayload
    ) -> BereanObjectContext {
        let capturedAt = Date().timeIntervalSince1970

        switch payload {
        case .verse(let p):
            return BereanObjectContext(
                objectType: objectType,
                objectId: objectId,
                sourceSurface: surface,
                capturedAt: capturedAt,
                payloadText: p.text,
                payloadAuthorId: nil,
                payloadThreadId: nil,
                payloadReference: p.reference,
                payloadTranslation: p.translation,
                payloadCreatorId: nil,
                payloadDisplayName: nil,
                payloadCommunityId: nil,
                payloadVideoId: nil,
                payloadDurationSeconds: nil,
                payloadEventId: nil,
                payloadResourceId: nil,
                payloadFormat: nil,
                payloadUserId: nil,
                payloadMessageId: nil,
                payloadSelectedText: nil,
                payloadSourceObjectId: nil,
                payloadSourceObjectType: nil
            )

        case .post(let p):
            return BereanObjectContext(
                objectType: objectType,
                objectId: objectId,
                sourceSurface: surface,
                capturedAt: capturedAt,
                payloadText: p.text,
                payloadAuthorId: p.authorId,
                payloadThreadId: nil,
                payloadReference: nil,
                payloadTranslation: nil,
                payloadCreatorId: nil,
                payloadDisplayName: nil,
                payloadCommunityId: p.communityId,
                payloadVideoId: nil,
                payloadDurationSeconds: nil,
                payloadEventId: nil,
                payloadResourceId: nil,
                payloadFormat: nil,
                payloadUserId: nil,
                payloadMessageId: nil,
                payloadSelectedText: nil,
                payloadSourceObjectId: nil,
                payloadSourceObjectType: nil
            )

        case .comment(let p):
            return BereanObjectContext(
                objectType: objectType,
                objectId: objectId,
                sourceSurface: surface,
                capturedAt: capturedAt,
                payloadText: p.text,
                payloadAuthorId: p.authorId,
                payloadThreadId: p.threadId,
                payloadReference: nil,
                payloadTranslation: nil,
                payloadCreatorId: nil,
                payloadDisplayName: nil,
                payloadCommunityId: nil,
                payloadVideoId: nil,
                payloadDurationSeconds: nil,
                payloadEventId: nil,
                payloadResourceId: nil,
                payloadFormat: nil,
                payloadUserId: nil,
                payloadMessageId: nil,
                payloadSelectedText: nil,
                payloadSourceObjectId: nil,
                payloadSourceObjectType: nil
            )

        case .creator(let p):
            return BereanObjectContext(
                objectType: objectType,
                objectId: objectId,
                sourceSurface: surface,
                capturedAt: capturedAt,
                payloadText: nil,
                payloadAuthorId: nil,
                payloadThreadId: nil,
                payloadReference: nil,
                payloadTranslation: nil,
                payloadCreatorId: p.creatorId,
                payloadDisplayName: p.displayName,
                payloadCommunityId: nil,
                payloadVideoId: nil,
                payloadDurationSeconds: nil,
                payloadEventId: nil,
                payloadResourceId: nil,
                payloadFormat: nil,
                payloadUserId: nil,
                payloadMessageId: nil,
                payloadSelectedText: nil,
                payloadSourceObjectId: nil,
                payloadSourceObjectType: nil
            )

        case .community(let p):
            return BereanObjectContext(
                objectType: objectType,
                objectId: objectId,
                sourceSurface: surface,
                capturedAt: capturedAt,
                payloadText: nil,
                payloadAuthorId: nil,
                payloadThreadId: nil,
                payloadReference: nil,
                payloadTranslation: nil,
                payloadCreatorId: nil,
                payloadDisplayName: p.displayName,
                payloadCommunityId: p.communityId,
                payloadVideoId: nil,
                payloadDurationSeconds: nil,
                payloadEventId: nil,
                payloadResourceId: nil,
                payloadFormat: nil,
                payloadUserId: nil,
                payloadMessageId: nil,
                payloadSelectedText: nil,
                payloadSourceObjectId: nil,
                payloadSourceObjectType: nil
            )

        case .video(let p):
            return BereanObjectContext(
                objectType: objectType,
                objectId: objectId,
                sourceSurface: surface,
                capturedAt: capturedAt,
                payloadText: p.title,
                payloadAuthorId: p.creatorId,
                payloadThreadId: nil,
                payloadReference: nil,
                payloadTranslation: nil,
                payloadCreatorId: p.creatorId,
                payloadDisplayName: nil,
                payloadCommunityId: nil,
                payloadVideoId: p.videoId,
                payloadDurationSeconds: p.durationSeconds,
                payloadEventId: nil,
                payloadResourceId: nil,
                payloadFormat: nil,
                payloadUserId: nil,
                payloadMessageId: nil,
                payloadSelectedText: nil,
                payloadSourceObjectId: nil,
                payloadSourceObjectType: nil
            )

        case .event(let p):
            return BereanObjectContext(
                objectType: objectType,
                objectId: objectId,
                sourceSurface: surface,
                capturedAt: capturedAt,
                payloadText: p.title,
                payloadAuthorId: nil,
                payloadThreadId: nil,
                payloadReference: nil,
                payloadTranslation: nil,
                payloadCreatorId: nil,
                payloadDisplayName: nil,
                payloadCommunityId: p.communityId,
                payloadVideoId: nil,
                payloadDurationSeconds: nil,
                payloadEventId: p.eventId,
                payloadResourceId: nil,
                payloadFormat: nil,
                payloadUserId: nil,
                payloadMessageId: nil,
                payloadSelectedText: nil,
                payloadSourceObjectId: nil,
                payloadSourceObjectType: nil
            )

        case .resource(let p):
            return BereanObjectContext(
                objectType: objectType,
                objectId: objectId,
                sourceSurface: surface,
                capturedAt: capturedAt,
                payloadText: p.title,
                payloadAuthorId: nil,
                payloadThreadId: nil,
                payloadReference: nil,
                payloadTranslation: nil,
                payloadCreatorId: nil,
                payloadDisplayName: nil,
                payloadCommunityId: nil,
                payloadVideoId: nil,
                payloadDurationSeconds: nil,
                payloadEventId: nil,
                payloadResourceId: p.resourceId,
                payloadFormat: p.format,
                payloadUserId: nil,
                payloadMessageId: nil,
                payloadSelectedText: nil,
                payloadSourceObjectId: nil,
                payloadSourceObjectType: nil
            )

        case .profileAvatar(let p):
            return BereanObjectContext(
                objectType: objectType,
                objectId: objectId,
                sourceSurface: surface,
                capturedAt: capturedAt,
                payloadText: nil,
                payloadAuthorId: nil,
                payloadThreadId: nil,
                payloadReference: nil,
                payloadTranslation: nil,
                payloadCreatorId: nil,
                payloadDisplayName: p.displayName,
                payloadCommunityId: nil,
                payloadVideoId: nil,
                payloadDurationSeconds: nil,
                payloadEventId: nil,
                payloadResourceId: nil,
                payloadFormat: nil,
                payloadUserId: p.userId,
                payloadMessageId: nil,
                payloadSelectedText: nil,
                payloadSourceObjectId: nil,
                payloadSourceObjectType: nil
            )

        case .message(let p):
            return BereanObjectContext(
                objectType: objectType,
                objectId: objectId,
                sourceSurface: surface,
                capturedAt: capturedAt,
                payloadText: p.text,
                payloadAuthorId: p.authorId,
                payloadThreadId: p.threadId,
                payloadReference: nil,
                payloadTranslation: nil,
                payloadCreatorId: nil,
                payloadDisplayName: nil,
                payloadCommunityId: nil,
                payloadVideoId: nil,
                payloadDurationSeconds: nil,
                payloadEventId: nil,
                payloadResourceId: nil,
                payloadFormat: nil,
                payloadUserId: nil,
                payloadMessageId: p.messageId,
                payloadSelectedText: nil,
                payloadSourceObjectId: nil,
                payloadSourceObjectType: nil
            )

        case .textSelection(let p):
            return BereanObjectContext(
                objectType: objectType,
                objectId: objectId,
                sourceSurface: surface,
                capturedAt: capturedAt,
                payloadText: nil,
                payloadAuthorId: nil,
                payloadThreadId: nil,
                payloadReference: nil,
                payloadTranslation: nil,
                payloadCreatorId: nil,
                payloadDisplayName: nil,
                payloadCommunityId: nil,
                payloadVideoId: nil,
                payloadDurationSeconds: nil,
                payloadEventId: nil,
                payloadResourceId: nil,
                payloadFormat: nil,
                payloadUserId: nil,
                payloadMessageId: nil,
                payloadSelectedText: p.selectedText,
                payloadSourceObjectId: p.sourceObjectId,
                payloadSourceObjectType: p.sourceObjectType
            )
        }
    }
}
