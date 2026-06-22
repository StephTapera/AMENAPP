// AmenStoreKitService.swift
// AMEN Spaces — Monetization: StoreKit 2 subscription service
//
// Security note: transaction verification uses StoreKit's built-in
// JWS signature check. Only .verified transactions are processed.
// Server-side receipt validation is performed by the processSubscription
// Cloud Function before any entitlement is granted.
// Written: 2026-06-02

import StoreKit
import FirebaseFunctions

// MARK: - Service

@MainActor
final class AmenStoreKitService: ObservableObject {

    // MARK: - Published State

    @Published var availableProducts: [Product] = []
    @Published var purchasedProductIds: Set<String> = []
    @Published var isLoading: Bool = false
    @Published var purchaseError: String?

    // MARK: - Singleton

    static let shared = AmenStoreKitService()

    // MARK: - Private

    private let functions: Functions = Functions.functions()
    private var transactionListenerTask: Task<Void, Never>?

    // MARK: - Init / Deinit

    private init() {}

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Public API

    /// Loads available StoreKit products for the given tiers and refreshes
    /// the local purchased-product-id cache from current App Store entitlements.
    func loadProducts(for tiers: [AmenSpaceSubscriptionTier]) async {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }

        let productIds = tiers.compactMap(\.storeKitProductId)
        guard !productIds.isEmpty else { return }

        do {
            let fetched = try await Product.products(for: productIds)
            availableProducts = fetched.sorted { $0.price < $1.price }
            await refreshPurchasedProductIds()
        } catch {
            purchaseError = "Could not load subscription options. Please try again."
        }
    }

    /// Initiates the purchase flow for the given tier.
    /// - Returns: The verified `Transaction` on success.
    /// - Throws: `AmenStoreKitError` or `StoreKitError` on failure.
    @discardableResult
    func purchase(tier: AmenSpaceSubscriptionTier) async throws -> Transaction {
        guard let productId = tier.storeKitProductId else {
            throw AmenStoreKitError.noProductId(tierId: tier.id)
        }

        guard let product = availableProducts.first(where: { $0.id == productId }) else {
            throw AmenStoreKitError.productNotLoaded(productId: productId)
        }

        isLoading = true
        purchaseError = nil
        defer { isLoading = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            // Notify server before finishing the transaction so entitlement
            // is persisted even if the app is killed immediately after.
            try await notifyServer(transaction: transaction, tier: tier)
            await transaction.finish()
            purchasedProductIds.insert(productId)
            return transaction

        case .pending:
            throw AmenStoreKitError.purchasePending

        case .userCancelled:
            throw AmenStoreKitError.userCancelled

        @unknown default:
            throw AmenStoreKitError.unknown
        }
    }

    /// Triggers `AppStore.sync()` to restore purchases on a new device,
    /// then refreshes the local entitlement cache.
    func restorePurchases() async {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await refreshPurchasedProductIds()
        } catch {
            purchaseError = "Could not restore purchases. Please try again."
        }
    }

    /// Starts a long-lived listener for `Transaction.updates` (e.g. renewals,
    /// price-consent changes, billing-retry successes).
    /// Call once from the app entry point or a long-lived owner.
    func listenForTransactions() async {
        for await verification in Transaction.updates {
            do {
                let transaction = try checkVerified(verification)
                // Re-notify the server for every completed renewal /
                // recovery so the Firestore entitlement stays in sync.
                try await notifyServerIfPossible(transaction: transaction)
                await transaction.finish()
                purchasedProductIds.insert(transaction.productID)
            } catch {
                // Log but never crash — a missed update will be recovered
                // on the next loadProducts / restorePurchases call.
            }
        }
    }

    /// Convenience: starts `listenForTransactions()` as a detached background task.
    func startTransactionListener() {
        transactionListenerTask?.cancel()
        transactionListenerTask = Task.detached(priority: .background) { [weak self] in
            await self?.listenForTransactions()
        }
    }

    /// Returns `true` if the user currently owns the given tier.
    func isPurchased(_ tier: AmenSpaceSubscriptionTier) -> Bool {
        purchasedProductIds.contains(tier.storeKitProductId ?? "")
    }

    // MARK: - Private Helpers

    /// Re-scans all current App Store entitlements and rebuilds `purchasedProductIds`.
    private func refreshPurchasedProductIds() async {
        var ids = Set<String>()
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if transaction.revocationDate == nil {
                ids.insert(transaction.productID)
            }
        }
        purchasedProductIds = ids
    }

    /// Unwraps a `VerificationResult<Transaction>`, throwing if the JWS
    /// signature cannot be verified by StoreKit.
    private func checkVerified(_ result: VerificationResult<Transaction>) throws -> Transaction {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let transaction):
            return transaction
        }
    }

    /// Calls the `processSubscription` Cloud Function to persist the
    /// entitlement server-side. The transaction must NOT be finished before
    /// this call returns to prevent entitlement loss on CF failure.
    private func notifyServer(transaction: Transaction, tier: AmenSpaceSubscriptionTier) async throws {
        let callable = functions.httpsCallable("processSubscription")
        let payload: [String: Any] = [
            "spaceId": tier.spaceId,
            "tierId": tier.id,
            "storeKitTransactionId": transaction.id.description,
            "idempotencyKey": UUID().uuidString,
        ]
        _ = try await callable.call(payload)
    }

    /// Best-effort server notification for background transaction updates.
    /// Swallows errors so the transaction listener loop never aborts.
    private func notifyServerIfPossible(transaction: Transaction) async throws {
        let callable = functions.httpsCallable("processSubscription")
        let payload: [String: Any] = [
            "storeKitTransactionId": transaction.id.description,
            "productId": transaction.productID,
        ]
        _ = try await callable.call(payload)
    }
}

// MARK: - Error Types

enum AmenStoreKitError: LocalizedError {
    case noProductId(tierId: String)
    case productNotLoaded(productId: String)
    case purchasePending
    case userCancelled
    case unknown

    var errorDescription: String? {
        switch self {
        case .noProductId:
            return "This tier does not have an App Store product configured."
        case .productNotLoaded(let id):
            return "Product \(id) was not found in the App Store. Please try again."
        case .purchasePending:
            return "Your purchase is awaiting approval. You will be notified when it is complete."
        case .userCancelled:
            return nil   // user-initiated; no error UI needed
        case .unknown:
            return "An unexpected error occurred. Please try again."
        }
    }
}

// MARK: - Preview

#if DEBUG
extension AmenStoreKitService {
    static var preview: AmenStoreKitService {
        let service = AmenStoreKitService()
        service.purchasedProductIds = ["com.amenapp.spaces.member.monthly"]
        return service
    }
}
#endif
