//
//  HeyFeedNLPreferencesService.swift
//  AMENAPP
//
//  Manages duration-aware natural-language feed preferences.
//  These layer on top of the existing global HeyFeedPreferences for
//  temporary, expiring controls created via the Hey Feed NL input.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class HeyFeedNLPreferencesService: ObservableObject {

    static let shared = HeyFeedNLPreferencesService()
    private init() {}

    // MARK: - State

    @Published private(set) var activePreferences: [HeyFeedNLPreference] = []
    @Published private(set) var isLoading = false

    private lazy var db = Firestore.firestore()
    private var listener: ListenerRegistration?

    // MARK: - Lifecycle

    func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        stopListening()
        listener = db
            .collection("users").document(uid)
            .collection("feedNLPreferences")
            .whereField("isActive", isEqualTo: true)
            .order(by: "createdAt", descending: true)
            .limit(to: 30)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let docs = snap?.documents else { return }
                var prefs = docs.compactMap { try? $0.data(as: HeyFeedNLPreference.self) }
                // Filter out expired ones
                prefs = prefs.filter { !$0.isExpired }
                self.activePreferences = prefs
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: - Write

    func applyIntent(_ intent: HeyFeedParsedIntent, source: String = "nl_input") async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let batch = db.batch()

        for target in intent.targets {
            let prefId = "\(uid)_\(target.id)_\(Int(Date().timeIntervalSince1970))"
            let ref = db.collection("users").document(uid)
                .collection("feedNLPreferences").document(prefId)

            let pref = HeyFeedNLPreference(
                id: prefId,
                action: intent.action,
                targetId: target.id,
                targetLabel: target.label,
                targetType: target.type,
                strength: intent.strength * target.confidence,
                duration: intent.duration,
                source: source,
                isActive: true,
                isPaused: false,
                createdAt: Date(),
                expiresAt: intent.duration.expiryDate
            )

            if let encoded = try? Firestore.Encoder().encode(pref) {
                batch.setData(encoded, forDocument: ref)
            }
        }

        try await batch.commit()
    }

    func pausePreference(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db.collection("users").document(uid)
            .collection("feedNLPreferences").document(id)
            .updateData(["isPaused": true])
    }

    func resumePreference(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db.collection("users").document(uid)
            .collection("feedNLPreferences").document(id)
            .updateData(["isPaused": false])
    }

    func removePreference(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db.collection("users").document(uid)
            .collection("feedNLPreferences").document(id)
            .updateData(["isActive": false])
        activePreferences.removeAll { $0.id == id }
    }

    func removeAll() async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let batch = db.batch()
        for pref in activePreferences {
            let ref = db.collection("users").document(uid)
                .collection("feedNLPreferences").document(pref.id)
            batch.updateData(["isActive": false], forDocument: ref)
        }
        try await batch.commit()
        activePreferences = []
    }

    // MARK: - Ranking Integration

    /// Returns net ranking delta for a given taxonomy key from all active NL preferences.
    func rankingDelta(for key: String) -> Double {
        let matching = activePreferences.filter { $0.targetId == key && !$0.isExpired && !$0.isPaused }
        guard !matching.isEmpty else { return 0 }
        // Sum deltas, capped at ±0.35
        let total = matching.map(\.rankingDelta).reduce(0, +)
        return max(-0.35, min(0.35, total))
    }

    /// Prune expired preferences (called periodically or on app foreground).
    func pruneExpired() async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let expired = activePreferences.filter(\.isExpired)
        guard !expired.isEmpty else { return }
        let batch = db.batch()
        for pref in expired {
            let ref = db.collection("users").document(uid)
                .collection("feedNLPreferences").document(pref.id)
            batch.updateData(["isActive": false], forDocument: ref)
        }
        try await batch.commit()
        activePreferences.removeAll(where: \.isExpired)
    }
}
