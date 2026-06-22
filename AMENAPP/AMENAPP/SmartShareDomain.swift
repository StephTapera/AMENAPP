import Foundation

enum ShareableEntityType: String, Codable, CaseIterable {
    case post
    case verse
    case churchNote
    case selahPassage
    case prayerRequest
    case testimony
    case sermonClip
    case profile
    case churchProfile
    case group
    case discoverResult
    case notificationTarget
}

enum ShareEntityVisibility: String, Codable {
    case `public`
    case privateOnly
    case closeFriends
    case churchOnly
    case groupOnly
    case prayerCircleOnly
    case unavailable
}

enum ShareAttributionPolicy: String, Codable {
    case required
    case optional
    case strippedForPrivateShare
}

enum ShareIntent: String, Codable, CaseIterable, Identifiable {
    case encourageSomeone = "encourage_someone"
    case startConversation = "start_conversation"
    case shareWithGroup = "share_with_group"
    case shareWithChurch = "share_with_church"
    case addToNotes = "add_to_notes"
    case remindMeLater = "remind_me_later"
    case reflectPrivately = "reflect_privately"
    case saveForLater = "save_for_later"
    case sendInMessage = "send_in_message"
    case createPrayerShare = "create_prayer_share"
    case copyLink = "copy_link"
    case createDiscussion = "create_discussion"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .encourageSomeone: return "Encourage"
        case .startConversation: return "Conversation"
        case .shareWithGroup: return "Share Group"
        case .shareWithChurch: return "Share Church"
        case .addToNotes: return "Add to Notes"
        case .remindMeLater: return "Remind Later"
        case .reflectPrivately: return "Reflect"
        case .saveForLater: return "Save Later"
        case .sendInMessage: return "Message"
        case .createPrayerShare: return "Prayer Share"
        case .copyLink: return "Copy Link"
        case .createDiscussion: return "Discussion"
        }
    }

    var systemImage: String {
        switch self {
        case .encourageSomeone: return "heart.text.square.fill"
        case .startConversation: return "text.bubble.fill"
        case .shareWithGroup: return "person.3.fill"
        case .shareWithChurch: return "building.columns.fill"
        case .addToNotes: return "note.text.badge.plus"
        case .remindMeLater: return "bell.badge.fill"
        case .reflectPrivately: return "lock.doc.fill"
        case .saveForLater: return "bookmark.fill"
        case .sendInMessage: return "paperplane.fill"
        case .createPrayerShare: return "hands.sparkles.fill"
        case .copyLink: return "link"
        case .createDiscussion: return "bubble.left.and.bubble.right.fill"
        }
    }

    var destinationType: ShareDestinationType {
        switch self {
        case .shareWithGroup: return .group
        case .shareWithChurch: return .church
        case .copyLink: return .copyLink
        case .saveForLater, .addToNotes, .reflectPrivately: return .saved
        case .encourageSomeone, .startConversation, .sendInMessage, .createPrayerShare, .createDiscussion:
            return .directMessage
        case .remindMeLater:
            return .externalApp
        }
    }
}

struct ShareRouteDescriptor: Codable, Equatable {
    let path: String
    let webFallbackPath: String
    let metadata: [String: String]
}

struct ShareableEntity: Identifiable, Codable, Equatable {
    let id: String
    let entityType: ShareableEntityType
    let authorId: String
    let authorName: String
    let authorUsername: String?
    let authorInitials: String
    let authorPhotoURL: String?
    let visibility: ShareEntityVisibility
    let title: String
    let previewText: String
    let mediaPreviewURL: String?
    let route: ShareRouteDescriptor
    let externallyShareable: Bool
    let attributionPolicy: ShareAttributionPolicy
    let sourceSurface: String
    let linkedPostId: String?
    let linkedChurchNoteId: String?
    let churchId: String?
    let churchName: String?
    let groupId: String?
    let prayerCircleId: String?
    let verseReference: String?
    let createdAt: Date

    var shareContentType: ShareContentType {
        switch entityType {
        case .post: return .regularPost
        case .verse: return .versePost
        case .churchNote: return .churchNote
        case .selahPassage: return .resource
        case .prayerRequest: return .prayerRequest
        case .testimony: return .testimony
        case .sermonClip: return .sermonClip
        case .profile: return .profile
        case .churchProfile: return .churchProfile
        case .group: return .resource
        case .discoverResult: return .resource
        case .notificationTarget: return .resource
        }
    }

    var contextMode: ShareContextMode {
        switch shareContentType {
        case .prayerRequest: return .prayerSensitive
        case .versePost: return .verseForward
        case .churchNote: return .churchNotePreview
        default: return .standard
        }
    }

    var displaySubtitle: String {
        switch entityType {
        case .churchNote:
            return churchName ?? "Church Note"
        case .profile:
            return authorUsername.map { "@\($0)" } ?? "Profile"
        case .churchProfile:
            return churchName ?? "Church"
        case .selahPassage:
            return verseReference ?? "Selah"
        default:
            return previewText
        }
    }

    static func post(_ post: Post, sourceSurface: String = "feed") -> ShareableEntity {
        ShareableEntity(
            id: post.firestoreId,
            entityType: entityType(for: post),
            authorId: post.authorId,
            authorName: post.authorName,
            authorUsername: post.authorUsername,
            authorInitials: post.authorInitials,
            authorPhotoURL: post.authorProfileImageURL,
            visibility: visibility(for: post),
            title: post.verseReference ?? post.topicTag ?? post.category.displayName,
            previewText: post.content,
            mediaPreviewURL: post.imageURLs?.first ?? post.linkPreviewImageURL,
            route: ShareRouteDescriptor(
                path: "post/\(post.firestoreId)",
                webFallbackPath: "post/\(post.firestoreId)",
                metadata: [
                    "postId": post.firestoreId,
                    "authorId": post.authorId
                ]
            ),
            externallyShareable: visibility(for: post) == .public,
            attributionPolicy: post.category == .prayer ? .strippedForPrivateShare : .required,
            sourceSurface: sourceSurface,
            linkedPostId: post.firestoreId,
            linkedChurchNoteId: post.churchNoteId,
            churchId: post.sharedChurchId ?? post.taggedChurchId,
            churchName: post.sharedChurchName ?? post.taggedChurchName,
            groupId: nil,
            prayerCircleId: nil,
            verseReference: post.verseReference,
            createdAt: post.createdAt
        )
    }

    static func churchNote(_ note: ChurchNote, sourceSurface: String = "church_note") -> ShareableEntity {
        ShareableEntity(
            id: note.id ?? note.shareLinkId ?? UUID().uuidString,
            entityType: .churchNote,
            authorId: note.userId,
            authorName: note.churchName ?? note.title,
            authorUsername: nil,
            authorInitials: note.title
                .split(separator: " ")
                .prefix(2)
                .compactMap { $0.first.map(String.init) }
                .joined()
                .uppercased(),
            authorPhotoURL: nil,
            visibility: visibility(for: note.permission),
            title: note.title,
            previewText: note.content,
            mediaPreviewURL: nil,
            route: ShareRouteDescriptor(
                path: "notes/\(note.shareLinkId ?? note.id ?? UUID().uuidString)",
                webFallbackPath: "notes/\(note.shareLinkId ?? note.id ?? UUID().uuidString)",
                metadata: [
                    "churchNoteId": note.id ?? "",
                    "shareLinkId": note.shareLinkId ?? ""
                ]
            ),
            externallyShareable: note.permission == .publicNote,
            attributionPolicy: .required,
            sourceSurface: sourceSurface,
            linkedPostId: nil,
            linkedChurchNoteId: note.id,
            churchId: note.churchId,
            churchName: note.churchName,
            groupId: nil,
            prayerCircleId: nil,
            verseReference: note.scripture,
            createdAt: note.createdAt
        )
    }

    static func profile(
        id: String,
        displayName: String,
        username: String,
        bio: String?,
        imageURL: String?,
        sourceSurface: String = "profile"
    ) -> ShareableEntity {
        ShareableEntity(
            id: id,
            entityType: .profile,
            authorId: id,
            authorName: displayName,
            authorUsername: username,
            authorInitials: displayName
                .split(separator: " ")
                .prefix(2)
                .compactMap { $0.first.map(String.init) }
                .joined()
                .uppercased(),
            authorPhotoURL: imageURL,
            visibility: .public,
            title: displayName,
            previewText: bio ?? "Profile on AMEN",
            mediaPreviewURL: imageURL,
            route: ShareRouteDescriptor(
                path: "profile/\(username)",
                webFallbackPath: username,
                metadata: [
                    "userId": id,
                    "username": username
                ]
            ),
            externallyShareable: true,
            attributionPolicy: .required,
            sourceSurface: sourceSurface,
            linkedPostId: nil,
            linkedChurchNoteId: nil,
            churchId: nil,
            churchName: nil,
            groupId: nil,
            prayerCircleId: nil,
            verseReference: nil,
            createdAt: Date()
        )
    }

    static func selah(
        id: String = UUID().uuidString,
        title: String,
        message: String,
        verseReference: String? = nil,
        sourceSurface: String = "selah"
    ) -> ShareableEntity {
        ShareableEntity(
            id: id,
            entityType: .selahPassage,
            authorId: "selah",
            authorName: "Selah",
            authorUsername: "selah",
            authorInitials: "SE",
            authorPhotoURL: nil,
            visibility: .public,
            title: title,
            previewText: message,
            mediaPreviewURL: nil,
            route: ShareRouteDescriptor(
                path: "selah/\(id)",
                webFallbackPath: "selah/\(id)",
                metadata: [
                    "selahId": id
                ]
            ),
            externallyShareable: true,
            attributionPolicy: .required,
            sourceSurface: sourceSurface,
            linkedPostId: nil,
            linkedChurchNoteId: nil,
            churchId: nil,
            churchName: nil,
            groupId: nil,
            prayerCircleId: nil,
            verseReference: verseReference,
            createdAt: Date()
        )
    }

    static func churchProfile(_ profile: ChurchProfile, sourceSurface: String = "church_profile") -> ShareableEntity {
        ShareableEntity(
            id: profile.id,
            entityType: .churchProfile,
            authorId: profile.ownerUserId,
            authorName: profile.displayName,
            authorUsername: profile.username,
            authorInitials: profile.displayName
                .split(separator: " ")
                .prefix(2)
                .compactMap { $0.first.map(String.init) }
                .joined()
                .uppercased(),
            authorPhotoURL: profile.logoURL,
            visibility: .public,
            title: profile.displayName,
            previewText: profile.bio ?? "Church profile on AMEN",
            mediaPreviewURL: profile.logoURL ?? profile.coverPhotoURL,
            route: ShareRouteDescriptor(
                path: "church/\(profile.id)",
                webFallbackPath: "church/\(profile.id)",
                metadata: [
                    "churchId": profile.id,
                    "username": profile.username
                ]
            ),
            externallyShareable: true,
            attributionPolicy: .required,
            sourceSurface: sourceSurface,
            linkedPostId: nil,
            linkedChurchNoteId: nil,
            churchId: profile.id,
            churchName: profile.displayName,
            groupId: nil,
            prayerCircleId: nil,
            verseReference: nil,
            createdAt: profile.createdAt
        )
    }

    private static func entityType(for post: Post) -> ShareableEntityType {
        if post.churchNoteId != nil { return .churchNote }
        if post.category == .prayer { return .prayerRequest }
        if post.category == .testimonies { return .testimony }
        if post.verseReference?.isEmpty == false { return .verse }
        if post.witnessMedia != nil || (post.mediaItems?.isEmpty == false) { return .sermonClip }
        return .post
    }

    private static func visibility(for post: Post) -> ShareEntityVisibility {
        if post.removed { return .unavailable }
        if post.category == .prayer { return .prayerCircleOnly }
        if post.authorIsPrivate == true { return .privateOnly }
        if post.sharedChurchId != nil || post.taggedChurchId != nil { return .churchOnly }
        return .public
    }

    private static func visibility(for permission: NotePermission) -> ShareEntityVisibility {
        switch permission {
        case .privateNote:
            return .privateOnly
        case .shared:
            return .closeFriends
        case .publicNote:
            return .public
        }
    }
}
