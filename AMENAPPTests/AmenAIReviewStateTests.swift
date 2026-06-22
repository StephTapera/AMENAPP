import XCTest
@testable import AMENAPP

final class AmenAIReviewStateTests: XCTestCase {
    func testApproveOnlyAllowedFromDraftReadyOrEditing() {
        XCTAssertTrue(AmenAIReviewState.draftReady.canApprove)
        XCTAssertTrue(AmenAIReviewState.editing.canApprove)
        XCTAssertFalse(AmenAIReviewState.generating.canApprove)
    }

    func testPreviewOnlyForDraftStates() {
        XCTAssertTrue(AmenAIReviewState.draftReady.canPreviewDraft)
        XCTAssertTrue(AmenAIReviewState.regenerating.canPreviewDraft)
        XCTAssertFalse(AmenAIReviewState.validating.canPreviewDraft)
    }
}
