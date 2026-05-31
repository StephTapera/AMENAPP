import Foundation
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class BereanLiveTranscriptService: ObservableObject {
    @Published private(set) var captions: [BereanCaptionChunk] = []
    @Published private(set) var scriptures: [BereanResolvedScriptureRef] = []
    @Published var listenerError: String?

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
            .addSnapshotListener { [weak self] snapshot, error in
                if let error {
                    dlog("⚠️ BereanLiveTranscriptService caption listener error: \(error.localizedDescription)")
                    Task { @MainActor in self?.listenerError = error.localizedDescription }
                    return
                }
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
            .addSnapshotListener { [weak self] snapshot, error in
                if let error {
                    dlog("⚠️ BereanLiveTranscriptService scripture listener error: \(error.localizedDescription)")
                    Task { @MainActor in self?.listenerError = error.localizedDescription }
                    return
                }
                guard let docs = snapshot?.documents else { return }
                Task { @MainActor in
                    self?.scriptures = docs.map { BereanResolvedScriptureRef(id: $0.documentID, data: $0.data()) }
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

    func savePreferences(userId: String) async throws {
        try await db.collection("translationPreferences").document(userId).setData([
            "userId": userId,
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
        let result = try await functions.callWithTimeout("translateMultilingualContent", data: [
            "text": text,
            "sourceLanguage": sourceLanguage.rawValue,
            "targetLanguage": targetLanguage.rawValue,
            "contentType": contentType,
            "sourceId": sourceId ?? "",
            "visibility": visibility,
        ], timeout: 30)
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
    @Published private(set) var references: [BereanResolvedScriptureRef] = []
    private let functions = Functions.functions()

    func resolve(
        text: String,
        language: BereanSupportedLanguage = .english,
        sessionId: String? = nil
    ) async throws -> [BereanResolvedScriptureRef] {
        let result = try await functions.callWithTimeout("resolveScriptureReferences", data: [
            "text": text,
            "language": language.rawValue,
            "sessionId": sessionId ?? "",
        ], timeout: 15)
        guard let data = result.data as? [String: Any],
              let items = data["references"] as? [[String: Any]] else { return [] }
        let resolved = items.enumerated().map { index, item in
            BereanResolvedScriptureRef(id: item["reference"] as? String ?? "ref_\(index)", data: item)
        }
        references = resolved
        return resolved
    }
}

@MainActor
final class BereanRealtimeModerationService {
    private let functions = Functions.functions()

    func validateTranscript(_ transcript: String, sessionId: String) async throws -> Bool {
        let result = try await functions.callWithTimeout("moderateRealtimeTranscript", data: [
            "transcript": transcript,
            "sessionId": sessionId,
        ], timeout: 15)
        let data = result.data as? [String: Any]
        return data?["allowed"] as? Bool ?? false
    }

    func persistApprovedChunk(
        sessionId: String,
        text: String,
        kind: String,
        language: BereanSupportedLanguage,
        targetLanguage: BereanSupportedLanguage? = nil,
        isFinal: Bool = true
    ) async throws {
        _ = try await functions.callWithTimeout("persistRealtimeTranscriptChunk", data: [
            "sessionId": sessionId,
            "text": text,
            "kind": kind,
            "language": language.rawValue,
            "targetLanguage": (targetLanguage ?? language).rawValue,
            "isFinal": isFinal,
        ], timeout: 10)
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
final class BereanSermonCaptureEngine: ObservableObject {
    @Published private(set) var isCapturing = false
    @Published private(set) var sessionId: String?
    @Published private(set) var currentSecret: BereanRealtimeClientSecret?
    @Published private(set) var error: String?

    // Exposed so call sites can observe captions / scriptures directly.
    let transcriptService: BereanLiveTranscriptService

    private let sessionManager: BereanRealtimeSessionManager
    private let scriptureEngine: BereanScriptureResolutionEngine
    private let analytics: BereanRealtimeAnalyticsService
    private let whisperService: BereanRealtimeWhisperService

    init(sessionManager: BereanRealtimeSessionManager = .shared) {
        self.sessionManager = sessionManager
        self.transcriptService = BereanLiveTranscriptService()
        self.scriptureEngine = BereanScriptureResolutionEngine()
        self.analytics = BereanRealtimeAnalyticsService()
        self.whisperService = BereanRealtimeWhisperService()
    }

    /// Creates a realtime session and begins streaming captions + scripture references.
    func start(
        sourceLanguage: BereanSupportedLanguage = .english,
        targetLanguages: [BereanSupportedLanguage]
    ) async {
        guard !isCapturing else { return }
        error = nil
        do {
            let secret = try await whisperService.createTranscriptionSession(
                sourceLanguage: sourceLanguage,
                targetLanguages: targetLanguages
            )
            currentSecret = secret
            sessionId = secret.sessionId
            let displayLanguage = targetLanguages.first ?? sourceLanguage
            transcriptService.start(sessionId: secret.sessionId, language: displayLanguage)
            isCapturing = true
            await analytics.track(
                sessionId: secret.sessionId,
                type: "sermon_capture_started",
                language: sourceLanguage,
                surface: "sermon_capture"
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Switches the live caption output to a different target language without restarting the session.
    func switchLanguage(to language: BereanSupportedLanguage) {
        guard let sid = sessionId else { return }
        transcriptService.start(sessionId: sid, language: language)
    }

    /// Stops capture, tears down listeners, and ends the backend session.
    func stop() {
        guard isCapturing else { return }
        let sid = sessionId
        transcriptService.stop()
        isCapturing = false
        sessionId = nil
        currentSecret = nil
        Task {
            if let sid {
                await analytics.track(sessionId: sid, type: "sermon_capture_ended", surface: "sermon_capture")
            }
            try? await sessionManager.endCurrentSession()
        }
    }
}

@MainActor
final class BereanAmbientIntelligenceEngine {
    private let moderation: BereanRealtimeModerationService
    private let analytics: BereanRealtimeAnalyticsService
    private let scripture: BereanScriptureResolutionEngine
    private let languageDetector = BereanLanguageDetectionService()

    init() {
        self.moderation = BereanRealtimeModerationService()
        self.analytics = BereanRealtimeAnalyticsService()
        self.scripture = BereanScriptureResolutionEngine()
    }

    /// Validates a transcript chunk through moderation, resolves any scripture references,
    /// and tracks the event. Returns resolved references, or empty if moderation blocks it.
    @discardableResult
    func analyzeTranscriptChunk(
        _ text: String,
        sessionId: String,
        language: BereanSupportedLanguage? = nil
    ) async throws -> [BereanResolvedScriptureRef] {
        let allowed = try await moderation.validateTranscript(text, sessionId: sessionId)
        guard allowed else { return [] }

        let detectedLanguage = language ?? languageDetector.detectLanguageCode(in: text)
        let refs = try await scripture.resolve(text: text, language: detectedLanguage, sessionId: sessionId)

        if !refs.isEmpty {
            await analytics.track(
                sessionId: sessionId,
                type: "ambient_scripture_detected",
                language: detectedLanguage,
                surface: "ambient_intelligence"
            )
        }
        return refs
    }

    /// Returns true when the content carries enough spiritual signal to proactively
    /// surface Berean context (e.g., pop a scripture card). Requires ≥ 5 words and
    /// ≥ 2 spiritual keyword matches so single-word utterances never trigger it.
    func shouldSurfaceScripture(for text: String) -> Bool {
        let words = text.split(separator: " ").count
        guard words >= 5 else { return false }
        let keywords = ["pray", "prayer", "scripture", "verse", "bible", "god", "lord",
                        "jesus", "spirit", "faith", "grace", "amen", "worship", "sermon",
                        "holy", "gospel", "revelation", "salvation", "repent", "glory"]
        let lower = text.lowercased()
        return keywords.filter { lower.contains($0) }.count >= 2
    }

    /// Records a user interaction with an ambient intelligence surface for analytics.
    func recordInteraction(type: String, sessionId: String, language: BereanSupportedLanguage? = nil) async {
        await analytics.track(sessionId: sessionId, type: type, language: language, surface: "ambient_intelligence")
    }
}

