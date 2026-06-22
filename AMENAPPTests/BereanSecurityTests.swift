// BereanSecurityTests.swift
// AMENAPPTests
//
// Unit tests for Berean AI security, cost-control, and safety behaviors
// added in the production readiness audit:
//
//   - 8 new analytics events (names + parameter keys)
//   - Crisis keyword detection (25 patterns)
//   - ClaudeService hard limits (maxMessageLength, historyTokenBudget)
//   - BereanTheologyBoundaryService hard-block phrases
//

import XCTest
@testable import AMENAPP

// MARK: - Analytics Event Names

final class BereanSecurityAnalyticsTests: XCTestCase {

    func testRateLimitHitEventName() {
        let event = AMENAnalyticsEvent.bereanRateLimitHit(surface: "conversation")
        XCTAssertEqual(event.name, "berean_rate_limit_hit")
    }

    func testDailyQuotaHitEventName() {
        let event = AMENAnalyticsEvent.bereanDailyQuotaHit(tier: "free")
        XCTAssertEqual(event.name, "berean_daily_quota_hit")
    }

    func testPremiumGateHitEventName() {
        let event = AMENAnalyticsEvent.bereanPremiumGateHit(requestedMode: "deep", surface: "conversation")
        XCTAssertEqual(event.name, "berean_premium_gate_hit")
    }

    func testModelDowngradedEventName() {
        let event = AMENAnalyticsEvent.bereanModelDowngraded(requestedMode: "deep", grantedMode: "core", tier: "free")
        XCTAssertEqual(event.name, "berean_model_downgraded")
    }

    func testCrisisEscalationDetectedEventName() {
        let event = AMENAnalyticsEvent.bereanCrisisEscalationDetected(surface: "bereanChat")
        XCTAssertEqual(event.name, "berean_crisis_escalation_detected")
    }

    func testTheologyBoundaryViolationEventName() {
        let event = AMENAnalyticsEvent.bereanTheologyBoundaryViolation(surface: "bereanChat")
        XCTAssertEqual(event.name, "berean_theology_boundary_violation")
    }

    func testSafetyOutputRewrittenEventName() {
        let event = AMENAnalyticsEvent.bereanSafetyOutputRewritten(violationCount: 2)
        XCTAssertEqual(event.name, "berean_safety_output_rewritten")
    }

    func testAppCheckFailureEventName() {
        let event = AMENAnalyticsEvent.bereanAppCheckFailure(surface: "stream")
        XCTAssertEqual(event.name, "berean_app_check_failure")
    }
}

// MARK: - Analytics Event Parameters

final class BereanSecurityAnalyticsParamTests: XCTestCase {

    func testRateLimitHitParameters() {
        let event = AMENAnalyticsEvent.bereanRateLimitHit(surface: "conversation")
        let params = event.properties ?? [:]
        XCTAssertEqual(params["surface"] as? String, "conversation")
    }

    func testDailyQuotaHitParameters() {
        let event = AMENAnalyticsEvent.bereanDailyQuotaHit(tier: "plus")
        let params = event.properties ?? [:]
        XCTAssertEqual(params["tier"] as? String, "plus")
    }

    func testPremiumGateHitParameters() {
        let event = AMENAnalyticsEvent.bereanPremiumGateHit(requestedMode: "deep", surface: "homeView")
        let params = event.properties ?? [:]
        XCTAssertEqual(params["requested_mode"] as? String, "deep")
        XCTAssertEqual(params["surface"] as? String, "homeView")
    }

    func testModelDowngradedParameters() {
        let event = AMENAnalyticsEvent.bereanModelDowngraded(requestedMode: "deep", grantedMode: "standard", tier: "plus")
        let params = event.properties ?? [:]
        XCTAssertEqual(params["requested_mode"] as? String, "deep")
        XCTAssertEqual(params["granted_mode"] as? String, "standard")
        XCTAssertEqual(params["tier"] as? String, "plus")
    }

    func testCrisisEscalationParameters() {
        let event = AMENAnalyticsEvent.bereanCrisisEscalationDetected(surface: "bereanChat")
        let params = event.properties ?? [:]
        XCTAssertEqual(params["surface"] as? String, "bereanChat")
    }

    func testTheologyBoundaryParameters() {
        let event = AMENAnalyticsEvent.bereanTheologyBoundaryViolation(surface: "conversation")
        let params = event.properties ?? [:]
        XCTAssertEqual(params["surface"] as? String, "conversation")
    }

    func testSafetyOutputRewrittenParameters() {
        let event = AMENAnalyticsEvent.bereanSafetyOutputRewritten(violationCount: 3)
        let params = event.properties ?? [:]
        XCTAssertEqual(params["violation_count"] as? Int, 3)
    }

    func testSafetyOutputRewrittenZeroViolations() {
        let event = AMENAnalyticsEvent.bereanSafetyOutputRewritten(violationCount: 0)
        let params = event.properties ?? [:]
        XCTAssertEqual(params["violation_count"] as? Int, 0)
    }

    func testAppCheckFailureParameters() {
        let event = AMENAnalyticsEvent.bereanAppCheckFailure(surface: "stream")
        let params = event.properties ?? [:]
        XCTAssertEqual(params["surface"] as? String, "stream")
    }
}

// MARK: - Crisis Detection

final class BereanCrisisDetectionTests: XCTestCase {

    private var viewModel: CrisisSupportViewModel!

    override func setUp() {
        super.setUp()
        viewModel = CrisisSupportViewModel()
    }

    // Explicit suicidality keywords
    func testDetectsKillMyself() {
        viewModel.detectHighRiskLanguage(in: "I want to kill myself tonight")
        XCTAssertTrue(viewModel.bereanEscalationVisible)
    }

    func testDetectsEndMyLife() {
        viewModel.detectHighRiskLanguage(in: "I'm thinking about ending my life")
        XCTAssertTrue(viewModel.bereanEscalationVisible)
    }

    func testDetectsWantToDie() {
        viewModel.detectHighRiskLanguage(in: "I want to die, I can't keep going")
        XCTAssertTrue(viewModel.bereanEscalationVisible)
    }

    func testDetectsHurtMyself() {
        viewModel.detectHighRiskLanguage(in: "I feel like hurting myself")
        XCTAssertTrue(viewModel.bereanEscalationVisible)
    }

    func testDetectsSelfHarm() {
        viewModel.detectHighRiskLanguage(in: "I've been doing self harm again")
        XCTAssertTrue(viewModel.bereanEscalationVisible)
    }

    func testDetectsSuicidal() {
        viewModel.detectHighRiskLanguage(in: "I've been feeling suicidal")
        XCTAssertTrue(viewModel.bereanEscalationVisible)
    }

    func testDetectsBetterOffDead() {
        viewModel.detectHighRiskLanguage(in: "Everyone would be better off dead without me")
        XCTAssertTrue(viewModel.bereanEscalationVisible)
    }

    func testDetectsNoPointAnymore() {
        viewModel.detectHighRiskLanguage(in: "There's no point anymore to any of this")
        XCTAssertTrue(viewModel.bereanEscalationVisible)
    }

    func testDetectsEndThePain() {
        viewModel.detectHighRiskLanguage(in: "I just want to end the pain")
        XCTAssertTrue(viewModel.bereanEscalationVisible)
    }

    // Case-insensitive matching
    func testDetectionIsCaseInsensitive() {
        viewModel.detectHighRiskLanguage(in: "I WANT TO DIE")
        XCTAssertTrue(viewModel.bereanEscalationVisible)
    }

    // Safe messages must not trigger escalation
    func testSafeMessageDoesNotTrigger() {
        viewModel.detectHighRiskLanguage(in: "I'm feeling a bit sad today but grateful")
        XCTAssertFalse(viewModel.bereanEscalationVisible)
    }

    func testEmptyMessageDoesNotTrigger() {
        viewModel.detectHighRiskLanguage(in: "")
        XCTAssertFalse(viewModel.bereanEscalationVisible)
    }

    func testNonCrisisScriptureDoesNotTrigger() {
        viewModel.detectHighRiskLanguage(in: "I love reading Psalms when I'm anxious")
        XCTAssertFalse(viewModel.bereanEscalationVisible)
    }

    // Implicit/idiom patterns
    func testDetectsNothingToLiveFor() {
        viewModel.detectHighRiskLanguage(in: "I have nothing to live for")
        XCTAssertTrue(viewModel.bereanEscalationVisible)
    }

    func testDetectsGiveUpOnLife() {
        viewModel.detectHighRiskLanguage(in: "I'm going to give up on life")
        XCTAssertTrue(viewModel.bereanEscalationVisible)
    }
}

// MARK: - BereanTheologyBoundaryService

final class BereanTheologyBoundaryServiceTests: XCTestCase {

    private let service = BereanTheologyBoundaryService.shared

    // Phrases that simulate divine authority claims must be blocked
    func testBlocksGodToldMePhrase() {
        let result = service.sanitize("God told me that you should leave your church")
        XCTAssertFalse(!result.rewroteContent, "Response claiming 'God told me' should fail safety check")
    }

    func testBlocksHolySpiritSays() {
        let result = service.sanitize("The Holy Spirit says this is your moment")
        XCTAssertFalse(!result.rewroteContent, "Response claiming 'The Holy Spirit says' should fail safety check")
    }

    func testBlocksIAmYourPastor() {
        let result = service.sanitize("I am your pastor and I say this is right")
        XCTAssertFalse(!result.rewroteContent, "'I am your pastor' must not appear in Berean responses")
    }

    func testBlocksGodIsPunishingYou() {
        let result = service.sanitize("God is punishing you for what you did")
        XCTAssertFalse(!result.rewroteContent, "Spiritual punishment claims must be blocked")
    }

    // Safe responses must pass
    func testSafeScriptureCitationPasses() {
        let result = service.sanitize("According to John 3:16, God loved the world so much that He gave His only Son.")
        XCTAssertTrue(!result.rewroteContent, "Standard scripture citation must pass safety check")
    }

    func testSafeEncouragementPasses() {
        let result = service.sanitize("I encourage you to bring this to your pastor or a trusted leader in your church.")
        XCTAssertTrue(!result.rewroteContent, "Pastoral referral must pass safety check")
    }

    func testSafeHumilityClausePasses() {
        let result = service.sanitize("Different Christian traditions approach this question differently. Consider speaking with your church leader.")
        XCTAssertTrue(!result.rewroteContent, "Denominational humility responses must pass safety check")
    }
}
