import Foundation
import FirebaseFirestore

enum BereanRealtimeSessionType: String, Codable, CaseIterable {
    case sermonTranslation = "sermon_translation"
    case livePrayerRoom = "live_prayer_room"
    case voiceAssistant = "voice_assistant"
    case smartNotes = "smart_notes"
    case multilingualConversation = "multilingual_conversation"
}

enum BereanRealtimeSessionStatus: String, Codable {
    case initializing
    case active
    case paused
    case disconnecting
    case ended
    case failed
}

enum BereanSupportedLanguage: String, Codable, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"
    case portuguese = "pt"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case japanese = "ja"
    case mandarin = "zh"
    case arabic = "ar"
    case hindi = "hi"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Spanish"
        case .portuguese: return "Portuguese"
        case .korean: return "Korean"
        case .french: return "French"
        case .german: return "German"
        case .japanese: return "Japanese"
        case .mandarin: return "Mandarin"
        case .arabic: return "Arabic"
        case .hindi: return "Hindi"
        }
    }
}

struct BereanRealtimeSession: Identifiable, Codable, Equatable {
    let id: String
    let ownerId: String
    let sessionType: BereanRealtimeSessionType
    var status: BereanRealtimeSessionStatus
    var sourceLanguage: BereanSupportedLanguage
    var targetLanguages: [BereanSupportedLanguage]
    var selectedLanguage: BereanSupportedLanguage
    var providerSessionId: String?
    var model: String?
    var expiresAt: Date?

    init(
        id: String,
        ownerId: String,
        sessionType: BereanRealtimeSessionType,
        status: BereanRealtimeSessionStatus = .initializing,
        sourceLanguage: BereanSupportedLanguage = .english,
        targetLanguages: [BereanSupportedLanguage] = [.english],
        selectedLanguage: BereanSupportedLanguage = .english,
        providerSessionId: String? = nil,
        model: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.ownerId = ownerId
        self.sessionType = sessionType
        self.status = status
        self.sourceLanguage = sourceLanguage
        self.targetLanguages = targetLanguages
        self.selectedLanguage = selectedLanguage
        self.providerSessionId = providerSessionId
        self.model = model
        self.expiresAt = expiresAt
    }
}

struct BereanRealtimeClientSecret: Equatable {
    let sessionId: String
    let value: String
    let expiresAt: Date
    let providerSessionId: String?
    let model: String?
    /// WebSocket endpoint issued by the server-side broker. Must be set by the
    /// server; the client never falls over to a hardcoded provider URL.
    let endpoint: URL?
}

struct BereanCaptionChunk: Identifiable, Equatable {
    let id: String
    let text: String
    let language: BereanSupportedLanguage
    let isFinal: Bool
    let startsAtMs: Int
    let durationMs: Int
    let createdAt: Date?

    init(id: String, data: [String: Any]) {
        self.id = id
        self.text = data["text"] as? String ?? data["translatedText"] as? String ?? ""
        self.language = BereanSupportedLanguage(rawValue: data["language"] as? String ?? data["targetLanguage"] as? String ?? "en") ?? .english
        self.isFinal = data["isFinal"] as? Bool ?? true
        self.startsAtMs = data["startsAtMs"] as? Int ?? 0
        self.durationMs = data["durationMs"] as? Int ?? 0
        self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
    }
}

struct BereanScriptureReference: Identifiable, Equatable {
    let id: String
    let reference: String
    let normalizedReference: String
    let confidence: Double
    /// H-10: true when ScriptureReferenceValidator flagged this reference as
    /// an unknown book or an out-of-range chapter/verse from LLM output.
    var isUnverified: Bool

    init(id: String, data: [String: Any]) {
        self.id = id
        self.reference = data["reference"] as? String ?? ""
        self.normalizedReference = data["normalizedReference"] as? String ?? (data["reference"] as? String ?? "")
        self.confidence = data["confidence"] as? Double ?? 0
        self.isUnverified = false  // validated post-init in BereanScriptureKnowledgeGraph
    }
}

struct BereanTranslationResult: Equatable {
    let translationId: String
    let translatedText: String
    let sourceLanguage: BereanSupportedLanguage
    let targetLanguage: BereanSupportedLanguage
    let confidence: Double
}
