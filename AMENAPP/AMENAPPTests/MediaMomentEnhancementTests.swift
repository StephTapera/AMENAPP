#if canImport(Testing)
import Testing
@testable import AMENAPP

@Suite("Media Moment Enhancements")
struct MediaMomentEnhancementTests {
    @Test("video metadata stores verse-linked moments and presentation mode")
    func videoMetadataSupportsMomentEnhancements() {
        let verseMoment = VerseLinkedMoment(
            momentId: "moment-1",
            reference: "James 1:5",
            displayText: "Ask God for wisdom",
            timestamp: 18
        )
        let draft = VideoMetadataDraft(
            keyMoments: [KeyMomentDraft(timestamp: 18, label: "Wisdom", kind: .verse, verseReference: "James 1:5")],
            verseLinkedMoments: [verseMoment],
            presentationMode: .teaching
        )

        #expect(draft.verseLinkedMoments == [verseMoment])
        #expect(draft.presentationMode == .teaching)
        #expect(draft.keyMoments.first?.verseReference == "James 1:5")
    }

    @Test("shared moment routing round-trips timestamp targets")
    func sharedMomentRoutingRoundTrips() {
        let target = SharedMomentTarget(
            postId: "post-1",
            mediaIndex: 2,
            mediaId: "media-9",
            timestamp: 42,
            frameIndex: nil,
            momentId: "moment-42"
        )

        let url = SharedMomentRoutingService.shared.url(for: target)
        let parsed = url.flatMap { SharedMomentRoutingService.shared.parse($0) }

        #expect(parsed == target)
    }

    @Test("saved moments service matches anchors")
    @MainActor
    func savedMomentsServiceMatchesAnchor() {
        let service = SavedMomentsService.shared
        let anchor = MediaMomentAnchor(
            postId: "post-1",
            mediaId: "media-1",
            timestamp: 12,
            frameIndex: nil,
            anchorType: .timestamp
        )
        let saved = SavedMoment(
            id: UUID().uuidString,
            postId: anchor.postId,
            mediaId: anchor.mediaId,
            timestamp: anchor.timestamp,
            frameIndex: anchor.frameIndex,
            label: "Moment 00:12",
            source: .moment,
            verseReference: nil,
            createdAt: Date()
        )

        service.save(saved)
        #expect(service.isSaved(anchor: anchor))
        service.removeMatching(anchor: anchor)
    }
}
#endif
