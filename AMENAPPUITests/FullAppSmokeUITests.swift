import XCTest

final class FullAppSmokeUITests: XCTestCase {
    func testFullReleaseSmokeFlow() {
        let app = launchReleaseHarness()

        XCTAssertTrue(app.staticTexts["Auth entry"].exists)
        tap("Sign Up Test User", in: app)
        XCTAssertTrue(app.staticTexts["Authenticated test user"].waitForExistence(timeout: 2))
        tap("Complete Required Onboarding", in: app)
        XCTAssertTrue(app.staticTexts["Main app ready after auth resolution"].waitForExistence(timeout: 2))

        tap("Sign Out Test User", in: app)
        XCTAssertTrue(app.staticTexts["Auth entry"].waitForExistence(timeout: 2))
        tap("Sign Up Test User", in: app)
        tap("Complete Required Onboarding", in: app)

        XCTAssertTrue(app.staticTexts["Eligible seeded post"].exists)
        XCTAssertTrue(app.staticTexts["Removed flagged deleted posts hidden"].exists)
        tap("Daily Verse John 3:16 KJV", in: app)
        tap("Open Hey Feed", in: app)

        let composer = app.textFields["post_composer"]
        XCTAssertTrue(composer.exists)
        tap("Create Post", in: app)
        XCTAssertTrue(app.staticTexts["Empty post blocked until text is entered"].exists)
        composer.tap()
        composer.typeText("Release smoke post")
        tap("Create Post", in: app)
        XCTAssertTrue(app.staticTexts["Post action row visible"].waitForExistence(timeout: 2))

        tap("Amen reaction", in: app)
        tap("Lightbulb", in: app)
        tap("Comment", in: app)
        tap("Share", in: app)
        tap("More", in: app)

        tap("Send Berean Message", in: app)
        XCTAssertTrue(app.staticTexts["Safe Berean response"].waitForExistence(timeout: 2))
        tap("Open Deep Mode", in: app)
        tap("Crisis Fixture", in: app)
        XCTAssertTrue(app.staticTexts["Immediate support: call or text 988"].exists)

        tap("Open Audio Capture", in: app)
        tap("Open Photo OCR", in: app)
        XCTAssertTrue(app.staticTexts["AI-assisted draft - review before saving"].exists)
        tap("Approve AI Draft", in: app)
        XCTAssertTrue(app.staticTexts["Approved content inserted"].waitForExistence(timeout: 2))
        tap("Reject AI Draft", in: app)
        XCTAssertTrue(app.staticTexts["Draft not inserted"].waitForExistence(timeout: 2))

        tap("Open Paywall", in: app)
        tap("Start Purchase", in: app)
        tap("Cancel Purchase", in: app)
        tap("Complete Sandbox Purchase", in: app)
        XCTAssertTrue(app.staticTexts["Premium entitlement active"].waitForExistence(timeout: 2))
        tap("Restore Purchases", in: app)
        tap("Manage Subscription", in: app)

        tap("Request Account Deletion", in: app)
        XCTAssertTrue(app.staticTexts["Deletion request accepted, cleanup pending"].waitForExistence(timeout: 2))
    }
}
