// AmenContentSafetyService.swift
// AMENAPP
// Thin wrapper used at the CreatePost / publish boundary.

import Foundation
import FirebaseAuth

@MainActor
final class AmenContentSafetyService {
    static let shared = AmenContentSafetyService()
    private let core = AmenSocialSafetyService.shared

    /// Called from CreatePostView before finalising a publish.
    func gate(
        draft text: String?,
        mediaURLs: [String],
        contentType: String = "post"
    ) async -> SafetyDecision {
        guard AMENFeatureFlags.shared.socialSafetyOSEnabled else {
            return SafetyDecision(action: .allow, riskCategory: nil, severity: .low,
                                  reason: nil, userFacingMessage: nil,
                                  requiresHumanReview: false, appealEligible: false,
                                  decidedAt: Date())
        }
        let uid = Auth.auth().currentUser?.uid ?? "anonymous"
        do {
            return try await core.evaluateContentSafety(
                contentId: UUID().uuidString,
                contentType: contentType,
                text: text,
                mediaURLs: mediaURLs,
                authorId: uid
            )
        } catch {
            // Fail open — let the post through if the safety call itself errors
            return SafetyDecision(action: .allow, riskCategory: nil, severity: .low,
                                  reason: "Safety service unavailable",
                                  userFacingMessage: nil,
                                  requiresHumanReview: false, appealEligible: false,
                                  decidedAt: Date())
        }
    }
}
