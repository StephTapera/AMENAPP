import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions
import SwiftUI

// MARK: - CalmControlService
// Firestore paths:
//   privacySettings   → users/{uid}/privacySettings/main
//   feedControls      → users/{uid}/feedControls/main
//   presence          → users/{uid}/presence/main
//   notificationSettings → users/{uid}/notificationSettings/main
//   audienceLayers    → users/{uid}/audienceLayers/{layerId}

@MainActor
final class CalmControlService: ObservableObject {

    static let shared = CalmControlService()

    @Published var privacySettings = AmenPrivacySettings()
    @Published var feedControls = AmenFeedControls()
    @Published var presence = AmenPresenceSettings()
    @Published var notificationSettings = AmenNotificationSettings()
    @Published var audienceLayers: [AmenAudienceLayer] = []
    @Published var isLoading = false
    @Published var error: Error?

    private let db = Firestore.firestore()
    private var uid: String? { Auth.auth().currentUser?.uid }

    private var privacyListener: ListenerRegistration?
    private var feedListener: ListenerRegistration?
    private var presenceListener: ListenerRegistration?
    private var notifListener: ListenerRegistration?
    private var layersListener: ListenerRegistration?

    private init() {}

    deinit {
        stopListening()
    }

    // MARK: - Start / Stop Listening

    func startListening() {
        guard let uid else { return }
        isLoading = true

        privacyListener = db.collection("users").document(uid)
            .collection("privacySettings").document("main")
            .addSnapshotListener { [weak self] snap, _ in
                guard let self else { return }
                self.isLoading = false
                if let data = snap?.data(),
                   let decoded = try? Firestore.Decoder().decode(AmenPrivacySettings.self, from: data) {
                    self.privacySettings = decoded
                }
            }

        feedListener = db.collection("users").document(uid)
            .collection("feedControls").document("main")
            .addSnapshotListener { [weak self] snap, _ in
                guard let self else { return }
                if let data = snap?.data(),
                   let decoded = try? Firestore.Decoder().decode(AmenFeedControls.self, from: data) {
                    self.feedControls = decoded
                }
            }

        presenceListener = db.collection("users").document(uid)
            .collection("presence").document("main")
            .addSnapshotListener { [weak self] snap, _ in
                guard let self else { return }
                if let data = snap?.data(),
                   let decoded = try? Firestore.Decoder().decode(AmenPresenceSettings.self, from: data) {
                    self.presence = decoded
                }
            }

        notifListener = db.collection("users").document(uid)
            .collection("notificationSettings").document("main")
            .addSnapshotListener { [weak self] snap, _ in
                guard let self else { return }
                if let data = snap?.data(),
                   let decoded = try? Firestore.Decoder().decode(AmenNotificationSettings.self, from: data) {
                    self.notificationSettings = decoded
                }
            }
    }

    func startListeningToLayers() {
        guard let uid else { return }
        layersListener = db.collection("users").document(uid)
            .collection("audienceLayers")
            .addSnapshotListener { [weak self] snap, _ in
                guard let self else { return }
                self.audienceLayers = (snap?.documents ?? [])
                    .compactMap { try? $0.data(as: AmenAudienceLayer.self) }
            }
    }

    func stopListening() {
        privacyListener?.remove(); privacyListener = nil
        feedListener?.remove(); feedListener = nil
        presenceListener?.remove(); presenceListener = nil
        notifListener?.remove(); notifListener = nil
        layersListener?.remove(); layersListener = nil
    }

    // MARK: - Privacy Settings

    func savePrivacySettings() async {
        do {
            _ = try await Functions.functions()
                .httpsCallable("updatePrivacySettings").call(encode(privacySettings))
        } catch { self.error = error }
    }

    // MARK: - Feed Controls

    func saveFeedControls() async {
        do {
            _ = try await Functions.functions()
                .httpsCallable("updateFeedControls").call(encode(feedControls))
        } catch { self.error = error }
    }

    // MARK: - Presence

    func updatePresence(_ state: AmenCalmPresenceState) async {
        guard let uid else { return }
        presence.state = state
        do {
            try await db.collection("users").document(uid)
                .collection("presence").document("main")
                .setData(["state": state.rawValue, "updatedAt": FieldValue.serverTimestamp()], merge: true)
        } catch { self.error = error }
    }

    // MARK: - Notification Settings

    func saveNotificationSettings() async {
        do {
            _ = try await Functions.functions()
                .httpsCallable("updateNotificationSettings").call(encode(notificationSettings))
        } catch { self.error = error }
    }

    func toggleNotificationCategory(_ category: AmenRhythmNotificationCategory, enabled: Bool) async {
        notificationSettings.enabledCategories[category] = enabled
        await saveNotificationSettings()
    }

    // MARK: - Audience Layers

    func createAudienceLayer(name: String) async {
        guard let uid else { return }
        do {
            _ = try await Functions.functions()
                .httpsCallable("createAudienceLayer").call(["name": name, "uid": uid])
        } catch { self.error = error }
    }

    func deleteAudienceLayer(_ layerId: String) async {
        do {
            _ = try await Functions.functions()
                .httpsCallable("deleteAudienceLayer").call(["layerId": layerId])
        } catch { self.error = error }
    }

    // MARK: - Helpers

    private func encode<T: Encodable>(_ value: T) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(value),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return dict
    }
}
