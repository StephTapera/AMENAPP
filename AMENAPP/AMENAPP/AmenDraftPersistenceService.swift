import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

// Local-first draft persistence with Firestore cross-device sync.
// Local UserDefaults write is synchronous; Firestore push/pull is async background.
@MainActor
final class AmenDraftPersistenceService: ObservableObject {
    static let shared = AmenDraftPersistenceService()

    private let defaults = UserDefaults.standard
    private let db = Firestore.firestore()
    private let keyPrefix = "amen_draft_"

    /// Set when a syncDown fetch fails — the UI can observe this to show a recovery prompt.
    @Published var syncError: Error?

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
        do {
            let snap = try await db
                .collection("users").document(uid)
                .collection("drafts").document(key)
                .getDocument()
            guard snap.exists, let remote = snap.data()?["text"] as? String else { return nil }
            syncError = nil
            defaults.set(remote, forKey: keyPrefix + key)
            return remote
        } catch {
            print("[DraftSync] syncDown failed for key '\(key)': \(error.localizedDescription)")
            syncError = error
            return nil
        }
    }

    // MARK: - Private Sync

    private func syncUp(key: String, text: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db
                .collection("users").document(uid)
                .collection("drafts").document(key)
                .setData(["text": text, "updatedAt": FieldValue.serverTimestamp()], merge: true)
        } catch {
            // Background sync — don't surface to user, but log for diagnostics.
            print("[DraftSync] syncUp failed for key '\(key)': \(error.localizedDescription)")
        }
    }

    private func syncDelete(key: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db
                .collection("users").document(uid)
                .collection("drafts").document(key)
                .delete()
        } catch {
            // Background delete — log but don't crash or surface to user.
            print("[DraftSync] syncDelete failed for key '\(key)': \(error.localizedDescription)")
        }
    }
}
