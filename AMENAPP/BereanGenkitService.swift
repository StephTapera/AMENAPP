//
//  BereanGenkitService.swift
//  AMENAPP
//
//  Created by Steph on 1/23/26.
//

import Foundation
import SwiftUI
import Combine

/// Service for AI-powered Bible study using Firebase Genkit
/// Genkit provides structured AI flows with better observability and testing
@MainActor
class BereanGenkitService: ObservableObject {
    static let shared = BereanGenkitService()
    
    @Published var isProcessing = false
    @Published var lastError: Error?
    
    // ⚡ Response cache for faster repeat queries (15-minute TTL)
    private var responseCache: [String: CachedResponse] = [:]
    private let cacheTTL: TimeInterval = 900 // 15 minutes
    
    // Genkit configuration
    private let genkitEndpoint: String
    private let apiKey: String?
    
    // Feature flag to disable AI when server is offline
    var isEnabled: Bool {
        // AI is always enabled - production uses Cloud Run
        return true
    }
    
    init() {
        // Configure your Genkit endpoint
        // Priority: Info.plist -> Default Cloud Run URL
        if let endpoint = Bundle.main.object(forInfoDictionaryKey: "GENKIT_ENDPOINT") as? String {
            self.genkitEndpoint = endpoint
        } else {
            // Production & TestFlight: Use Cloud Run
            self.genkitEndpoint = "https://genkit-amen-78278013543.us-central1.run.app"
            
            // 💡 For local development, you can override this in Info.plist:
            // <key>GENKIT_ENDPOINT</key>
            // <string>http://localhost:3400</string>
        }
        
        // Optional: API key for production (recommended for security)
        self.apiKey = Bundle.main.object(forInfoDictionaryKey: "GENKIT_API_KEY") as? String
        
        print("✅ BereanGenkitService initialized")
        print("   Endpoint: \(genkitEndpoint)")
        print("   API Key: \(apiKey != nil ? "✓ Configured" : "⚠️ Not set (consider adding for production)")")
    }
    
    // MARK: - Core AI Chat
    
    /// Send a message to the AI and get streaming response
    func sendMessage(_ message: String, conversationHistory: [BereanMessage] = []) -> AsyncThrowingStream<String, Error> {
        // Check if AI is enabled
        guard isEnabled else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: NSError(
                    domain: "BereanGenkitService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "AI features are currently disabled. Start the Genkit server to enable them."]
                ))
            }
        }
        
        // ⚡ Check cache for instant responses (only for queries without history)
        if conversationHistory.isEmpty, let cached = getCachedResponse(for: message) {
            print("⚡ Cache hit! Returning instant response")
            return AsyncThrowingStream { continuation in
                Task {
                    // Stream cached response word by word for consistent UX
                    let words = cached.split(separator: " ")
                    for word in words {
                        continuation.yield(String(word) + " ")
                        try await Task.sleep(nanoseconds: 8_000_000)
                    }
                    continuation.finish()
                }
            }
        }
        
        return AsyncThrowingStream { continuation in
            Task {
                await MainActor.run {
                    self.isProcessing = true
                }
                
                do {
                    // Convert conversation history to the format Genkit expects
                    let history = conversationHistory.map { msg in
                        [
                            "role": msg.isFromUser ? "user" : "assistant",
                            "content": msg.content
                        ]
                    }
                    
                    // Call Genkit flow
                    let response = try await self.callGenkitFlow(
                        flowName: "bibleChat",
                        input: [
                            "message": message,
                            "history": history
                        ]
                    )
                    
                    // For streaming, we'll simulate chunks (Genkit can do real streaming with SSE)
                    if let text = response["response"] as? String {
                        // ⚡ Cache the response for future use
                        if conversationHistory.isEmpty {
                            cacheResponse(text, for: message)
                        }
                        
                        // ⚡ SPEED OPTIMIZATION: Reduced to 8ms for near-instant streaming
                        // This provides smooth visual feedback while maximizing speed
                        let words = text.split(separator: " ")
                        for word in words {
                            continuation.yield(String(word) + " ")
                            try await Task.sleep(nanoseconds: 8_000_000) // 8ms delay (6x faster than original)
                        }
                    }
                    
                    continuation.finish()
                    
                    await MainActor.run {
                        self.isProcessing = false
                    }
                    
                } catch {
                    print("❌ Genkit error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                    
                    await MainActor.run {
                        self.isProcessing = false
                        self.lastError = error
                    }
                }
            }
        }
    }
    
    /// Send message synchronously (for non-streaming use cases)
    func sendMessageSync(_ message: String, conversationHistory: [BereanMessage] = []) async throws -> String {
        // Check if AI is enabled
        guard isEnabled else {
            throw NSError(
                domain: "BereanGenkitService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "AI features are currently disabled. Start the Genkit server to enable them."]
            )
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        let history = conversationHistory.map { msg in
            [
                "role": msg.isFromUser ? "user" : "assistant",
                "content": msg.content
            ]
        }
        
        let response = try await callGenkitFlow(
            flowName: "bibleChat",
            input: [
                "message": message,
                "history": history
            ]
        )
        
        guard let text = response["response"] as? String else {
            throw GenkitError.invalidResponse
        }
        
        return text
    }
    
    // MARK: - Devotional Generation
    
    func generateDevotional(topic: String? = nil) async throws -> Devotional {
        isProcessing = true
        defer { isProcessing = false }
        
        print("📖 Generating devotional...")
        
        let input: [String: Any] = topic != nil ? ["topic": topic!] : [:]
        
        let response = try await callGenkitFlow(
            flowName: "generateDevotional",
            input: input
        )
        
        guard let title = response["title"] as? String,
              let scripture = response["scripture"] as? String,
              let content = response["content"] as? String,
              let prayer = response["prayer"] as? String else {
            throw GenkitError.invalidResponse
        }
        
        print("✅ Devotional generated: \(title)")
        
        return Devotional(
            title: title,
            scripture: scripture,
            content: content,
            prayer: prayer
        )
    }
    
    // MARK: - Study Plan Generation
    
    func generateStudyPlan(topic: String, duration: Int) async throws -> StudyPlan {
        isProcessing = true
        defer { isProcessing = false }
        
        print("📚 Generating \(duration)-day study plan on \(topic)...")
        
        let response = try await callGenkitFlow(
            flowName: "generateStudyPlan",
            input: [
                "topic": topic,
                "duration": duration
            ]
        )
        
        guard let id = response["id"] as? String,
              let title = response["title"] as? String,
              let description = response["description"] as? String else {
            throw GenkitError.invalidResponse
        }
        
        print("✅ Study plan generated")
        
        return StudyPlan(
            id: id,
            title: title,
            duration: "\(duration) days",
            description: description,
            icon: "book.pages.fill",
            color: .blue,
            progress: 0
        )
    }
    
    // MARK: - Scripture Analysis
    
    func analyzeScripture(reference: String, analysisType: AnalysisType) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }
        
        print("🔍 Analyzing \(reference) - Type: \(analysisType)")
        
        let response = try await callGenkitFlow(
            flowName: "analyzeScripture",
            input: [
                "reference": reference,
                "analysisType": analysisType.rawValue
            ]
        )
        
        guard let analysis = response["analysis"] as? String else {
            throw GenkitError.invalidResponse
        }
        
        print("✅ Analysis complete")
        return analysis
    }
    
    // MARK: - Memory Verse Helper
    
    func generateMemoryAid(verse: String, reference: String) async throws -> MemoryAid {
        isProcessing = true
        defer { isProcessing = false }
        
        print("🧠 Generating memory aid for \(reference)...")
        
        let response = try await callGenkitFlow(
            flowName: "generateMemoryAid",
            input: [
                "verse": verse,
                "reference": reference
            ]
        )
        
        guard let techniques = response["techniques"] as? String else {
            throw GenkitError.invalidResponse
        }
        
        print("✅ Memory aid generated")
        
        return MemoryAid(
            verse: verse,
            reference: reference,
            techniques: techniques
        )
    }
    
    // MARK: - AI Insights
    
    func generateInsights(topic: String? = nil) async throws -> [AIInsight] {
        isProcessing = true
        defer { isProcessing = false }
        
        print("💡 Generating AI insights...")
        
        let input: [String: Any] = topic != nil ? ["topic": topic!] : [:]
        
        let response = try await callGenkitFlow(
            flowName: "generateInsights",
            input: input
        )
        
        guard let insightsData = response["insights"] as? [[String: Any]] else {
            throw GenkitError.invalidResponse
        }
        
        let insights = insightsData.compactMap { data -> AIInsight? in
            guard let title = data["title"] as? String,
                  let verse = data["verse"] as? String,
                  let content = data["content"] as? String else {
                return nil
            }
            
            return AIInsight(
                title: title,
                verse: verse,
                content: content,
                icon: data["icon"] as? String ?? "lightbulb.fill",
                color: .purple
            )
        }
        
        print("✅ Generated \(insights.count) insights")
        return insights
    }
    
    // MARK: - Low-Level Genkit Communication
    
    func callGenkitFlow(flowName: String, input: [String: Any]) async throws -> [String: Any] {
        // Construct the Genkit flow URL
        let urlString = "\(genkitEndpoint)/\(flowName)"
        
        guard let url = URL(string: urlString) else {
            throw GenkitError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20  // ⚡ Reduced to 20 seconds for faster feedback
        
        // Add API key if available
        if let apiKey = apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        // Encode input as JSON
        // ✅ FIXED: Send input directly, not wrapped in "data"
        // Genkit flows accessed via HTTP expect the input object directly
        request.httpBody = try JSONSerialization.data(withJSONObject: input)
        
        print("📤 Calling Genkit flow: \(flowName)")
        print("   URL: \(urlString)")
        print("   Input: \(input)")
        
        // Debug: Print the actual request body being sent
        if let bodyData = request.httpBody,
           let bodyString = String(data: bodyData, encoding: .utf8) {
            print("   Request body: \(bodyString)")
        }
        
        // Make the request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GenkitError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                print("❌ HTTP Error: \(httpResponse.statusCode)")
                if let errorText = String(data: data, encoding: .utf8) {
                    print("❌ Error response: \(errorText)")
                }
                throw GenkitError.httpError(statusCode: httpResponse.statusCode)
            }
            
            // Parse JSON response
            // ✅ FIXED: Genkit returns the result directly, not wrapped
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ Failed to parse JSON response")
                if let responseText = String(data: data, encoding: .utf8) {
                    print("   Response was: \(responseText)")
                }
                throw GenkitError.invalidResponse
            }
            
            print("✅ Genkit flow completed: \(flowName)")
            print("   Response: \(json)")
            
            return json
        } catch let error as URLError {
            print("❌ Network error: \(error.localizedDescription)")
            print("   Error code: \(error.code.rawValue)")
            if error.code == .cannotConnectToHost || error.code == .timedOut {
                throw GenkitError.networkError(NSError(
                    domain: "BereanGenkitService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Could not connect to the server."]
                ))
            }
            throw error
        }
    }
    
    // MARK: - Fun Bible Fact
    
    /// Generate a fun and fascinating Bible fact
    func generateFunBibleFact(category: String? = nil) async throws -> String {
        // Cloud Run endpoint expects: { "data": { "category": "..." } }
        let input: [String: Any] = [
            "data": [
                "category": category ?? "random"
            ]
        ]
        
        let result = try await callGenkitFlow(flowName: "generateFunBibleFact", input: input)
        
        // Response format: { "result": { "fact": "..." } }
        if let resultData = result["result"] as? [String: Any],
           let fact = resultData["fact"] as? String {
            return fact
        }
        
        // Fallback: try direct fact field
        if let fact = result["fact"] as? String {
            return fact
        }
        
        throw GenkitError.invalidResponse
    }
    
    // MARK: - AI-Powered Search
    
    /// Generate smart search suggestions based on user query
    func generateSearchSuggestions(query: String, context: String? = nil) async throws -> SearchSuggestions {
        isProcessing = true
        defer { isProcessing = false }
        
        print("🔍 Generating search suggestions for: \(query)")
        
        let input: [String: Any] = [
            "query": query,
            "context": context ?? "general"
        ]
        
        let result = try await callGenkitFlow(flowName: "generateSearchSuggestions", input: input)
        
        guard let suggestions = result["suggestions"] as? [String],
              let relatedTopics = result["relatedTopics"] as? [String] else {
            throw GenkitError.invalidResponse
        }
        
        print("✅ Generated \(suggestions.count) suggestions")
        
        return SearchSuggestions(
            suggestions: suggestions,
            relatedTopics: relatedTopics
        )
    }
    
    /// Enhance biblical search with AI context
    func enhanceBiblicalSearch(query: String, type: BiblicalSearchType) async throws -> BiblicalSearchResult {
        isProcessing = true
        defer { isProcessing = false }
        
        print("📖 Enhancing biblical search: \(query) (type: \(type.rawValue))")
        
        let result = try await callGenkitFlow(
            flowName: "enhanceBiblicalSearch",
            input: [
                "query": query,
                "type": type.rawValue
            ]
        )
        
        guard let summary = result["summary"] as? String,
              let keyVerses = result["keyVerses"] as? [String],
              let relatedPeople = result["relatedPeople"] as? [String],
              let funFacts = result["funFacts"] as? [String] else {
            throw GenkitError.invalidResponse
        }
        
        print("✅ Biblical search enhanced with \(keyVerses.count) verses")
        
        return BiblicalSearchResult(
            query: query,
            summary: summary,
            keyVerses: keyVerses,
            relatedPeople: relatedPeople,
            funFacts: funFacts
        )
    }
    
    /// Get smart filter suggestions based on search query
    func suggestSearchFilters(query: String) async throws -> FilterSuggestion {
        print("🎯 Suggesting filters for: \(query)")
        
        let result = try await callGenkitFlow(
            flowName: "suggestSearchFilters",
            input: ["query": query]
        )
        
        guard let filters = result["suggestedFilters"] as? [String],
              let explanation = result["explanation"] as? String else {
            throw GenkitError.invalidResponse
        }
        
        return FilterSuggestion(
            filters: filters,
            explanation: explanation
        )
    }
    
    // MARK: - Cache Management
    
    /// Get cached response if available and not expired
    private func getCachedResponse(for query: String) -> String? {
        let cacheKey = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let cached = responseCache[cacheKey] else {
            return nil
        }
        
        // Check if cache entry is still valid
        let age = Date().timeIntervalSince(cached.timestamp)
        if age > cacheTTL {
            // Remove expired entry
            responseCache.removeValue(forKey: cacheKey)
            return nil
        }
        
        return cached.response
    }
    
    /// Cache a response for faster future lookups
    private func cacheResponse(_ response: String, for query: String) {
        let cacheKey = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        responseCache[cacheKey] = CachedResponse(response: response, timestamp: Date())
        
        // Limit cache size to 50 entries (oldest entries removed first)
        if responseCache.count > 50 {
            let sortedKeys = responseCache.sorted { $0.value.timestamp < $1.value.timestamp }
            if let oldestKey = sortedKeys.first?.key {
                responseCache.removeValue(forKey: oldestKey)
            }
        }
        
        print("💾 Cached response for: \(query.prefix(50))...")
    }
}

// MARK: - Cache Types

struct CachedResponse {
    let response: String
    let timestamp: Date
}

// MARK: - Search Support Types

struct SearchSuggestions {
    let suggestions: [String]
    let relatedTopics: [String]
}

struct BiblicalSearchResult {
    let query: String
    let summary: String
    let keyVerses: [String]
    let relatedPeople: [String]
    let funFacts: [String]
}

enum BiblicalSearchType: String {
    case person
    case place
    case event
}

struct FilterSuggestion {
    let filters: [String]
    let explanation: String
}

// MARK: - Genkit Error Types

enum GenkitError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Genkit endpoint URL"
        case .invalidResponse:
            return "Invalid response from Genkit"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

