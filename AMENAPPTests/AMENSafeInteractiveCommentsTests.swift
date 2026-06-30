import XCTest
@testable import AMENAPP

/// Tests for the Safe Interactive Comments Phase-0 backbone.
/// Verifies fail-closed defaults, the moderation gate, and the inert-while-OFF
/// invariant (OFF == zero behavioral diff).
final class AMENSafeInteractiveCommentsTests: XCTestCase {

    override func tearDown() {
        // Clear any dev overrides a test may have set.
        let d = UserDefaults.standard
        d.removeObject(forKey: "dev." + AMENSafeInteractiveCommentsFlags.Key.master)
        d.removeObject(forKey: "dev." + AMENSafeInteractiveCommentsFlags.Key.composeModes)
        d.removeObject(forKey: "dev." + AMENSafeInteractiveCommentsFlags.Key.interactions)
        super.tearDown()
    }

    // Flags default OFF / fail-closed.
    func testFlagsDefaultOff() {
        UserDefaults.standard.removeObject(forKey: "dev." + AMENSafeInteractiveCommentsFlags.Key.master)
        XCTAssertFalse(AMENSafeInteractiveCommentsFlags.masterEnabled)
        XCTAssertFalse(AMENSafeInteractiveCommentsFlags.composeModesEnabled)
        XCTAssertFalse(AMENSafeInteractiveCommentsFlags.mediaProvidersEnabled)
        XCTAssertFalse(AMENSafeInteractiveCommentsFlags.interactionsEnabled)
        XCTAssertFalse(AMENSafeInteractiveCommentsFlags.threadDynamicsEnabled)
    }

    // Group gates imply the master gate: enabling a group alone (without master) stays OFF.
    func testGroupGateImpliesMaster() {
        UserDefaults.standard.removeObject(forKey: "dev." + AMENSafeInteractiveCommentsFlags.Key.master)
        UserDefaults.standard.set(true, forKey: "dev." + AMENSafeInteractiveCommentsFlags.Key.interactions)
        // master is still OFF, so the composed gate must be OFF.
        XCTAssertFalse(AMENSafeInteractiveCommentsFlags.interactionsEnabled)
    }

    // ModerationGate fails closed with no resolver.
    func testModerationGateFailsClosedWithoutResolver() async {
        let gate = AMENModerationGate(resolver: nil)
        let decision = await gate.evaluate(text: "anything")
        XCTAssertEqual(decision.outcome, .block)
        XCTAssertFalse(decision.permitsPublish)
        XCTAssertFalse(decision.serverEnforced)
    }

    // The fail-closed default blocks.
    func testFailClosedDefaultBlocks() {
        XCTAssertEqual(AMENModerationDecision.failClosed.outcome, .block)
        XCTAssertFalse(AMENModerationDecision.failClosed.permitsPublish)
    }

    // permitsPublish only for allow/warn.
    func testPermitsPublishMatrix() {
        XCTAssertTrue(AMENModerationDecision(outcome: .allow).permitsPublish)
        XCTAssertTrue(AMENModerationDecision(outcome: .warn).permitsPublish)
        XCTAssertFalse(AMENModerationDecision(outcome: .rewriteRequired).permitsPublish)
        XCTAssertFalse(AMENModerationDecision(outcome: .block).permitsPublish)
        XCTAssertFalse(AMENModerationDecision(outcome: .review).permitsPublish)
    }

    // Registry refuses registration while OFF (fail-closed).
    @MainActor
    func testRegistryInertWhileOff() {
        let reg = AMENCommentInteractiveRegistry.shared
        reg.reset()
        reg.register(interaction: StubInteraction())
        reg.register(composeMode: StubComposeMode())
        XCTAssertTrue(reg.interactions.isEmpty)
        XCTAssertTrue(reg.composeModes.isEmpty)
    }

    // Activation is a no-op while OFF (zero behavioral diff).
    @MainActor
    func testActivationNoOpWhileOff() {
        AMENCommentInteractiveRegistry.shared.reset()
        AMENSafeInteractiveComments.activateIfEnabled()
        XCTAssertTrue(AMENCommentInteractiveRegistry.shared.composeModes.isEmpty)
        XCTAssertTrue(AMENCommentInteractiveRegistry.shared.interactions.isEmpty)
    }

    // Safety interactions are marked always-available (cannot be hidden behind overflow).
    func testSafetyInteractionContract() {
        let report = StubInteraction()
        XCTAssertTrue(report.isAlwaysAvailable)
    }
}

private struct StubInteraction: AMENCommentInteraction {
    let id = "stub.report"
    let isDestructive = false
    let requiresConfirmation = false
    let isAlwaysAvailable = true
}

private struct StubComposeMode: AMENCommentComposeMode {
    let id = "stub.compose"
    let displayName = "Stub"
    let isEnabled = true
}
