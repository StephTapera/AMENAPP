// SpacesEntitlementModels.swift
// AMENAPP — Spaces v2 Entitlement Layer (Agent A)
//
// Entitlement model and live-observation service for Space access control.
// All paid-space access decisions funnel through EntitlementService.shared.
// Firestore path: entitlements/{userId}_{spaceId}

import Foundation
import Combine
import FirebaseFirestore

// MARK: - Entitlement Status

enum EntitlementStatus: String, Codable {
    case active  = "active"
    case grace   = "grace"
    case expired = "expired"
}

// MARK: - Entitlement Source

enum EntitlementSource: String, Codable {
    case purchase = "purchase"
    case grant    = "grant"
}

// MARK: - Space Entitlement (v1 — manually decoded, used only by EntitlementService)

struct SpaceEntitlementV1: Codable, Identifiable, Equatable {
    var id: String { "\(userId)_\(spaceId)" }
    var userId: String
    var spaceId: String
    var status: EntitlementStatus
    var source: EntitlementSource
    var stripeSubId: String?
    var expiresAt: Date?
    var updatedAt: Date
}

// MARK: - Entitlement Service

@MainActor
final class EntitlementService: ObservableObject {

    static let shared = EntitlementService()

    private let db = Firestore.firestore()
    private var listeners: [String: ListenerRegistration] = [:]

    private init() {}

    // Reads the entitlement document once; returns nil if the doc does not exist.
    func fetchEntitlement(userId: String, spaceId: String) async throws -> SpaceEntitlementV1? {
        let docId = "\(userId)_\(spaceId)"
        let snapshot = try await db.collection("entitlements").document(docId).getDocument()
        guard snapshot.exists, let data = snapshot.data() else { return nil }
        return decode(data: data, userId: userId, spaceId: spaceId)
    }

    // Returns an AsyncStream that emits on each Firestore snapshot update.
    // The stream emits nil when the document does not exist.
    func observeEntitlement(userId: String, spaceId: String) -> AsyncStream<SpaceEntitlementV1?> {
        let docId = "\(userId)_\(spaceId)"
        let ref = db.collection("entitlements").document(docId)

        return AsyncStream { continuation in
            let listener = ref.addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                guard let snapshot, snapshot.exists, let data = snapshot.data() else {
                    continuation.yield(nil)
                    return
                }
                let entitlement = self.decode(data: data, userId: userId, spaceId: spaceId)
                continuation.yield(entitlement)
            }

            // Retain the listener keyed by docId; cancel it when the stream terminates.
            Task { @MainActor in
                self.listeners[docId] = listener
            }

            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.listeners[docId]?.remove()
                    self?.listeners[docId] = nil
                }
            }
        }
    }

    // Decodes raw Firestore data into SpaceEntitlementV1 without force-unwrapping.
    private func decode(data: [String: Any], userId: String, spaceId: String) -> SpaceEntitlementV1? {
        guard
            let statusRaw = data["status"] as? String,
            let status = EntitlementStatus(rawValue: statusRaw),
            let sourceRaw = data["source"] as? String,
            let source = EntitlementSource(rawValue: sourceRaw),
            let updatedAtTimestamp = data["updatedAt"] as? Timestamp
        else { return nil }

        let stripeSubId = data["stripeSubId"] as? String
        let expiresAt = (data["expiresAt"] as? Timestamp)?.dateValue()

        return SpaceEntitlementV1(
            userId: userId,
            spaceId: spaceId,
            status: status,
            source: source,
            stripeSubId: stripeSubId,
            expiresAt: expiresAt,
            updatedAt: updatedAtTimestamp.dateValue()
        )
    }
}
