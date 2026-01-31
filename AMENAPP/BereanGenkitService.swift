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
    
    // Genkit configuration
    private let genkitEndpoint: String
    private let apiKey: String?
    
    init() {
        // Configure your Genkit endpoint
        // In development: http://localhost:3400
        // In production: your deployed Cloud Run URL
        if let endpoint = Bundle.main.object(forInfoDictionaryKey: "GENKIT_ENDPOINT") as? String {
            self.genkitEndpoint = endpoint
        } else {
            #if targetEnvironment(simulator)
            // iOS Simulator: use localhost
            self.genkitEndpoint = "http://localhost:3400"
            #else
            // Real device: use your Mac's IP address
            self.genkitEndpoint = "http://192.168.1.XXX:3400"  // Replace with your Mac's IP
            #endif
            print("⚠️ Using default Genkit endpoint: \(self.genkitEndpoint)")
        }
        
        // Optional: API key for production
        self.apiKey = Bundle.main.object(forInfoDictionaryKey: "GENKIT_API_KEY") as? String
        
        print("✅ BereanGenkitService initialized with endpoint: \(genkitEndpoint)")
    }
    
    // MARK: - Core AI Chat
    
    /// Send a message to the AI and get streaming response
    func sendMessage(_ message: String, conversationHistory: [BereanMessage] = []) -> AsyncThrowingStream<String, Error> {
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
                        // Split into words for streaming effect
                        let words = text.split(separator: " ")
                        for word in words {
                            continuation.yield(String(word) + " ")
                            try await Task.sleep(nanoseconds: 50_000_000) // 50ms delay
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
        request.timeoutInterval = 30  // 30 second timeout
        
        // Add API key if available
        if let apiKey = apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        // Encode input as JSON
        let requestBody = ["data": input]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        print("📤 Calling Genkit flow: \(flowName)")
        print("   URL: \(urlString)")
        
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
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json["result"] as? [String: Any] else {
                throw GenkitError.invalidResponse
            }
            
            print("✅ Genkit flow completed: \(flowName)")
            
            return result
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
        let input: [String: Any] = [
            "category": category ?? "random"
        ]
        
        let result = try await callGenkitFlow(flowName: "generateFunBibleFact", input: input)
        
        guard let fact = result["fact"] as? String else {
            throw GenkitError.invalidResponse
        }
        
        return fact
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

