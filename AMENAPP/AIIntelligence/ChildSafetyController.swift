// ChildSafetyController.swift
// AMENAPP
//
// Wave 6 — Child-Safety surface (visible, protective).
//
// Manages a real, persisted YouthModeProfile with teen-safe DEFAULTS (adult DMs
// blocked, slow feed) and routes a grooming-detection signal into the EXISTING
// escalation spine (ModerationAuditLogService) fail-closed (hold-for-review).
//
// §6 honesty gate: CSAM reporting to NCMEC/ESP is a human/registration gate, NOT
// code. This controller builds the controls + escalation plumbing only; it never
// pretends the app can file an NCMEC report. requestCSAMEscalation routes to the
// internal safety queue and the UI states the external gate plainly.
//
// Gated by AMENFeatureFlags.shared.childSafetySurfaceEnabled (default OFF).

import Foundation
import SwiftUI
import FirebaseAuth

@MainActor
final class ChildSafetyController: ObservableObject {

    // Teen-safe DEFAULTS — adult DMs blocked, slow feed, guardian sees categories only.
    @AppStorage("childsafety.dmAdultsBlocked") var dmAdultsBlocked: Bool = true
    @AppStorage("childsafety.slowFeed")        var slowFeed: Bool = true
    @AppStorage("childsafety.guardianCategoriesOnly") var guardianCategoriesOnly: Bool = true

    /// Builds the real YouthModeProfile reflecting current controls.
    func profile() -> YouthModeProfile {
        YouthModeProfile(
            uid: Auth.auth().currentUser?.uid ?? "",
            feedPacing: slowFeed ? .slow : .standard,
            dmPolicy: dmAdultsBlocked ? .verifiedAdultsBlocked : .standard,
            bereanToneKey: "gentle",
            guardianVisibility: guardianCategoriesOnly ? .categoriesOnly : .none_
        )
    }

    /// Routes a grooming-detection signal into the existing escalation spine.
    /// Fail-closed: the DM is held for review; no content is auto-cleared.
    func escalateGroomingSignal(conversationId: String, messageId: String, signalSummary: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        ModerationAuditLogService.shared.record(
            surface: .dmText,
            userId: uid,
            contentPath: "conversations/\(conversationId)/messages/\(messageId)",
            contentPreview: signalSummary,
            action: .holdForReview,
            categories: ["grooming_signal", "minor_safety"],
            severity: 0.95,
            confidence: 0.6,            // coarse signal — held, not auto-acted
            provider: "client_heuristic",
            modelVersion: "ChildSafety-groomingSignal-v1",
            evidencePreserved: true,
            idempotencyKey: "grooming-\(messageId)"
        )
    }

    /// CSAM escalation — routes to the INTERNAL safety queue only. Filing to NCMEC
    /// is a human/registration gate (§6) and is NOT performed here.
    func requestCSAMEscalation(contentPath: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        ModerationAuditLogService.shared.record(
            surface: .media,
            userId: uid,
            contentPath: contentPath,
            contentPreview: "[redacted — minor safety escalation]",
            action: .holdForReview,
            categories: ["csam_escalation", "minor_safety"],
            severity: 1.0,
            confidence: 1.0,
            provider: "user_report",
            modelVersion: "ChildSafety-csamEscalation-v1",
            evidencePreserved: true
        )
    }
}
