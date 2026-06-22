import Testing
@testable import AMENAPP

@Suite("Liquid Glass Upload Capsule")
struct LiquidGlassUploadCapsuleTests {
    @Test("Progress clamps between zero and one")
    func progressClamps() {
        #expect(UploadCapsuleMetrics.clampedProgress(-0.4) == 0)
        #expect(UploadCapsuleMetrics.clampedProgress(1.4) == 1)
    }

    @Test("Progress percent rounds for rendering")
    func progressPercentRounds() {
        #expect(UploadCapsuleMetrics.percent(0.426) == 43)
        #expect(UploadCapsuleMetrics.percent(4.2) == 100)
    }

    @Test("Preparing stage maps into the opening progress band")
    func preparingStageMaps() {
        let value = UploadCapsuleMetrics.weightedProgress(for: .preparing, stageProgress: 0.5)
        #expect(value == 0.05)
    }

    @Test("Uploading stage maps into the main transfer band")
    func uploadingStageMaps() {
        let value = UploadCapsuleMetrics.weightedProgress(for: .uploading, stageProgress: 0.55)
        #expect(abs(value - 0.43) < 0.0001)
    }

    @Test("Processing stage starts after uploads")
    func processingStageMaps() {
        let value = UploadCapsuleMetrics.weightedProgress(for: .processing, stageProgress: 0.5)
        #expect(value == 0.76)
    }

    @Test("Moderating stage begins after processing")
    func moderatingStageMaps() {
        let value = UploadCapsuleMetrics.weightedProgress(for: .moderating, stageProgress: 0.5)
        #expect(abs(value - 0.88) < 0.0001)
    }

    @Test("Finalizing stage reaches the last progress band")
    func finalizingStageMaps() {
        let value = UploadCapsuleMetrics.weightedProgress(for: .finalizing, stageProgress: 0.5)
        #expect(value == 0.97)
    }

    @Test("Success maps to complete progress")
    func successMaps() {
        #expect(UploadCapsuleMetrics.weightedProgress(for: .success, stageProgress: 0) == 1)
    }

    @Test("Blocked and review states keep calm user copy")
    func blockedAndReviewCopy() {
        #expect(UploadCapsuleMetrics.title(for: .blocked(reason: nil), uploadedCount: 0, totalCount: 1) == "Cannot post media")
        #expect(UploadCapsuleMetrics.title(for: .reviewRequired, uploadedCount: 0, totalCount: 1) == "Under review")
        #expect(UploadCapsuleMetrics.meta(for: .reviewRequired, progress: 0.9, uploadedCount: 1, totalCount: 1) == "We'll keep this private for now")
    }

    @Test("Failure copy remains retry oriented")
    func failureCopy() {
        #expect(UploadCapsuleMetrics.meta(for: .failed(message: nil), progress: 0.4, uploadedCount: 0, totalCount: 2) == "Tap retry")
    }
}
