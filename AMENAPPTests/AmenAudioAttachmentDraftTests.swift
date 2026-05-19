import Foundation
import Testing
@testable import AMENAPP

struct AmenAudioAttachmentDraftTests {
    @Test("Approved audio draft generates audio bed metadata")
    func approvedAudioBuildsAudioBed() {
        let draft = AmenAudioAttachmentDraft(
            title: "Worship Atmosphere",
            artist: "Amen Library",
            source: "approved_catalog",
            category: .worship,
            trimStartMs: 5000,
            trimDurationMs: 15000,
            musicVolume: 0.4,
            originalAudioVolume: 0.6,
            isApproved: true
        )

        let audioBed = draft.asMediaAudioBed
        #expect(audioBed != nil)
        #expect(audioBed?.title == "Worship Atmosphere")
        #expect(audioBed?.source == "approved_catalog")
    }

    @Test("Unapproved audio draft does not generate public audio bed")
    func unapprovedAudioIsRejected() {
        let draft = AmenAudioAttachmentDraft(
            title: "Unapproved Upload",
            artist: "Unknown",
            source: "user_upload",
            category: .originalAudio,
            trimStartMs: 0,
            trimDurationMs: 10000,
            musicVolume: 0.5,
            originalAudioVolume: 0.7,
            isApproved: false
        )

        #expect(draft.asMediaAudioBed == nil)
    }
}
