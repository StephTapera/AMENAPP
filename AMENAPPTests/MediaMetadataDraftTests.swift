import Testing
@testable import AMENAPP

@Suite("Media Metadata Drafts")
struct MediaMetadataDraftTests {
    @Test("syncForImages creates per-frame draft rows")
    func syncForImagesCreatesFrames() {
        var draft = CreatePostMediaMetadataDraft()
        draft.syncForImages(count: 3)

        #expect(draft.frameCaptions.count == 3)
        #expect(draft.featuredFrameIndex == 0)
        #expect(draft.frameCaptions[0].frameIndex == 0)
        #expect(draft.frameCaptions[2].frameIndex == 2)
    }

    @Test("caption track prefers user-edited transcript")
    func captionTrackPrefersEditedContent() {
        let videoDraft = VideoMetadataDraft(
            captionStyle: .standard,
            captionCues: [
                VideoCaptionCueDraft(startTime: 0, endTime: 2, text: "Edited line")
            ],
            userEdited: true
        )

        let track = videoDraft.captionTrack

        #expect(track?.effectiveSource == .userEdited)
        #expect(track?.editedTranscript == "Edited line")
        #expect(track?.style == .standard)
    }

    @Test("media item generation status falls back from embedded metadata")
    func generationStatusFallsBack() {
        let item = PostMediaItem(
            type: .video,
            url: "https://example.com/video.mp4",
            duration: 60
        )

        #expect(item.generationStatus.mediaProcessing == .ready)
        #expect(item.generationStatus.captions == .notRequested)
        #expect(item.generationStatus.keyMoments == .notRequested)
        #expect(item.generationStatus.featuredFrame == .notRequested)
    }
}
