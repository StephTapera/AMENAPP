// AmenEntitlementService.swift
// AMEN App — CommunityOS/Monetization
//
// Phase 6 — Agent M1 (Plans & Entitlements)
// iOS-side entitlement service. Reads entitlement state from Firestore.
// Initiates payment flows via Firebase Callable Functions ONLY — no Stripe SDK on iOS.
//
// PAYMENTS ADAPTER: All payment operations go through Firebase Callable Functions
// (createCovenantCheckoutSession, stripeCovenantWebhook, processGivingCharge).
// No Stripe SDK is imported on iOS — Stripe runs server-side only.
// HUMAN-GATED: payment flow changes require explicit human approval per §9 operating model.
//
// Firestore path: /entitlements/{holderId}
// Written: 2026-06-05

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

// MARK: - AmenEntitlementError

enum AmenEntitlementError: LocalizedError {
    case notAuthenticated
    case noEntitlementFound
    case serverError(Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to check your plan."
        case .noEntitlementFound:
            return "No active plan found. Your account is on the free tier."
        case .serverError(let underlying):
            return underlying.localizedDescription
        case .invalidResponse:
            return "Received an unexpected response from the server."
        }
    }
}

// MARK: - AmenEntitlementService

/// iOS-side entitlement service.
/// - Reads `/entitlements/{holderId}` from Firestore.
/// - All payment-initiating calls go through Firebase Callable Functions.
/// - `checkFeature()` always returns `false` (deny) when entitlement is not loaded — fail closed.
@MainActor
class AmenEntitlementService: ObservableObject {

    // MARK: - Published state

    @Published var currentEntitlement: AmenEntitlement?
    @Published var isLoading: Bool = false

    // MARK: - Private dependencies

    private let db = Firestore.firestore()
    // PAYMENTS ADAPTER: Firebase Functions proxy — no Stripe SDK imported on iOS.
    private let functions = Functions.functions()

    // MARK: - Firestore read

    /// Loads the entitlement document from `/entitlements/{holderId}`.
    /// Sets `currentEntitlement` on success; leaves it nil on failure (fail closed).
    func loadEntitlement(for holderId: String) async throws {
        guard !holderId.isEmpty else { throw AmenEntitlementError.notAuthenticated }
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await db
                .collection("entitlements")
                .document(holderId)
                .getDocument()

            guard let data = snapshot.data() else {
                // No document = free tier — create a synthetic free entitlement
                currentEntitlement = AmenEntitlement(
                    id: holderId,
                    holderType: "user",
                    planTier: .free,
                    stripeCustomerId: nil,
                    stripeSubscriptionId: nil,
                    status: .active,
                    currentPeriodEnd: nil,
                    cancelAtPeriodEnd: false,
                    createdAt: Date(),
                    updatedAt: Date()
                )
                return
            }

            currentEntitlement = try decodeEntitlement(from: data, holderId: holderId)
        } catch let error as AmenEntitlementError {
            throw error
        } catch {
            throw AmenEntitlementError.serverError(error)
        }
    }

    /// Async feature check — fetches entitlement fresh if needed, then evaluates.
    func isFeatureEnabled(_ feature: AmenFeatureGate, for holderId: String) async throws -> Bool {
        if currentEntitlement == nil {
            try await loadEntitlement(for: holderId)
        }
        return checkFeature(feature)
    }

    /// Synchronous check against the cached `currentEntitlement`.
    /// Returns `false` (deny) if entitlement has not been loaded yet — fail closed.
    func checkFeature(_ feature: AmenFeatureGate) -> Bool {
        guard let entitlement = currentEntitlement else {
            // Fail closed: no cached entitlement → deny access
            return false
        }
        return entitlement.hasFeature(feature)
    }

    // MARK: - Payment flow (all HUMAN-GATED via CF)

    /// Initiates a plan upgrade by calling the `createCovenantCheckoutSession` Firebase
    /// callable function.
    ///
    /// Returns a Stripe-hosted checkout URL for presentation in SFSafariViewController.
    /// The Stripe webhook CF (`stripeCovenantWebhook`) updates Firestore after payment.
    /// iOS NEVER writes to `/entitlements/` directly.
    ///
    /// HUMAN-GATED — payment flow changes require explicit human approval per §9.
    func initiateUpgrade(to tier: AmenPlanTier, for holderId: String) async throws -> String {
        guard Auth.auth().currentUser != nil else {
            throw AmenEntitlementError.notAuthenticated
        }

        // HUMAN-GATED: calls createCovenantCheckoutSession CF (Stripe key must be set before deploy)
        let callable = functions.httpsCallable("createCovenantCheckoutSession")
        let result = try await callable.call([
            "communityId": holderId,
            "tierId": tier.rawValue,
            // planContext differentiates this from per-Covenant checkout
            "planContext": "communityOS_plan_upgrade",
        ] as [String: Any])

        guard
            let data = result.data as? [String: Any],
            let checkoutUrl = data["checkoutUrl"] as? String,
            !checkoutUrl.isEmpty
        else {
            throw AmenEntitlementError.invalidResponse
        }

        return checkoutUrl
    }

    /// Opens the Stripe customer portal for subscription management.
    ///
    /// Returns a portal URL for presentation in SFSafariViewController.
    /// HUMAN-GATED — requires `STRIPE_SECRET_KEY` set on the CF.
    func openCustomerPortal(for holderId: String) async throws -> String {
        guard Auth.auth().currentUser != nil else {
            throw AmenEntitlementError.notAuthenticated
        }

        // HUMAN-GATED: calls createCustomerPortalSession CF
        let callable = functions.httpsCallable("createCustomerPortalSession")
        let result = try await callable.call([
            "holderId": holderId,
        ] as [String: Any])

        guard
            let data = result.data as? [String: Any],
            let portalUrl = data["portalUrl"] as? String,
            !portalUrl.isEmpty
        else {
            throw AmenEntitlementError.invalidResponse
        }

        return portalUrl
    }

    // MARK: - Webhook-driven refresh

    /// Re-reads Firestore after the user returns from Stripe checkout.
    /// The `stripeCovenantWebhook` CF updates the `/entitlements/{holderId}` document
    /// before the user is redirected back — so this read should see the new tier.
    func refreshEntitlement(for holderId: String) async throws {
        currentEntitlement = nil   // clear cache to force fresh read
        try await loadEntitlement(for: holderId)
    }

    // MARK: - Private helpers

    private func decodeEntitlement(from data: [String: Any], holderId: String) throws -> AmenEntitlement {
        // Map Firestore Timestamp → Date
        func date(for key: String) -> Date {
            if let ts = data[key] as? Timestamp { return ts.dateValue() }
            return Date()
        }
        func optionalDate(for key: String) -> Date? {
            if let ts = data[key] as? Timestamp { return ts.dateValue() }
            return nil
        }

        let planTierRaw = data["plan_tier"] as? String ?? "free"
        let planTier = AmenPlanTier(rawValue: planTierRaw) ?? .free

        let statusRaw = data["status"] as? String ?? "active"
        let status = EntitlementStatus(rawValue: statusRaw) ?? .active

        return AmenEntitlement(
            id: holderId,
            holderType: data["holder_type"] as? String ?? "user",
            planTier: planTier,
            // stripeCustomerId and stripeSubscriptionId are read from Firestore
            // for internal cache but NEVER displayed in UI.
            stripeCustomerId: data["stripe_customer_id"] as? String,
            stripeSubscriptionId: data["stripe_subscription_id"] as? String,
            status: status,
            currentPeriodEnd: optionalDate(for: "current_period_end"),
            cancelAtPeriodEnd: data["cancel_at_period_end"] as? Bool ?? false,
            createdAt: date(for: "created_at"),
            updatedAt: date(for: "updated_at")
        )
    }
}
