import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// P1-Phase-F: Saved Communities client-side service.
//
// The savedCommunities path is owner-isolated and callable-only at the rules
// layer. iOS goes through `setCommunitySaved` to write and reads
// users/{uid}/savedCommunities directly (rules allow owner read).

enum SavedCommunityType: String, Codable {
    case covenant
    case hub
    case ark
}

struct SavedCommunityRecord: Identifiable, Equatable {
    let communityKey: String
    let communityId: String
    let communityType: SavedCommunityType
    let titleSnapshot: String?
    let avatarUrlSnapshot: String?
    let visibilitySnapshot: String?
    let savedAt: Date?

    var id: String { communityKey }
}

@MainActor
final class SavedCommunitiesService: ObservableObject {
    static let shared = SavedCommunitiesService()

    @Published private(set) var savedKeys: Set<String> = []
    @Published private(set) var saved: [SavedCommunityRecord] = []

    private let functions = Functions.functions()
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private func key(for type: SavedCommunityType, id: String) -> String {
        "\(type.rawValue)_\(id)"
    }

    func isSaved(type: SavedCommunityType, id: String) -> Bool {
        savedKeys.contains(key(for: type, id: id))
    }

    /// Server-authoritative save toggle. Returns the resulting saved state.
    @discardableResult
    func setSaved(type: SavedCommunityType, id: String, saved: Bool) async throws -> Bool {
        let payload: [String: Any] = [
            "communityType": type.rawValue,
            "communityId": id,
            "saved": saved,
        ]
        let result = try await functions
            .httpsCallable("setCommunitySaved")
            .call(payload)
        let data = result.data as? [String: Any] ?? [:]
        let serverSaved = (data["saved"] as? Bool) ?? saved
        let communityKey = (data["communityKey"] as? String) ?? key(for: type, id: id)
        if serverSaved {
            savedKeys.insert(communityKey)
            CommunitiesAnalytics.communitySaved(type: type.rawValue)
        } else {
            savedKeys.remove(communityKey)
            CommunitiesAnalytics.communityUnsaved(type: type.rawValue)
        }
        return serverSaved
    }

    /// Owner-isolated read of users/{uid}/savedCommunities. Idempotent —
    /// re-entrant callers reuse the active listener.
    func startListening() {
        guard listener == nil, let uid = Auth.auth().currentUser?.uid else { return }
        listener = db.collection("users").document(uid)
            .collection("savedCommunities")
            .addSnapshotListener { [weak self] snap, _ in
                guard let self else { return }
                let docs = snap?.documents ?? []
                let records: [SavedCommunityRecord] = docs.compactMap { d in
                    let data = d.data()
                    guard
                        let typeRaw = data["communityType"] as? String,
                        let type = SavedCommunityType(rawValue: typeRaw),
                        let cid = data["communityId"] as? String
                    else { return nil }
                    let savedAt = (data["savedAt"] as? Timestamp)?.dateValue()
                    return SavedCommunityRecord(
                        communityKey: d.documentID,
                        communityId: cid,
                        communityType: type,
                        titleSnapshot: data["titleSnapshot"] as? String,
                        avatarUrlSnapshot: data["avatarUrlSnapshot"] as? String,
                        visibilitySnapshot: data["visibilitySnapshot"] as? String,
                        savedAt: savedAt
                    )
                }
                Task { @MainActor in
                    self.saved = records.sorted { (a, b) in
                        (a.savedAt ?? .distantPast) > (b.savedAt ?? .distantPast)
                    }
                    self.savedKeys = Set(records.map { $0.communityKey })
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }
}
