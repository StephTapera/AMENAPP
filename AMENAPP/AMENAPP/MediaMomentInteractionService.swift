import Foundation

@MainActor
final class MediaMomentInteractionService: ObservableObject {
    static let shared = MediaMomentInteractionService()

    @Published var activeCommentAnchor: MediaMomentAnchor?
    @Published var pendingSharedMomentTarget: SharedMomentTarget?

    private init() {}

    func makeCommentAnchor(
        postId: String,
        mediaId: String,
        timestamp: Double? = nil,
        frameIndex: Int? = nil,
        anchorType: MediaMomentAnchorType,
        cueId: String? = nil,
        momentId: String? = nil,
        title: String? = nil,
        verseReference: String? = nil
    ) -> MediaMomentAnchor {
        MediaMomentAnchor(
            postId: postId,
            mediaId: mediaId,
            timestamp: timestamp,
            frameIndex: frameIndex,
            anchorType: anchorType,
            cueId: cueId,
            momentId: momentId,
            title: title,
            verseReference: verseReference
        )
    }

    func makeSavedMoment(anchor: MediaMomentAnchor, label: String, source: SavedMomentSource) -> SavedMoment {
        SavedMoment(
            id: UUID().uuidString,
            postId: anchor.postId,
            mediaId: anchor.mediaId,
            timestamp: anchor.timestamp,
            frameIndex: anchor.frameIndex,
            label: label,
            source: source,
            verseReference: anchor.verseReference,
            createdAt: Date()
        )
    }

    func makeSharedMomentTarget(anchor: MediaMomentAnchor, mediaIndex: Int) -> SharedMomentTarget {
        SharedMomentTarget(
            postId: anchor.postId,
            mediaIndex: mediaIndex,
            mediaId: anchor.mediaId,
            timestamp: anchor.timestamp,
            frameIndex: anchor.frameIndex,
            momentId: anchor.momentId
        )
    }

    func resolveViewerAnchor(
        postId: String,
        mediaId: String,
        mediaIndex: Int,
        timestamp: Double? = nil,
        frameIndex: Int? = nil,
        momentId: String? = nil
    ) -> SharedMomentTarget {
        SharedMomentTarget(
            postId: postId,
            mediaIndex: mediaIndex,
            mediaId: mediaId,
            timestamp: timestamp,
            frameIndex: frameIndex,
            momentId: momentId
        )
    }

    func clearActiveCommentAnchor() {
        activeCommentAnchor = nil
    }
}
