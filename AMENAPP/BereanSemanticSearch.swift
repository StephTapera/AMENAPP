//
//  BereanSemanticSearch.swift
//  AMENAPP
//
//  Vector-based semantic search over the Bible.
//  Embeds Bible chapters using Vertex AI embeddings (via Cloud Function),
//  stores vectors locally + in Firestore, and retrieves the top-K
//  most relevant passages for any user query.
//
//  This transforms Berean from "answer about verses you name" →
//  "find verses you didn't know existed."
//
//  Architecture:
//  - Cloud Function `bereanEmbedText` generates embeddings (768-dim)
//  - Local cache stores embeddings for offline + fast retrieval
//  - Cosine similarity ranks passages against query embedding
//  - Top-K results injected into BereanAnswerEngine context
//

import Foundation
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Embedding Models

struct BibleChapterEmbedding: Codable, Identifiable {
    let id: String              // e.g., "GEN.1"
    let book: String            // e.g., "Genesis"
    let chapter: Int
    let summary: String         // 1-2 sentence chapter summary for display
    let keyVerses: [String]     // Notable verse references in this chapter
    let embedding: [Float]      // 768-dimensional vector
    let version: String         // Bible version used
    let updatedAt: Date
}

struct SemanticSearchResult: Identifiable {
    let id: String
    let book: String
    let chapter: Int
    let summary: String
    let keyVerses: [String]
    let similarityScore: Double
    let relevantPassages: [ScripturePassage]
}

struct RAGContext {
    let query: String
    let retrievedPassages: [SemanticSearchResult]
    let formattedContext: String  // Ready to inject into prompt

    var topReferences: [String] {
        retrievedPassages.flatMap { $0.keyVerses }
    }
}

// MARK: - Semantic Search Service

@MainActor
final class BereanSemanticSearch: ObservableObject {
    static let shared = BereanSemanticSearch()

    @Published var isIndexReady = false
    @Published var indexProgress: Double = 0.0
    @Published var isSearching = false

    private let functions = Functions.functions()
    private let db = Firestore.firestore()

    // Local embedding index (loaded from Firestore/cache)
    private var embeddingIndex: [BibleChapterEmbedding] = []
    private let embeddingDimension = 768
    private let maxResults = 5
    private let similarityThreshold: Double = 0.3

    // Cache
    private var queryEmbeddingCache: [String: [Float]] = [:]
    private let maxCacheSize = 200

    private init() {
        Task { await loadIndex() }
    }

    // MARK: - Index Management

    /// Load the Bible embedding index from Firestore cache
    func loadIndex() async {
        print("📖 SemanticSearch: Loading Bible embedding index...")

        // Try local cache first
        if let cached = loadLocalIndex() {
            embeddingIndex = cached
            isIndexReady = true
            print("✅ SemanticSearch: Loaded \(cached.count) chapter embeddings from cache")
            return
        }

        // Fetch from Firestore
        do {
            let snapshot = try await db.collection("berean_embeddings")
                .order(by: "updatedAt", descending: true)
                .limit(to: 1189)  // All Bible chapters
                .getDocuments()

            embeddingIndex = snapshot.documents.compactMap { doc in
                try? doc.data(as: BibleChapterEmbedding.self)
            }

            if !embeddingIndex.isEmpty {
                isIndexReady = true
                saveLocalIndex()
                print("✅ SemanticSearch: Loaded \(embeddingIndex.count) embeddings from Firestore")
            } else {
                print("⚠️ SemanticSearch: No embeddings found — index needs to be built")
            }
        } catch {
            print("❌ SemanticSearch: Failed to load index: \(error.localizedDescription)")
        }
    }

    /// Build or refresh the embedding index (call from admin/setup)
    func buildIndex(books: [String]? = nil) async {
        print("🔨 SemanticSearch: Building embedding index...")

        let targetBooks = books ?? allBibleBooks
        let total = targetBooks.count

        for (index, book) in targetBooks.enumerated() {
            indexProgress = Double(index) / Double(total)

            do {
                let result = try await functions.httpsCallable("bereanEmbedChapters").call([
                    "book": book
                ])

                if let data = result.data as? [[String: Any]] {
                    for chapterData in data {
                        if let embedding = parseBibleChapterEmbedding(from: chapterData) {
                            // Store in Firestore
                            try await db.collection("berean_embeddings")
                                .document(embedding.id)
                                .setData(from: embedding)

                            embeddingIndex.append(embedding)
                        }
                    }
                }

                print("✅ SemanticSearch: Indexed \(book)")
            } catch {
                print("⚠️ SemanticSearch: Failed to index \(book): \(error.localizedDescription)")
            }
        }

        isIndexReady = true
        indexProgress = 1.0
        saveLocalIndex()
        print("✅ SemanticSearch: Index complete — \(embeddingIndex.count) chapters")
    }

    // MARK: - Semantic Search

    /// Search the Bible semantically — returns the most relevant chapters/passages
    func search(query: String, topK: Int? = nil) async -> [SemanticSearchResult] {
        guard isIndexReady, !embeddingIndex.isEmpty else {
            print("⚠️ SemanticSearch: Index not ready")
            return []
        }

        isSearching = true
        defer { isSearching = false }

        let k = topK ?? maxResults

        // 1. Get query embedding
        guard let queryEmbedding = await getQueryEmbedding(query) else {
            print("❌ SemanticSearch: Failed to embed query")
            return []
        }

        // 2. Compute cosine similarity against all chapters
        var scored: [(BibleChapterEmbedding, Double)] = []

        for chapter in embeddingIndex {
            let similarity = cosineSimilarity(queryEmbedding, chapter.embedding)
            if similarity >= similarityThreshold {
                scored.append((chapter, similarity))
            }
        }

        // 3. Sort by similarity and take top K
        scored.sort { $0.1 > $1.1 }
        let topResults = scored.prefix(k)

        // 4. Fetch actual verse text for top results
        var results: [SemanticSearchResult] = []

        for (chapter, score) in topResults {
            // Fetch key verses for this chapter
            let passages = await fetchKeyVerses(chapter: chapter)

            results.append(SemanticSearchResult(
                id: chapter.id,
                book: chapter.book,
                chapter: chapter.chapter,
                summary: chapter.summary,
                keyVerses: chapter.keyVerses,
                similarityScore: score,
                relevantPassages: passages
            ))
        }

        print("🔍 SemanticSearch: Found \(results.count) results for '\(query.prefix(40))'")
        return results
    }

    /// Build RAG context for a query — ready to inject into AI prompt
    func buildRAGContext(query: String) async -> RAGContext {
        let results = await search(query: query)

        // Format retrieved passages for prompt injection
        var contextParts: [String] = []

        for (index, result) in results.enumerated() {
            var part = "[\(index + 1)] \(result.book) \(result.chapter)"
            part += " (relevance: \(Int(result.similarityScore * 100))%)"
            part += "\n  Summary: \(result.summary)"

            if !result.relevantPassages.isEmpty {
                let verseTexts = result.relevantPassages.map { passage in
                    "  \(passage.reference): \"\(passage.text)\""
                }.joined(separator: "\n")
                part += "\n  Key verses:\n\(verseTexts)"
            } else {
                part += "\n  Key verses: \(result.keyVerses.joined(separator: ", "))"
            }

            contextParts.append(part)
        }

        let formatted = contextParts.isEmpty
            ? ""
            : "[RETRIEVED SCRIPTURE CONTEXT — cite these passages]\n" + contextParts.joined(separator: "\n\n")

        return RAGContext(
            query: query,
            retrievedPassages: results,
            formattedContext: formatted
        )
    }

    // MARK: - Query Embedding

    private func getQueryEmbedding(_ query: String) async -> [Float]? {
        // Check cache
        let cacheKey = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let cached = queryEmbeddingCache[cacheKey] {
            return cached
        }

        // Call Cloud Function for embedding
        do {
            let result = try await functions.httpsCallable("bereanEmbedText").call([
                "text": query
            ])

            guard let data = result.data as? [String: Any],
                  let embeddingArray = data["embedding"] as? [NSNumber] else {
                return nil
            }

            let embedding = embeddingArray.map { Float(truncating: $0) }

            // Cache it
            queryEmbeddingCache[cacheKey] = embedding
            if queryEmbeddingCache.count > maxCacheSize {
                // Remove oldest entries
                let keysToRemove = Array(queryEmbeddingCache.keys.prefix(maxCacheSize / 5))
                for key in keysToRemove {
                    queryEmbeddingCache.removeValue(forKey: key)
                }
            }

            return embedding
        } catch {
            print("❌ SemanticSearch: Embedding failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Cosine Similarity

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0.0 }

        return Double(dotProduct / denominator)
    }

    // MARK: - Verse Fetching

    private func fetchKeyVerses(chapter: BibleChapterEmbedding) async -> [ScripturePassage] {
        let youVersion = YouVersionBibleService.shared

        do {
            return try await youVersion.fetchVerses(
                references: Array(chapter.keyVerses.prefix(3))
            )
        } catch {
            return []
        }
    }

    // MARK: - Local Cache

    private func loadLocalIndex() -> [BibleChapterEmbedding]? {
        guard let data = UserDefaults.standard.data(forKey: "berean_embedding_index") else {
            return nil
        }

        return try? JSONDecoder().decode([BibleChapterEmbedding].self, from: data)
    }

    private func saveLocalIndex() {
        guard let data = try? JSONEncoder().encode(embeddingIndex) else { return }
        UserDefaults.standard.set(data, forKey: "berean_embedding_index")
    }

    // MARK: - Parsing

    private func parseBibleChapterEmbedding(from data: [String: Any]) -> BibleChapterEmbedding? {
        guard let id = data["id"] as? String,
              let book = data["book"] as? String,
              let chapter = data["chapter"] as? Int,
              let summary = data["summary"] as? String,
              let embeddingNums = data["embedding"] as? [NSNumber] else {
            return nil
        }

        return BibleChapterEmbedding(
            id: id,
            book: book,
            chapter: chapter,
            summary: summary,
            keyVerses: data["keyVerses"] as? [String] ?? [],
            embedding: embeddingNums.map { Float(truncating: $0) },
            version: data["version"] as? String ?? "ESV",
            updatedAt: Date()
        )
    }

    // MARK: - Bible Books List

    private let allBibleBooks = [
        "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy",
        "Joshua", "Judges", "Ruth", "1 Samuel", "2 Samuel",
        "1 Kings", "2 Kings", "1 Chronicles", "2 Chronicles",
        "Ezra", "Nehemiah", "Esther", "Job", "Psalms", "Proverbs",
        "Ecclesiastes", "Song of Solomon", "Isaiah", "Jeremiah",
        "Lamentations", "Ezekiel", "Daniel", "Hosea", "Joel",
        "Amos", "Obadiah", "Jonah", "Micah", "Nahum", "Habakkuk",
        "Zephaniah", "Haggai", "Zechariah", "Malachi",
        "Matthew", "Mark", "Luke", "John", "Acts",
        "Romans", "1 Corinthians", "2 Corinthians", "Galatians",
        "Ephesians", "Philippians", "Colossians", "1 Thessalonians",
        "2 Thessalonians", "1 Timothy", "2 Timothy", "Titus",
        "Philemon", "Hebrews", "James", "1 Peter", "2 Peter",
        "1 John", "2 John", "3 John", "Jude", "Revelation"
    ]
}
