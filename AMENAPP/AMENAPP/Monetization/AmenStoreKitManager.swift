// AmenStoreKitManager.swift
// AMENAPP — Platform Monetization
//
// StoreKit 2 subscription manager for platform-level tiers.
// This is the canonical entry point for all in-app purchase flows at the
// platform level (Amen+, AmenPro, CreatorPro, ChurchPro).
//
// Per-Space membership is handled separately by AmenStoreKitService.
//
// Design rules:
//   - @MainActor — all state mutations happen on the main actor.
//   - async/await only — no Combine, no StoreKit 1.
//   - Delegate server-side validation to AmenPlatformStoreKitService.
//   - Transaction listener started from AMENAPPApp on launch.
// Written: 2026-06-08

import StoreKit
import Foundation

// MARK: - Product ID Constants

extension AmenStoreKitManager {
    /// App Store Connect product identifiers.
    /// Replace the placeholder values with real IDs before App Store submission.
    static let amenPlusMonthly    = "com.amen.subscription.plus.monthly"
    static let amenProMonthly     = "com.amen.subscription.pro.monthly"
    static let creatorProMonthly  = "com.amen.subscription.creatorpro.monthly"
    static let churchProMonthly   = "com.amen.subscription.churchpro.monthly"

    // Annual variants
    static let amenPlusAnnual     = "com.amen.subscription.plus.annual"
    static let amenProAnnual      = "com.amen.subscription.pro.annual"
    static let creatorProAnnual   = "com.amen.subscription.creatorpro.annual"
    static let churchProAnnual    = "com.amen.subscription.churchpro.annual"

    /// All purchasable product IDs. Used by `loadProducts()`.
    static var allProductIDs: [String] {
        [
            amenPlusMonthly, amenProMonthly, creatorProMonthly, churchProMonthly,
            amenPlusAnnual,  amenProAnnual,  creatorProAnnual,  churchProAnnual,
        ]
    }
}

// MARK: - AmenStoreKitManager

/// Observable StoreKit 2 manager. The primary surface for subscription flows.
///
/// Typical usage from a SwiftUI view:
/// ```swift
/// @EnvironmentObject private var storeKit: AmenStoreKitManager
///
/// Button("Subscribe") {
///     Task { _ = try await storeKit.purchase(product) }
/// }
/// .task { await storeKit.loadProducts() }
/// ```
///
/// Start the transaction listener once from the app entry point:
/// ```swift
/// storeKit.startTransactionListener()
/// ```
@MainActor
final class AmenStoreKitManager: ObservableObject {

    // MARK: - Singleton

    static let shared = AmenStoreKitManager()

    // MARK: - Published State

    /// All fetched App Store products, sorted by price ascending.
    @Published var products: [Product] = []

    /// Product IDs of subscriptions the current user is actively entitled to.
    @Published var purchasedSubscriptions: Set<String> = []

    /// True while `loadProducts()` or a purchase is in flight.
    @Published var isLoading: Bool = false

    /// Non-nil when a purchase attempt has failed with a user-visible error.
    @Published var purchaseError: String?

    // MARK: - Private

    private var transactionListenerTask: Task<Void, Never>?

    // MARK: - Init

    init() {}

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Load Products

    /// Fetches all platform subscription products from the App Store.
    /// Falls back silently if the network is unavailable — callers display
    /// the static `AmenAccountTier.monthlyPrice` string as a fallback.
    func loadProducts() async {
        guard products.isEmpty else { return }  // already loaded
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await Product.products(for: AmenStoreKitManager.allProductIDs)
            products = fetched.sorted { $0.price < $1.price }
            await refreshEntitlements()
        } catch {
            // Non-fatal — UI falls back to static price strings.
        }
    }

    // MARK: - Purchase

    /// Initiates a StoreKit 2 purchase for the supplied product.
    /// - Returns: `true` on success, `false` if the user cancelled or the
    ///   purchase is pending (Ask-to-Buy), or rethrows on hard failure.
    /// - Throws: Any StoreKit error that should surface to the UI.
    @discardableResult
    func purchase(_ product: Product) async throws -> Bool {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            purchasedSubscriptions.insert(product.id)
            // Refresh the entitlement cache so gated features unlock immediately.
            await AmenAccountEntitlementService.shared.forceRefresh()
            return true

        case .pending:
            // Ask-to-Buy — entitlement will arrive via transaction listener.
            return false

        case .userCancelled:
            return false

        @unknown default:
            return false
        }
    }

    // MARK: - Restore Purchases

    /// Syncs with the App Store and rebuilds the local entitlement set.
    func restorePurchases() async {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            await AmenAccountEntitlementService.shared.forceRefresh()
        } catch {
            purchaseError = "Could not restore purchases. Please try again."
        }
    }

    // MARK: - Entitlement Helpers

    /// Returns `true` if the product ID is in the active entitlement set.
    func isSubscribed(to productID: String) -> Bool {
        purchasedSubscriptions.contains(productID)
    }

    /// Returns the loaded `Product` for a given tier product ID, or `nil`
    /// while products are still loading.
    func product(for productID: String) -> Product? {
        products.first(where: { $0.id == productID })
    }

    // MARK: - Transaction Listener

    /// Starts a long-lived background task that processes App Store transaction
    /// updates (renewals, billing-retry recoveries, revocations).
    /// Call once from the app entry point; idempotent.
    func startTransactionListener() {
        guard transactionListenerTask == nil else { return }
        transactionListenerTask = Task.detached(priority: .background) { [weak self] in
            await self?.listenForTransactions()
        }
    }

    // MARK: - Private

    private func listenForTransactions() async {
        for await verification in Transaction.updates {
            do {
                let transaction = try checkVerified(verification)
                await MainActor.run {
                    purchasedSubscriptions.insert(transaction.productID)
                }
                await transaction.finish()
                await AmenAccountEntitlementService.shared.forceRefresh()
            } catch {
                // Unverified or revoked — skip without crashing.
            }
        }
    }

    /// Rebuilds `purchasedSubscriptions` from the current App Store entitlements.
    private func refreshEntitlements() async {
        var ids = Set<String>()
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if transaction.revocationDate == nil {
                ids.insert(transaction.productID)
            }
        }
        purchasedSubscriptions = ids
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):  return value
        case .unverified(_, let error): throw error
        }
    }
}

// MARK: - Preview

#if DEBUG
extension AmenStoreKitManager {
    static var preview: AmenStoreKitManager {
        let m = AmenStoreKitManager()
        m.purchasedSubscriptions = [AmenStoreKitManager.amenPlusMonthly]
        return m
    }
}
#endif
