import Foundation
import FirebaseFunctions

// MARK: - Response models
// Daily Digest is handled exclusively by AmenDailyDigestService (decodes AmenDailyDigest).
// This service handles generateCreatorDraft and ragSearch only.

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

    private static var utcDayKey: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.string(from: Date())
    }

    // MARK: A. Creator Draft Assistant

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
        guard (5...300).contains(topic.count) else { throw AmenAIFeaturesError.invalidInput }
        guard UserDefaults.standard.bool(forKey: "consentCreatorAI") else {
            throw AmenAIFeaturesError.consentRequired
        }

        // Tier-aware rate limit: Amen+ and above have no per-day cap.
        // Free users are limited to 5 drafts/day.
        let isAmenPlus = AmenAccountEntitlementService.shared.currentTier >= .amenPlus
        if !isAmenPlus {
            let draftDayKey = "amenAI_creatorDraft_\(Self.utcDayKey)"
            let draftCount = UserDefaults.standard.integer(forKey: draftDayKey)
            guard draftCount < 5 else { throw AmenAIFeaturesError.writingCoachUpgradeRequired }
            UserDefaults.standard.set(draftCount + 1, forKey: draftDayKey)
        }
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
        guard (3...500).contains(query.count) else { throw AmenAIFeaturesError.invalidInput }
        if scope == .churchNotes || scope == .savedVerses {
            guard UserDefaults.standard.bool(forKey: "consentAIIndexingPersonalContent") else {
                throw AmenAIFeaturesError.consentRequired
            }
        }
        let now = Date().timeIntervalSince1970
        let searchTimestampsKey = "amenAI_ragSearch_timestamps"
        var recentTimestamps = (UserDefaults.standard.array(forKey: searchTimestampsKey) as? [Double]) ?? []
        recentTimestamps = recentTimestamps.filter { now - $0 < 60 }
        guard recentTimestamps.count < 10 else { throw AmenAIFeaturesError.rateLimitExceeded }
        recentTimestamps.append(now)
        UserDefaults.standard.set(recentTimestamps, forKey: searchTimestampsKey)
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
    case consentRequired
    case rateLimitExceeded
    /// Free-tier daily cap (5 drafts/day) reached — upgrade to Amen+ for unlimited drafts.
    case writingCoachUpgradeRequired

    var errorDescription: String? {
        switch self {
        case .draftOnlyViolation:
            return "Draft safety check failed. Please try again."
        case .invalidInput:
            return "Your input is too short or too long. Please adjust and try again."
        case .consentRequired:
            return "Please enable AI features in your privacy settings to use this feature."
        case .rateLimitExceeded:
            return "You've reached the usage limit for this feature. Please try again later."
        case .writingCoachUpgradeRequired:
            return "Upgrade to Amen+ for unlimited AI writing. Free accounts can generate up to 5 drafts per day."
        }
    }
}
