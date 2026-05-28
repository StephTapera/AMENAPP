// SpacesEntitlementService.swift
// AMENAPP — Spaces Monetization (Agent E)
//
// Entitlement check, purchase orchestration, and real-time observation
// for paid Spaces. The client READS entitlements; Cloud Functions write them.
//
// Architecture:
//   purchaseAccess(space:) → calls createSpaceCheckoutSession CF → opens Stripe
//   checkout via ASWebAuthenticationSession → Stripe webhook → CF writes
//   entitlement → AsyncStream fires → UI unlocks.
//
// Constraints:
//   - @MainActor throughout
//   - No Combine — AsyncStream for real-time updates
//   - No force-unwrap
//   - No "church" anywhere
//   - Entitlement writes: Cloud Functions / Admin SDK only
//   - Money never crosses a community Link

import Foundation
import AuthenticationServices
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import UIKit

// MARK: - Entitlement Service Error

enum SpacesEntitlementError: LocalizedError {
    case notAuthenticated
    case spaceNotPurchasable
    case missingPriceConfig
    case invalidServerResponse
    case checkoutCanceled
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to access paid Spaces."
        case .spaceNotPurchasable:
            return "This Space does not require a purchase."
        case .missingPriceConfig:
            return "This Space does not have a price configured."
        case .invalidServerResponse:
            return "Received an unexpected response. Please try again."
        case .checkoutCanceled:
            return "Checkout was canceled."
        case .network(let underlying):
            return underlying.localizedDescription
        }
    }
}

// MARK: - SpacesEntitlementService

/// Entitlement check, purchase flow, and real-time observation for paid Spaces.
/// The client only READS entitlements; all writes happen in Cloud Functions.
@MainActor
final class SpacesEntitlementService: NSObject, ObservableObject {

    static let shared = SpacesEntitlementService()

    // MARK: Published State

    /// Cached entitlement state per spaceId.
    @Published var entitlementsBySpace: [String: SpaceEntitlement] = [:]

    // MARK: Private

    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private var authSession: ASWebAuthenticationSession?

    // Active listener tasks, keyed by spaceId.
    private var listenerTasks: [String: Task<Void, Never>] = [:]

    private override init() {}

    // MARK: - Entitlement Check

    /// Returns true if the current user has active or grace entitlement to the space.
    func hasActiveEntitlement(spaceId: String) async throws -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw SpacesEntitlementError.notAuthenticated
        }
        let docId = "\(uid)_\(spaceId)"
        let doc = try await db.collection("entitlements").document(docId).getDocument()
        guard doc.exists, let data = doc.data() else { return false }
        let status = data["status"] as? String ?? ""
        return status == "active" || status == "grace"
    }

    // MARK: - Purchase Flow

    /// Initiates a Stripe checkout for a paid Space.
    /// On successful payment the Stripe webhook CF writes the entitlement;
    /// the real-time listener then fires and the paywall dissolves.
    func purchaseAccess(space: AmenSpace) async throws {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            throw SpacesEntitlementError.notAuthenticated
        }
        guard space.accessPolicy.isPaid else {
            throw SpacesEntitlementError.spaceNotPurchasable
        }
        guard space.priceConfig != nil else {
            throw SpacesEntitlementError.missingPriceConfig
        }
        guard let spaceId = space.id, !spaceId.isEmpty else {
            throw SpacesEntitlementError.invalidServerResponse
        }

        let payload: [String: Any] = ["spaceId": spaceId]
        let result: HTTPSCallableResult
        do {
            result = try await functions.httpsCallable("createSpaceCheckoutSession").call(payload)
        } catch {
            throw SpacesEntitlementError.network(error)
        }

        guard
            let data = result.data as? [String: Any],
            let urlString = data["checkoutURL"] as? String,
            let checkoutURL = URL(string: urlString)
        else {
            throw SpacesEntitlementError.invalidServerResponse
        }

        try await presentCheckoutSession(url: checkoutURL)
    }

    // MARK: - Restore

    /// Refreshes entitlement state from Firestore for one-time purchases.
    func restorePurchase(spaceId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw SpacesEntitlementError.notAuthenticated
        }
        let docId = "\(uid)_\(spaceId)"
        let doc = try await db.collection("entitlements").document(docId).getDocument()
        guard doc.exists, let raw = doc.data() else { return }
        if let entitlement = decodeEntitlement(raw, userId: uid, spaceId: spaceId) {
            entitlementsBySpace[spaceId] = entitlement
        }
    }

    // MARK: - Real-Time Listener

    /// Starts a real-time entitlement listener.
    /// Updates `entitlementsBySpace[spaceId]` on every Firestore snapshot.
    func startListening(userId: String, spaceId: String) {
        guard !userId.isEmpty, !spaceId.isEmpty else { return }
        stopListening(spaceId: spaceId)

        let docId = "\(userId)_\(spaceId)"
        let ref = db.collection("entitlements").document(docId)

        let task = Task { [weak self] in
            let stream = AsyncStream<SpaceEntitlement?> { continuation in
                let listener = ref.addSnapshotListener { [weak self] snapshot, _ in
                    guard let self else { return }
                    guard let snapshot, snapshot.exists, let data = snapshot.data() else {
                        continuation.yield(nil)
                        return
                    }
                    let entitlement = self.decodeEntitlement(data, userId: userId, spaceId: spaceId)
                    continuation.yield(entitlement)
                }
                continuation.onTermination = { _ in
                    listener.remove()
                }
            }

            for await entitlement in stream {
                guard !Task.isCancelled else { break }
                await MainActor.run { [weak self] in
                    if let entitlement {
                        self?.entitlementsBySpace[spaceId] = entitlement
                    } else {
                        self?.entitlementsBySpace.removeValue(forKey: spaceId)
                    }
                }
            }
        }

        listenerTasks[spaceId] = task
    }

    /// Stops the real-time listener for the given space.
    func stopListening(spaceId: String) {
        listenerTasks[spaceId]?.cancel()
        listenerTasks.removeValue(forKey: spaceId)
    }

    // MARK: - ASWebAuthenticationSession

    private func presentCheckoutSession(url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "amen"
            ) { [weak self] _, error in
                guard self != nil else { continuation.resume(); return }
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: SpacesEntitlementError.checkoutCanceled)
                    return
                }
                if let error {
                    continuation.resume(throwing: SpacesEntitlementError.network(error))
                    return
                }
                // Entitlement written by webhook CF — no client write needed.
                continuation.resume()
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }
    }

    // MARK: - Decode Helper

    private func decodeEntitlement(
        _ data: [String: Any],
        userId: String,
        spaceId: String
    ) -> SpaceEntitlement? {
        guard
            let statusRaw = data["status"] as? String,
            let status = SpaceEntitlement.EntitlementStatus(rawValue: statusRaw),
            let sourceRaw = data["source"] as? String,
            let source = SpaceEntitlement.EntitlementSource(rawValue: sourceRaw),
            let updatedAt = (data["updatedAt"] as? Timestamp)
        else { return nil }

        return SpaceEntitlement(
            userId: userId,
            spaceId: spaceId,
            status: status,
            source: source,
            stripeSubId: data["stripeSubId"] as? String,
            expiresAt: (data["expiresAt"] as? Timestamp),
            updatedAt: updatedAt
        )
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension SpacesEntitlementService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.windows.first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

// MARK: - Notification

extension Notification.Name {
    static let spacesCheckoutSucceeded = Notification.Name("spacesCheckoutSucceeded")
}
