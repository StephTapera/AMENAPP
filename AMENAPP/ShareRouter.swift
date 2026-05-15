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
}
