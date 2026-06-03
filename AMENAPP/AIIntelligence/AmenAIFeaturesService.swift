import Foundation
import FirebaseFunctions

// MARK: - Response models

/// Daily Digest morning card data (maps to getDailyDigest CF response)
struct AmenDailyDigestResponse: Codable {
    struct DailyVerse: Codable {
        let reference: String
        let text: String
        let reflection: String
    }
    struct PrayerReminder: Codable {
        let postId: String
        let excerpt: String
        let hoursAgo: Int
    }
    struct MentorMessage: Codable {
        let threadId: String
        let senderId: String
        let senderName: String
        let preview: String
    }
    struct ChurchEvent: Codable {
        let eventId: String
        let title: String
        let startsAt: String?
        let church: String
    }
    struct SpaceUpdate: Codable {
        let spaceId: String
        let spaceName: String
        let summary: String
        let unreadCount: Int
    }
    struct StudyProgress: Codable {
        let studyId: String
        let title: String
        let progressPct: Double
        let nextLesson: String?
    }

    let dailyVerse: DailyVerse
    let prayerReminders: [PrayerReminder]
    let unreadMentorMessages: [MentorMessage]
    let churchEvents: [ChurchEvent]
    let spaceUpdates: [SpaceUpdate]
    let studiesToContinue: [StudyProgress]
    let reflectionPrompt: String
    let cached: Bool
    let generatedAt: String
}

/// Creator Draft response (maps to generateCreatorDraft CF response)
struct CreatorDraftResponse: Codable {
    let draft: String
    let type: String
    /// Always true — user must approve before publishing
    let draftOnly: Bool

    enum CodingKeys: String, CodingKey {
        case draft, type
        case draftOnly = "draft_only"
    }
}

/// A single RAG search result
struct RAGSearchResult: Codable, Identifiable {
    let id: String
    let title: String
    let excerpt: String
    let score: Double
    let type: String
    let sourceRef: String
}

/// RAG Search response (maps to ragSearch CF response)
struct RAGSearchResponse: Codable {
    let results: [RAGSearchResult]
    let scope: String
    let query: String
    let resultCount: Int
}

// MARK: - Service

/// Call-site wrappers for the three AI callable features.
/// All calls go through Firebase Cloud Functions — no API keys on device.
@MainActor
final class AmenAIFeaturesService: ObservableObject {
    static let shared = AmenAIFeaturesService()

    private let functions = Functions.functions(region: "us-central1")

    private init() {}

    // MARK: A. Daily Digest

    /// Fetches the morning digest card for the authenticated user.
    /// Results are cached server-side in Firestore (once per day per user).
    ///
    /// - Parameters:
    ///   - dateKey: ISO date string "YYYY-MM-DD" for today
    ///   - forceRefresh: bypass server cache and recompute
    func getDailyDigest(
        dateKey: String,
        forceRefresh: Bool = false
    ) async throws -> AmenDailyDigestResponse {
        // AUDIT GAP: No consent check before calling getDailyDigest. This CF reads
        // the user's prayer reminders, mentor messages, and study progress — personal
        // spiritual data. A BereanConsentManager.shared.hasGrantedDigestConsent() gate
        // must be checked here (and enforced server-side) before the call proceeds.
        //
        // AUDIT GAP: No client-side daily quota guard. Although the server caches
        // once per day, forceRefresh=true can trigger repeated LLM calls without limit.
        // Add a local UserDefaults counter keyed to dateKey to prevent more than
        // 3 forced refreshes per day per user before hitting the CF.
        let payload: [String: Any] = [
            "dateKey": dateKey,
            "timezone": TimeZone.current.identifier,
            "forceRefresh": forceRefresh,
        ]
        let result = try await functions
            .httpsCallable("getDailyDigest")
            .call(payload)

        let data = try JSONSerialization.data(
            withJSONObject: result.data as? [String: Any] ?? [:]
        )
        let decoder = JSONDecoder()
        return try decoder.decode(AmenDailyDigestResponse.self, from: data)
    }

    // MARK: B. Creator Draft Assistant

    /// Generates a content draft for mentors and church creators.
    ///
    /// - Parameters:
    ///   - type: "post" | "devotional" | "studyGuide" | "announcement"
    ///   - topic: Subject matter (5–300 chars)
    ///   - audience: Target audience description (optional)
    ///   - tone: "warm" | "formal" | "encouraging" | "teaching"
    ///
    /// - Important: The returned draft MUST be reviewed and approved by the user
    ///   before publishing. `response.draftOnly` is always `true`.
    func generateCreatorDraft(
        type: String,
        topic: String,
        audience: String = "faith community",
        tone: String = "warm"
    ) async throws -> CreatorDraftResponse {
        // AUDIT GAP: No consent check before sending topic/audience text to the AI.
        // Creator OS consent (confirming the user understands their input is processed
        // by an AI system) must be verified via ConsentManager before this call.
        //
        // AUDIT GAP: No input length validation enforced client-side. The doc comment
        // says 5–300 chars for topic but nothing guards this before the CF call.
        // Add: guard (5...300).contains(topic.count) else { throw AmenAIFeaturesError.invalidInput }
        //
        // AUDIT GAP: No rate-limit guard. Repeated calls to generateCreatorDraft with
        // different topics cost LLM tokens on every invocation. A per-user hourly or
        // daily quota (e.g. 10 drafts/day for Creator tier, 3 for standard) must be
        // enforced server-side in the CF and echoed here to prevent abuse.
        let payload: [String: Any] = [
            "type": type,
            "topic": topic,
            "audience": audience,
            "tone": tone,
        ]
        let result = try await functions
            .httpsCallable("generateCreatorDraft")
            .call(payload)

        let data = try JSONSerialization.data(
            withJSONObject: result.data as? [String: Any] ?? [:]
        )
        let decoder = JSONDecoder()
        let response = try decoder.decode(CreatorDraftResponse.self, from: data)

        // Safety assertion: never auto-publish even if the flag were somehow missing
        guard response.draftOnly else {
            assertionFailure("generateCreatorDraft returned draftOnly=false — this must never happen.")
            throw AmenAIFeaturesError.draftOnlyViolation
        }
        return response
    }

    // MARK: C. RAG Search

    /// Semantic search across AMEN content using server-side Pinecone vector DB.
    ///
    /// - Parameters:
    ///   - query: Natural-language search query (3–500 chars)
    ///   - scope: "churchNotes" | "savedVerses" | "posts" | "sermons" | "all"
    ///
    /// - Note: Multilingual support is a TODO on the backend.
    ///   Results are currently returned in the source language of the content.
    func ragSearch(
        query: String,
        scope: RAGSearchScope = .all
    ) async throws -> RAGSearchResponse {
        // AUDIT GAP: No input length validation enforced client-side. The doc comment
        // says 3–500 chars but no guard exists before the CF is called.
        // Add: guard (3...500).contains(query.count) else { throw AmenAIFeaturesError.invalidInput }
        //
        // AUDIT GAP: When scope includes "churchNotes" or "savedVerses", the CF
        // embeds and searches the user's personal spiritual content. A consent check
        // confirming the user has approved AI indexing of their private notes must be
        // performed before calling ragSearch with those scopes.
        //
        // AUDIT GAP: No client-side rate-limit guard. Each ragSearch call triggers a
        // Pinecone vector query with an LLM embedding round-trip. A debounce or
        // per-minute call cap (e.g. max 10 queries/minute) should be applied at the
        // call site (e.g. SearchView) and enforced server-side in the CF.
        let payload: [String: Any] = [
            "query": query,
            "scope": scope.rawValue,
        ]
        let result = try await functions
            .httpsCallable("ragSearch")
            .call(payload)

        let data = try JSONSerialization.data(
            withJSONObject: result.data as? [String: Any] ?? [:]
        )
        let decoder = JSONDecoder()
        return try decoder.decode(RAGSearchResponse.self, from: data)
    }
}

// MARK: - Supporting types

enum RAGSearchScope: String, CaseIterable {
    case churchNotes
    case savedVerses
    case posts
    case sermons
    case all
}

enum CreatorDraftType: String, CaseIterable {
    case post
    case devotional
    case studyGuide
    case announcement

    var displayName: String {
        switch self {
        case .post:         return "Post"
        case .devotional:   return "Devotional"
        case .studyGuide:   return "Study Guide"
        case .announcement: return "Announcement"
        }
    }
}

enum AmenAIFeaturesError: LocalizedError {
    case draftOnlyViolation
    /// Input failed client-side length validation before being sent to a CF.
    case invalidInput

    var errorDescription: String? {
        switch self {
        case .draftOnlyViolation:
            return "Draft safety check failed. Please try again."
        case .invalidInput:
            return "Your input is too short or too long. Please adjust and try again."
        }
    }
}
