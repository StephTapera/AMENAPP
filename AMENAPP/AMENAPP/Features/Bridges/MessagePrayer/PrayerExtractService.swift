import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Creates a PrayerRequest from a message suggestion and emits the appropriate signal.
actor PrayerExtractService {
    static let shared = PrayerExtractService()

    func createPrayer(from suggestion: PrayerSuggestion) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()

        // Tier-S prayers stay device-local (write to local DB, not Firestore)
        if suggestion.tierCeiling == .s {
            // On-device only: save to UserDefaults with a prayers key
            savePrayerLocally(suggestion)
        } else {
            let prayerRef = db.collection("prayerRequests").document(uid).collection("prayers").document()
            try await prayerRef.setData([
                "title": suggestion.suggestedTitle,
                "excerpt": suggestion.excerpt,
                "sourceThreadID": suggestion.threadID,
                "sourceSenderName": suggestion.senderName,
                "tierCeiling": suggestion.tierCeiling.rawValue,
                "createdAt": FieldValue.serverTimestamp(),
                "status": "active"
            ])

            // Emit prayerCreated signal
            let signal = ContextSignal(
                id: UUID(),
                type: .prayerCreated,
                tierCeiling: suggestion.tierCeiling,
                subjectRefs: [
                    GraphRef(nodeType: .prayerRequest, nodeID: prayerRef.documentID),
                    GraphRef(nodeType: .person, nodeID: suggestion.senderName)
                ],
                payload: [
                    "source": .string("message"),
                    "senderName": .string(suggestion.senderName)
                ],
                occurredAt: Date(),
                decayHalfLifeDays: 14,
                consentEdgeRequired: .messagesToPrayer
            )
            Task { await ContextBus.shared.emit(signal) }
        }
    }

    private func savePrayerLocally(_ suggestion: PrayerSuggestion) {
        var prayers = (UserDefaults.standard.array(forKey: "local_prayers_tier_s") as? [[String: String]]) ?? []
        prayers.append([
            "title": suggestion.suggestedTitle,
            "excerpt": suggestion.excerpt,
            "createdAt": ISO8601DateFormatter().string(from: Date())
        ])
        UserDefaults.standard.set(prayers, forKey: "local_prayers_tier_s")
    }
}
