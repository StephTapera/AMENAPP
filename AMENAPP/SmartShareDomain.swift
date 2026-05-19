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
    case storyCard = "story_card"
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
        case .storyCard: return "Story Card"
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
        case .storyCard: return "rectangle.stack.fill"
        case .copyLink: return "link"
        case .createDiscussion: return "bubble.left.and.bubble.right.fill"
        }
    }

    var destinationType: ShareDestinationType {
        switch self {
        case .shareWithGroup: return .group
        case .shareWithChurch: return .church
        case .storyCard: return .story
        case .copyLink: return .copyLink
        case .saveForLater:
            return .collection
        case .addToNotes:
            return .notes
        case .reflectPrivately:
            return .privateReflection
        case .encourageSomeone, .startConversation, .sendInMessage:
            return .directMessage
        case .createPrayerShare:
            return .prayerCircle
        case .remindMeLater:
            return .reminder
        case .createDiscussion:
            return .discussion
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
        case .group, .discoverResult, .notificationTarget: return .resource
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
                metadata: ["postId": post.firestoreId, "authorId": post.authorId]
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
            authorInitials: note.title.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased(),
            authorPhotoURL: nil,
            visibility: visibility(for: note.permission),
            title: note.title,
            previewText: note.content,
            mediaPreviewURL: nil,
            route: ShareRouteDescriptor(
                path: "notes/\(note.shareLinkId ?? note.id ?? UUID().uuidString)",
                webFallbackPath: "notes/\(note.shareLinkId ?? note.id ?? UUID().uuidString)",
                metadata: ["churchNoteId": note.id ?? "", "shareLinkId": note.shareLinkId ?? ""]
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
            authorInitials: displayName.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased(),
            authorPhotoURL: imageURL,
            visibility: .public,
            title: displayName,
            previewText: bio ?? "Profile on AMEN",
            mediaPreviewURL: imageURL,
            route: ShareRouteDescriptor(
                path: "profile/\(username)",
                webFallbackPath: username,
                metadata: ["userId": id, "username": username]
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

    static func verse(
        reference: String,
        text: String,
        translation: String? = nil,
        sourceSurface: String = "scripture_detail"
    ) -> ShareableEntity {
        let id = "\(reference)|\(translation ?? "")"
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        let preview: String = {
            if let translation, !translation.isEmpty {
                return "\(text)\n— \(reference) (\(translation))"
            }
            return "\(text)\n— \(reference)"
        }()
        return ShareableEntity(
            id: id,
            entityType: .verse,
            authorId: "scripture",
            authorName: reference,
            authorUsername: nil,
            authorInitials: "VS",
            authorPhotoURL: nil,
            visibility: .public,
            title: reference,
            previewText: preview,
            mediaPreviewURL: nil,
            route: ShareRouteDescriptor(
                path: "verse/\(id)",
                webFallbackPath: "verse/\(id)",
                metadata: ["reference": reference, "translation": translation ?? ""]
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
            verseReference: reference,
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
                metadata: ["selahId": id]
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

    /// Build a churchProfile share entity from minimal listing values.
    /// Used by surfaces that have a lightweight `Church`/`VisitCompanionChurch`
    /// model rather than a full `ChurchEntity` or `ChurchProfile`.
    static func churchListing(
        id: String,
        name: String,
        denomination: String? = nil,
        address: String? = nil,
        imageURL: String? = nil,
        sourceSurface: String = "church_listing"
    ) -> ShareableEntity {
        let initials = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
        let preview: String = {
            if let denomination, !denomination.isEmpty, let address, !address.isEmpty {
                return "\(denomination) — \(address)"
            }
            if let address, !address.isEmpty { return address }
            if let denomination, !denomination.isEmpty { return "\(denomination) church on AMEN" }
            return "Church on AMEN"
        }()
        return ShareableEntity(
            id: id,
            entityType: .churchProfile,
            authorId: id,
            authorName: name,
            authorUsername: nil,
            authorInitials: initials.isEmpty ? "CH" : initials,
            authorPhotoURL: imageURL,
            visibility: .public,
            title: name,
            previewText: preview,
            mediaPreviewURL: imageURL,
            route: ShareRouteDescriptor(
                path: "church/\(id)",
                webFallbackPath: "church/\(id)",
                metadata: ["churchId": id]
            ),
            externallyShareable: true,
            attributionPolicy: .required,
            sourceSurface: sourceSurface,
            linkedPostId: nil,
            linkedChurchNoteId: nil,
            churchId: id,
            churchName: name,
            groupId: nil,
            prayerCircleId: nil,
            verseReference: nil,
            createdAt: Date()
        )
    }

    static func church(
        from church: ChurchEntity,
        sourceSurface: String = "church_profile"
    ) -> ShareableEntity {
        let initials = church.name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
        let bio: String = {
            if let denomination = church.denomination, !denomination.isEmpty {
                return "\(denomination) church on AMEN"
            }
            return "Church on AMEN"
        }()
        return ShareableEntity(
            id: church.id,
            entityType: .churchProfile,
            authorId: church.id,
            authorName: church.name,
            authorUsername: nil,
            authorInitials: initials.isEmpty ? "CH" : initials,
            authorPhotoURL: church.logoURL ?? church.photoURL,
            visibility: .public,
            title: church.name,
            previewText: bio,
            mediaPreviewURL: church.photoURL ?? church.logoURL,
            route: ShareRouteDescriptor(
                path: "church/\(church.id)",
                webFallbackPath: "church/\(church.id)",
                metadata: ["churchId": church.id]
            ),
            externallyShareable: true,
            attributionPolicy: .required,
            sourceSurface: sourceSurface,
            linkedPostId: nil,
            linkedChurchNoteId: nil,
            churchId: church.id,
            churchName: church.name,
            groupId: nil,
            prayerCircleId: nil,
            verseReference: nil,
            createdAt: church.createdAt
        )
    }

    /// Build a `.group` share entity from a `CommunityGroup`.
    static func group(
        from group: CommunityGroup,
        sourceSurface: String = "group_profile"
    ) -> ShareableEntity {
        let initials = group.name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
        return ShareableEntity(
            id: group.id,
            entityType: .group,
            authorId: group.creatorId,
            authorName: group.name,
            authorUsername: nil,
            authorInitials: initials.isEmpty ? "GP" : initials,
            authorPhotoURL: group.coverImageURL,
            visibility: group.isPrivate ? .groupOnly : .public,
            title: group.name,
            previewText: group.description,
            mediaPreviewURL: group.coverImageURL,
            route: ShareRouteDescriptor(
                path: "group/\(group.id)",
                webFallbackPath: "group/\(group.id)",
                metadata: [
                    "groupId": group.id,
                    "category": group.category.rawValue
                ]
            ),
            externallyShareable: !group.isPrivate,
            attributionPolicy: .required,
            sourceSurface: sourceSurface,
            linkedPostId: nil,
            linkedChurchNoteId: nil,
            churchId: nil,
            churchName: nil,
            groupId: group.id,
            prayerCircleId: nil,
            verseReference: nil,
            createdAt: group.createdAt
        )
    }

    static func churchProfile(_ profile: ChurchProfile, sourceSurface: String = "church_profile") -> ShareableEntity {
        ShareableEntity(
            id: profile.id,
            entityType: .churchProfile,
            authorId: profile.ownerUserId,
            authorName: profile.displayName,
            authorUsername: profile.username,
            authorInitials: profile.displayName.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased(),
            authorPhotoURL: profile.logoURL,
            visibility: .public,
            title: profile.displayName,
            previewText: profile.bio ?? "Church profile on AMEN",
            mediaPreviewURL: profile.logoURL ?? profile.coverPhotoURL,
            route: ShareRouteDescriptor(
                path: "church/\(profile.id)",
                webFallbackPath: "church/\(profile.id)",
                metadata: ["churchId": profile.id, "username": profile.username]
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
        case .privateNote: return .privateOnly
        case .shared: return .closeFriends
        case .publicNote: return .public
        }
    }
}
