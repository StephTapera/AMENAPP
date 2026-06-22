// AmenIntegrityLabelService.swift
// AMENAPP
// Fetches and caches ContentIntegrityLabels; provides claim submission.

import Foundation
import Combine

@MainActor
final class AmenIntegrityLabelService: ObservableObject {
    static let shared = AmenIntegrityLabelService()

    private var cache: [String: ContentIntegrityLabel] = [:]
    private let core = AmenSocialSafetyService.shared

    func label(for contentId: String) async -> ContentIntegrityLabel? {
        if let cached = cache[contentId] { return cached }
        guard AMENFeatureFlags.shared.aiMediaDisclosureEnabled ||
              AMENFeatureFlags.shared.truthContextLayerEnabled else { return nil }
        let label = try? await core.fetchIntegrityLabel(for: contentId)
        if let label { cache[contentId] = label }
        return label
    }

    func submitClaim(_ claim: ClaimContext) async throws {
        guard AMENFeatureFlags.shared.claimSourceRequirementEnabled else { return }
        try await core.submitClaimContext(claim)
    }

    func explanationForContent(_ contentId: String) async -> String? {
        guard AMENFeatureFlags.shared.algorithmTransparencyEnabled else { return nil }
        return try? await core.getRecommendationContext(for: contentId)
    }
}
