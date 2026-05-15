import XCTest

final class ChurchNotesMediaUITests: XCTestCase {
    func testChurchNotesMediaDraftReviewRequiresApproval() {
        let app = launchReleaseHarness()

        tap("Open Audio Capture", in: app)
        tap("Open Photo OCR", in: app)
        XCTAssertTrue(app.staticTexts["AI-assisted draft - review before saving"].exists)

        tap("Reject AI Draft", in: app)
        XCTAssertTrue(app.staticTexts["Draft not inserted"].waitForExistence(timeout: 2))

        tap("Approve AI Draft", in: app)
        XCTAssertTrue(app.staticTexts["Approved content inserted"].waitForExistence(timeout: 2))

        assertEvent("churchNotesMediaCaptureOpened", in: app)
        assertEvent("photoOCRStarted", in: app)
        assertEvent("processingDraftReady", in: app)
        assertEvent("aiDraftApproved", in: app)
        assertEvent("aiDraftRejected", in: app)
    }
}
