import Foundation
import FirebaseAuth
import FirebaseFirestore

// Local-first draft persistence with Firestore cross-device sync.
// Local UserDefaults write is synchronous; Firestore push/pull is async background.
@MainActor
final class AmenDraftPersistenceService {
    static let shared = AmenDraftPersistenceService()

    private let defaults = UserDefaults.standard
    private let db = Firestore.firestore()
    private let keyPrefix = "amen_draft_"

    private init() {}

    // MARK: - Public API

    func save(key: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clear(key: key)
            return
        }
        defaults.set(text, forKey: keyPrefix + key)
        Task { await syncUp(key: key, text: text) }
    }

    func load(key: String) -> String {
        defaults.string(forKey: keyPrefix + key) ?? ""
    }

    func clear(key: String) {
        defaults.removeObject(forKey: keyPrefix + key)
        Task { await syncDelete(key: key) }
    }

    // Call on view appear when local draft is empty — pulls latest from Firestore for cross-device continuity.
    func syncDown(key: String) async -> String? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        guard let snap = try? await db
            .collection("users").document(uid)
            .collection("drafts").document(key)
            .getDocument(),
              snap.exists,
              let remote = snap.data()?["text"] as? String
        else { return nil }
        defaults.set(remote, forKey: keyPrefix + key)
        return remote
    }

    // MARK: - Private Sync

    private func syncUp(key: String, text: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? await db
            .collection("users").document(uid)
            .collection("drafts").document(key)
            .setData(["text": text, "updatedAt": FieldValue.serverTimestamp()], merge: true)
    }

    private func syncDelete(key: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? await db
            .collection("users").document(uid)
            .collection("drafts").document(key)
            .delete()
    }
}
