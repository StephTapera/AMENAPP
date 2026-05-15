import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFirestoreSwift

@MainActor
final class SavedMomentsService: ObservableObject {
    static let shared = SavedMomentsService()

    @Published private(set) var savedMoments: [SavedMoment] = []

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var authListener: AuthStateDidChangeListenerHandle?

    private init() {
        loadCachedMoments(for: Auth.auth().currentUser?.uid)
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.handleAuthStateChange(userID: user?.uid)
            }
        }
        handleAuthStateChange(userID: Auth.auth().currentUser?.uid)
    }

    deinit {
        listener?.remove()
        if let authListener {
            Auth.auth().removeStateDidChangeListener(authListener)
        }
    }

    func save(_ moment: SavedMoment) {
        guard !savedMoments.contains(moment) else { return }
        savedMoments.insert(moment, at: 0)
        persistCache()

        Task {
            try? await persist(moment)
        }
    }

    func remove(_ moment: SavedMoment) {
        savedMoments.removeAll { $0.id == moment.id }
        persistCache()

        Task {
            try? await removeRemote(momentID: moment.id)
        }
    }

    func removeMatching(anchor: MediaMomentAnchor) {
        let removedIDs = savedMoments
            .filter {
                $0.postId == anchor.postId &&
                $0.mediaId == anchor.mediaId &&
                $0.timestamp == anchor.timestamp &&
                $0.frameIndex == anchor.frameIndex
            }
            .map(\.id)

        savedMoments.removeAll {
            removedIDs.contains($0.id)
        }
        persistCache()

        guard !removedIDs.isEmpty else { return }
        Task {
            for id in removedIDs {
                try? await removeRemote(momentID: id)
            }
        }
    }

    func isSaved(anchor: MediaMomentAnchor) -> Bool {
        savedMoments.contains {
            $0.postId == anchor.postId &&
            $0.mediaId == anchor.mediaId &&
            $0.timestamp == anchor.timestamp &&
            $0.frameIndex == anchor.frameIndex
        }
    }

    private func handleAuthStateChange(userID: String?) {
        listener?.remove()
        listener = nil

        loadCachedMoments(for: userID)

        guard let userID else { return }
        listener = collection(for: userID)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let snapshot else { return }
                let remoteMoments = snapshot.documents.compactMap { try? $0.data(as: SavedMoment.self) }
                Task { @MainActor in
                    self.savedMoments = remoteMoments
                    self.persistCache()
                }
            }
    }

    private func persist(_ moment: SavedMoment) async throws {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        try collection(for: userID).document(moment.id).setData(from: moment)
    }

    private func removeRemote(momentID: String) async throws {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        try await collection(for: userID).document(momentID).delete()
    }

    private func collection(for userID: String) -> CollectionReference {
        db.collection("users").document(userID).collection("savedMoments")
    }

    private func cacheKey(for userID: String?) -> String {
        "amen_saved_media_moments_\(userID ?? "anonymous")"
    }

    private func loadCachedMoments(for userID: String?) {
        let key = cacheKey(for: userID)
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedMoment].self, from: data) else {
            savedMoments = []
            return
        }
        savedMoments = decoded
    }

    private func persistCache() {
        let key = cacheKey(for: Auth.auth().currentUser?.uid)
        guard let data = try? JSONEncoder().encode(savedMoments) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
