#if canImport(Testing)
import Testing
@testable import AMENAPP

@Suite("Amen Immersive Media Eligibility")
struct AmenImmersiveMediaEligibilityTests {
    @Test("Messages video eligibility shows summarize only with transcript")
    func messagesVideoSummarizeEligibility() {
        let eligible = AmenImmersiveEligibilityInput(
            canTranslate: false,
            canSummarize: true,
            canAskBerean: false,
            canSaveToChurchNotes: true,
            canReflectInSelah: true,
            canReportSafety: true,
            canReplyOrComment: true,
            canShare: true,
            canComposeOrEdit: false
        )
        let noTranscript = AmenImmersiveEligibilityInput(
            canTranslate: false,
            canSummarize: false,
            canAskBerean: false,
            canSaveToChurchNotes: true,
            canReflectInSelah: true,
            canReportSafety: true,
            canReplyOrComment: true,
            canShare: true,
            canComposeOrEdit: false
        )

        #expect(AmenImmersiveMediaEligibility.smartPills(from: eligible).contains(.summarize))
        #expect(!AmenImmersiveMediaEligibility.smartPills(from: noTranscript).contains(.summarize))
    }

    @Test("Feed eligibility includes comment-share-save-berean paths")
    func feedEligibility() {
        let input = AmenImmersiveEligibilityInput(
            canTranslate: true,
            canSummarize: true,
            canAskBerean: true,
            canSaveToChurchNotes: true,
            canReflectInSelah: false,
            canReportSafety: true,
            canReplyOrComment: true,
            canShare: true,
            canComposeOrEdit: true
        )
        let pills = AmenImmersiveMediaEligibility.smartPills(from: input)
        #expect(pills.contains(.translate))
        #expect(pills.contains(.askBerean))
        #expect(pills.contains(.saveToChurchNotes))
        #expect(pills.contains(.reportSafety))
    }

    @Test("Private Selah can hide public share")
    func privateSelahShareHidden() {
        let input = AmenImmersiveEligibilityInput(
            canTranslate: false,
            canSummarize: true,
            canAskBerean: true,
            canSaveToChurchNotes: true,
            canReflectInSelah: true,
            canReportSafety: true,
            canReplyOrComment: true,
            canShare: false,
            canComposeOrEdit: false
        )
        #expect(input.canShare == false)
    }

    @Test("Ask Berean hidden without valid context")
    func askBereanHiddenWithoutContext() {
        let input = AmenImmersiveEligibilityInput(
            canTranslate: true,
            canSummarize: true,
            canAskBerean: false,
            canSaveToChurchNotes: true,
            canReflectInSelah: true,
            canReportSafety: true,
            canReplyOrComment: true,
            canShare: true,
            canComposeOrEdit: false
        )
        #expect(!AmenImmersiveMediaEligibility.smartPills(from: input).contains(.askBerean))
    }

    @Test("Visible actions must not be dead buttons")
    func noDeadButtonsValidation() {
        let valid: [AmenImmersiveMediaChromeAction] = [
            .init(id: "save", title: "Save", systemImage: "bookmark", action: {}),
            .init(id: "share", title: "Share", systemImage: "square.and.arrow.up", action: {})
        ]
        #expect(!AmenImmersiveMediaEligibility.hasDeadButtons(actions: valid))

        let invalid: [AmenImmersiveMediaChromeAction] = [
            .init(id: "blank", title: "   ", systemImage: "bookmark", action: {})
        ]
        #expect(AmenImmersiveMediaEligibility.hasDeadButtons(actions: invalid))
    }

    @Test("Message surface action IDs include reply and summarize when eligible")
    func messageSurfaceActions() {
        let input = AmenImmersiveEligibilityInput(
            canTranslate: false,
            canSummarize: true,
            canAskBerean: true,
            canSaveToChurchNotes: true,
            canReflectInSelah: true,
            canReportSafety: true,
            canReplyOrComment: true,
            canShare: true,
            canComposeOrEdit: false
        )
        let ids = AmenImmersiveSurfaceActionFactory.messageAttachmentActionIDs(
            eligibility: input,
            hasReplyHandler: true
        )
        #expect(ids.contains("reply"))
        #expect(ids.contains("summarize"))
        #expect(ids.contains("ask_berean"))
    }

    @Test("Feed surface IDs include comment/share/report when eligible")
    func feedSurfaceActions() {
        let input = AmenImmersiveEligibilityInput(
            canTranslate: true,
            canSummarize: false,
            canAskBerean: true,
            canSaveToChurchNotes: true,
            canReflectInSelah: false,
            canReportSafety: true,
            canReplyOrComment: true,
            canShare: true,
            canComposeOrEdit: false
        )
        let ids = AmenImmersiveSurfaceActionFactory.feedActionIDs(eligibility: input)
        #expect(ids.contains("comment"))
        #expect(ids.contains("share"))
        #expect(ids.contains("report"))
    }

    @Test("Private Selah excludes share from action IDs")
    func privateSelahActionsHideShare() {
        let input = AmenImmersiveEligibilityInput(
            canTranslate: false,
            canSummarize: false,
            canAskBerean: true,
            canSaveToChurchNotes: true,
            canReflectInSelah: true,
            canReportSafety: true,
            canReplyOrComment: true,
            canShare: false,
            canComposeOrEdit: false
        )
        let ids = AmenImmersiveSurfaceActionFactory.selahActionIDs(eligibility: input)
        #expect(!ids.contains("share"))
        #expect(ids.contains("reflect"))
    }

    @Test("Previous-next controls hidden for single media item")
    func previousNextVisibility() {
        #expect(!AmenImmersiveSurfaceActionFactory.previousNextVisible(itemCount: 1))
        #expect(AmenImmersiveSurfaceActionFactory.previousNextVisible(itemCount: 2))
    }

    @Test("Finite session policy clamps queues to healthy bounds")
    func finiteSessionPolicyClampsQueues() {
        #expect(AmenMediaFiniteSessionPolicy.clampedItemCount(nil) == 3)
        #expect(AmenMediaFiniteSessionPolicy.clampedItemCount(1) == 3)
        #expect(AmenMediaFiniteSessionPolicy.clampedItemCount(20) == 12)
    }

    @Test("Generated metadata is hidden until creator approval")
    func generatedMetadataRequiresApproval() {
        let draftTrack = MediaCaptionTrack(
            generatedTranscript: "Draft generated caption",
            source: .generated,
            status: "draft",
            approvedByUser: false
        )
        let approvedTrack = MediaCaptionTrack(
            generatedTranscript: "Approved generated caption",
            source: .generated,
            status: "approved",
            approvedByUser: true
        )
        let draftMoment = MediaKeyMoment(
            timestamp: 12,
            label: "Draft moment",
            kind: .prayer,
            source: "generated",
            status: "draft",
            approvedByUser: false
        )

        #expect(!draftTrack.isPubliclyApproved)
        #expect(approvedTrack.isPubliclyApproved)
        #expect(!draftMoment.isPubliclyApproved)
    }
}
#else
import Foundation

struct AmenImmersiveMediaEligibilityTests {
}
#endif
