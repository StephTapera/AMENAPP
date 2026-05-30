// SpacesPurchaseService.swift
// AMENAPP — Spaces Monetization (Agent E)
//
// Purchase orchestration and live entitlement observation for paid Spaces.
//
// Flow:
//   1. purchaseSpace(_:userId:) calls purchaseSpaceAccess CF -> gets clientSecret
//   2. Stripe payment confirmation happens client-side (Stripe SDK / Apple Pay)
//   3. Stripe webhook -> stripeWebhookEntitlementHandler CF writes entitlement
//   4. observeEntitlement stream fires -> @Published entitlement updates -> UI unlocks
//
// Constraints:
//   - @MainActor throughout
//   - No force-unwrap
//   - No "church" anywhere
//   - Money never crosses a community Link -- owning community Connect always collects
//   - Entitlement status flips only; never hard-deleted

import Foundation
import FirebaseFunctions
import Combine

// MARK: - Purchase Error

enum SpacesPurchaseError: LocalizedError {
    case policyNotPurchasable
    case missingSpaceId
    case missingPriceConfig
    case networkError(Error)
    case invalidServerResponse
    case userNotAuthenticated

    var errorDescription: String? {
        switch self {
        case .policyNotPurchasable:
            return "This space is free to join. No purchase required."
        case .missingSpaceId:
            return "Unable to identify the space. Please try again."
        case .missingPriceConfig:
            return "This space does not have a price configured. Please contact the community."
        case .networkError(let underlying):
            return underlying.localizedDescription
        case .invalidServerResponse:
            return "Received an unexpected response. Please try again."
        case .userNotAuthenticated:
            return "You must be signed in to purchase access."
        }
    }
}

// MARK: - Spaces Purchase Service

@MainActor
final class SpacesPurchaseService: ObservableObject {

    // MARK: Published state

    @Published var isPurchasing: Bool = false
    @Published var purchaseError: String? = nil
    @Published var entitlement: SpaceEntitlementV1? = nil

    /// Returned by `purchaseSpace` — the Stripe client secret for payment confirmation.
    /// The caller is responsible for presenting Stripe's payment sheet with this secret.
    @Published var pendingClientSecret: String? = nil

    // MARK: Private state

    private let functions = Functions.functions()
    private var observationTask: Task<Void, Never>? = nil

    // MARK: - Purchase

    /// Initiates a purchase for a paid space.
    /// - Free spaces: throws `SpacesPurchaseError.policyNotPurchasable`
    /// - oneTime / recurring: calls `purchaseSpaceAccess` CF -> returns `clientSecret`.
    ///   Stripe payment confirmation and entitlement flip happen asynchronously via webhook.
    ///
    /// After this returns successfully, observe `pendingClientSecret` and present
    /// the Stripe payment sheet. Entitlement will arrive via `observeEntitlement` stream.
    func purchaseSpace(_ space: AmenSpaceExtended, userId: String) async throws {
        // B-24: Gate — purchaseSpaceAccess CF is not yet deployed.
        guard AMENFeatureFlags.shared.paymentsEnabled else {
            purchaseError = "Paid Space access is coming soon."
            throw SpacesPurchaseError.networkError(
                NSError(domain: "AMENPayments", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Paid Space access is coming soon."])
            )
        }
        guard !userId.isEmpty else {
            purchaseError = SpacesPurchaseError.userNotAuthenticated.localizedDescription
            throw SpacesPurchaseError.userNotAuthenticated
        }

        guard space.accessPolicy != .free else {
            purchaseError = SpacesPurchaseError.policyNotPurchasable.localizedDescription
            throw SpacesPurchaseError.policyNotPurchasable
        }

        guard let spaceId = space.id, !spaceId.isEmpty else {
            purchaseError = SpacesPurchaseError.missingSpaceId.localizedDescription
            throw SpacesPurchaseError.missingSpaceId
        }

        guard let priceConfig = space.priceConfig else {
            purchaseError = SpacesPurchaseError.missingPriceConfig.localizedDescription
            throw SpacesPurchaseError.missingPriceConfig
        }

        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        // Build payload for purchaseSpaceAccess CF.
        // Backend validates communityId -> Connect account; client never touches money routing.
        var priceConfigPayload: [String: Any] = [
            "amountCents": priceConfig.amountCents,
            "currency": priceConfig.currency,
        ]
        if let interval = priceConfig.interval {
            priceConfigPayload["interval"] = interval
        }

        let payload: [String: Any] = [
            "spaceId": spaceId,
            "userId": userId,
            "communityId": space.communityId,
            "priceConfig": priceConfigPayload,
        ]

        do {
            let result = try await functions
                .httpsCallable(SpacesCallable.purchaseSpaceAccess.rawValue)
                .call(payload)

            guard
                let data = result.data as? [String: Any],
                let clientSecret = data["clientSecret"] as? String,
                !clientSecret.isEmpty
            else {
                purchaseError = SpacesPurchaseError.invalidServerResponse.localizedDescription
                throw SpacesPurchaseError.invalidServerResponse
            }

            // Publish secret -- UI layer presents Stripe payment sheet.
            pendingClientSecret = clientSecret

        } catch let error as SpacesPurchaseError {
            purchaseError = error.localizedDescription
            throw error
        } catch {
            let wrapped = SpacesPurchaseError.networkError(error)
            purchaseError = wrapped.localizedDescription
            throw wrapped
        }
    }

    // MARK: - Entitlement Observation

    /// Wires live Firestore entitlement updates into `@Published var entitlement`.
    /// Call on view appear; cancel via `stopObserving()` on view disappear.
    func startObservingEntitlement(userId: String, spaceId: String) {
        guard !userId.isEmpty, !spaceId.isEmpty else { return }
        stopObserving()
        observationTask = Task { [weak self] in
            let stream = EntitlementService.shared.observeEntitlement(
                userId: userId,
                spaceId: spaceId
            )
            for await entitlement in stream {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self?.entitlement = entitlement
                }
            }
        }
    }

    /// Cancels the active entitlement observation stream.
    func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }

    /// Convenience: whether the user currently has read access to the space.
    var hasActiveAccess: Bool {
        guard let status = entitlement?.status else { return false }
        return status == .active || status == .grace
    }
}
