import XCTest
@testable import AMENAPP

final class AmenLocalTriggerEngineTests: XCTestCase {
    private let engine = AmenLocalTriggerEngine.shared

    func testDetectsScripturePrayerAndPriorityOrdering() {
        let results = engine.analyze(
            text: "Please pray for me. Psalm 139 says God knows me fully.",
            surface: .post
        )

        XCTAssertTrue(results.contains(where: { $0.type == .prayerRequest }))
        XCTAssertTrue(results.contains(where: { $0.type == .scriptureReference }))
        XCTAssertEqual(results.first?.type, .prayerRequest)
    }

    func testDetectsTestimonyAndGrief() {
        let results = engine.analyze(
            text: "I was lost for a long time, but God brought me back slowly after my grandmother passed away.",
            surface: .post
        )

        XCTAssertTrue(results.contains(where: { $0.type == .testimony }))
        XCTAssertTrue(results.contains(where: { $0.type == .grief }))
    }

    func testDetectsWisdomShameAndConflict() {
        let results = engine.analyze(
            text: "I need wisdom before I respond. You should be ashamed of yourself.",
            surface: .comment
        )

        XCTAssertTrue(results.contains(where: { $0.type == .wisdomPrompt }))
        XCTAssertTrue(results.contains(where: { $0.type == .shameTone }))
        XCTAssertEqual(results.first?.shouldShowDiscernmentSheet, true)
    }

    func testAvoidsTriggeringOnOrdinaryText() {
        let results = engine.analyze(
            text: "Heading to church later and grabbing coffee first.",
            surface: .post
        )

        XCTAssertTrue(results.isEmpty)
    }
}
