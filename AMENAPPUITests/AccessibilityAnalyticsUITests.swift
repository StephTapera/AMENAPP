import XCTest

final class AccessibilityAnalyticsUITests: XCTestCase {
    func testReleaseCriticalAccessibilityAndAnalyticsPrivacy() {
        let app = launchReleaseHarness()

        let requiredButtons = [
            "Sign Up Test User",
            "Complete Required Onboarding",
            "Daily Verse John 3:16 KJV",
            "Open Hey Feed",
            "Create Post",
            "Amen reaction",
            "Lightbulb",
            "Comment",
            "Repost",
            "Share",
            "More",
            "Send Berean Message",
            "Open Audio Capture",
            "Open Photo OCR",
            "Approve AI Draft",
            "Reject AI Draft",
            "Open Paywall",
            "Start Purchase",
            "Restore Purchases",
            "Manage Subscription",
            "Request Account Deletion"
        ]

        for label in requiredButtons {
            let button = app.buttons[label]
            XCTAssertTrue(button.exists, "Missing accessible button: \(label)")
            XCTAssertFalse(button.label.isEmpty)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, "Tap target too small: \(label)")
        }

        let privateNeedles = [
            "email", "phone", "token", "rawPrompt", "transcriptText",
            "ocrText", "privateNote", "paymentSecret", "providerToken", "Authorization"
        ]
        let eventLog = app.staticTexts["analytics_event_log"]
        XCTAssertTrue(eventLog.exists)
        let label = eventLog.label
        for needle in privateNeedles {
            XCTAssertFalse(label.localizedCaseInsensitiveContains(needle), "Analytics log contains private key: \(needle)")
        }
    }
}
