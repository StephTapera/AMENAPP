import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class BereanLiveTranscriptService: ObservableObject {
    @Published private(set) var captions: [BereanCaptionChunk] = []
    @Published private(set) var scriptures: [BereanScriptureReference] = []

    private let db = Firestore.firestore()
    private var captionListener: ListenerRegistration?
    private var scriptureListener: ListenerRegistration?

    func start(sessionId: String, language: BereanSupportedLanguage) {
        captionListener?.remove()
        scriptureListener?.remove()

        captionListener = db.collection("realtimeSessions")
            .document(sessionId)
            .collection("translationChunks")
            .whereField("targetLanguage", isEqualTo: language.rawValue)
            .order(by: "createdAt", descending: false)
            .limit(toLast: 40)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                Task { @MainActor in
                    self?.captions = docs.map { BereanCaptionChunk(id: $0.documentID, data: $0.data()) }
                }
            }

        scriptureListener = db.collection("realtimeSessions")
            .document(sessionId)
            .collection("scriptureReferences")
            .order(by: "createdAt", descending: false)
            .limit(toLast: 20)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                Task { @MainActor in
                    self?.scriptures = docs.map { BereanScriptureReference(id: $0.documentID, data: $0.data()) }
                }
            }
    }

    func stop() {
        captionListener?.remove()
        scriptureListener?.remove()
        captionListener = nil
        scriptureListener = nil
    }
}

@MainActor
final class BereanTranslationCoordinator: ObservableObject {
    @Published var preferredLanguage: BereanSupportedLanguage = .english
    @Published var captionLanguages: [BereanSupportedLanguage] = [.english]
    @Published var dualLanguageMode = false
    @Published private(set) var lastResult: BereanTranslationResult?

    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    func loadPreferences(userId: String) async {
        do {
            let snapshot = try await db.collection("translationPreferences").document(userId).getDocument()
            guard let data = snapshot.data() else { return }
            preferredLanguage = BereanSupportedLanguage(rawValue: data["preferredLanguage"] as? String ?? "en") ?? .english
            captionLanguages = (data["captionLanguages"] as? [String] ?? [preferredLanguage.rawValue]).compactMap(BereanSupportedLanguage.init(rawValue:))
            dualLanguageMode = data["dualLanguageMode"] as? Bool ?? false
        } catch {
            dlog("BereanTranslationCoordinator: load preferences failed \(error)")
        }
    }

    func savePreferences() async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db.collection("translationPreferences").document(uid).setData([
            "userId": uid,
            "preferredLanguage": preferredLanguage.rawValue,
            "captionLanguages": captionLanguages.map(\.rawValue),
            "dualLanguageMode": dualLanguageMode,
            "autoTranslateFeeds": true,
            "autoTranslatePrayerRooms": true,
            "autoTranslateSermons": true,
            "showOriginalByDefault": false,
            "updatedAt": FieldValue.serverTimestamp(),
            "createdAt": FieldValue.serverTimestamp(),
        ], merge: true)
    }

    func translate(
        text: String,
        sourceLanguage: BereanSupportedLanguage,
        targetLanguage: BereanSupportedLanguage,
        contentType: String,
        sourceId: String? = nil,
        visibility: String = "private"
    ) async throws -> BereanTranslationResult {
        let result = try await functions.httpsCallable("translateMultilingualContent").call([
            "text": text,
            "sourceLanguage": sourceLanguage.rawValue,
            "targetLanguage": targetLanguage.rawValue,
            "contentType": contentType,
            "sourceId": sourceId ?? "",
            "visibility": visibility,
        ])
        guard let data = result.data as? [String: Any],
              let translatedText = data["translatedText"] as? String else {
            throw BereanRealtimeError.invalidBrokerResponse
        }
        let value = BereanTranslationResult(
            translationId: data["translationId"] as? String ?? UUID().uuidString,
            translatedText: translatedText,
            sourceLanguage: BereanSupportedLanguage(rawValue: data["sourceLanguage"] as? String ?? sourceLanguage.rawValue) ?? sourceLanguage,
            targetLanguage: BereanSupportedLanguage(rawValue: data["targetLanguage"] as? String ?? targetLanguage.rawValue) ?? targetLanguage,
            confidence: data["confidence"] as? Double ?? 0
        )
        lastResult = value
        return value
    }
}

@MainActor
final class BereanScriptureResolutionEngine: ObservableObject {
    @Published private(set) var references: [BereanScriptureReference] = []
    private let functions = Functions.functions()

    func resolve(text: String, sessionId: String? = nil, language: BereanSupportedLanguage = .english) async throws -> [BereanScriptureReference] {
        let result = try await functions.httpsCallable("resolveScriptureReferences").call([
            "text": text,
            "sessionId": sessionId ?? "",
            "language": language.rawValue,
        ])
        guard let data = result.data as? [String: Any],
              let items = data["references"] as? [[String: Any]] else { return [] }
        let resolved = items.enumerated().map { index, item in
            BereanScriptureReference(id: item["reference"] as? String ?? "ref_\(index)", data: item)
        }
        references = resolved
        return resolved
    }
}

@MainActor
final class BereanRealtimeModerationService {
    private let functions = Functions.functions()

    /// - Parameter constitutionalMode: Forwarded to the moderateRealtimeTranscript CF so
    ///   the backend can apply mode-appropriate policy. Defaults to `.ask` for legacy callers;
    ///   PrayerRoomModerationEngine always passes `.guard` (G-3).
    func validateTranscript(
        _ transcript: String,
        sessionId: String,
        constitutionalMode: BereanConstitutionalMode = .ask
    ) async throws -> Bool {
        let result = try await functions.httpsCallable("moderateRealtimeTranscript").call([
            "transcript": transcript,
            "sessionId": sessionId,
            "constitutionalMode": constitutionalMode.rawValue,
        ])
        let data = result.data as? [String: Any]
        return data?["allowed"] as? Bool ?? false
    }

    /// - Parameter scriptureVerification: Optional segment-level scripture verification
    ///   status (G-3). Forwarded to the persistRealtimeTranscriptChunk CF to be stored on
    ///   the Firestore chunk document. Defaults to nil (omitted) for legacy callers.
    func persistApprovedChunk(
        sessionId: String,
        text: String,
        kind: String,
        language: BereanSupportedLanguage,
        targetLanguage: BereanSupportedLanguage? = nil,
        isFinal: Bool = true,
        scriptureVerification: ScriptureVerificationStatus? = nil
    ) async throws {
        var payload: [String: Any] = [
            "sessionId": sessionId,
            "text": text,
            "kind": kind,
            "language": language.rawValue,
            "targetLanguage": (targetLanguage ?? language).rawValue,
            "isFinal": isFinal,
        ]
        if let sv = scriptureVerification {
            payload["scriptureVerification"] = sv.rawValue
        }
        _ = try await functions.httpsCallable("persistRealtimeTranscriptChunk").call(payload)
    }
}

@MainActor
final class BereanRealtimeAnalyticsService {
    private let functions = Functions.functions()

    func track(sessionId: String, type: String, language: BereanSupportedLanguage? = nil, latencyMs: Double = 0, surface: String = "berean_realtime") async {
        do {
            _ = try await functions.httpsCallable("logRealtimeVoiceEvent").call([
                "sessionId": sessionId,
                "type": type,
                "language": language?.rawValue ?? "",
                "latencyMs": latencyMs,
                "surface": surface,
            ])
        } catch {
            dlog("BereanRealtimeAnalyticsService: track failed \(error)")
        }
    }
}

@MainActor
final class BereanRealtimeWhisperService {
    private let sessionManager = BereanRealtimeSessionManager.shared

    func createTranscriptionSession(sourceLanguage: BereanSupportedLanguage, targetLanguages: [BereanSupportedLanguage]) async throws -> BereanRealtimeClientSecret {
        try await sessionManager.createSession(
            type: .sermonTranslation,
            sourceLanguage: sourceLanguage,
            targetLanguages: targetLanguages,
            selectedLanguage: targetLanguages.first
        )
    }
}

struct BereanLanguageDetectionService {
    func detectLanguageCode(in text: String) -> BereanSupportedLanguage {
        if text.range(of: #"[\u0600-\u06FF]"#, options: .regularExpression) != nil { return .arabic }
        if text.range(of: #"[\u3040-\u30ff]"#, options: .regularExpression) != nil { return .japanese }
        if text.range(of: #"[\u4e00-\u9fff]"#, options: .regularExpression) != nil { return .mandarin }
        if text.range(of: #"[\uac00-\ud7af]"#, options: .regularExpression) != nil { return .korean }
        return .english
    }
}

@MainActor
final class BereanSermonCaptureEngine {
    let sessionManager = BereanRealtimeSessionManager.shared
    let transcriptService = BereanLiveTranscriptService()
    let scriptureEngine = BereanScriptureResolutionEngine()
}

@MainActor
final class BereanAmbientIntelligenceEngine {
    let moderation = BereanRealtimeModerationService()
    let analytics = BereanRealtimeAnalyticsService()
    let scripture = BereanScriptureResolutionEngine()
}

