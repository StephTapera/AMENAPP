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
            captionStyle: .sermon,
            captionCues: [
                VideoCaptionCueDraft(startTime: 0, endTime: 2, text: "Edited line")
            ],
            userEdited: true
        )

        let track = videoDraft.captionTrack

        #expect(track?.effectiveSource == .userEdited)
        #expect(track?.displayText == "Edited line")
        #expect(track?.style == .sermon)
    }

    @Test("late generation does not overwrite user-edited metadata")
    func generatedSuggestionsRespectUserEdits() {
        var draft = CreatePostMediaMetadataDraft(
            videoDraft: VideoMetadataDraft(
                captionCues: [VideoCaptionCueDraft(startTime: 0, endTime: 2, text: "User line")],
                keyMoments: [KeyMomentDraft(timestamp: 5, label: "User moment", kind: .mainPoint)],
                featuredFrameTime: 7,
                userEdited: true
            )
        )

        draft.applyGeneratedVideoSuggestions(
            cues: [VideoCaptionCueDraft(startTime: 0, endTime: 2, text: "Generated line")],
            keyMoments: [KeyMomentDraft(timestamp: 12, label: "Generated moment", kind: .prayer, source: .generated)],
            featuredFrameTime: 15
        )

        #expect(draft.videoDraft?.captionCues.first?.text == "User line")
        #expect(draft.videoDraft?.keyMoments.first?.label == "User moment")
        #expect(draft.videoDraft?.featuredFrameTime == 7)
    }

    @Test("media item generation status falls back from embedded metadata")
    func generationStatusFallsBack() {
        let item = PostMediaItem(
            type: .video,
            url: "https://example.com/video.mp4",
            duration: 60,
            captionTrack: MediaCaptionTrack(generatedTranscript: "Line one", cues: [
                MediaCaptionCue(startTime: 0, endTime: 2, text: "Line one")
            ]),
            keyMoments: [
                MediaKeyMoment(timestamp: 0, label: "Intro", kind: .intro)
            ],
            isFeaturedFrame: true
        )

        #expect(item.generationStatus.mediaProcessing == .ready)
        #expect(item.generationStatus.captions == .ready)
        #expect(item.generationStatus.keyMoments == .ready)
        #expect(item.generationStatus.featuredFrame == .ready)
    }
}
