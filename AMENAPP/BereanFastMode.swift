//
//  BereanFastMode.swift
//  AMENAPP
//
//  Fast Mode architecture: caching + streaming + background prep
//  Makes Berean feel instant while maintaining quality.
//
//  Core principles:
//  - Answer cache with TTL
//  - Local-first snippets (offline verse fetch)
//  - Streaming responses (show partial, refine later)
//  - Prefetch on navigation
//

import Foundation
import Combine
import FirebaseFirestore

// MARK: - Cache Models

/// Cached Berean answer with metadata
struct CachedBereanAnswer: Codable {
    let answer: BereanAnswer
    let cacheKey: String
    let createdAt: Date
    let expiresAt: Date
    let hitCount: Int
    let containsSensitiveData: Bool
}

/// Local verse snippet for offline access
struct LocalVerseSnippet: Codable, Identifiable {
    let id: String
    let reference: String           // "John 3:16"
    let text: String
    let version: String
    let quickDefinitions: [String: String]  // Word → definition
    let cachedAt: Date
}

/// Streaming response chunk
struct StreamChunk {
    let content: String
    let isPartial: Bool
    let confidence: Double
    let metadata: StreamMetadata?
    
    struct StreamMetadata {
        let citations: [BereanCitation]?
        let estimatedRemaining: TimeInterval?
    }
}

/// Prefetch request
struct PrefetchRequest {
    let context: BereanContext
    let predictedQueries: [String]
    let priority: PrefetchPriority
    
    enum PrefetchPriority {
        case high       // User navigating to this screen now
        case medium     // Likely next screen
        case low        // Background optimization
    }
}

// MARK: - Fast Mode Service

@MainActor
class BereanFastMode: ObservableObject {
    static let shared = BereanFastMode()
    
    @Published var cacheStatus: CacheStatus = .initializing
    @Published var prefetchQueue: [PrefetchRequest] = []
    
    private let answerEngine = BereanAnswerEngine.shared
    private let router = BereanIntentRouter.shared
    
    // Multi-tier cache
    private var memoryCache: [String: CachedBereanAnswer] = [:]
    private var localVerseCache: [String: LocalVerseSnippet] = [:]
    private let db = Firestore.firestore()
    
    // Cache configuration
    private let memoryCacheTTL: TimeInterval = 3600      // 1 hour
    private let verseCacheTTL: TimeInterval = 86400      // 24 hours
    private let maxMemoryCacheSize = 100
    private let maxVerseCacheSize = 500
    
    // Rate limiting & circuit breaker
    private var requestCount: Int = 0
    private var lastResetTime = Date()
    private let requestLimit = 50  // per minute
    private var circuitBreakerOpen = false
    
    enum CacheStatus {
        case initializing
        case ready
        case degraded       // Using basic mode
        case offline
    }
    
    private init() {
        loadLocalVerseCache()
    }
    
    // MARK: - Fast Response
    
    /// Get answer as fast as possible (cache → stream → full)
    func getFastAnswer(
        query: String,
        context: BereanContext
    ) async -> AsyncStream<StreamChunk> {
        return AsyncStream { continuation in
            Task {
                // 1. Check memory cache first (fastest)
                if let cached = getFromMemoryCache(query: query, context: context) {
                    print("⚡️ FastMode: Memory cache hit")
                    continuation.yield(StreamChunk(
                        content: cached.answer.response,
                        isPartial: false,
                        confidence: 1.0,
                        metadata: StreamChunk.StreamMetadata(
                            citations: createCitations(from: cached.answer),
                            estimatedRemaining: nil
                        )
                    ))
                    continuation.finish()
                    return
                }
                
                // 2. Check local verse cache (fast for offline)
                if let verse = getFromVerseCache(query: query) {
                    print("⚡️ FastMode: Verse cache hit")
                    continuation.yield(StreamChunk(
                        content: verse.text,
                        isPartial: true,
                        confidence: 0.8,
                        metadata: nil
                    ))
                    // Continue to get full answer with context
                }
                
                // 3. Check circuit breaker
                if circuitBreakerOpen {
                    print("⚠️ FastMode: Circuit breaker open, returning basic mode")
                    let basicResponse = getBasicModeResponse(query: query)
                    continuation.yield(basicResponse)
                    continuation.finish()
                    return
                }
                
                // 4. Rate limit check
                if !checkRateLimit() {
                    print("⚠️ FastMode: Rate limit exceeded")
                    let rateLimitResponse = StreamChunk(
                        content: "You're exploring quickly! Take a moment, then continue.",
                        isPartial: false,
                        confidence: 1.0,
                        metadata: nil
                    )
                    continuation.yield(rateLimitResponse)
                    continuation.finish()
                    return
                }
                
                // 5. Stream full answer
                await streamFullAnswer(
                    query: query,
                    context: context,
                    continuation: continuation
                )
                
                continuation.finish()
            }
        }
    }
    
    // MARK: - Caching
    
    private func getFromMemoryCache(query: String, context: BereanContext) -> CachedBereanAnswer? {
        let key = cacheKey(query: query, context: context)
        
        guard let cached = memoryCache[key] else { return nil }
        
        // Check expiration
        if Date() > cached.expiresAt {
            memoryCache.removeValue(forKey: key)
            return nil
        }
        
        // Increment hit count
        var updated = cached
        updated = CachedBereanAnswer(
            answer: cached.answer,
            cacheKey: cached.cacheKey,
            createdAt: cached.createdAt,
            expiresAt: cached.expiresAt,
            hitCount: cached.hitCount + 1,
            containsSensitiveData: cached.containsSensitiveData
        )
        memoryCache[key] = updated
        
        return updated
    }
    
    func cacheAnswer(_ answer: BereanAnswer, context: BereanContext) {
        // Don't cache sensitive content (prayers, confessions)
        if context.featureContext == .prayer {
            return
        }
        
        let key = cacheKey(query: answer.query, context: context)
        
        let cached = CachedBereanAnswer(
            answer: answer,
            cacheKey: key,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(memoryCacheTTL),
            hitCount: 0,
            containsSensitiveData: false
        )
        
        // Add to memory cache
        memoryCache[key] = cached
        
        // Evict old entries if cache too large
        if memoryCache.count > maxMemoryCacheSize {
            evictOldestCacheEntries()
        }
        
        // Cache Scripture passages to verse cache
        for scripture in answer.scripture {
            cacheVerseLocally(scripture: scripture)
        }
    }
    
    private func evictOldestCacheEntries() {
        // Sort by creation date and remove oldest 20%
        let sorted = memoryCache.sorted { $0.value.createdAt < $1.value.createdAt }
        let removeCount = maxMemoryCacheSize / 5
        
        for (key, _) in sorted.prefix(removeCount) {
            memoryCache.removeValue(forKey: key)
        }
        
        print("🧹 FastMode: Evicted \(removeCount) cache entries")
    }
    
    private func cacheKey(query: String, context: BereanContext) -> String {
        let mode = answerEngine.currentMode.rawValue
        let feature = context.featureContext.rawValue
        return "\(query.lowercased())_\(mode)_\(feature)"
    }
    
    // MARK: - Local Verse Cache
    
    private func getFromVerseCache(query: String) -> LocalVerseSnippet? {
        // Extract verse reference from query
        let refs = extractScriptureReferences(from: query)
        guard let firstRef = refs.first else { return nil }
        
        let key = firstRef.lowercased()
        guard let cached = localVerseCache[key] else { return nil }
        
        // Check if expired (24 hours)
        if Date().timeIntervalSince(cached.cachedAt) > verseCacheTTL {
            localVerseCache.removeValue(forKey: key)
            return nil
        }
        
        return cached
    }
    
    private func cacheVerseLocally(scripture: ScripturePassage) {
        let key = scripture.reference.lowercased()
        
        let snippet = LocalVerseSnippet(
            id: scripture.id,
            reference: scripture.reference,
            text: scripture.text,
            version: scripture.version.rawValue,
            quickDefinitions: [:],  // TODO: Add common word definitions
            cachedAt: Date()
        )
        
        localVerseCache[key] = snippet
        
        // Persist to UserDefaults for offline access
        saveLocalVerseCache()
    }
    
    private func loadLocalVerseCache() {
        // Load from UserDefaults
        guard let data = UserDefaults.standard.data(forKey: "berean_verse_cache"),
              let cache = try? JSONDecoder().decode([String: LocalVerseSnippet].self, from: data) else {
            print("📖 FastMode: No local verse cache found")
            return
        }
        
        localVerseCache = cache
        print("📖 FastMode: Loaded \(cache.count) verses from cache")
    }
    
    private func saveLocalVerseCache() {
        guard let data = try? JSONEncoder().encode(localVerseCache) else { return }
        UserDefaults.standard.set(data, forKey: "berean_verse_cache")
    }
    
    // MARK: - Streaming
    
    private func streamFullAnswer(
        query: String,
        context: BereanContext,
        continuation: AsyncStream<StreamChunk>.Continuation
    ) async {
        do {
            // Start with immediate partial response
            let partialChunk = StreamChunk(
                content: "Let me explore that...",
                isPartial: true,
                confidence: 0.3,
                metadata: StreamChunk.StreamMetadata(
                    citations: nil,
                    estimatedRemaining: 1.5
                )
            )
            continuation.yield(partialChunk)
            
            // Get full answer
            let response = try await router.process(input: query, context: context)
            
            // Stream the complete response
            let finalChunk = StreamChunk(
                content: response.content,
                isPartial: false,
                confidence: response.confidence,
                metadata: StreamChunk.StreamMetadata(
                    citations: response.answer.flatMap { createCitations(from: $0) },
                    estimatedRemaining: nil
                )
            )
            continuation.yield(finalChunk)
            
            // Cache the answer
            if let answer = response.answer {
                cacheAnswer(answer, context: context)
            }
            
        } catch {
            print("❌ FastMode: Stream error: \(error)")
            openCircuitBreaker()
            
            let errorChunk = StreamChunk(
                content: "I encountered an issue. Please try again.",
                isPartial: false,
                confidence: 0.0,
                metadata: nil
            )
            continuation.yield(errorChunk)
        }
    }
    
    private func createCitations(from answer: BereanAnswer) -> [BereanCitation] {
        var citations: [BereanCitation] = []
        
        // Add Scripture citations
        for scripture in answer.scripture {
            citations.append(BereanCitation(
                id: scripture.id,
                type: .scripture,
                content: scripture.text,
                reference: scripture.reference,
                confidence: 1.0
            ))
        }
        
        // Add historical context citations
        if let contexts = answer.historicalContext {
            for context in contexts {
                citations.append(BereanCitation(
                    id: context.id,
                    type: .historicalContext,
                    content: context.description,
                    reference: context.sources.joined(separator: ", "),
                    confidence: 0.8
                ))
            }
        }
        
        return citations
    }
    
    // MARK: - Prefetching
    
    /// Prefetch content on navigation
    func prefetchFor(screen: BereanContext.FeatureContext, userId: String?) {
        print("🔮 FastMode: Prefetching for \(screen.rawValue)")
        
        let queries = predictQueriesFor(screen: screen)
        
        let request = PrefetchRequest(
            context: BereanContext(
                userId: userId,
                featureContext: screen,
                sessionId: nil
            ),
            predictedQueries: queries,
            priority: .high
        )
        
        prefetchQueue.append(request)
        
        Task {
            await processPrefetchQueue()
        }
    }
    
    private func predictQueriesFor(screen: BereanContext.FeatureContext) -> [String] {
        switch screen {
        case .post:
            return [
                "verse context",
                "is this post okay"
            ]
        case .prayer:
            return [
                "help me pray",
                "prayer focus"
            ]
        case .notes:
            return [
                "summarize notes",
                "main themes"
            ]
        case .findChurch:
            return [
                "what to expect first visit",
                "find church near me"
            ]
        case .chat:
            return [
                "explain verse",
                "theological question"
            ]
        }
    }
    
    private func processPrefetchQueue() async {
        guard !prefetchQueue.isEmpty else { return }
        
        // Process high priority requests first
        let sorted = prefetchQueue.sorted { $0.priority == .high && $1.priority != .high }
        
        for request in sorted.prefix(3) {  // Process max 3 at a time
            for query in request.predictedQueries {
                // Check if already cached
                if getFromMemoryCache(query: query, context: request.context) != nil {
                    continue
                }
                
                // Prefetch in background
                do {
                    let response = try await router.process(
                        input: query,
                        context: request.context
                    )
                    
                    if let answer = response.answer {
                        cacheAnswer(answer, context: request.context)
                    }
                    
                    print("✅ FastMode: Prefetched '\(query.prefix(30))...'")
                } catch {
                    print("⚠️ FastMode: Prefetch failed for '\(query.prefix(30))...'")
                }
            }
        }
        
        // Clear queue
        prefetchQueue.removeAll()
    }
    
    /// Generate context panel for post (with verse references)
    func generateContextPanel(for post: Post) async -> ContextPanel? {
        let text = post.content
        let refs = extractScriptureReferences(from: text)
        
        guard !refs.isEmpty else { return nil }
        
        var verses: [LocalVerseSnippet] = []
        
        for ref in refs {
            // Check cache first
            if let cached = getFromVerseCache(query: ref) {
                verses.append(cached)
            } else {
                // Fetch and cache
                // In production, call Bible API
                // For now, skip
            }
        }
        
        if verses.isEmpty { return nil }
        
        return ContextPanel(
            verses: verses,
            summary: "Referenced: \(refs.joined(separator: ", "))"
        )
    }
    
    // MARK: - Rate Limiting & Circuit Breaker
    
    private func checkRateLimit() -> Bool {
        let now = Date()
        
        // Reset counter every minute
        if now.timeIntervalSince(lastResetTime) > 60 {
            requestCount = 0
            lastResetTime = now
        }
        
        requestCount += 1
        
        if requestCount > requestLimit {
            print("⚠️ FastMode: Rate limit exceeded (\(requestCount)/\(requestLimit))")
            return false
        }
        
        return true
    }
    
    private func openCircuitBreaker() {
        circuitBreakerOpen = true
        cacheStatus = .degraded
        
        // Auto-reset after 30 seconds
        Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            await closeCircuitBreaker()
        }
    }
    
    private func closeCircuitBreaker() async {
        circuitBreakerOpen = false
        cacheStatus = .ready
        print("✅ FastMode: Circuit breaker closed")
    }
    
    private func getBasicModeResponse(query: String) -> StreamChunk {
        // Degraded mode: simple response without AI
        let basicResponse = "I'm experiencing high demand right now. Please try again in a moment."
        
        return StreamChunk(
            content: basicResponse,
            isPartial: false,
            confidence: 0.5,
            metadata: nil
        )
    }
    
    // MARK: - Helper: Scripture Reference Extraction
    
    private func extractScriptureReferences(from text: String) -> [String] {
        var references: [String] = []
        
        // Pattern: "Book Chapter:Verse" (e.g., "John 3:16")
        let pattern = "([1-3]?\\s?[A-Za-z]+)\\s+(\\d+):(\\d+(?:-\\d+)?)"
        
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                if match.numberOfRanges >= 4 {
                    let book = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
                    let chapter = nsString.substring(with: match.range(at: 2))
                    let verses = nsString.substring(with: match.range(at: 3))
                    
                    references.append("\(book) \(chapter):\(verses)")
                }
            }
        }
        
        return references
    }
    
    // MARK: - Cache Stats
    
    func getCacheStats() -> CacheStats {
        let totalMemoryEntries = memoryCache.count
        let totalVerseEntries = localVerseCache.count
        let hitCounts = memoryCache.values.map { $0.hitCount }
        let avgHitCount = hitCounts.isEmpty ? 0 : hitCounts.reduce(0, +) / hitCounts.count
        
        return CacheStats(
            memoryEntries: totalMemoryEntries,
            verseEntries: totalVerseEntries,
            averageHitCount: avgHitCount,
            status: cacheStatus
        )
    }
    
    func clearCache() {
        memoryCache.removeAll()
        print("🧹 FastMode: Memory cache cleared")
    }
}

// MARK: - Supporting Models

struct ContextPanel {
    let verses: [LocalVerseSnippet]
    let summary: String
}

struct CacheStats {
    let memoryEntries: Int
    let verseEntries: Int
    let averageHitCount: Int
    let status: BereanFastMode.CacheStatus
}

// MARK: - Post Extension for Context

extension Post {
    var bereanContextPanel: ContextPanel? {
        get async {
            return await BereanFastMode.shared.generateContextPanel(for: self)
        }
    }
}
