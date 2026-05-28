#if canImport(XCTest)
import Foundation
import XCTest
@testable import AMENAPP

final class AmenMessagingProductionGateTests: XCTestCase {
    @MainActor
    func testHighRiskMessagingFlagsDefaultOff() {
        let flags = AMENFeatureFlags.shared

        XCTAssertFalse(flags.messagingSmartPillsEnabled)
        XCTAssertFalse(flags.messagingTranslationEnabled)
        XCTAssertFalse(flags.messagingCrossSurfaceActionsEnabled)
        XCTAssertFalse(flags.messagingSafetyNudgesEnabled)
        XCTAssertFalse(flags.messagingApprovalCardsEnabled)
        XCTAssertFalse(flags.messagingCatchUpEnabled)
        XCTAssertFalse(flags.messagingVoiceIntelligenceEnabled)
        XCTAssertFalse(flags.messagingMediaIntelligenceEnabled)
        XCTAssertFalse(flags.messagingPresencePolishEnabled)
    }

    @MainActor
    func testAvailabilityUsesMessagingKillSwitches() {
        let availability = AmenMessagingFeatureAvailability()

        XCTAssertEqual(availability.catchUp, AMENFeatureFlags.shared.messagingCatchUpEnabled)
        XCTAssertEqual(availability.mediaIntelligence, AMENFeatureFlags.shared.messagingMediaIntelligenceEnabled)
        XCTAssertEqual(availability.presencePolish, AMENFeatureFlags.shared.messagingPresencePolishEnabled)
    }

    func testRequiredSmartPillTypesExist() {
        let required: Set<AmenSmartPillType> = [
            .translate,
            .summarize,
            .saveToSelah,
            .addToChurchNotes,
            .saveToNotes,
            .replyKindly,
            .toneCheck,
            .remindMe,
            .markAsPrayerRequest,
            .makePrivate,
            .safetyReview,
            .catchMeUp,
            .voiceTranscript,
            .extractActions
        ]

        XCTAssertTrue(required.isSubset(of: Set(AmenSmartPillType.allCases)))
    }

    func testUnavailableSmartPillStatesCannotExecute() {
        let blockedStates: [AmenSmartPillState] = [
            .loading,
            .failed("Failed"),
            .unavailable("Unavailable"),
            .disabled,
            .permissionDenied("Permission denied"),
            .moderationBlocked("Blocked"),
            .featureFlagOff,
            .error("Error")
        ]

        for state in blockedStates {
            XCTAssertFalse(state.canExecute)
        }

        XCTAssertTrue(AmenSmartPillState.idle.canExecute)
        XCTAssertTrue(AmenSmartPillState.active.canExecute)
        XCTAssertTrue(AmenSmartPillState.succeeded("Done").canExecute)
    }

    @MainActor
    func testDefaultPriorityExposesNoHighRiskActions() {
        let context = AmenSmartPillEligibilityContext(
            conversationId: "conversation-1",
            messageCount: 25,
            unreadCount: 25,
            lastMessage: nil,
            selectedMessage: AppMessage(
                text: "Necesito ayuda con esta nota larga.",
                isFromCurrentUser: false,
                timestamp: Date(),
                detectedLanguage: "es"
            ),
            userLanguageCode: "en",
            isGroupConversation: false,
            detectedLanguage: "es",
            hasVoiceMessage: true,
            hasMediaMessage: true,
            hasLongText: true,
            safetySignalPresent: true,
            transcriptAvailable: false,
            isNetworkAvailable: true
        )

        let pills = AmenSmartPillPriorityEngine.eligiblePills(
            for: context,
            flags: AMENFeatureFlags.shared
        )

        XCTAssertTrue(pills.isEmpty)
    }

    func testAppMessagePreservesDetectedLanguage() {
        let message = AppMessage(
            text: "Hola",
            isFromCurrentUser: false,
            timestamp: Date(),
            detectedLanguage: "es"
        )

        XCTAssertEqual(message.detectedLanguage, "es")
    }
}
#else
import Foundation

struct AmenMessagingProductionGateTests {
}
#endif
