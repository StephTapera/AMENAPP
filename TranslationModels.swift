// TranslationModels.swift
// AMEN App — Translation System
//
// Firestore Schema:
//
// translations/{cacheKey}                          ← Global dedup cache
//   cacheKey: String                               ← SHA256(normalizedText + sourceLang + targetLang + engineVersion)
//   originalText: String
//   translatedText: String
//   sourceLanguage: String                         ← ISO 639-1 "es"
//   targetLanguage: String
//   engineVersion: String                          ← "gcp-v3" | "apple-on-device"
//   characterCount: Int
//   createdAt: Timestamp
//   lastAccessedAt: Timestamp
//   accessCount: Int
//   isPublicContent: Bool                          ← false = DM, restricted cache lifetime
//
// posts/{postId}
//   detectedLanguage: String?                      ← Set at write time
//   detectedLanguageConfidence: Double?
//   translations: { "es": TranslationVariant, ... } ← Embedded map for common langs
//
// posts/{postId}/comments/{commentId}
//   detectedLanguage: String?
//   translations: { "en": TranslationVariant }     ← Embedded map
//
// users/{uid}
//   languagePreferences: UserLanguagePreferences   ← Embedded sub-object
//
// translationAnalytics/{date}/events/{eventId}
//   surface: String
//   sourceLang: String
//   targetLang: String
//   cacheHit: Bool
//   latencyMs: Int
//   timestamp: Timestamp
//   userId: String (hashed for privacy)

import Foundation
import FirebaseFirestore

// MARK: - Core Translation Model

/// Represents a single translated variant of content
struct TranslationVariant: Codable, Equatable {
    let translatedText: String
    let sourceLanguage: String          // ISO 639-1, e.g. "es"
    let targetLanguage: String          // ISO 639-1, e.g. "en"
    let engineVersion: TranslationEngine
    let translatedAt: Date
    let characterCount: Int
    var confidence: Double?             // Engine confidence 0.0–1.0 if available
    var isUserRequested: Bool           // true = user tapped "See translation"

    enum CodingKeys: String, CodingKey {
        case translatedText, sourceLanguage, targetLanguage
        case engineVersion, translatedAt, characterCount
        case confidence, isUserRequested
    }
}

/// Translation engine used to generate the result
enum TranslationEngine: String, Codable {
    case gcpV3 = "gcp-v3"               // Google Cloud Translation v3 (server-side)
    case appleOnDevice = "apple-on-device" // Apple Translation framework (iOS 17.4+)
    case unknown = "unknown"
}

// MARK: - Language Detection Result

struct LanguageDetectionResult: Equatable {
    let languageCode: String            // ISO 639-1 "es"
    let confidence: Double              // 0.0 – 1.0
    let isReliable: Bool               // confidence >= 0.7 AND length >= 15 chars
    let rawText: String
}

// MARK: - Translation Request/Response for Backend

/// Sent to Cloud Function / Cloud Run translation endpoint
struct TranslationRequest: Codable {
    let requestId: String               // Idempotency key
    let contentType: TranslatableContentType
    let contentId: String              // postId, commentId, etc.
    let text: String
    let sourceLanguage: String?        // nil = auto-detect
    let targetLanguage: String         // ISO 639-1
    let requestingUserId: String
    let isPublicContent: Bool
    let surface: TranslationSurface
    let engineHint: TranslationEngine?  // prefer on-device if available
}

struct TranslationResponse: Codable {
    let requestId: String
    let translatedText: String
    let sourceLanguage: String
    let targetLanguage: String
    let engineVersion: TranslationEngine
    let cacheHit: Bool
    let charactersBilled: Int
    let latencyMs: Int
}

struct TranslationErrorResponse: Codable, Error {
    let requestId: String
    let errorCode: TranslationErrorCode
    let message: String
    let retryAfterSeconds: Int?
}

enum TranslationErrorCode: String, Codable {
    case unsupportedLanguage = "UNSUPPORTED_LANGUAGE"
    case contentTooLong = "CONTENT_TOO_LONG"
    case rateLimitExceeded = "RATE_LIMIT_EXCEEDED"
    case contentRestricted = "CONTENT_RESTRICTED"  // private/blocked content
    case serviceUnavailable = "SERVICE_UNAVAILABLE"
    case detectionFailed = "DETECTION_FAILED"
    case unknown = "UNKNOWN"
}

// MARK: - Content Type Taxonomy

/// What kind of content is being translated
enum TranslatableContentType: String, Codable, CaseIterable {
    case post = "post"
    case comment = "comment"
    case reply = "reply"
    case testimony = "testimony"
    case prayerRequest = "prayer_request"
    case profileBio = "profile_bio"
    case message = "message"            // DMs — feature-flagged, off by default
    case resourceDescription = "resource_description"
    case churchNote = "church_note"
}

/// Which UI surface the translation was triggered from
enum TranslationSurface: String, Codable {
    case feed = "feed"
    case postDetail = "post_detail"
    case commentSheet = "comment_sheet"
    case profilePage = "profile_page"
    case search = "search"
    case notifications = "notifications"
    case messages = "messages"
}

// MARK: - User Language Preferences

/// Stored in Firestore users/{uid} under "languagePreferences"
struct UserLanguagePreferences: Codable, Equatable {
    /// The user's primary language for app content (ISO 639-1, e.g. "en")
    var appLanguage: String

    /// Content translation mode
    var contentTranslationMode: ContentTranslationMode

    /// Whether to auto-translate posts whose detected language != appLanguage
    var autoTranslatePosts: Bool

    /// Whether to auto-translate comments/replies
    var autoTranslateComments: Bool

    /// Show original text alongside the translation
    var showOriginalAlongTranslation: Bool

    /// Secondary languages the user understands (no translation needed for these)
    var understoodLanguages: [String]

    /// When was this last updated
    var updatedAt: Date

    static var `default`: UserLanguagePreferences {
        UserLanguagePreferences(
            appLanguage: Locale.current.language.languageCode?.identifier ?? "en",
            contentTranslationMode: .onRequest,
            autoTranslatePosts: false,
            autoTranslateComments: false,
            showOriginalAlongTranslation: true,
            understoodLanguages: [],
            updatedAt: Date()
        )
    }
}

enum ContentTranslationMode: String, Codable, CaseIterable {
    case never = "never"                // User disabled translation entirely
    case onRequest = "on_request"       // "See Translation" button only
    case auto = "auto"                  // Auto-show when language differs

    var displayLabel: String {
        switch self {
        case .never: return "Off"
        case .onRequest: return "On Request"
        case .auto: return "Automatic"
        }
    }

    var description: String {
        switch self {
        case .never: return "Never show translations"
        case .onRequest: return "Show \u{201C}See Translation\u{201D} button"
        case .auto: return "Auto-translate foreign language content"
        }
    }
}

// MARK: - Translation Cache Entry (Firestore)

/// Stored in translations/{cacheKey}
struct TranslationCacheEntry: Codable {
    @DocumentID var id: String?
    let cacheKey: String                // Primary lookup key
    let originalText: String
    let normalizedText: String          // Lowercase trimmed for lookup
    let translatedText: String
    let sourceLanguage: String
    let targetLanguage: String
    let engineVersion: TranslationEngine
    let characterCount: Int
    let isPublicContent: Bool
    let createdAt: Date
    var lastAccessedAt: Date
    var accessCount: Int

    /// Firestore document path helper
    static func documentId(for cacheKey: String) -> String { cacheKey }
}

// MARK: - Translation UI State

/// Drives the per-content translation UI state machine
enum TranslationUIState: Equatable {
    case notNeeded                  // Same language as user
    case available                  // Different language, not yet translated
    case loading                    // Request in flight
    case translated(TranslationVariant)  // Success
    case error(TranslationDisplayError)  // Failure
    case disabled                   // Feature off / DM without approval

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var translatedText: String? {
        if case .translated(let variant) = self { return variant.translatedText }
        return nil
    }

    var sourceLangCode: String? {
        if case .translated(let variant) = self { return variant.sourceLanguage }
        return nil
    }
}

enum TranslationDisplayError: Equatable {
    case unsupportedLanguage
    case networkUnavailable
    case serviceUnavailable
    case contentRestricted
    case rateLimited

    var userFacingMessage: String {
        switch self {
        case .unsupportedLanguage: return "This language isn't supported yet"
        case .networkUnavailable: return "Translation unavailable offline"
        case .serviceUnavailable: return "Translation unavailable right now"
        case .contentRestricted: return "This content can't be translated"
        case .rateLimited: return "Too many requests — try again shortly"
        }
    }
}

// MARK: - Translation Analytics Event

struct TranslationAnalyticsEvent: Codable {
    let eventId: String
    let surface: TranslationSurface
    let contentType: TranslatableContentType
    let sourceLanguage: String
    let targetLanguage: String
    let engineVersion: TranslationEngine
    let cacheHit: Bool
    let latencyMs: Int
    let wasAutoTranslated: Bool
    let timestamp: Date
    let hashedUserId: String        // SHA256 of userId for privacy
}

// MARK: - Supported Languages

/// Languages supported by AMEN Translation — can be extended
struct SupportedLanguage: Identifiable, Hashable {
    let id: String          // ISO 639-1
    let displayName: String
    let nativeName: String
    let isRTL: Bool

    static let all: [SupportedLanguage] = [
        SupportedLanguage(id: "en", displayName: "English", nativeName: "English", isRTL: false),
        SupportedLanguage(id: "es", displayName: "Spanish", nativeName: "Español", isRTL: false),
        SupportedLanguage(id: "fr", displayName: "French", nativeName: "Français", isRTL: false),
        SupportedLanguage(id: "pt", displayName: "Portuguese", nativeName: "Português", isRTL: false),
        SupportedLanguage(id: "de", displayName: "German", nativeName: "Deutsch", isRTL: false),
        SupportedLanguage(id: "it", displayName: "Italian", nativeName: "Italiano", isRTL: false),
        SupportedLanguage(id: "zh", displayName: "Chinese (Simplified)", nativeName: "中文", isRTL: false),
        SupportedLanguage(id: "ja", displayName: "Japanese", nativeName: "日本語", isRTL: false),
        SupportedLanguage(id: "ko", displayName: "Korean", nativeName: "한국어", isRTL: false),
        SupportedLanguage(id: "ar", displayName: "Arabic", nativeName: "العربية", isRTL: true),
        SupportedLanguage(id: "hi", displayName: "Hindi", nativeName: "हिन्दी", isRTL: false),
        SupportedLanguage(id: "sw", displayName: "Swahili", nativeName: "Kiswahili", isRTL: false),
        SupportedLanguage(id: "yo", displayName: "Yoruba", nativeName: "Yorùbá", isRTL: false),
        SupportedLanguage(id: "ig", displayName: "Igbo", nativeName: "Igbo", isRTL: false),
        SupportedLanguage(id: "ha", displayName: "Hausa", nativeName: "Hausa", isRTL: false),
        SupportedLanguage(id: "nl", displayName: "Dutch", nativeName: "Nederlands", isRTL: false),
        SupportedLanguage(id: "ru", displayName: "Russian", nativeName: "Русский", isRTL: false),
        SupportedLanguage(id: "pl", displayName: "Polish", nativeName: "Polski", isRTL: false),
        SupportedLanguage(id: "tl", displayName: "Filipino", nativeName: "Filipino", isRTL: false),
        SupportedLanguage(id: "id", displayName: "Indonesian", nativeName: "Bahasa Indonesia", isRTL: false),
    ]

    static func displayName(for code: String) -> String {
        all.first(where: { $0.id == code })?.displayName ?? code.uppercased()
    }
}

// MARK: - Content Preprocessing (Preserve AMEN entities)

/// Rules for what NOT to translate in AMEN content
struct TranslationPreservationRules {
    /// Regex patterns for content segments that should be excluded from translation
    static let preservedPatterns: [String] = [
        // Bible verse references: John 3:16, Romans 8:28, Psalm 23, 1 Corinthians 13:4-7
        #"(?:(?:\d\s+)?[A-Za-z]+\s+\d+:\d+(?:-\d+)?)"#,
        // Bible translation acronyms: KJV, ESV, NIV, NASB, NLT, MSG, AMP
        #"\b(KJV|ESV|NIV|NASB|NLT|MSG|AMP|NKJV|CSB|HCSB|RSV|CEV)\b"#,
        // @mentions
        #"@[\w\.]+"#,
        // #hashtags
        #"#\w+"#,
        // URLs
        #"https?://[^\s]+"#,
        // Email addresses
        #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#,
    ]

    /// Short content that likely doesn't need translation (low-signal words)
    static let noTranslationNeeded: Set<String> = [
        "amen", "wow", "lol", "ok", "yes", "no", "❤️", "🙏", "😂", "🔥", "👍", "🎉"
    ]

    /// Minimum character count to attempt translation (avoid wasting API calls)
    static let minimumCharCount = 10

    /// Minimum language detection confidence to proceed
    static let minimumDetectionConfidence = 0.55
}
