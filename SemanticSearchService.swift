//
//  SemanticSearchService.swift
//  AMENAPP
//
//  OpenAI Embeddings-powered semantic search for "More Like This" recommendations
//  Uses text-embedding-3-large model for 1536-dimensional embeddings
//

import Foundation
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

/// Enterprise-grade semantic search using OpenAI embeddings
class SemanticSearchService {
    static let shared = SemanticSearchService()
    private let db = Firestore.firestore()
    
    // OpenAI Configuration
    private let openAIAPIKey = "" // TODO: Add from Firebase Remote Config
    private let embeddingModel = "text-embedding-3-large"
    private let embeddingDimensions = 1536
    
    // Caching
    private var embeddingCache: [String: [Double]] = [:]
    private var lastCacheClean: Date = Date()
    private let cacheMaxAge: TimeInterval = 3600 // 1 hour
    private let cacheMaxSize = 100 // Max 100 embeddings in memory
    
    private init() {}
    
    // MARK: - Embedding Generation
    
    /// Generate embedding for content using OpenAI text-embedding-3-large
    func generateEmbedding(for content: String) async throws -> [Double] {
        // Check cache first
        if let cached = embeddingCache[content] {
            print("📦 [CACHE HIT] Using cached embedding")
            return cached
        }
        
        guard !openAIAPIKey.isEmpty else {
            throw NSError(
                domain: "SemanticSearch",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "OpenAI API key not configured"]
            )
        }
        
        // Clean cache if too large
        if embeddingCache.count > cacheMaxSize {
            cleanCache()
        }
        
        let url = URL(string: "https://api.openai.com/v1/embeddings")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(openAIAPIKey)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "input": content,
            "model": embeddingModel,
            "encoding_format": "float"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("🔮 [EMBEDDING] Generating for content (\(content.count) chars)...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "SemanticSearch", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(
                domain: "SemanticSearch",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "OpenAI API error: \(errorMsg)"]
            )
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let dataArray = json?["data"] as? [[String: Any]],
              let firstResult = dataArray.first,
              let embedding = firstResult["embedding"] as? [Double] else {
            throw NSError(domain: "SemanticSearch", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid embedding response"])
        }
        
        // Cache the result
        embeddingCache[content] = embedding
        
        print("✅ [EMBEDDING] Generated \(embedding.count)-dimensional vector")
        
        return embedding
    }
    
    /// Generate and store embedding for a post
    func storePostEmbedding(postId: String, content: String) async throws {
        // Check if embedding already exists
        let existingDoc = try await db.collection("postEmbeddings")
            .whereField("postId", isEqualTo: postId)
            .limit(to: 1)
            .getDocuments()
        
        if !existingDoc.documents.isEmpty {
            print("ℹ️ [EMBEDDING] Already exists for post \(postId)")
            return
        }
        
        // Generate embedding
        let embedding = try await generateEmbedding(for: content)
        
        // Store in Firestore
        let embeddingDoc = PostEmbedding(
            postId: postId,
            embedding: embedding,
            content: String(content.prefix(200)), // Store snippet
            createdAt: Date(),
            modelVersion: embeddingModel
        )
        
        try db.collection("postEmbeddings").document(postId).setData(from: embeddingDoc)
        
        print("💾 [EMBEDDING] Stored for post \(postId)")
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
    
    /// Find similar posts using semantic similarity
    func findSimilarPosts(to postId: String, limit: Int = 10, minSimilarity: Double = 0.7) async throws -> [SimilarPost] {
        // Get the target post's embedding
        let targetDoc = try await db.collection("postEmbeddings")
            .document(postId)
            .getDocument()
        
        guard targetDoc.exists,
              let targetEmbedding = try? targetDoc.data(as: PostEmbedding.self) else {
            throw NSError(
                domain: "SemanticSearch",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Post embedding not found"]
            )
        }
        
        print("🔍 [SEARCH] Finding similar posts to \(postId)...")
        
        // Fetch all embeddings (TODO: Use vector database like Pinecone for scale)
        let allEmbeddings = try await db.collection("postEmbeddings")
            .limit(to: 500) // Limit for performance
            .getDocuments()
        
        var similarPosts: [SimilarPost] = []
        
        for doc in allEmbeddings.documents {
            guard let embedding = try? doc.data(as: PostEmbedding.self),
                  embedding.postId != postId else { // Exclude the target post itself
                continue
            }
            
            let similarity = cosineSimilarity(targetEmbedding.embedding, embedding.embedding)
            
            if similarity >= minSimilarity {
                similarPosts.append(SimilarPost(
                    id: doc.documentID,
                    postId: embedding.postId,
                    similarityScore: similarity,
                    content: embedding.content
                ))
            }
        }
        
        // Sort by similarity (highest first) and limit
        let topResults = similarPosts
            .sorted { $0.similarityScore > $1.similarityScore }
            .prefix(limit)
        
        print("✅ [SEARCH] Found \(topResults.count) similar posts")
        
        return Array(topResults)
    }
    
    /// Find posts similar to given text (for "more like this" search)
    func findPostsSimilarToText(_ text: String, limit: Int = 10, minSimilarity: Double = 0.7) async throws -> [SimilarPost] {
        // Generate embedding for the search text
        let searchEmbedding = try await generateEmbedding(for: text)
        
        print("🔍 [SEARCH] Finding posts similar to text (\(text.count) chars)...")
        
        // Fetch all embeddings
        let allEmbeddings = try await db.collection("postEmbeddings")
            .limit(to: 500)
            .getDocuments()
        
        var similarPosts: [SimilarPost] = []
        
        for doc in allEmbeddings.documents {
            guard let embedding = try? doc.data(as: PostEmbedding.self) else {
                continue
            }
            
            let similarity = cosineSimilarity(searchEmbedding, embedding.embedding)
            
            if similarity >= minSimilarity {
                similarPosts.append(SimilarPost(
                    id: doc.documentID,
                    postId: embedding.postId,
                    similarityScore: similarity,
                    content: embedding.content
                ))
            }
        }
        
        // Sort and limit
        let topResults = similarPosts
            .sorted { $0.similarityScore > $1.similarityScore }
            .prefix(limit)
        
        print("✅ [SEARCH] Found \(topResults.count) similar posts")
        
        return Array(topResults)
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
    
    /// Get embedding statistics
    func getEmbeddingStats() async throws -> EmbeddingStats {
        let snapshot = try await db.collection("postEmbeddings").getDocuments()
        
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
        try await SemanticSearchService.shared.storePostEmbedding(
            postId: id.uuidString,
            content: content
        )
    }
    
    /// Find similar posts
    func findSimilar(limit: Int = 10) async throws -> [SimilarPost] {
        try await SemanticSearchService.shared.findSimilarPosts(
            to: id.uuidString,
            limit: limit
        )
    }
}
