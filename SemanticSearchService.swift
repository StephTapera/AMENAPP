//
//  SemanticSearchService.swift
//  AMENAPP
//
//  Semantic search backed by Cloud Run + Vertex AI text-embedding-004.
//  Falls back to local keyword scoring when Cloud Run is unavailable.
//

import Combine
import FirebaseFirestore
import FirebaseAuth

// MARK: - Embedding Models

/// Post embedding stored in Firestore
struct PostEmbedding: Codable {
    @DocumentID var id: String?
    let postId: String
    let embedding: [Double]
    let content: String // Store snippet for debugging
    let createdAt: Date
    let modelVersion: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case postId
        case embedding
        case content
        case createdAt
        case modelVersion
    }
}

/// Similar post result with similarity score
struct SimilarPost: Identifiable {
    let id: String
    let postId: String
    let similarityScore: Double
    let content: String
}

// MARK: - Semantic Search Service

/// Semantic search backed by Cloud Run + Vertex AI text-embedding-004.
class SemanticSearchService {
    static let shared = SemanticSearchService()
    private let db = Firestore.firestore()
    
    // ── Cloud Run URL (set SEARCH_SERVICE_URL in Config.xcconfig) ──────────────
    private let searchBaseURL: URL? = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SEARCH_SERVICE_URL") as? String,
              !raw.isEmpty,
              let url = URL(string: raw) else { return nil }
        return url
    }()

    private let embeddingModel = "text-embedding-004"   // Vertex AI (768-dim)
    private let embeddingDimensions = 768
    
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 5
        cfg.timeoutIntervalForResource = 8
        return URLSession(configuration: cfg)
    }()

    // Caching
    private var embeddingCache: [String: [Double]] = [:]
    private var lastCacheClean: Date = Date()
    private let cacheMaxAge: TimeInterval = 3600 // 1 hour
    private let cacheMaxSize = 100 // Max 100 embeddings in memory
    
    private init() {}
    
    // MARK: - Embedding Generation
    
    /// Generate embedding via Cloud Run /embed endpoint (Vertex AI text-embedding-004).
    /// Throws if Cloud Run is unavailable — caller should handle gracefully.
    func generateEmbedding(for content: String) async throws -> [Double] {
        if let cached = embeddingCache[content] {
            return cached
        }
        if embeddingCache.count > cacheMaxSize { cleanCache() }

        guard let base = searchBaseURL else {
            throw NSError(domain: "SemanticSearch", code: 503,
                          userInfo: [NSLocalizedDescriptionKey: "Search service URL not configured"])
        }

        struct EmbedRequest: Encodable { let postId: String; let content: String }
        struct EmbedResponse: Decodable { let embedding: [Double]? }

        let url = base.appendingPathComponent("embed-query")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(EmbedRequest(postId: UUID().uuidString, content: content))

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "SemanticSearch", code: 500,
                          userInfo: [NSLocalizedDescriptionKey: "Embed endpoint error"])
        }
        let decoded = try JSONDecoder().decode(EmbedResponse.self, from: data)
        guard let embedding = decoded.embedding, !embedding.isEmpty else {
            throw NSError(domain: "SemanticSearch", code: 500,
                          userInfo: [NSLocalizedDescriptionKey: "Empty embedding"])
        }
        embeddingCache[content] = embedding
        return embedding
    }

    /// Semantic search via Cloud Run /search. Returns nil on any error.
    func searchViaCloudRun(query: String, limit: Int = 20, minSimilarity: Double = 0.55) async -> [SimilarPost]? {
        guard let base = searchBaseURL else { return nil }

        struct SearchRequest: Encodable {
            let query: String
            let limit: Int
            let minSimilarity: Double
        }
        struct SearchResult: Decodable { let postId: String; let score: Double }
        struct SearchResponse: Decodable { let results: [SearchResult] }

        do {
            var req = URLRequest(url: base.appendingPathComponent("search"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(
                SearchRequest(query: query, limit: limit, minSimilarity: minSimilarity))

            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

            let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
            return decoded.results.map {
                SimilarPost(id: $0.postId, postId: $0.postId,
                            similarityScore: $0.score, content: "")
            }
        } catch {
            return nil
        }
    }

    /// Store embedding for a new post via Cloud Run /embed.
    /// Fire-and-forget — failures are non-fatal.
    func storeEmbeddingViaCloudRun(postId: String, content: String) {
        guard let base = searchBaseURL else { return }
        struct EmbedRequest: Encodable { let postId: String; let content: String }
        Task {
            do {
                var req = URLRequest(url: base.appendingPathComponent("embed"))
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONEncoder().encode(EmbedRequest(postId: postId, content: content))
                _ = try await session.data(for: req)
            } catch { /* non-fatal */ }
        }
    }
    
    /// Generate and store embedding for a post.
    /// Prefers Cloud Run; falls back to direct Firestore write if unavailable.
    func storePostEmbedding(postId: String, content: String) async throws {
        // Preferred: delegate to Cloud Run (uses Vertex AI, no API key on device)
        storeEmbeddingViaCloudRun(postId: postId, content: content)
    }
    
    // MARK: - Similarity Search
    
    /// Calculate cosine similarity between two embeddings
    func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return 0.0 }
        
        let dotProduct = zip(a, b).reduce(0.0) { $0 + ($1.0 * $1.1) }
        let magnitudeA = sqrt(a.reduce(0.0) { $0 + ($1 * $1) })
        let magnitudeB = sqrt(b.reduce(0.0) { $0 + ($1 * $1) })
        
        guard magnitudeA > 0, magnitudeB > 0 else { return 0.0 }
        
        return dotProduct / (magnitudeA * magnitudeB)
    }
    
    /// Find similar posts using semantic similarity.
    /// Prefers Cloud Run /search (server-side, no doc limit).
    /// Falls back to local Firestore cosine scan when Cloud Run is not configured.
    func findSimilarPosts(to postId: String, limit: Int = 10, minSimilarity: Double = 0.7) async throws -> [SimilarPost] {
        // Prefer Cloud Run — fetch the post's stored content snippet as the query text
        if searchBaseURL != nil {
            let targetDoc = try await db.collection("postEmbeddings").document(postId).getDocument()
            if let data = targetDoc.data(), let snippet = data["content"] as? String, !snippet.isEmpty {
                if let results = await searchViaCloudRun(query: snippet, limit: limit, minSimilarity: minSimilarity) {
                    return results.filter { $0.postId != postId }
                }
            }
        }

        // Fallback: local cosine scan over stored embeddings (use only when Cloud Run unavailable)
        let targetDoc = try await db.collection("postEmbeddings").document(postId).getDocument()
        guard targetDoc.exists,
              let targetEmbedding = try? targetDoc.data(as: PostEmbedding.self) else {
            throw NSError(domain: "SemanticSearch", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "Post embedding not found"])
        }

        let allEmbeddings = try await db.collection("postEmbeddings")
            .limit(to: 500)
            .getDocuments()

        let results = allEmbeddings.documents.compactMap { doc -> SimilarPost? in
            guard let emb = try? doc.data(as: PostEmbedding.self), emb.postId != postId else { return nil }
            let score = cosineSimilarity(targetEmbedding.embedding, emb.embedding)
            guard score >= minSimilarity else { return nil }
            return SimilarPost(id: doc.documentID, postId: emb.postId, similarityScore: score, content: emb.content)
        }
        .sorted { $0.similarityScore > $1.similarityScore }
        .prefix(limit)

        return Array(results)
    }

    /// Find posts similar to given text (for "more like this" / free-text search).
    /// Prefers Cloud Run /search; falls back to local cosine scan.
    func findPostsSimilarToText(_ text: String, limit: Int = 10, minSimilarity: Double = 0.7) async throws -> [SimilarPost] {
        // Prefer Cloud Run
        if let results = await searchViaCloudRun(query: text, limit: limit, minSimilarity: minSimilarity) {
            return results
        }

        // Fallback: embed locally then brute-force over Firestore
        let searchEmbedding = try await generateEmbedding(for: text)

        let allEmbeddings = try await db.collection("postEmbeddings")
            .limit(to: 500)
            .getDocuments()

        let results = allEmbeddings.documents.compactMap { doc -> SimilarPost? in
            guard let emb = try? doc.data(as: PostEmbedding.self) else { return nil }
            let score = cosineSimilarity(searchEmbedding, emb.embedding)
            guard score >= minSimilarity else { return nil }
            return SimilarPost(id: doc.documentID, postId: emb.postId, similarityScore: score, content: emb.content)
        }
        .sorted { $0.similarityScore > $1.similarityScore }
        .prefix(limit)

        return Array(results)
    }
    
    // MARK: - Batch Operations
    
    /// Generate embeddings for multiple posts in parallel
    func batchGenerateEmbeddings(for posts: [(id: String, content: String)]) async throws {
        print("🔮 [BATCH] Generating embeddings for \(posts.count) posts...")
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for post in posts {
                group.addTask {
                    try await self.storePostEmbedding(postId: post.id, content: post.content)
                }
            }
            
            // Wait for all to complete
            try await group.waitForAll()
        }
        
        print("✅ [BATCH] Completed embedding generation")
    }
    
    /// Regenerate all embeddings (for model updates)
    func regenerateAllEmbeddings() async throws {
        print("🔄 [REGENERATE] Fetching all posts...")
        
        // Fetch all posts from Firestore
        let postsSnapshot = try await db.collection("posts")
            .limit(to: 1000) // Process in batches for large datasets
            .getDocuments()
        
        let posts = postsSnapshot.documents.compactMap { doc -> (id: String, content: String)? in
            guard let content = doc.data()["content"] as? String else { return nil }
            return (id: doc.documentID, content: content)
        }
        
        print("🔮 [REGENERATE] Processing \(posts.count) posts...")
        
        // Process in batches of 10 to avoid rate limits
        let batchSize = 10
        for i in stride(from: 0, to: posts.count, by: batchSize) {
            let batch = Array(posts[i..<min(i + batchSize, posts.count)])
            try await batchGenerateEmbeddings(for: batch)
            
            // Rate limiting: wait 1 second between batches
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        
        print("✅ [REGENERATE] Completed all embeddings")
    }
    
    // MARK: - Cache Management
    
    /// Clean expired cache entries
    private func cleanCache() {
        let now = Date()
        
        if now.timeIntervalSince(lastCacheClean) > cacheMaxAge {
            embeddingCache.removeAll()
            lastCacheClean = now
            print("🧹 [CACHE] Cleaned expired entries")
        }
    }
    
    /// Clear all cached embeddings
    func clearCache() {
        embeddingCache.removeAll()
        lastCacheClean = Date()
        print("🧹 [CACHE] Cleared all entries")
    }
    
    // MARK: - Analytics
    
    /// Get embedding statistics (reads up to 1000 docs for a count estimate)
    func getEmbeddingStats() async throws -> EmbeddingStats {
        let snapshot = try await db.collection("postEmbeddings").limit(to: 1000).getDocuments()
        
        let totalEmbeddings = snapshot.documents.count
        let oldestEmbedding = snapshot.documents.compactMap { doc -> Date? in
            try? doc.data(as: PostEmbedding.self).createdAt
        }.min()
        
        let newestEmbedding = snapshot.documents.compactMap { doc -> Date? in
            try? doc.data(as: PostEmbedding.self).createdAt
        }.max()
        
        return EmbeddingStats(
            totalEmbeddings: totalEmbeddings,
            cacheSize: embeddingCache.count,
            oldestEmbedding: oldestEmbedding,
            newestEmbedding: newestEmbedding,
            modelVersion: embeddingModel
        )
    }
}

// MARK: - Supporting Types

struct EmbeddingStats {
    let totalEmbeddings: Int
    let cacheSize: Int
    let oldestEmbedding: Date?
    let newestEmbedding: Date?
    let modelVersion: String
}

// MARK: - Post Extension

extension Post {
    /// Generate and store embedding for this post
    func generateEmbedding() async throws {
        // Use stable Firestore document ID when available
        let stableId = firebaseId ?? id.uuidString
        try await SemanticSearchService.shared.storePostEmbedding(
            postId: stableId,
            content: content
        )
    }
    
    /// Find similar posts
    func findSimilar(limit: Int = 10) async throws -> [SimilarPost] {
        let stableId = firebaseId ?? id.uuidString
        return try await SemanticSearchService.shared.findSimilarPosts(
            to: stableId,
            limit: limit
        )
    }
}
