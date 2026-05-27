import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class CompanionPrivacyManager: ObservableObject {
    static let shared = CompanionPrivacyManager()

    @Published private(set) var preferences: CompanionPrivacyPreferences = .default
    @Published private(set) var isLoading = false

    private lazy var db = Firestore.firestore()

    private init() {}

    func load() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let snap = try await db.collection("users").document(uid)
                .collection("companion_privacy").document("main").getDocument()
            guard let data = snap.data() else { return }
            preferences = try Firestore.Decoder().decode(CompanionPrivacyPreferences.self, from: data)
        } catch {}
    }

    func update(_ updated: CompanionPrivacyPreferences) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let data = try Firestore.Encoder().encode(updated)
        try await db.collection("users").document(uid)
            .collection("companion_privacy").document("main")
            .setData(data, merge: true)
        preferences = updated
    }

    func setLocationSharing(_ enabled: Bool) async throws {
        var updated = preferences
        updated.locationSharingEnabled = enabled
        try await update(updated)
    }

    func setSafeConnection(_ enabled: Bool) async throws {
        var updated = preferences
        updated.safeConnectionEnabled = enabled
        try await update(updated)
    }

    func setNewAreaDetection(_ enabled: Bool) async throws {
        var updated = preferences
        updated.newAreaDetectionEnabled = enabled
        try await update(updated)
    }

    // Whether companion features can run at all
    var companionActive: Bool {
        preferences.locationSharingEnabled && preferences.churchDiscoveryEnabled
    }
}
