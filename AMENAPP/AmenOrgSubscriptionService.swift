// AmenOrgSubscriptionService.swift
// AMENAPP
//
// iOS service layer for org subscription management.
// Calls Cloud Functions: createOrgSubscriptionCheckout, getOrgBillingPortalURL.
// Membership / billing status is NEVER written from the client —
// stripeOrgWebhook handles Firestore writes after Stripe confirms payment.

import Foundation
import FirebaseFunctions
import FirebaseFirestore
import FirebaseAuth
import AuthenticationServices
import UIKit

// MARK: - AmenOrgSubscriptionService

@MainActor
final class AmenOrgSubscriptionService: NSObject, ObservableObject {

    static let shared = AmenOrgSubscriptionService()

    // MARK: - State

    enum CheckoutState: Equatable {
        case idle
        case loading
        case redirecting(URL)
        case error(String)

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.loading, .loading): return true
            case (.redirecting(let a), .redirecting(let b)): return a == b
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }

    enum PortalState: Equatable {
        case idle
        case loading
        case redirecting(URL)
        case error(String)

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.loading, .loading): return true
            case (.redirecting(let a), .redirecting(let b)): return a == b
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }

    @Published var checkoutState: CheckoutState = .idle
    @Published var portalState: PortalState = .idle

    // MARK: - Private

    private let functions = Functions.functions(region: "us-central1")
    private let db = Firestore.firestore()

    /// Idempotency guard: prevents rapid double-tap from issuing two Stripe charges.
    private var isCheckoutInProgress = false

    private var authSession: ASWebAuthenticationSession?

    private override init() {}

    // MARK: - Checkout

    /// Opens a Stripe-hosted checkout session for the given org + plan.
    /// Calls `createOrgSubscriptionCheckout` Cloud Function.
    func startCheckout(orgId: String, plan: AmenOrganizationBillingPlan) async {
        guard !isCheckoutInProgress else { return }
        guard plan != .free else {
            checkoutState = .error("The Free plan has no checkout.")
            return
        }
        guard AMENFeatureFlags.shared.paymentsEnabled else {
            checkoutState = .error("Payments are currently unavailable.")
            return
        }

        isCheckoutInProgress = true
        defer { isCheckoutInProgress = false }
        checkoutState = .loading

        let callable = functions.httpsCallable("createOrgSubscriptionCheckout")
        do {
            let result = try await callable.call([
                "orgId": orgId,
                "plan": plan.rawValue
            ])
            guard
                let data = result.data as? [String: Any],
                let urlString = data["checkoutUrl"] as? String,
                let url = URL(string: urlString)
            else {
                checkoutState = .error("Received an unexpected response from the server.")
                return
            }

            checkoutState = .redirecting(url)
            await openWebAuthSession(url: url, callbackScheme: "amen", context: .checkout(orgId: orgId))
        } catch {
            checkoutState = .error(error.localizedDescription)
        }
    }

    // MARK: - Billing Portal

    /// Opens the Stripe Customer Portal for the given org.
    /// Calls `getOrgBillingPortalURL` Cloud Function.
    func openBillingPortal(orgId: String) async {
        guard AMENFeatureFlags.shared.paymentsEnabled else {
            portalState = .error("Payments are currently unavailable.")
            return
        }

        portalState = .loading
        let callable = functions.httpsCallable("getOrgBillingPortalURL")
        do {
            let result = try await callable.call(["orgId": orgId])
            guard
                let data = result.data as? [String: Any],
                let urlString = data["portalUrl"] as? String,
                let url = URL(string: urlString)
            else {
                portalState = .error("Received an unexpected response from the server.")
                return
            }

            portalState = .redirecting(url)
            await openWebAuthSession(url: url, callbackScheme: "amen", context: .portal(orgId: orgId))
        } catch {
            portalState = .error(error.localizedDescription)
        }
    }

    // MARK: - Refresh Billing Status

    /// Reads the current billing document for `orgId` from Firestore.
    /// Call after receiving a push/Firestore listener update confirming a tier change.
    @discardableResult
    func refreshBillingStatus(orgId: String) async -> AmenOrganizationBilling? {
        do {
            let snap = try await db
                .collection("organizations").document(orgId)
                .collection("billing").document("subscription")
                .getDocument()
            guard snap.exists, let data = snap.data() else { return nil }
            let tierRaw = data["tier"] as? String ?? "free"
            let tier = AmenOrganizationBillingPlan(rawValue: tierRaw) ?? .free
            let status = data["status"] as? String ?? "unknown"
            let stripeCustomerId = data["stripeCustomerId"] as? String
            let subscriptionId = data["stripeSubscriptionId"] as? String
            return AmenOrganizationBilling(
                stripeCustomerId: stripeCustomerId,
                subscriptionId: subscriptionId,
                tier: tier,
                status: status
            )
        } catch {
            return nil
        }
    }

    // MARK: - Reset

    func reset() {
        checkoutState = .idle
        portalState = .idle
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension AmenOrgSubscriptionService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

// MARK: - Private Helpers

private enum AmenOrgWebAuthContext {
    case checkout(orgId: String)
    case portal(orgId: String)
}

private extension AmenOrgSubscriptionService {

    func openWebAuthSession(
        url: URL,
        callbackScheme: String,
        context: AmenOrgWebAuthContext
    ) async {
        await withCheckedContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                guard let self else { continuation.resume(); return }

                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    Task { @MainActor in
                        switch context {
                        case .checkout: self.checkoutState = .idle
                        case .portal:   self.portalState = .idle
                        }
                    }
                    continuation.resume()
                    return
                }

                if let callbackURL {
                    let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
                    let result = components?.queryItems?.first(where: { $0.name == "result" })?.value

                    Task { @MainActor in
                        if result == "success" {
                            let orgId: String
                            switch context {
                            case .checkout(let id): orgId = id
                            case .portal(let id):   orgId = id
                            }
                            // Refresh billing from Firestore to pick up new tier.
                            _ = await self.refreshBillingStatus(orgId: orgId)
                            switch context {
                            case .checkout: self.checkoutState = .idle
                            case .portal:   self.portalState = .idle
                            }
                        } else {
                            switch context {
                            case .checkout: self.checkoutState = .idle
                            case .portal:   self.portalState = .idle
                            }
                        }
                    }
                }
                continuation.resume()
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }
    }
}
