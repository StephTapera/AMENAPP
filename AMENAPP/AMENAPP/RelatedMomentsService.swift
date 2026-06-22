import Foundation

@MainActor
final class RelatedMomentsService {
    static let shared = RelatedMomentsService()

    private init() {}

    func relatedMoments(
        for item: PostMediaItem,
        in container: PostMediaContainer?,
        presentationMode: MediaPresentationMode
    ) -> [RelatedMoment] {
        var results: [RelatedMoment] = []

        if let verseReference = item.frameCaptionMetadata?.verseReference ?? item.verseLinkedMoments?.first?.reference {
            results.append(
                RelatedMoment(
                    id: "verse-\(item.id)-\(verseReference)",
                    postId: "",
                    mediaId: item.id,
                    label: verseReference,
                    kind: .verse,
                    verseReference: verseReference,
                    presentationMode: presentationMode,
                    timestamp: item.featuredFrameTime,
                    frameIndex: item.frameCaptionMetadata?.frameIndex
                )
            )
        }

        for moment in item.resolvedKeyMoments.prefix(3) {
            results.append(
                RelatedMoment(
                    id: moment.id,
                    postId: "",
                    mediaId: item.id,
                    label: moment.label,
                    kind: moment.kind,
                    verseReference: nil,
                    presentationMode: presentationMode,
                    timestamp: moment.timestamp,
                    frameIndex: nil
                )
            )
        }

        if results.isEmpty, let container {
            for sibling in container.sortedItems where sibling.id != item.id {
                if let caption = sibling.effectiveFrameCaption {
                    results.append(
                        RelatedMoment(
                            id: "frame-\(sibling.id)",
                            postId: "",
                            mediaId: sibling.id,
                            label: caption,
                            kind: nil,
                            verseReference: sibling.frameCaptionMetadata?.verseReference,
                            presentationMode: presentationMode,
                            timestamp: sibling.featuredFrameTime,
                            frameIndex: sibling.frameCaptionMetadata?.frameIndex
                        )
                    )
                }
            }
        }

        return Array(results.prefix(4))
    }
}
