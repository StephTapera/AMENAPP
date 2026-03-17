//
//  PrayerMatchingService.swift
//  AMENAPP
//
//  Smart Prayer Matching — uses text embeddings to find users praying
//  for semantically similar things. "struggling with anxiety" matches
//  "fear and worry" and "trusting God through hard times."
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
class PrayerMatchingService: ObservableObject {
    static let shared = PrayerMatchingService()

    @Published var similarPrayers: [SimilarPrayer] = []
    @Published var isMatching = false

    private let db = Firestore.firestore()
    private var matchCache: [String: (prayers: [SimilarPrayer], cachedAt: Date)] = [:]
    private let cacheTTL: TimeInterval = 86400 // 24 hours

    private init() {}

    // MARK: - Models

    struct SimilarPrayer: Identifiable, Codable {
        let id: String // prayer request ID
        let authorName: String
        let authorProfileImageURL: String?
        let preview: String // first 80 chars
        let similarityScore: Float
    }

    // MARK: - Public API

    /// Find prayers semantically similar to the given text.
    /// Results are cached for 24 hours per prayer ID.
    func findSimilarPrayers(forPrayerID prayerID: String, text: String) async {
        // Check cache
        if let cached = matchCache[prayerID],
           Date().timeIntervalSince(cached.cachedAt) < cacheTTL {
            similarPrayers = cached.prayers
            return
        }

        guard let currentUID = Auth.auth().currentUser?.uid else { return }

        isMatching = true
        defer { isMatching = false }

        do {
            // Generate embedding for this prayer
            let embedding = try await generateEmbedding(for: text)

            // Store embedding on the prayer document
            try await db.collection("posts").document(prayerID).updateData([
                "embedding": embedding,
            ])

            // Fetch recent prayer requests (last 30 days, not from current user)
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            let snapshot = try await db.collection("posts")
                .whereField("category", isEqualTo: "prayer")
                .whereField("createdAt", isGreaterThan: Timestamp(date: thirtyDaysAgo))
                .order(by: "createdAt", descending: true)
                .limit(to: 200)
                .getDocuments()

            var matches: [SimilarPrayer] = []

            for doc in snapshot.documents {
                let data = doc.data()
                let authorId = data["authorId"] as? String ?? data["userId"] as? String ?? ""

                // Skip own prayers
                guard authorId != currentUID else { continue }
                guard doc.documentID != prayerID else { continue }

                // Get stored embedding
                guard let otherEmbedding = data["embedding"] as? [Double] else { continue }
                let otherFloats = otherEmbedding.map { Float($0) }

                let similarity = cosineSimilarity(embedding, otherFloats)

                if similarity > 0.75 {
                    let preview = String((data["content"] as? String ?? "").prefix(80))
                    let authorName = data["authorName"] as? String ?? "Someone"
                    let authorPhoto = data["authorProfileImageURL"] as? String

                    matches.append(SimilarPrayer(
                        id: doc.documentID,
                        authorName: authorName,
                        authorProfileImageURL: authorPhoto,
                        preview: preview,
                        similarityScore: similarity
                    ))
                }
            }

            // Sort by similarity, take top 5
            matches.sort { $0.similarityScore > $1.similarityScore }
            let topMatches = Array(matches.prefix(5))

            // Store matches on the prayer document
            let matchIDs = topMatches.map { $0.id }
            try? await db.collection("posts").document(prayerID).updateData([
                "similarPrayers": matchIDs,
                "matchedAt": FieldValue.serverTimestamp(),
            ])

            // Cache and publish
            matchCache[prayerID] = (prayers: topMatches, cachedAt: Date())
            similarPrayers = topMatches

        } catch {
            dlog("Prayer matching failed: \(error.localizedDescription)")
            similarPrayers = []
        }
    }

    // MARK: - Embedding Generation

    private func generateEmbedding(for text: String) async throws -> [Float] {
        let trimmed = String(text.prefix(500))

        // Call Cloud Function to generate embedding
        let result = try await CloudFunctionsService.shared.call(
            "bereanPostAssist",
            data: [
                "postContent": trimmed,
                "purpose": "generate_embedding",
            ] as [String: Any]
        )

        // If the Cloud Function returns an embedding array, use it
        if let dict = result as? [String: Any],
           let embeddingArray = dict["embedding"] as? [Double] {
            return embeddingArray.map { Float($0) }
        }

        // Fallback: generate a simple keyword-based embedding
        return generateKeywordEmbedding(for: trimmed)
    }

    /// Simple keyword-based embedding as fallback when AI embedding is unavailable.
    private func generateKeywordEmbedding(for text: String) -> [Float] {
        let keywords = [
            "anxiety", "fear", "worry", "peace", "healing", "health", "sick",
            "family", "marriage", "children", "job", "work", "finance", "money",
            "faith", "trust", "hope", "love", "forgiveness", "grief", "loss",
            "guidance", "direction", "purpose", "strength", "courage", "patience",
            "addiction", "depression", "loneliness", "community", "church",
            "salvation", "grace", "mercy", "praise", "thanksgiving", "worship",
            "protection", "safety", "travel", "relationship", "friendship",
        ]

        let lower = text.lowercased()
        return keywords.map { keyword in
            lower.contains(keyword) ? Float(1.0) : Float(0.0)
        }
    }

    // MARK: - Cosine Similarity

    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot = zip(a, b).map(*).reduce(0, +)
        let magA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        guard magA > 0 && magB > 0 else { return 0 }
        return dot / (magA * magB)
    }
}
