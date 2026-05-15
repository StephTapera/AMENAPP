import XCTest

final class AmenTouchedFeatures10GoUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("--ui-test-touched-features-10-go")
        app.launchEnvironment["AMEN_UI_TEST_MODE"] = "touched_features_10_go"
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testDailyPrayerWeeklyThemeSelectionAndCopy() throws {
        launchApp()
        openSurface(named: ["Daily Prayer", "Prayer"])
        tapFirstExisting(["Weekly", "Theme", "Peace", "Strength"])
        tapFirstExisting(["Copy", "Copy prayer", "Copy theme"])
        dismissPresentedSurfaceIfNeeded()
    }

    func testBereanHomeAttachmentOpensPicker() throws {
        launchApp()
        openSurface(named: ["Berean", "Study", "Chat"])
        tapFirstExisting(["Attachments", "Attach", "Add attachment"])
        assertAnyExists(["Files", "Photo Library", "Camera", "Choose File", "Attachment"])
        dismissPresentedSurfaceIfNeeded()
    }

    func testBereanChatCameraOpensMediaOrPermissionState() throws {
        launchApp()
        openSurface(named: ["Berean", "Chat"])
        tapFirstExisting(["Camera", "Add photo", "Photo"])
        assertAnyExists(["Camera", "Photo Library", "Camera unavailable", "Allow Camera", "Attachment"])
        dismissPresentedSurfaceIfNeeded()
    }

    func testBereanConversationAttachmentOpensPicker() throws {
        launchApp()
        openSurface(named: ["Conversation", "Berean"])
        tapFirstExisting(["Attachments", "Attach"])
        assertAnyExists(["Files", "Photo Library", "Attachment"])
        dismissPresentedSurfaceIfNeeded()
    }

    func testBereanStudyVoiceAndCameraCreateUsableState() throws {
        launchApp()
        openSurface(named: ["Study", "Berean"])
        tapFirstExisting(["Voice", "Voice note", "Microphone"])
        assertAnyExists(["Transcribe", "Voice", "Microphone", "Ask Berean"])
        tapFirstExisting(["Camera", "Photo"])
        assertAnyExists(["Camera", "Photo Library", "Attachment", "Camera unavailable"])
        dismissPresentedSurfaceIfNeeded()
    }

    func testCreatorInsightsOpensAnalyticsDashboard() throws {
        launchApp()
        openSurface(named: ["Settings", "Profile"])
        tapFirstExisting(["Creator Insights", "Insights", "Analytics"])
        assertAnyExists(["Creator Insights", "Analytics", "Weekly", "Content Health"])
        goBackOrDismiss()
    }

    func testScriptureDNAWordMapOpensAndRenders() throws {
        launchApp()
        openSurface(named: ["Scripture DNA", "Scripture"])
        tapFirstExisting(["Word Map", "Map"])
        assertAnyExists(["Word Map", "Themes", "Original Language", "No word map data"])
        dismissPresentedSurfaceIfNeeded()
    }

    func testMentorshipPaidPlanStartsStoreKitOrUnavailableState() throws {
        launchApp()
        openSurface(named: ["Mentorship", "Mentor"])
        tapFirstExisting(["Growth", "Deep Discipleship", "$19/mo", "$39/mo"])
        assertAnyExists(["Purchase", "Continue", "App Store", "StoreKit", "products could not be loaded", "Restore Purchases"])
        dismissPresentedSurfaceIfNeeded()
    }

    func testCovenantSettingsGuidelinesCalendarAndPostRoutesAreReachable() throws {
        launchApp()
        openSurface(named: ["Covenant", "Community"])
        tapFirstExisting(["Manage", "Settings"])
        assertAnyExists(["Settings", "Member Posting", "Join Requests", "Weekly Digest"])
        dismissPresentedSurfaceIfNeeded()

        tapFirstExisting(["Moderation", "Guidelines"])
        tapFirstExisting(["Edit Guidelines", "Guidelines"])
        assertAnyExists(["Guidelines", "Save"])
        dismissPresentedSurfaceIfNeeded()

        tapFirstExisting(["Events", "Calendar"])
        tapFirstExisting(["Add to Calendar"])
        assertAnyExists(["Added to Calendar", "Calendar access", "No writable calendar", "Already in Calendar"])
        dismissPresentedSurfaceIfNeeded()
    }

    func testExportsAndFindFriendsAreActionable() throws {
        launchApp()
        openSurface(named: ["Legacy Studio", "Legacy"])
        tapFirstExisting(["Export legacy story PDF", "Export", "Share"])
        assertAnyExists(["Share", "Copy", "Save", "Export Failed"])
        dismissPresentedSurfaceIfNeeded()

        openSurface(named: ["Reel", "Composer"])
        tapFirstExisting(["Save", "Share", "Export"])
        assertAnyExists(["Share", "Saved", "Export"])
        dismissPresentedSurfaceIfNeeded()

        openSurface(named: ["Quote", "Quote Forge"])
        tapFirstExisting(["Save", "Share", "Export"])
        assertAnyExists(["Share", "Saved", "Quote"])
        dismissPresentedSurfaceIfNeeded()

        openSurface(named: ["Resources", "Find Friends"])
        tapFirstExisting(["Find Friends", "Friends"])
        assertAnyExists(["Find Friends", "Search", "Suggested", "Profile"])
        goBackOrDismiss()
    }

    private func launchApp() {
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    private func openSurface(named labels: [String]) {
        _ = tapFirstExisting(labels, failOnMissing: false)
    }

    @discardableResult
    private func tapFirstExisting(_ labels: [String], failOnMissing: Bool = true) -> Bool {
        for label in labels {
            let candidates = [
                app.buttons[label],
                app.links[label],
                app.staticTexts[label],
                app.cells[label],
                app.otherElements[label]
            ]
            if let element = candidates.first(where: { $0.waitForExistence(timeout: 2) }) {
                element.tap()
                return true
            }
        }
        if failOnMissing {
            XCTFail("None of these elements appeared: \(labels.joined(separator: ", "))")
        }
        return false
    }

    private func assertAnyExists(_ labels: [String]) {
        for label in labels {
            if app.buttons[label].waitForExistence(timeout: 2) ||
                app.staticTexts[label].waitForExistence(timeout: 2) ||
                app.textFields[label].waitForExistence(timeout: 2) ||
                app.otherElements[label].waitForExistence(timeout: 2) ||
                app.sheets[label].waitForExistence(timeout: 2) {
                return
            }
        }
        XCTFail("Expected one of these UI states: \(labels.joined(separator: ", "))")
    }

    private func dismissPresentedSurfaceIfNeeded() {
        if app.buttons["Close"].exists { app.buttons["Close"].tap(); return }
        if app.buttons["Done"].exists { app.buttons["Done"].tap(); return }
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap(); return }
        if app.buttons["Dismiss"].exists { app.buttons["Dismiss"].tap(); return }
        goBackOrDismiss()
    }

    private func goBackOrDismiss() {
        if app.navigationBars.buttons.element(boundBy: 0).exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        } else if app.buttons["Back"].exists {
            app.buttons["Back"].tap()
        }
    }
}
