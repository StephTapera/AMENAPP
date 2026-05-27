// AmenSemanticPinService.swift
// AMEN App — Semantic Pinning System
//
// Extends PostPinningService with spiritual/org/intelligent/dynamic pin types.
// Intelligent pins (server-assigned) are read-only from client.
// User pins (spiritual/org) are writable.

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class AmenSemanticPinService: ObservableObject {

    static let shared = AmenSemanticPinService()

    @Published private(set) var spacePin: [AmenSemanticPin] = []
    @Published private(set) var isLoading: Bool = false

    private let db = Firestore.firestore()
    private var userId: String { Auth.auth().currentUser?.uid ?? "" }
    private var listeners: [ListenerRegistration] = []

    private init() {}

    deinit {
        listeners.forEach { $0.remove() }
    }

    // MARK: - Subscribe to Space Pins

    func subscribeToSpacePins(spaceId: String) {
        guard AMENFeatureFlags.shared.semanticPinningEnabled else { return }
        listeners.forEach { $0.remove() }
        listeners.removeAll()

        let listener = db
            .collection("spaces").document(spaceId)
            .collection("pins")
            .order(by: "score", descending: true)
            .limit(to: 30)
            .addSnapshotListener { [weak self] snap, error in
                guard let self, error == nil else { return }
                self.spacePin = snap?.documents.compactMap { try? $0.data(as: AmenSemanticPin.self) } ?? []
            }
        listeners.append(listener)
    }

    // MARK: - Save User Pin

    func savePin(
        spaceId: String,
        threadId: String? = nil,
        messageId: String? = nil,
        pinType: AmenPinType,
        title: String,
        preview: String,
        scriptureRef: String? = nil,
        tags: [String] = []
    ) async throws {
        guard AMENFeatureFlags.shared.semanticPinningEnabled else { return }
        guard !userId.isEmpty else { return }
        guard !pinType.isIntelligent else {
            dlog("[AmenSemanticPinService] Client cannot create intelligent pins.")
            return
        }

        let id = UUID().uuidString
        let now = Date()
        let pin = AmenSemanticPin(
            id: id,
            spaceId: spaceId,
            threadId: threadId,
            messageId: messageId,
            pinnedBy: userId,
            pinType: pinType,
            title: title,
            preview: preview,
            tags: tags,
            scriptureRef: scriptureRef,
            score: 1.0,
            createdAt: now,
            updatedAt: now,
            evolutionHistory: []
        )

        let ref = db.collection("spaces").document(spaceId)
            .collection("pins").document(id)
        try await ref.setData(pin.firestoreData)

        AMENAnalyticsService.shared.track(.custom(
            name: "semantic_pin_created",
            parameters: ["pin_type": pinType.rawValue, "space_id": spaceId]
        ))
    }

    // MARK: - Remove User Pin

    func removePin(pinId: String, spaceId: String) async throws {
        guard AMENFeatureFlags.shared.semanticPinningEnabled else { return }
        guard !userId.isEmpty else { return }

        // Only allow removal of own pins or non-intelligent pins
        if let pin = spacePin.first(where: { $0.id == pinId }) {
            guard pin.pinnedBy == userId || !pin.isServerGenerated else {
                dlog("[AmenSemanticPinService] Cannot remove server-generated pin.")
                return
            }
        }

        try await db.collection("spaces").document(spaceId)
            .collection("pins").document(pinId)
            .delete()
    }

    // MARK: - Pin Accessors

    func pins(of type: AmenPinType, spaceId: String) -> [AmenSemanticPin] {
        spacePin.filter { $0.pinType == type && $0.spaceId == spaceId }
    }

    func intelligentPins(spaceId: String) -> [AmenSemanticPin] {
        spacePin.filter { $0.isServerGenerated && $0.spaceId == spaceId }
    }

    var prayerPins: [AmenSemanticPin] {
        spacePin.filter { $0.pinType == .prayer }
    }

    var scripturePins: [AmenSemanticPin] {
        spacePin.filter { $0.pinType == .scripture }
    }

    var unresolvedPins: [AmenSemanticPin] {
        spacePin.filter { $0.pinType == .unresolved || $0.pinType == .requiresFollowUp }
    }
}

// MARK: - Firestore Serialization

private extension AmenSemanticPin {
    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "id": id,
            "spaceId": spaceId,
            "pinnedBy": pinnedBy,
            "pinType": pinType.rawValue,
            "title": title,
            "preview": preview,
            "tags": tags,
            "score": score,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt),
            "evolutionHistory": []
        ]
        if let tid = threadId { data["threadId"] = tid }
        if let mid = messageId { data["messageId"] = mid }
        if let ref = scriptureRef { data["scriptureRef"] = ref }
        return data
    }
}
