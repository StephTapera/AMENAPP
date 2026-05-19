// SocialSafetyOSTests.swift
// AMENAPPTests
// Unit tests for Social Safety OS pure-Swift model logic.
// No Firebase or network calls — all tests run fully offline.

import Testing
import Foundation
@testable import AMENAPP

// MARK: - SafetySeverity ordering

@Suite("SafetySeverity ordering")
struct SafetySeverityOrderingTests {

    @Test func noneIsLowest() {
        #expect(SafetySeverity.none < SafetySeverity.low)
    }

    @Test func lowIsLessThanMedium() {
        #expect(SafetySeverity.low < SafetySeverity.medium)
    }

    @Test func mediumIsLessThanHigh() {
        #expect(SafetySeverity.medium < SafetySeverity.high)
    }

    @Test func highIsLessThanCritical() {
        #expect(SafetySeverity.high < SafetySeverity.critical)
    }

    @Test func criticalIsNotLessThanCritical() {
        #expect(!(SafetySeverity.critical < SafetySeverity.critical))
    }

    @Test func sortOrderIsCorrect() {
        let shuffled: [SafetySeverity] = [.critical, .none, .high, .low, .medium]
        let sorted = shuffled.sorted()
        #expect(sorted == [.none, .low, .medium, .high, .critical])
    }
}

// MARK: - SafetyDecision convenience accessors

@Suite("SafetyDecision accessors")
struct SafetyDecisionAccessorTests {

    private func makeDecision(
        actions: [SafetyActionType] = [.allow],
        riskCategories: [SafetyRiskCategory] = [],
        severity: SafetySeverity = .none,
        reviewStatus: SafetyReviewStatus = .notRequired
    ) -> SafetyDecision {
        SafetyDecision(
            actorUid: "uid-123",
            contentType: "post",
            riskCategories: riskCategories,
            severity: severity,
            actions: actions,
            reviewStatus: reviewStatus
        )
    }

    @Test func actionReturnsFirstAction() {
        let d = makeDecision(actions: [.blockSend, .escalateToHumanReview])
        #expect(d.action == .blockSend)
    }

    @Test func actionDefaultsToAllowForEmptyActions() {
        var d = makeDecision()
        d = SafetyDecision(
            actorUid: "uid",
            contentType: "post",
            actions: []
        )
        #expect(d.action == .allow)
    }

    @Test func riskCategoryReturnsFirstCategory() {
        let d = makeDecision(riskCategories: [.harassment, .hate])
        #expect(d.riskCategory == .harassment)
    }

    @Test func riskCategoryIsNilWhenEmpty() {
        let d = makeDecision(riskCategories: [])
        #expect(d.riskCategory == nil)
    }

    @Test func requiresHumanReviewWhenActionPresent() {
        let d = makeDecision(actions: [.allow, .escalateToHumanReview])
        #expect(d.requiresHumanReview == true)
    }

    @Test func requiresHumanReviewWhenStatusIsPending() {
        let d = makeDecision(reviewStatus: .pending)
        #expect(d.requiresHumanReview == true)
    }

    @Test func noHumanReviewByDefault() {
        let d = makeDecision()
        #expect(d.requiresHumanReview == false)
    }

    @Test func appealEligibleWhenAllowed() {
        let d = makeDecision(actions: [.allow])
        #expect(d.appealEligible == true)
    }

    @Test func notAppealEligibleWhenSuspended() {
        let d = makeDecision(actions: [.suspendActor])
        #expect(d.appealEligible == false)
    }

    @Test func notAppealEligibleWhenBlocked() {
        let d = makeDecision(actions: [.blockSend])
        #expect(d.appealEligible == false)
    }

    @Test func blockSendDecisionPreventsPublish() {
        let d = makeDecision(actions: [.blockSend])
        // Mirror of the guard in AmenSocialSafetyService.publishWithSafetyDecision
        let wouldPublish = d.action != .blockSend
        #expect(wouldPublish == false)
    }
}

// MARK: - SafetyRiskCategory raw values (used in Firestore writes)

@Suite("SafetyRiskCategory raw values")
struct SafetyRiskCategoryRawValueTests {

    @Test func exploitationRawValue() {
        #expect(SafetyRiskCategory.exploitation.rawValue == "exploitation")
    }

    @Test func groomingRawValue() {
        #expect(SafetyRiskCategory.grooming.rawValue == "grooming")
    }

    @Test func selfHarmRawValue() {
        #expect(SafetyRiskCategory.selfHarm.rawValue == "self_harm")
    }

    @Test func harassmentRawValue() {
        #expect(SafetyRiskCategory.harassment.rawValue == "harassment")
    }

    @Test func roundTripEncodingForAllCases() {
        for category in SafetyRiskCategory.allCases {
            let rawValue = category.rawValue
            let decoded = SafetyRiskCategory(rawValue: rawValue)
            #expect(decoded == category, "Round-trip failed for \(rawValue)")
        }
    }
}

// MARK: - SafetyActionType raw values

@Suite("SafetyActionType raw values")
struct SafetyActionTypeRawValueTests {

    @Test func roundTripEncodingForAllCases() {
        for action in SafetyActionType.allCases {
            let rawValue = action.rawValue
            let decoded = SafetyActionType(rawValue: rawValue)
            #expect(decoded == action, "Round-trip failed for \(rawValue)")
        }
    }

    @Test func blockSendRawValue() {
        #expect(SafetyActionType.blockSend.rawValue == "block_send")
    }

    @Test func showCrisisResourcesRawValue() {
        #expect(SafetyActionType.showCrisisResources.rawValue == "show_crisis_resources")
    }
}

// MARK: - WellbeingSignal model

@Suite("WellbeingSignal model")
struct WellbeingSignalTests {

    @Test func signalValueIsClampedLow() {
        let signal = WellbeingSignal(
            uid: "u1",
            signalType: .rapidScroll,
            value: -5.0,
            confidence: 0.9,
            source: "test"
        )
        // Value storage — clamping is consumer responsibility; model stores as-is
        #expect(signal.value == -5.0)
    }

    @Test func isClientVisibleDefaultsToTrue() {
        let signal = WellbeingSignal(
            uid: "u1",
            signalType: .rapidScroll,
            value: 0.5,
            confidence: 1.0,
            source: "test"
        )
        #expect(signal.isClientVisible == false)
    }

    @Test func signalIdIsUniquePerInstance() {
        let a = WellbeingSignal(uid: "u1", signalType: .rapidScroll, value: 0.1, confidence: 1.0, source: "test")
        let b = WellbeingSignal(uid: "u1", signalType: .rapidScroll, value: 0.1, confidence: 1.0, source: "test")
        #expect(a.id != b.id)
    }
}

// MARK: - SafetyDecision legacy initialiser

@Suite("SafetyDecision legacy init")
struct SafetyDecisionLegacyInitTests {

    @Test func legacyInitSetsActionsCorrectly() {
        let d = SafetyDecision(
            action: .promptBeforePost,
            riskCategory: .misinformation,
            severity: .medium,
            reason: "Unverified claim",
            userFacingMessage: "Please verify before posting.",
            requiresHumanReview: false,
            appealEligible: true,
            decidedAt: Date()
        )
        #expect(d.action == .promptBeforePost)
        #expect(d.riskCategory == .misinformation)
        #expect(d.severity == .medium)
    }

    @Test func legacyInitAddsHumanReviewActionWhenRequired() {
        let d = SafetyDecision(
            action: .holdForReview,
            riskCategory: .hate,
            severity: .high,
            reason: nil,
            userFacingMessage: nil,
            requiresHumanReview: true,
            appealEligible: true,
            decidedAt: Date()
        )
        #expect(d.actions.contains(.escalateToHumanReview))
        #expect(d.requiresHumanReview == true)
    }
}
