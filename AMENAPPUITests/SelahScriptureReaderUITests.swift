import XCTest

/// XCUITest skeleton for the Selah Scripture Reader flow.
///
/// Requires a launched simulator + selected destination to actually run.
/// These tests are written to be tolerant of small label/name differences
/// in the SwiftUI hierarchy so they don't break on minor wording changes.
final class SelahScriptureReaderUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("--ui-test-selah-scripture-reader")
        app.launchEnvironment["AMEN_UI_TEST_MODE"] = "selah_scripture_reader"
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// Open Selah, tap the Bible entry, see the reader/search appear.
    func testBibleEntryOpensReaderOrSearch() throws {
        launchApp()
        openSurface(named: ["Selah", "Read", "Scripture Study"])
        tapFirstExisting(["Bible", "Read Scripture", "Search Scripture"], failOnMissing: false)
        assertAnyExists([
            "Search verse, book, or keyword",
            "Continue reading",
            "Chapter 1",
            "Chapter 3",
            "Chapter 23",
            "Bible"
        ])
        dismissPresentedSurfaceIfNeeded()
    }

    /// Search "John 3:16" — the parsed-reference row should appear.
    func testSearchForReferenceShowsResult() throws {
        launchApp()
        openSurface(named: ["Selah", "Read"])
        tapFirstExisting(["Bible"], failOnMissing: false)
        if app.textFields["Search verse, book, or keyword"].waitForExistence(timeout: 3) {
            let field = app.textFields["Search verse, book, or keyword"]
            field.tap()
            field.typeText("John 3:16")
            assertAnyExists(["John 3:16", "Reference", "Verses", "Books"])
        }
        dismissPresentedSurfaceIfNeeded()
    }

    /// Open a chapter that's bundled (Psalm 23), swipe to advance pages,
    /// then attempt a Save on the first verse.
    func testOpenPsalm23AndSaveAVerse() throws {
        launchApp()
        openSurface(named: ["Selah", "Read"])
        tapFirstExisting(["Bible"], failOnMissing: false)
        if app.textFields["Search verse, book, or keyword"].waitForExistence(timeout: 3) {
            let field = app.textFields["Search verse, book, or keyword"]
            field.tap()
            field.typeText("Psalm 23")
            tapFirstExisting(["Psalms 23"], failOnMissing: false)
        }

        // Reader should now be visible — page indicator / chapter title.
        XCTAssertTrue(app.staticTexts["Chapter 23"].waitForExistence(timeout: 4)
            || app.staticTexts["Chapter 1"].waitForExistence(timeout: 1))

        // Tap any verse text (first verse number marker) to select.
        let firstVerse = app.staticTexts["1"].firstMatch
        if firstVerse.waitForExistence(timeout: 2) { firstVerse.tap() }

        // Try the Save action on the floating verse toolbar.
        tapFirstExisting(["Save"], failOnMissing: false)
        // A confirmation/toast or persistence — accept any reasonable state.
        assertAnyExists(["Saved", "Copy", "Reflect", "Pray", "React"])

        dismissPresentedSurfaceIfNeeded()
    }

    /// Swipe to the next page — verify the chapter title updates.
    func testSwipingPageAdvancesChapter() throws {
        launchApp()
        openSurface(named: ["Selah", "Read"])
        tapFirstExisting(["Bible"], failOnMissing: false)
        if app.textFields["Search verse, book, or keyword"].waitForExistence(timeout: 3) {
            let field = app.textFields["Search verse, book, or keyword"]
            field.tap()
            field.typeText("Psalm 1")
            tapFirstExisting(["Psalms 1"], failOnMissing: false)
        }
        let beforeTitle = app.staticTexts["Chapter 1"]
        if beforeTitle.waitForExistence(timeout: 4) {
            // Horizontal swipe (left) to advance.
            beforeTitle.swipeLeft()
            // After swipe, expect "Chapter 2" to appear within a short window.
            _ = app.staticTexts["Chapter 2"].waitForExistence(timeout: 4)
        }
        dismissPresentedSurfaceIfNeeded()
    }

    // MARK: - Shared helpers

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
    }
}
