// AmenPlatformStoreKitService.swift
// AMENAPP — Platform Monetization
//
// StoreKit 2 purchase flow for platform-level subscription tiers.
// Enterprise tier is manual — not handled via StoreKit.
// Server-side validation is performed via the `processAccountSubscription`
// Firebase callable after every successful purchase.
//
// Design rules:
//   - @MainActor singleton
//   - No Combine — StoreKit 2 async/await only
//   - 4-space indentation
// Written: 2026-06-05

import StoreKit
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

// MARK: - PlatformPurchaseState

enum PlatformPurchaseState {
    case idle
    case purchasing(tier: AmenAccountTier)
    case success(tier: AmenAccountTier)
    case failed(Error)
}

// MARK: - PlatformPurchaseError

enum PlatformPurchaseError: LocalizedError {
    case productNotFound
    case verificationFailed
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "This subscription product could not be found. Please try again later."
        case .verificationFailed:
            return "Purchase verification failed. Please contact support if the issue persists."
        case .serverError(let message):
            return "A server error occurred: \(message)"
        }
    }
}

// MARK: - AmenPlatformStoreKitService

@MainActor
final class AmenPlatformStoreKitService: ObservableObject {

    // MARK: - Singleton

    static let shared = AmenPlatformStoreKitService()

    // MARK: - Product ID Maps
    // Enterprise is manual — omitted intentionally.
    // Canonical product IDs are defined in AmenStoreKitManager; these maps
    // bridge from AmenAccountTier for backwards-compatible call sites.

    static let monthlyProductIDs: [AmenAccountTier: String] = [
        .amenPlus:   AmenStoreKitManager.amenPlusMonthly,
        .amenPro:    AmenStoreKitManager.amenProMonthly,
        .creatorPro: AmenStoreKitManager.creatorProMonthly,
        .churchPro:  AmenStoreKitManager.churchProMonthly,
    ]

    static let annualProductIDs: [AmenAccountTier: String] = [
        .amenPlus:   AmenStoreKitManager.amenPlusAnnual,
        .amenPro:    AmenStoreKitManager.amenProAnnual,
        .creatorPro: AmenStoreKitManager.creatorProAnnual,
        .churchPro:  AmenStoreKitManager.churchProAnnual,
    ]

    /// Backward-compatible alias — always returns monthly IDs.
    static var productIDs: [AmenAccountTier: String] { monthlyProductIDs }

    // MARK: - Published State

    @Published var monthlyProducts: [AmenAccountTier: Product] = [:]
    @Published var annualProducts: [AmenAccountTier: Product] = [:]
    @Published var purchaseState: PlatformPurchaseState = .idle

    /// Backward-compatible — returns the monthly product map.
    var products: [AmenAccountTier: Product] { monthlyProducts }

    // MARK: - Private

    private var updateListenerTask: Task<Void, Error>?

    // MARK: - Init

    private init() {
        listenForTransactions()
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Load Products

    /// Fetches StoreKit products for all purchasable tiers (both monthly and annual).
    func loadProducts() async {
        let allIDs = Array(AmenPlatformStoreKitService.monthlyProductIDs.values)
                   + Array(AmenPlatformStoreKitService.annualProductIDs.values)
        do {
            let fetched = try await Product.products(for: allIDs)
            var monthly: [AmenAccountTier: Product] = [:]
            var annual: [AmenAccountTier: Product] = [:]
            for product in fetched {
                if let tier = AmenPlatformStoreKitService.monthlyProductIDs
                    .first(where: { $0.value == product.id })?.key {
                    monthly[tier] = product
                } else if let tier = AmenPlatformStoreKitService.annualProductIDs
                    .first(where: { $0.value == product.id })?.key {
                    annual[tier] = product
                }
            }
            monthlyProducts = monthly
            annualProducts = annual
        } catch {
            // Non-fatal — paywall will fall back to static pricing strings.
        }
    }

    // MARK: - Purchase

    /// Initiates a StoreKit 2 purchase for the given tier.
    /// - Parameters:
    ///   - tier: The subscription tier to purchase.
    ///   - annually: Pass `true` to purchase the annual product. Defaults to `false` (monthly).
    /// - Throws: `PlatformPurchaseError.productNotFound`, `.verificationFailed`, or `.serverError`.
    func purchase(_ tier: AmenAccountTier, annually: Bool = false) async throws {
        let map = annually ? annualProducts : monthlyProducts
        guard let product = map[tier] else {
            purchaseState = .failed(PlatformPurchaseError.productNotFound)
            throw PlatformPurchaseError.productNotFound
        }

        purchaseState = .purchasing(tier: tier)

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                try await processSubscriptionWithServer(
                    transactionId: String(transaction.id),
                    tier: tier
                )
                await transaction.finish()
                await AmenAccountEntitlementService.shared.forceRefresh()
                purchaseState = .success(tier: tier)

            case .userCancelled:
                purchaseState = .idle

            case .pending:
                purchaseState = .idle

            @unknown default:
                purchaseState = .idle
            }
        } catch let purchaseError as PlatformPurchaseError {
            purchaseState = .failed(purchaseError)
            throw purchaseError
        } catch {
            purchaseState = .failed(error)
            throw error
        }
    }

    // MARK: - Restore Purchases

    /// Re-syncs App Store transactions and refreshes the server-backed account entitlement cache.
    func restorePurchases() async throws {
        do {
            try await AppStore.sync()
            await AmenAccountEntitlementService.shared.forceRefresh()
            purchaseState = .idle
        } catch {
            purchaseState = .failed(error)
            throw error
        }
    }

    // MARK: - StoreKit Verification Helper

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw PlatformPurchaseError.verificationFailed
        }
    }

    // MARK: - Server Validation

    /// Calls the `processAccountSubscription` Firebase callable to record the
    /// subscription server-side and update the user's entitlement document.
    private func processSubscriptionWithServer(transactionId: String, tier: AmenAccountTier) async throws {
        let functions = Functions.functions()
        let callable = functions.httpsCallable("processAccountSubscription")
        let payload: [String: Any] = [
            "transactionId": transactionId,
            "tier": tier.rawValue,
            "uid": Auth.auth().currentUser?.uid ?? "",
        ]
        do {
            _ = try await callable.call(payload)
        } catch {
            throw PlatformPurchaseError.serverError(error.localizedDescription)
        }
    }

    // MARK: - Transaction Listener

    /// Starts a long-lived task that processes any transactions delivered outside
    /// the normal purchase flow (e.g. renewals, purchases made on other devices).
    private func listenForTransactions() {
        updateListenerTask = Task(priority: .background) {
            for await result in Transaction.updates {
                do {
                    let transaction = try checkVerified(result)
                    await transaction.finish()
                    await AmenAccountEntitlementService.shared.forceRefresh()
                } catch {
                    // Unverified transaction — skip and do not grant entitlement.
                }
            }
        }
    }
}
