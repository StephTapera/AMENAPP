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

    // MARK: - Product ID Map
    // Enterprise is manual — omitted intentionally.

    static let productIDs: [AmenAccountTier: String] = [
        .amenPlus:   "com.amenapp.subscription.amenplus.monthly",
        .amenPro:    "com.amenapp.subscription.amenpro.monthly",
        .creatorPro: "com.amenapp.subscription.creatorpro.monthly",
        .churchPro:  "com.amenapp.subscription.churchpro.monthly",
    ]

    // MARK: - Published State

    @Published var products: [AmenAccountTier: Product] = [:]
    @Published var purchaseState: PlatformPurchaseState = .idle

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

    /// Fetches StoreKit products for all purchasable tiers and populates `products`.
    func loadProducts() async {
        let ids = Array(AmenPlatformStoreKitService.productIDs.values)
        do {
            let fetched = try await Product.products(for: ids)
            var map: [AmenAccountTier: Product] = [:]
            for product in fetched {
                if let tier = AmenPlatformStoreKitService.productIDs
                    .first(where: { $0.value == product.id })?.key {
                    map[tier] = product
                }
            }
            products = map
        } catch {
            // Non-fatal — paywall will fall back to static pricing strings.
        }
    }

    // MARK: - Purchase

    /// Initiates a StoreKit 2 purchase for the given tier.
    /// - Throws: `PlatformPurchaseError.productNotFound` if the product has not been loaded,
    ///   `PlatformPurchaseError.verificationFailed` for JWS verification failures,
    ///   or `PlatformPurchaseError.serverError` if the Cloud Function returns an error.
    func purchase(_ tier: AmenAccountTier) async throws {
        guard let product = products[tier] else {
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
