//
//  PresenceAndCommentEnforcementTests.swift
//  AMENAPPTests — Verification suite (NEW, additive)
//
//  Presence fail-closed + comment moderation enforcement.
//  Implemented now: the model-level fail-closed contract testable without
//  source changes. Deferred tests are NAMED + .disabled with the exact blocker
//  so the owner can enable each in one step (the suite names every required test).
//

import Testing
import Foundation
@testable import AMENAPP

@Suite("Presence fail-closed")
struct PresenceFailClosedTests {

    @Test("presence_defaultPreferences_areConservative")
    func presence_defaultPreferences_areConservative() {
        // Fail-closed at the model level: travel + worship suppression default ON.
        let p = PresencePreferences.default
        #expect(p.travelAwareSuppression == true)
        #expect(p.worshipAwareSuppression == true)
    }

    // CONTRACT: eligibleSignals() returns [] when quietModeEnabled (default-nobody).
    // BLOCKED: AmbientPresenceIntelligence is a private-init singleton whose state is
    // private(set) — can't seed. ENABLE: add a pure overload
    // eligibleSignals(signals:preferences:...) or test-only setters, then assert [].
    @Test("presence_quietMode_suppressesAllSignals", .disabled("needs eligibleSignals pure overload / settable state seam"))
    func presence_quietMode_suppressesAllSignals() {}

    // CONTRACT: a signal with confidence < minimumConfidence(for:) — and any
    // null/zero-confidence signal — is filtered out (not rendered).
    // BLOCKED: same seam + PresenceSignal needs nested fixtures
    // (ChurchConfidenceLevel, ChurchGroundingSource, ChurchEntity.GeoPoint).
    @Test("presence_belowThresholdOrZeroConfidence_notEligible", .disabled("needs seam + PresenceSignal fixture factory"))
    func presence_belowThresholdOrZeroConfidence_notEligible() {}
}

@Suite("Comment moderation enforcement")
struct CommentEnforcementTests {

    // CONTRACT: addComment rejects when moderation decision is missing or = block.
    // BLOCKED: addComment → _performAddComment → ModerationGatewayService (CF) + RTDB.
    // ENABLE: inject a moderation provider protocol into PostInteractionsService and
    // assert _performAddComment throws on .blocked / missing decision.
    @Test("comment_missingOrBlockModerationDecision_rejectedByAddComment", .disabled("needs ModerationGatewayService DI seam in PostInteractionsService"))
    func comment_missingOrBlockModerationDecision_rejectedByAddComment() {}

    // CONTRACT: a direct client write to the RTDB comments path is denied by RTDB rules
    // (only the moderated CF path may write).
    // BLOCKED: no root database.rules.json — confirm RTDB rules path; add RTDB emulator
    // harness (mirror Backend/verification/noteShareAccess.rules.test.js).
    @Test("comment_directClientRTDBWrite_fails", .disabled("no root database.rules.json; needs RTDB rules path + emulator harness"))
    func comment_directClientRTDBWrite_fails() {}
}
