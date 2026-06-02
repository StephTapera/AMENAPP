// ONEEntitlementService.swift
// ONE P5-F — StoreKit 2 subscription purchase + server-side verification.
//
// Rules:
//   • Never show paywall UI or call verifyEntitlement until a .verified Transaction confirms locally.
//   • currentTier is informational. Server-side gating enforced in CF (one_verifyEntitlement).
//   • Restore calls restorePurchases() then re-verifies with server.
//   • No Stripe on iOS — digital subscriptions require Apple IAP (App Store review rule).

import Foundation
import StoreKit
import FirebaseAuth

// MARK: - Product IDs

private enum ONEProductID {
    static let monthly = "one.subscriber.monthly"
    static let annual  = "one.subscriber.annual"
    static var all: [String] { [monthly, annual] }
}

// MARK: - ONEEntitlementService

@MainActor
final class ONEEntitlementService: ObservableObject {
    static let shared = ONEEntitlementService()

    @Published var currentEntitlement: ONEEntitlement = .free
    @Published var products: [Product] = []
    @Published var isPurchasing = false
    @Published var isVerifying  = false
    @Published var purchaseError: String? = nil

    private var transactionListenerTask: Task<Void, Never>?

    private init() {
        transactionListenerTask = listenForTransactions()
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Load products

    func loadProducts() async {
        do {
            products = try await Product.products(for: ONEProductID.all)
                .sorted { $0.price < $1.price }
        } catch {
            // Products unavailable (sandbox/no network) — UI shows static fallback
            products = []
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    purchaseError = "Transaction could not be verified. Please try again."
                    return
                }
                await transaction.finish()
                await verifyWithServer()
            case .pending:
                break  // Ask-to-buy or SCA pending — listener handles when approved
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        isVerifying = true
        defer { isVerifying = false }
        // StoreKit 2: iterate current entitlements
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                await transaction.finish()
            }
        }
        await verifyWithServer()
    }

    // MARK: - Server verification

    func verifyWithServer() async {
        guard Auth.auth().currentUser != nil else { return }
        isVerifying = true
        defer { isVerifying = false }
        do {
            currentEntitlement = try await ONECallableService.shared.verifyEntitlement()
        } catch {
            // Network/server failure — keep current cached entitlement; don't downgrade
        }
    }

    // MARK: - Transaction listener (runs for app lifetime)

    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self.verifyWithServer()
                }
            }
        }
    }

    // MARK: - Gate helper

    /// Whether the current user has subscriber access.
    /// Informational only — server enforces gating in CF.
    var isSubscriber: Bool { currentEntitlement.isActive }
}
