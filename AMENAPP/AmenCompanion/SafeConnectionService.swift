import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// Handles privacy-first nearby believer connections.
// Exact location is never shared. Both users must opt in before any connection details are revealed.
@MainActor
final class SafeConnectionService: ObservableObject {
    static let shared = SafeConnectionService()

    @Published private(set) var pendingConnections: [SafeConnection] = []
    @Published private(set) var activeConnections: [SafeConnection] = []
    @Published private(set) var isSearching = false

    private lazy var db = Firestore.firestore()
    private let functions = Functions.functions(region: "us-central1")
    private var listener: ListenerRegistration?

    private init() {}

    // User opts into safe connection discovery for their broad area
    func optInToDiscovery(intent: SafeConnectionIntent, broadArea: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let data: [String: Any] = [
            "uid": uid,
            "intent": intent.rawValue,
            "broadArea": broadArea,
            "optedIn": true,
            "updatedAt": FieldValue.serverTimestamp(),
            "expiresAt": Timestamp(date: Date().addingTimeInterval(24 * 3600))
        ]
        try await db.collection("safe_connection_pool")
            .document(uid)
            .setData(data, merge: true)
    }

    func optOutOfDiscovery() async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db.collection("safe_connection_pool").document(uid).delete()
    }

    // Request mutual connection with another user in the same broad area
    func requestConnection(intent: SafeConnectionIntent, broadArea: String) async throws -> SafeConnection {
        guard let uid = Auth.auth().currentUser?.uid else { throw SafeConnectionError.notAuthenticated }

        let result = try await functions.httpsCallable("requestSafeConnection").call([
            "intent": intent.rawValue,
            "broadArea": broadArea
        ])

        guard let data = result.data as? [String: Any],
              let id = data["connectionId"] as? String else {
            throw SafeConnectionError.noMatchFound
        }

        let connection = SafeConnection(
            id: id,
            initiatorUID: uid,
            receiverUID: nil,
            broadArea: broadArea,
            intent: intent,
            state: .pending,
            initiatorOptedIn: true,
            receiverOptedIn: false,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(48 * 3600)
        )
        pendingConnections.append(connection)
        return connection
    }

    func acceptConnection(connectionId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await functions.httpsCallable("acceptSafeConnection").call([
            "connectionId": connectionId,
            "uid": uid
        ])
        if let idx = pendingConnections.firstIndex(where: { $0.id == connectionId }) {
            var updated = pendingConnections[idx]
            updated = SafeConnection(
                id: updated.id,
                initiatorUID: updated.initiatorUID,
                receiverUID: uid,
                broadArea: updated.broadArea,
                intent: updated.intent,
                state: .active,
                initiatorOptedIn: true,
                receiverOptedIn: true,
                createdAt: updated.createdAt,
                expiresAt: updated.expiresAt
            )
            pendingConnections.remove(at: idx)
            activeConnections.append(updated)
        }
    }

    func declineConnection(connectionId: String) async throws {
        try await functions.httpsCallable("declineSafeConnection").call(["connectionId": connectionId])
        pendingConnections.removeAll { $0.id == connectionId }
    }

    func startListeningForIncoming() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        listener = db.collection("safe_connections")
            .whereField("receiverUID", isEqualTo: uid)
            .whereField("state", isEqualTo: SafeConnectionState.pending.rawValue)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let docs = snap?.documents else { return }
                Task { @MainActor in
                    self.pendingConnections = docs.compactMap {
                        try? Firestore.Decoder().decode(SafeConnection.self, from: $0.data())
                    }
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }
}

enum SafeConnectionError: LocalizedError {
    case notAuthenticated
    case noMatchFound
    case connectionExpired

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Sign in to connect with nearby believers."
        case .noMatchFound:     return "No one nearby opted in right now. Try again later."
        case .connectionExpired: return "This connection request has expired."
        }
    }
}
