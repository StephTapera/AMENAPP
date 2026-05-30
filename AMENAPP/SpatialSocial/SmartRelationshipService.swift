import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// Manages typed social relationships and intelligent introductions.
// Unlike generic "friend" models, every relationship has context and type.
@MainActor
final class SmartRelationshipService: ObservableObject {
    static let shared = SmartRelationshipService()

    @Published private(set) var relationships: [SocialRelationship] = []
    @Published private(set) var pendingIntroductions: [SmartIntroduction] = []
    @Published private(set) var isLoading = false

    private lazy var db = Firestore.firestore()
    private let functions = Functions.functions(region: "us-central1")

    private init() {}

    func loadRelationships() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let snap = try await db.collection("social_relationships")
                .whereField("uid", isEqualTo: uid)
                .limit(to: 50)
                .getDocuments()
            relationships = snap.documents.compactMap {
                try? Firestore.Decoder().decode(SocialRelationship.self, from: $0.data())
            }
        } catch {
            print("[ERROR] SmartRelationshipService.loadRelationships: \(error)")
        }
    }

    func proposeRelationship(targetUID: String, type: SpatialRelationshipType, context: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let id = UUID().uuidString
        let relationship = SocialRelationship(
            id: id,
            uid: uid,
            targetUID: targetUID,
            type: type,
            commonContexts: [context],
            mutualScore: 0.0,
            createdAt: Date(),
            isConfirmed: false
        )
        let data = try Firestore.Encoder().encode(relationship)
        try await db.collection("social_relationships").document(id).setData(data)
        relationships.append(relationship)
    }

    func confirmRelationship(id: String) async throws {
        try await db.collection("social_relationships").document(id)
            .updateData(["isConfirmed": true])
        if let idx = relationships.firstIndex(where: { $0.id == id }) {
            relationships[idx] = SocialRelationship(
                id: relationships[idx].id,
                uid: relationships[idx].uid,
                targetUID: relationships[idx].targetUID,
                type: relationships[idx].type,
                commonContexts: relationships[idx].commonContexts,
                mutualScore: relationships[idx].mutualScore,
                createdAt: relationships[idx].createdAt,
                isConfirmed: true
            )
        }
    }

    // Smart introductions: finds people with shared context, events, or goals
    func fetchSmartIntroductions(context: PostingContext, broadArea: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let result = try await functions.httpsCallable("getSmartIntroductions").call([
                "uid": uid,
                "context": context.rawValue,
                "broadArea": broadArea,
                "limit": 5
            ])
            guard let data = result.data as? [String: Any],
                  let rows = data["introductions"] as? [[String: Any]] else { return }

            pendingIntroductions = rows.compactMap { row in
                guard let id = row["id"] as? String,
                      let targetUID = row["targetUID"] as? String,
                      let displayName = row["displayName"] as? String,
                      let reason = row["reason"] as? String,
                      let typeString = row["relationshipType"] as? String,
                      let relType = SpatialRelationshipType(rawValue: typeString) else { return nil }
                return SmartIntroduction(
                    id: id,
                    targetUID: targetUID,
                    targetDisplayName: displayName,
                    targetPhotoURL: row["photoURL"] as? String,
                    commonContexts: row["commonContexts"] as? [String] ?? [],
                    suggestedRelationshipType: relType,
                    introductionReason: reason,
                    overlapScore: row["overlapScore"] as? Double ?? 0.5,
                    isAnonymized: false
                )
            }
        } catch {
            pendingIntroductions = []
        }
    }

    func dismissIntroduction(id: String) {
        pendingIntroductions.removeAll { $0.id == id }
    }

    func relationships(ofType type: SpatialRelationshipType) -> [SocialRelationship] {
        relationships.filter { $0.type == type && $0.isConfirmed }
    }
}
