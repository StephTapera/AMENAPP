import XCTest

extension XCTestCase {
    func launchReleaseHarness() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "--ui-test-release-verification",
            "UITEST_MODE=1",
            "USE_FIREBASE_EMULATOR=1",
            "DISABLE_ANIMATIONS=1",
            "RESET_APP_STATE=1",
            "SEEDED_TEST_USER=1",
            "STOREKIT_TEST_MODE=1"
        ]
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launchEnvironment["USE_FIREBASE_EMULATOR"] = "1"
        app.launchEnvironment["DISABLE_ANIMATIONS"] = "1"
        app.launchEnvironment["RESET_APP_STATE"] = "1"
        app.launchEnvironment["SEEDED_TEST_USER"] = "1"
        app.launchEnvironment["STOREKIT_TEST_MODE"] = "1"
        app.launch()
        XCTAssertTrue(app.otherElements["release_verification_harness"].waitForExistence(timeout: 8))
        return app
    }

    func tap(_ label: String, in app: XCUIApplication) {
        let button = app.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 4), "Missing button: \(label)")
        button.tap()
    }

    func assertEvent(_ event: String, in app: XCUIApplication) {
        let predicate = NSPredicate(format: "label CONTAINS %@", event)
        XCTAssertTrue(app.staticTexts.containing(predicate).firstMatch.waitForExistence(timeout: 3), "Missing analytics event: \(event)")
    }
}
