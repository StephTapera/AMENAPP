// AmenMessageSafetyService.swift
// AMENAPP
// Evaluates DM / Conversation messages through the Safety OS firewall.

import Foundation
import FirebaseAuth

@MainActor
final class AmenMessageSafetyService {
    static let shared = AmenMessageSafetyService()
    private let core = AmenSocialSafetyService.shared

    /// Returns a SafetyDecision. Callers should block send if action == .block.
    func evaluate(
        message text: String,
        in conversationId: String,
        recipientId: String,
        recipientIsMinor: Bool
    ) async -> SafetyDecision {
        guard AMENFeatureFlags.shared.dmRiskFirewallEnabled else {
            return .allow
        }
        let uid = Auth.auth().currentUser?.uid ?? ""
        do {
            return try await core.evaluateMessageSafety(
                conversationId: conversationId,
                message: text,
                senderId: uid,
                recipientId: recipientId,
                recipientIsMinor: recipientIsMinor
            )
        } catch {
            return .allow
        }
    }
}

extension SafetyDecision {
    static var allow: SafetyDecision {
        SafetyDecision(action: .allow, riskCategory: nil, severity: .low,
                       reason: nil, userFacingMessage: nil,
                       requiresHumanReview: false, appealEligible: false,
                       decidedAt: Date())
    }
}
