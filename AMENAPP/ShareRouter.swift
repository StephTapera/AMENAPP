import SwiftUI

struct SharePresentationRoute: Identifiable, Equatable {
    let entity: ShareableEntity

    var id: String {
        "\(entity.entityType.rawValue):\(entity.id):\(entity.sourceSurface)"
    }
}

@MainActor
final class SharePresenter: ObservableObject {
    static let shared = SharePresenter()

    @Published var route: SharePresentationRoute?

    private init() {}

    func present(entity: ShareableEntity) {
        route = SharePresentationRoute(entity: entity)
    }

    func dismiss() {
        route = nil
    }
}

enum ShareRouter {
    static func entity(for post: Post, note: ChurchNote? = nil, sourceSurface: String) -> ShareableEntity {
        if let note {
            return .churchNote(note, sourceSurface: sourceSurface)
        }
        return .post(post, sourceSurface: sourceSurface)
    }

    static func entity(for note: ChurchNote, sourceSurface: String) -> ShareableEntity {
        .churchNote(note, sourceSurface: sourceSurface)
    }

    static func entityForSelah(
        title: String,
        message: String,
        verseReference: String? = nil,
        sourceSurface: String
    ) -> ShareableEntity {
        .selah(title: title, message: message, verseReference: verseReference, sourceSurface: sourceSurface)
    }

    static func entityForProfile(
        id: String,
        displayName: String,
        username: String,
        bio: String?,
        imageURL: String?,
        sourceSurface: String
    ) -> ShareableEntity {
        .profile(
            id: id,
            displayName: displayName,
            username: username,
            bio: bio,
            imageURL: imageURL,
            sourceSurface: sourceSurface
        )
    }

    static func entityForProfilePost(_ post: ProfilePost, sourceSurface: String) -> ShareableEntity {
        ShareableEntity(
            id: post.id,
            entityType: .post,
            authorId: post.authorId,
            authorName: post.authorName ?? "AMEN",
            authorUsername: nil,
            authorInitials: (post.authorName ?? "AM")
                .split(separator: " ")
                .prefix(2)
                .compactMap { $0.first.map(String.init) }
                .joined()
                .uppercased(),
            authorPhotoURL: post.authorProfileImageURL,
            visibility: .public,
            title: post.verseReference ?? "Post",
            previewText: post.content,
            mediaPreviewURL: post.imageURLs?.first,
            route: ShareRouteDescriptor(
                path: "post/\(post.id)",
                webFallbackPath: "post/\(post.id)",
                metadata: ["postId": post.id]
            ),
            externallyShareable: true,
            attributionPolicy: .required,
            sourceSurface: sourceSurface,
            linkedPostId: post.id,
            linkedChurchNoteId: nil,
            churchId: nil,
            churchName: nil,
            groupId: nil,
            prayerCircleId: nil,
            verseReference: post.verseReference,
            createdAt: post.createdAt
        )
    }

    static func present(post: Post, note: ChurchNote? = nil, sourceSurface: String) {
        SharePresenter.shared.present(entity: entity(for: post, note: note, sourceSurface: sourceSurface))
    }

    static func present(note: ChurchNote, sourceSurface: String) {
        SharePresenter.shared.present(entity: entity(for: note, sourceSurface: sourceSurface))
    }

    static func presentSelah(
        title: String,
        message: String,
        verseReference: String? = nil,
        sourceSurface: String
    ) {
        SharePresenter.shared.present(
            entity: entityForSelah(
                title: title,
                message: message,
                verseReference: verseReference,
                sourceSurface: sourceSurface
            )
        )
    }

    static func presentProfile(
        id: String,
        displayName: String,
        username: String,
        bio: String?,
        imageURL: String?,
        sourceSurface: String
    ) {
        SharePresenter.shared.present(
            entity: entityForProfile(
                id: id,
                displayName: displayName,
                username: username,
                bio: bio,
                imageURL: imageURL,
                sourceSurface: sourceSurface
            )
        )
    }

    static func presentGroup(_ group: CommunityGroup, sourceSurface: String) {
        let entity = ShareableEntity(
            id: group.id,
            entityType: .group,
            authorId: group.creatorId,
            authorName: group.name,
            authorUsername: nil,
            authorInitials: String(group.name.prefix(2)).uppercased(),
            authorPhotoURL: group.coverImageURL,
            visibility: group.isPrivate ? .privateOnly : .public,
            title: group.name,
            previewText: group.description,
            mediaPreviewURL: group.coverImageURL,
            route: ShareRouteDescriptor(
                path: "group/\(group.id)",
                webFallbackPath: "group/\(group.id)",
                metadata: ["groupId": group.id]
            ),
            externallyShareable: !group.isPrivate,
            attributionPolicy: .optional,
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
        SharePresenter.shared.present(entity: entity)
    }
}
