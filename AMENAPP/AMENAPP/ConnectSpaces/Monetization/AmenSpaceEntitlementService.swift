// AmenSpaceEntitlementService.swift
// AMEN Spaces — Monetization: Server-authoritative entitlement gate
//
// Security note: all access decisions are validated server-side via
// getSpaceEntitlement callable. Client state is a display cache only.
// Written: 2026-06-02

import Foundation
import FirebaseFunctions

// MARK: - Access Matrix Constants

private enum AccessMatrix {
    /// Minimum tier order required to unlock each feature.
    /// Free tier (order 0) always covers spaceFeed only.
    /// Paid tier order thresholds are applied in ascending order.
    static let paidFeatureThresholds: [AmenSpaceGatedFeature: Int] = [
        .spaceFeed:           0,
        .chatChannels:        1,
        .liveRoom:            1,
        .replayLibrary:       1,
        .aiRecap:             2,
        .studyCompanion:      2,
        .directMessage:       2,
        .aiTranscriptSearch:  3,
        .aiClips:             3,
    ]
}

// MARK: - Service

@MainActor
final class AmenSpaceEntitlementService: ObservableObject {

    @Published var currentEntitlement: AmenSpaceEntitlement?
    @Published var isLoading: Bool = false
    @Published var entitlementError: String?

    private let functions: Functions = Functions.functions()
    private var cachedFetchKey: String?
    private var cachedFetchTime: Date?
    private let cacheTTL: TimeInterval = 300 // 5 minutes

    // MARK: - Public API

    func checkEntitlement(userId: String, spaceId: String) async -> AmenSpaceEntitlement? {
        let fetchKey = "\(userId):\(spaceId)"
        if let cachedKey = cachedFetchKey,
           cachedKey == fetchKey,
           let fetchTime = cachedFetchTime,
           Date().timeIntervalSince(fetchTime) < cacheTTL,
           let cached = currentEntitlement {
            return cached
        }

        isLoading = true
        entitlementError = nil
        defer { isLoading = false }

        do {
            let callable = functions.httpsCallable("getSpaceEntitlement")
            let result = try await callable.call(["userId": userId, "spaceId": spaceId])

            guard let data = result.data as? [String: Any] else {
                entitlementError = "Unexpected response format from server."
                return nil
            }

            let entitlement = try decode(AmenSpaceEntitlement.self, from: data)
            currentEntitlement = entitlement
            cachedFetchKey = fetchKey
            cachedFetchTime = Date()
            return entitlement
        } catch {
            entitlementError = "Could not verify membership. Please try again."
            return nil
        }
    }

    func refreshEntitlement(userId: String, spaceId: String) async {
        cachedFetchKey = nil
        cachedFetchTime = nil
        _ = await checkEntitlement(userId: userId, spaceId: spaceId)
    }

    /// Access matrix — security-critical.
    /// Never grants access based on client-held state alone.
    /// Expired and revoked entitlements yield no access.
    func hasAccess(
        to feature: AmenSpaceGatedFeature,
        entitlement: AmenSpaceEntitlement?,
        tier: AmenSpaceSubscriptionTier?
    ) -> Bool {
        guard let entitlement else { return false }
        guard entitlement.isActive else { return false }

        if let expiresAt = entitlement.expiresAt, expiresAt < Date() {
            if let gracePeriodEndsAt = entitlement.gracePeriodEndsAt,
               gracePeriodEndsAt >= Date() {
                return feature == .spaceFeed
            }
            return false
        }

        switch entitlement.source {
        case .revoked:
            return false
        case .paymentFailed:
            if let gracePeriodEndsAt = entitlement.gracePeriodEndsAt,
               gracePeriodEndsAt >= Date() {
                return feature == .spaceFeed
            }
            return false
        case .hostComp, .scholarship:
            return true
        case .freeTier:
            return feature == .spaceFeed
        case .appStoreSubscription:
            guard let tier else { return false }
            guard tier.isActive else { return false }
            if tier.isFreeTier { return feature == .spaceFeed }
            let tierOrder = tier.order
            let requiredOrder = AccessMatrix.paidFeatureThresholds[feature] ?? Int.max
            return tierOrder >= requiredOrder
        }
    }

    // MARK: - Preview Instance

    static let preview: AmenSpaceEntitlementService = {
        let service = AmenSpaceEntitlementService()
        service.currentEntitlement = AmenSpaceEntitlement(
            userId: "preview-user",
            spaceId: "preview-space",
            tierId: "free",
            source: .freeTier,
            grantedAt: Date(),
            expiresAt: nil,
            gracePeriodEndsAt: nil,
            isActive: true
        )
        return service
    }()

    // MARK: - Private Helpers

    private func decode<T: Decodable>(_ type: T.Type, from dict: [String: Any]) throws -> T {
        let jsonData = try JSONSerialization.data(withJSONObject: dict)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(type, from: jsonData)
    }
}
