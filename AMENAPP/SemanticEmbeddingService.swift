// SemanticEmbeddingService.swift
// AMENAPP
//
// Client-side wrapper for the semanticEmbeddings Cloud Functions.
// Provides scripture recommendations, similar testimony discovery,
// prayer partner matching, and prayer wellness data retrieval.
//
// All calls are lightweight — heavy work (embedding, Pinecone queries)
// runs server-side in Cloud Functions. Results are cached in memory
// for the duration of the session.

import Foundation
import Combine
import FirebaseFunctions
import FirebaseAuth
import FirebaseFirestore

// MARK: - Response Models

struct ScriptureRecommendation: Identifiable {
    let id: String         // e.g. "John_3_16"
    let reference: String
    let text: String
    let book: String
    let chapter: Int
    let verse: Int
    let testament: String
    let relevanceScore: Double

    init(from dict: [String: Any]) {
        self.book            = dict["book"]            as? String ?? ""
        self.chapter         = dict["chapter"]         as? Int    ?? 0
        self.verse           = dict["verse"]           as? Int    ?? 0
        self.reference       = dict["reference"]       as? String ?? ""
        self.text            = dict["text"]            as? String ?? ""
        self.testament       = dict["testament"]       as? String ?? ""
        self.relevanceScore  = dict["relevanceScore"]  as? Double ?? 0
        self.id              = reference.isEmpty ? "\(book)_\(chapter)_\(verse)" : reference
    }
}

struct SimilarTestimony: Identifiable {
    let postId: String
    let authorId: String
    let authorDisplayName: String
    let authorPhotoURL: String
    let content: String
    let createdAt: Date
    let relevanceScore: Double

    var id: String { postId }

    init(from dict: [String: Any]) {
        self.postId            = dict["postId"]            as? String ?? ""
        self.authorId          = dict["authorId"]          as? String ?? ""
        self.authorDisplayName = dict["authorDisplayName"] as? String ?? ""
        self.authorPhotoURL    = dict["authorPhotoURL"]    as? String ?? ""
        self.content           = dict["content"]           as? String ?? ""
        self.createdAt         = Date(timeIntervalSince1970: Double(dict["createdAt"] as? Int ?? 0) / 1000)
        self.relevanceScore    = dict["relevanceScore"]    as? Double ?? 0
    }
}

struct PrayerPartnerMatch: Identifiable {
    let userId: String
    let displayName: String
    let photoURL: String
    let similarityScore: Double
    let spiritualGift: String?

    var id: String { userId }

    init(from dict: [String: Any]) {
        self.userId          = dict["userId"]          as? String ?? ""
        self.displayName     = dict["displayName"]     as? String ?? ""
        self.photoURL        = dict["photoURL"]        as? String ?? ""
        self.similarityScore = dict["similarityScore"] as? Double ?? 0
        self.spiritualGift   = dict["spiritualGift"]   as? String
    }
}

struct PrayerSentimentDataPoint: Identifiable {
    let prayerId: String
    let date: String
    let score: Double
    let dominantTone: String

    var id: String { prayerId }
}

struct PrayerWellnessData {
    let dataPoints: [PrayerSentimentDataPoint]
    let trend: Double         // positive = improving, negative = declining
    let currentScore: Double
    let overallAvg: Double
    let prayerCount: Int
    let weekOf: String

    /// Human-readable trend description
    var trendDescription: String {
        switch trend {
        case ..<(-1.5): return "Your prayers suggest a difficult season. You are seen and loved."
        case -1.5..<(-0.5): return "Things feel heavy lately. Keep bringing it to God."
        case -0.5..<0.5:    return "Your prayer life shows steady faithfulness."
        case 0.5..<1.5:     return "There's growing peace and hope in your recent prayers."
        default:            return "Your prayers reflect a season of joy and gratitude."
        }
    }

    /// Maps overallAvg (-5…5) to a SpiritualMood-like label
    var overallMoodLabel: String {
        switch overallAvg {
        case ..<(-2): return "Struggling"
        case -2..<(-0.5): return "Seeking Help"
        case -0.5..<0.5:  return "Steady"
        case 0.5..<2:     return "Growing"
        default:          return "Flourishing"
        }
    }
}

// MARK: - Service

@MainActor
final class SemanticEmbeddingService: ObservableObject {

    static let shared = SemanticEmbeddingService()
    private init() {}

    private let functions = Functions.functions(region: "us-central1")
    private let db        = Firestore.firestore()

    // MARK: - In-Memory Session Cache

    private var scriptureCache: [String: [ScriptureRecommendation]] = [:]
    private var testimonyCache:  [String: [SimilarTestimony]]        = [:]
    private var partnerCache:    [String: [PrayerPartnerMatch]]      = [:]

    // MARK: - Scripture Recommendation

    /// Returns up to `limit` Bible verses semantically relevant to `text`.
    /// `postId` is used as a Firestore cache key server-side so repeated calls for
    /// the same post never re-embed.
    func getScriptureRecommendation(
        for text: String,
        postId: String? = nil,
        limit: Int = 3
    ) async throws -> [ScriptureRecommendation] {
        let cacheKey = postId ?? text.prefix(60).description
        if let cached = scriptureCache[cacheKey] { return cached }

        var params: [String: Any] = ["text": text, "limit": limit]
        if let postId { params["postId"] = postId }

        let result = try await functions.httpsCallable("getScriptureRecommendation").safeCall(params)
        guard let data = result.data as? [String: Any],
              let rawList = data["scriptures"] as? [[String: Any]] else {
            return []
        }

        let scriptures = rawList.map { ScriptureRecommendation(from: $0) }
        scriptureCache[cacheKey] = scriptures
        return scriptures
    }

    // MARK: - Similar Testimonies

    /// Returns testimonies semantically similar to `postId`.
    /// Only works for posts with category "testimonies".
    func findSimilarTestimonies(to postId: String, limit: Int = 5) async throws -> [SimilarTestimony] {
        if let cached = testimonyCache[postId] { return cached }

        let result = try await functions.httpsCallable("findSimilarTestimonies").safeCall([
            "postId": postId,
            "limit": limit,
        ])

        guard let data = result.data as? [String: Any],
              let rawList = data["testimonies"] as? [[String: Any]] else {
            return []
        }

        let testimonies = rawList.map { SimilarTestimony(from: $0) }
        testimonyCache[postId] = testimonies
        return testimonies
    }

    // MARK: - Prayer Partner Matching

    /// Finds users whose prayer topics are semantically similar to `prayerText`.
    /// Also upserts the caller into the prayer-partner-pool for discoverability.
    func matchPrayerPartners(for prayerText: String, prayerId: String? = nil) async throws -> [PrayerPartnerMatch] {
        let cacheKey = prayerId ?? prayerText.prefix(60).description
        if let cached = partnerCache[cacheKey] { return cached }

        var params: [String: Any] = ["prayerText": prayerText]
        if let prayerId { params["prayerId"] = prayerId }

        let result = try await functions.httpsCallable("matchPrayerPartners").safeCall(params)
        guard let data = result.data as? [String: Any],
              let rawList = data["partners"] as? [[String: Any]] else {
            return []
        }

        let partners = rawList.map { PrayerPartnerMatch(from: $0) }
        partnerCache[cacheKey] = partners
        return partners
    }

    // MARK: - Prayer Wellness Data

    /// Reads the pre-computed prayer sentiment data from Firestore.
    /// The `trackPrayerSentimentWellness` Cloud Function refreshes this weekly.
    func fetchPrayerWellness() async throws -> PrayerWellnessData? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }

        let doc = try await db.collection("users").document(uid)
            .collection("wellness").document("prayerSentiment")
            .getDocument()

        guard doc.exists, let d = doc.data() else { return nil }

        let rawPoints = d["dataPoints"] as? [[String: Any]] ?? []
        let dataPoints = rawPoints.map { point in
            PrayerSentimentDataPoint(
                prayerId:     point["prayerId"]     as? String ?? "",
                date:         point["date"]         as? String ?? "",
                score:        point["score"]        as? Double ?? 0,
                dominantTone: point["dominantTone"] as? String ?? "neutral"
            )
        }

        return PrayerWellnessData(
            dataPoints:   dataPoints,
            trend:        d["trend"]        as? Double ?? 0,
            currentScore: d["currentScore"] as? Double ?? 0,
            overallAvg:   d["overallAvg"]   as? Double ?? 0,
            prayerCount:  d["prayerCount"]  as? Int    ?? 0,
            weekOf:       d["weekOf"]       as? String ?? ""
        )
    }

    // MARK: - Cache Management

    func clearSessionCache() {
        scriptureCache.removeAll()
        testimonyCache.removeAll()
        partnerCache.removeAll()
    }
}
