//
//  PremiumManager.swift
//  AMENAPP
//
//  Premium subscription and usage tracking manager
//

import Foundation
import StoreKit
import SwiftUI
import Combine

// MARK: - Premium Manager

@MainActor
class PremiumManager: ObservableObject {
    static let shared = PremiumManager()

    // MARK: - Published Properties

    @Published var hasProAccess: Bool = false
    @Published var isLoading: Bool = false
    @Published var purchaseError: String?

    // Usage tracking for free tier
    @Published var freeMessagesUsed: Int = 0
    @Published var freeMessagesRemaining: Int = 10

    // MARK: - Constants

    // Free tier limits
    let FREE_MESSAGES_PER_DAY = 10
    let FREE_MESSAGES_PER_MONTH = 100

    // Product IDs (must match App Store Connect)
    enum ProductID: String {
        case monthly = "com.amen.pro.monthly"
        case yearly = "com.amen.pro.yearly"
        case lifetime = "com.amen.pro.lifetime"
    }

    // MARK: - Products

    @Published var products: [Product] = []
    private var updates: Task<Void, Never>?

    // MARK: - Init

    init() {
        // Start transaction listener
        updates = observeTransactionUpdates()

        // Load saved premium status
        loadPremiumStatus()

        // Load usage data
        loadUsageData()

        // Check for active subscription
        Task {
            await checkSubscriptionStatus()
        }
    }

    deinit {
        updates?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        isLoading = true
        purchaseError = nil

        do {
            // Request products from App Store
            let productIDs: Set<String> = [
                ProductID.monthly.rawValue,
                ProductID.yearly.rawValue,
                ProductID.lifetime.rawValue
            ]

            products = try await Product.products(for: productIDs)
            print("✅ Loaded \(products.count) products")

        } catch {
            print("❌ Failed to load products: \(error.localizedDescription)")
            purchaseError = "Failed to load subscription options. Please try again."
        }

        isLoading = false
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async -> Bool {
        isLoading = true
        purchaseError = nil

        do {
            // Start purchase
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                // Check if transaction is verified
                let transaction = try checkVerified(verification)

                // Grant premium access
                await grantPremiumAccess()

                // Finish transaction
                await transaction.finish()

                print("✅ Purchase successful")
                isLoading = false
                return true

            case .userCancelled:
                print("❌ User cancelled purchase")
                purchaseError = nil
                isLoading = false
                return false

            case .pending:
                print("⏳ Purchase pending")
                purchaseError = "Purchase is pending approval"
                isLoading = false
                return false

            @unknown default:
                print("❌ Unknown purchase result")
                purchaseError = "Unknown error occurred"
                isLoading = false
                return false
            }

        } catch {
            print("❌ Purchase failed: \(error.localizedDescription)")
            purchaseError = "Purchase failed. Please try again."
            isLoading = false
            return false
        }
    }

    // MARK: - Restore Purchases

    func restorePurchases() async -> Bool {
        isLoading = true
        purchaseError = nil

        do {
            // Sync with App Store
            try await AppStore.sync()

            // Check subscription status
            await checkSubscriptionStatus()

            if hasProAccess {
                print("✅ Purchases restored successfully")
                isLoading = false
                return true
            } else {
                print("❌ No active subscription found")
                purchaseError = "No active subscription found"
                isLoading = false
                return false
            }

        } catch {
            print("❌ Restore failed: \(error.localizedDescription)")
            purchaseError = "Failed to restore purchases"
            isLoading = false
            return false
        }
    }

    // MARK: - Check Subscription Status

    func checkSubscriptionStatus() async {
        // Check for active subscriptions
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)

                // Check if subscription is active
                if transaction.productType == .autoRenewable {
                    await grantPremiumAccess()
                    return
                }

                // Check for non-consumable (lifetime)
                if transaction.productType == .nonConsumable {
                    await grantPremiumAccess()
                    return
                }

            } catch {
                print("❌ Transaction verification failed: \(error)")
            }
        }

        // No active subscription found
        await revokePremiumAccess()
    }

    // MARK: - Observe Transaction Updates

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task(priority: .background) {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)

                    // Update subscription status
                    await self.checkSubscriptionStatus()

                    // Finish transaction
                    await transaction.finish()

                } catch {
                    print("❌ Transaction update failed: \(error)")
                }
            }
        }
    }

    // MARK: - Grant/Revoke Premium

    private func grantPremiumAccess() async {
        hasProAccess = true
        savePremiumStatus(true)
        print("✅ Premium access granted")
    }

    private func revokePremiumAccess() async {
        hasProAccess = false
        savePremiumStatus(false)
        print("❌ Premium access revoked")
    }

    // MARK: - Verify Transaction

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Usage Tracking

    func canSendMessage() -> Bool {
        // Premium users have unlimited messages
        if hasProAccess {
            return true
        }

        // Check daily limit
        let today = Calendar.current.startOfDay(for: Date())
        let lastResetDate = UserDefaults.standard.object(forKey: "lastMessageResetDate") as? Date ?? Date.distantPast

        // Reset daily count if new day
        if today > lastResetDate {
            resetDailyUsage()
        }

        // Check if under limit
        return freeMessagesUsed < FREE_MESSAGES_PER_DAY
    }

    func incrementMessageCount() {
        if hasProAccess {
            return // Premium users don't count
        }

        freeMessagesUsed += 1
        freeMessagesRemaining = max(0, FREE_MESSAGES_PER_DAY - freeMessagesUsed)

        // Save to UserDefaults
        UserDefaults.standard.set(freeMessagesUsed, forKey: "freeMessagesUsed")
        print("📊 Messages used: \(freeMessagesUsed)/\(FREE_MESSAGES_PER_DAY)")
    }

    private func resetDailyUsage() {
        freeMessagesUsed = 0
        freeMessagesRemaining = FREE_MESSAGES_PER_DAY

        UserDefaults.standard.set(freeMessagesUsed, forKey: "freeMessagesUsed")
        UserDefaults.standard.set(Date(), forKey: "lastMessageResetDate")
        print("🔄 Daily usage reset")
    }

    // MARK: - Persistence

    private func savePremiumStatus(_ status: Bool) {
        UserDefaults.standard.set(status, forKey: "hasProAccess")
    }

    private func loadPremiumStatus() {
        hasProAccess = UserDefaults.standard.bool(forKey: "hasProAccess")
    }

    private func loadUsageData() {
        freeMessagesUsed = UserDefaults.standard.integer(forKey: "freeMessagesUsed")
        freeMessagesRemaining = max(0, FREE_MESSAGES_PER_DAY - freeMessagesUsed)

        // Check if need to reset
        let today = Calendar.current.startOfDay(for: Date())
        let lastResetDate = UserDefaults.standard.object(forKey: "lastMessageResetDate") as? Date ?? Date.distantPast

        if today > lastResetDate {
            resetDailyUsage()
        }
    }

    // MARK: - Helper Methods

    func getMonthlyProduct() -> Product? {
        products.first { $0.id == ProductID.monthly.rawValue }
    }

    func getYearlyProduct() -> Product? {
        products.first { $0.id == ProductID.yearly.rawValue }
    }

    func getLifetimeProduct() -> Product? {
        products.first { $0.id == ProductID.lifetime.rawValue }
    }
}

// MARK: - Store Error

enum StoreError: Error {
    case failedVerification
}
