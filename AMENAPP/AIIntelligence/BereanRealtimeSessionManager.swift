import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class BereanRealtimeSessionManager: ObservableObject {
    static let shared = BereanRealtimeSessionManager()

    @Published private(set) var currentSession: BereanRealtimeSession?
    @Published private(set) var isConnecting = false
    @Published var lastError: String?

    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private var listener: ListenerRegistration?

    private init() {}

    func createSession(
        type: BereanRealtimeSessionType,
        sourceLanguage: BereanSupportedLanguage = .english,
        targetLanguages: [BereanSupportedLanguage] = [.english],
        selectedLanguage: BereanSupportedLanguage? = nil,
        churchId: String? = nil,
        sermonId: String? = nil,
        prayerRoomId: String? = nil,
        conversationId: String? = nil
    ) async throws -> BereanRealtimeClientSecret {
        isConnecting = true
        defer { isConnecting = false }

        let callable = functions.httpsCallable("createRealtimeSession")
        let result = try await callable.call([
            "sessionType": type.rawValue,
            "sourceLanguage": sourceLanguage.rawValue,
            "targetLanguages": targetLanguages.map(\.rawValue),
            "selectedLanguage": (selectedLanguage ?? targetLanguages.first ?? sourceLanguage).rawValue,
            "churchId": churchId ?? "",
            "sermonId": sermonId ?? "",
            "prayerRoomId": prayerRoomId ?? "",
            "conversationId": conversationId ?? "",
        ])

        guard let data = result.data as? [String: Any],
              let sessionId = data["sessionId"] as? String,
              let clientSecret = data["clientSecret"] as? String else {
            throw BereanRealtimeError.invalidBrokerResponse
        }

        let expiresAtMs = data["expiresAtMs"] as? Double ?? Date().addingTimeInterval(60).timeIntervalSince1970 * 1000
        let secret = BereanRealtimeClientSecret(
            sessionId: sessionId,
            value: clientSecret,
            expiresAt: Date(timeIntervalSince1970: expiresAtMs / 1000),
            providerSessionId: data["providerSessionId"] as? String,
            model: data["model"] as? String
        )

        listen(to: sessionId)
        return secret
    }

    func markActive(sessionId: String) async {
        do {
            try await db.collection("realtimeSessions").document(sessionId).updateData([
                "status": BereanRealtimeSessionStatus.active.rawValue,
                "updatedAt": FieldValue.serverTimestamp(),
            ])
        } catch {
            lastError = error.localizedDescription
        }
    }

    func pause(sessionId: String) async {
        await updateStatus(.paused, sessionId: sessionId)
    }

    func resume(sessionId: String) async {
        await updateStatus(.active, sessionId: sessionId)
    }

    func endCurrentSession() async {
        guard let sessionId = currentSession?.id else { return }
        do {
            _ = try await functions.httpsCallable("endRealtimeSession").call(["sessionId": sessionId])
        } catch {
            lastError = error.localizedDescription
        }
        listener?.remove()
        listener = nil
        currentSession = nil
    }

    func listen(to sessionId: String) {
        listener?.remove()
        listener = db.collection("realtimeSessions").document(sessionId).addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                if let error {
                    self?.lastError = error.localizedDescription
                    return
                }
                guard let snapshot, let data = snapshot.data() else { return }
                self?.currentSession = Self.decodeSession(id: snapshot.documentID, data: data)
            }
        }
    }

    private func updateStatus(_ status: BereanRealtimeSessionStatus, sessionId: String) async {
        do {
            try await db.collection("realtimeSessions").document(sessionId).updateData([
                "status": status.rawValue,
                "updatedAt": FieldValue.serverTimestamp(),
            ])
        } catch {
            lastError = error.localizedDescription
        }
    }

    private static func decodeSession(id: String, data: [String: Any]) -> BereanRealtimeSession {
        let type = BereanRealtimeSessionType(rawValue: data["sessionType"] as? String ?? "voice_assistant") ?? .voiceAssistant
        let status = BereanRealtimeSessionStatus(rawValue: data["status"] as? String ?? "initializing") ?? .initializing
        let source = BereanSupportedLanguage(rawValue: data["sourceLanguage"] as? String ?? "en") ?? .english
        let selected = BereanSupportedLanguage(rawValue: data["selectedLanguage"] as? String ?? source.rawValue) ?? source
        let targets = (data["targetLanguages"] as? [String] ?? [source.rawValue]).compactMap(BereanSupportedLanguage.init(rawValue:))
        let provider = data["provider"] as? [String: Any]

        return BereanRealtimeSession(
            id: id,
            ownerId: data["ownerId"] as? String ?? "",
            sessionType: type,
            status: status,
            sourceLanguage: source,
            targetLanguages: targets.isEmpty ? [source] : targets,
            selectedLanguage: selected,
            providerSessionId: provider?["sessionId"] as? String,
            model: provider?["model"] as? String,
            expiresAt: (data["expiresAt"] as? Timestamp)?.dateValue()
        )
    }
}

enum BereanRealtimeError: LocalizedError {
    case invalidBrokerResponse

    var errorDescription: String? {
        switch self {
        case .invalidBrokerResponse:
            return "Realtime session broker returned an invalid response."
        }
    }
}
