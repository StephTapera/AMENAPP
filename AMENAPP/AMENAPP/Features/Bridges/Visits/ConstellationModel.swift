import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - ConstellationRelationship

/// Church relationship type for the user's constellation model.
/// Signal weights reflect engagement depth for context scoring.
/// Migration: existing saves are assigned .exploring on first open.
enum ConstellationRelationship: String, Codable, CaseIterable, Sendable {
    case primary    // main home church
    case visiting   // currently attending but not yet joined
    case family     // family member attends
    case exploring  // viewed/saved, considering
    case former     // previously attended

    /// Weight used when this relationship contributes to a ContextSignal payload.
    /// primary=1.0, visiting=0.6, family=0.4, exploring=0.3, former=0.1
    var signalWeight: Double {
        switch self {
        case .primary:   return 1.0
        case .visiting:  return 0.6
        case .family:    return 0.4
        case .exploring: return 0.3
        case .former:    return 0.1
        }
    }
}

// MARK: - ChurchConstellation

struct ChurchConstellation: Codable, Identifiable, Sendable {
    let id: String          // churchID
    var relationship: ConstellationRelationship
    var labeledAt: Date
}

// MARK: - ConstellationService

/// Actor-isolated service for reading and writing church relationship labels.
/// Writes flow to Firestore collection: constellation/{uid}/churches/{churchID}
/// A lightweight in-memory cache avoids redundant Firestore reads per session.
actor ConstellationService {
    static let shared = ConstellationService()

    private var cache: [String: ChurchConstellation] = [:]

    // MARK: - Read

    func relationship(for churchID: String) async -> ConstellationRelationship {
        if let cached = cache[churchID] { return cached.relationship }
        guard let uid = Auth.auth().currentUser?.uid else { return .exploring }
        let db = Firestore.firestore()
        let doc = try? await db
            .collection("constellation").document(uid)
            .collection("churches").document(churchID)
            .getDocument()
        if let data = doc?.data(),
           let relRaw = data["relationship"] as? String,
           let rel = ConstellationRelationship(rawValue: relRaw) {
            let labeledAt = (data["labeledAt"] as? Timestamp)?.dateValue() ?? Date()
            let entry = ChurchConstellation(id: churchID, relationship: rel, labeledAt: labeledAt)
            cache[churchID] = entry
            return rel
        }
        return .exploring
    }

    // MARK: - Write

    func setRelationship(_ rel: ConstellationRelationship, for churchID: String) async {
        let entry = ChurchConstellation(id: churchID, relationship: rel, labeledAt: Date())
        cache[churchID] = entry
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        try? await db
            .collection("constellation").document(uid)
            .collection("churches").document(churchID)
            .setData([
                "relationship": rel.rawValue,
                "labeledAt": FieldValue.serverTimestamp()
            ])
    }

    // MARK: - Migration

    /// One-time migration: assign .exploring to any church IDs that have no label yet.
    /// Already-labeled churches are skipped; idempotent.
    func migrateExistingSaves(churchIDs: [String]) async {
        for id in churchIDs {
            // Only write if there is no cached entry and no Firestore record
            if cache[id] != nil { continue }
            let existing = await relationship(for: id)
            // relationship(for:) populates cache from Firestore if present.
            // If still .exploring it means no record existed — the default is correct,
            // but we explicitly persist it so it shows up in the constellation doc.
            if existing == .exploring {
                await setRelationship(.exploring, for: id)
            }
        }
    }
}
