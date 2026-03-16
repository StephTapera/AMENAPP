//
//  StudioPaymentService.swift
//  AMENAPP
//
//  Stripe Connect integration for Creator Studio payouts.
//  Handles connected account creation, payment intents, and payout management.
//
//  Setup:
//  1. Set STRIPE_PUBLISHABLE_KEY in Config.xcconfig
//  2. Deploy stripeCreateConnectedAccount and stripeCreatePaymentIntent Cloud Functions
//  3. Configure Stripe Connect in your Stripe Dashboard
//

import Foundation
import Combine
import FirebaseAuth

@MainActor
class StudioPaymentService: ObservableObject {
    static let shared = StudioPaymentService()

    @Published var hasConnectedAccount = false
    @Published var accountStatus: ConnectedAccountStatus = .none
    @Published var pendingBalance: Double = 0
    @Published var availableBalance: Double = 0
    @Published var isLoading = false

    private init() {}

    // MARK: - Connected Account

    enum ConnectedAccountStatus: String {
        case none
        case pending       // Onboarding started but not complete
        case active        // Can receive payments
        case restricted    // Needs additional verification
        case disabled      // Account disabled
    }

    /// Create a Stripe Connected Account for the creator.
    /// Returns an onboarding URL to complete identity verification.
    func createConnectedAccount() async throws -> URL {
        guard Auth.auth().currentUser?.uid != nil else {
            throw PaymentError.notAuthenticated
        }

        isLoading = true
        defer { isLoading = false }

        let result = try await CloudFunctionsService.shared.call(
            "stripeCreateConnectedAccount",
            data: [:] as [String: Any]
        )

        guard let dict = result as? [String: Any],
              let urlString = dict["onboardingUrl"] as? String,
              let url = URL(string: urlString) else {
            throw PaymentError.invalidResponse
        }

        accountStatus = .pending
        return url
    }

    /// Check the status of the creator's connected account.
    func refreshAccountStatus() async {
        guard Auth.auth().currentUser?.uid != nil else { return }

        do {
            let result = try await CloudFunctionsService.shared.call(
                "stripeGetAccountStatus",
                data: [:] as [String: Any]
            )

            guard let dict = result as? [String: Any] else { return }

            if let status = dict["status"] as? String {
                accountStatus = ConnectedAccountStatus(rawValue: status) ?? .none
                hasConnectedAccount = accountStatus == .active
            }

            pendingBalance = dict["pendingBalance"] as? Double ?? 0
            availableBalance = dict["availableBalance"] as? Double ?? 0
        } catch {
            AMENLog.error("Failed to refresh Stripe account status: \(error)", category: .api)
        }
    }

    // MARK: - Payment Intents

    /// Create a payment intent for a studio purchase (service, product, commission).
    /// Returns client secret for Stripe SDK payment sheet.
    func createPaymentIntent(
        creatorId: String,
        amount: Int, // in cents
        currency: String = "usd",
        description: String
    ) async throws -> String {
        isLoading = true
        defer { isLoading = false }

        let result = try await CloudFunctionsService.shared.call(
            "stripeCreatePaymentIntent",
            data: [
                "creatorId": creatorId,
                "amount": amount,
                "currency": currency,
                "description": description,
            ] as [String: Any]
        )

        guard let dict = result as? [String: Any],
              let clientSecret = dict["clientSecret"] as? String else {
            throw PaymentError.invalidResponse
        }

        return clientSecret
    }

    // MARK: - Payouts

    /// Request a payout of available balance to the creator's bank account.
    func requestPayout(amount: Int) async throws {
        isLoading = true
        defer { isLoading = false }

        _ = try await CloudFunctionsService.shared.call(
            "stripeRequestPayout",
            data: ["amount": amount] as [String: Any]
        )

        // Refresh balance after payout
        await refreshAccountStatus()
    }

    // MARK: - Errors

    enum PaymentError: LocalizedError {
        case notAuthenticated
        case invalidResponse
        case payoutFailed(String)
        case accountNotActive

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Sign in required."
            case .invalidResponse: return "Invalid payment response."
            case .payoutFailed(let msg): return "Payout failed: \(msg)"
            case .accountNotActive: return "Complete your payout setup first."
            }
        }
    }
}
