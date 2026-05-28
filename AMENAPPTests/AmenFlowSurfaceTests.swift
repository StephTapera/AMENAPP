import SwiftUI
import XCTest
@testable import AMENAPP

final class AmenFlowSurfaceTests: XCTestCase {
    @MainActor
    func testAmenFlowSurfacesInstantiate() {
        XCTAssertNotNil(AmenFlowGatewayView())
        XCTAssertNotNil(AmenNowCapsule(
            mode: .continueReflection,
            title: "Continue Reflection",
            subtitle: "Return to prayer, Scripture, or notes when ready.",
            actionTitle: "Continue"
        ))
        XCTAssertNotNil(SpacesDiscoveryView())
    }

    func testSmartMessageLocalActionsCoverAmenFlowActionTypes() {
        let context = SmartMessageHostContext.local(messageId: "amen-flow-test", surface: "amen_flow")
        let text = "Please pray for my family before Bible study Friday at 7pm. Read Romans 8:28."
        let actions = SmartMessageLocalDetector.detect(in: text, respectFeatureFlags: false)
            .flatMap { SmartMessageLocalDetector.actions(for: $0, context: context) }
        let actionTypes = Set(actions.map(\.actionType))

        XCTAssertTrue(actionTypes.contains(.createPrayerRequest))
        XCTAssertTrue(actionTypes.contains(.addReminder))
        XCTAssertTrue(actionTypes.contains(.addToCalendar))
        XCTAssertTrue(actionTypes.contains(.askBerean))
        XCTAssertTrue(actionTypes.contains(.openScripture))
    }

    func testSmartMessageActionsDoNotRequireSensitiveAnalyticsPayloads() {
        let context = SmartMessageHostContext.local(messageId: "privacy-test", surface: "amen_flow")
        let entities = SmartMessageLocalDetector.detect(in: "Please pray for my family", respectFeatureFlags: false)
        let actions = entities.flatMap { SmartMessageLocalDetector.actions(for: $0, context: context) }

        XCTAssertFalse(actions.isEmpty)
        XCTAssertTrue(actions.allSatisfy { $0.privacyLevel == .private || $0.privacyLevel == .space })
        XCTAssertTrue(actions.allSatisfy { $0.payload["messageText"] == nil })
        XCTAssertTrue(actions.allSatisfy { $0.payload["prayerText"] == nil })
    }
}
