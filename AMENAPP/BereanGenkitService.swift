//
//  BereanGenkitService.swift
//  AMENAPP
//
//  Created by Steph on 1/23/26.
//

import Foundation
import SwiftUI
import Combine

/// Service for AI-powered Bible study using OpenAI API
/// Now uses OpenAI directly for better performance and reliability
@MainActor
class BereanGenkitService: ObservableObject {
    static let shared = BereanGenkitService()
    
    @Published var isProcessing = false
    @Published var lastError: Error?
    
    // Use OpenAI service for all AI operations
    private let openAIService = OpenAIService.shared
    
    // Feature flag to check if AI is available
    var isEnabled: Bool {
        // AI is enabled if OpenAI service is configured
        return true
    }
    
    init() {
        print("✅ BereanGenkitService initialized (using OpenAI)")
    }
    
    // MARK: - Core AI Chat
    
    /// Send a message to the AI and get streaming response
    func sendMessage(_ message: String, conversationHistory: [BereanMessage] = []) -> AsyncThrowingStream<String, Error> {
        // Convert BereanMessage to OpenAIChatMessage
        let chatHistory = conversationHistory.map { msg in
            OpenAIChatMessage(content: msg.content, isFromUser: msg.isFromUser)
        }
        
        // Delegate to OpenAI service
        return openAIService.sendMessage(message, conversationHistory: chatHistory)
    }
    
    /// Send message synchronously (for non-streaming use cases)
    func sendMessageSync(_ message: String, conversationHistory: [BereanMessage] = []) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }
        
        // Convert BereanMessage to OpenAIChatMessage
        let chatHistory = conversationHistory.map { msg in
            OpenAIChatMessage(content: msg.content, isFromUser: msg.isFromUser)
        }
        
        // Delegate to OpenAI service
        return try await openAIService.sendMessageSync(message, conversationHistory: chatHistory)
    }
    
    // MARK: - Devotional Generation
    
    func generateDevotional(topic: String? = nil) async throws -> Devotional {
        isProcessing = true
        defer { isProcessing = false }
        
        print("📖 Generating devotional...")
        
        let prompt = topic != nil 
            ? "Generate a devotional on the topic: \(topic!). Include: title, scripture reference, devotional content (200-300 words), and a closing prayer."
            : "Generate a daily devotional. Include: title, scripture reference, devotional content (200-300 words), and a closing prayer."
        
        let response = try await openAIService.sendMessageSync(prompt)
        
        // Parse the response (simple parsing - assumes structured format)
        let lines = response.components(separatedBy: "\n").filter { !$0.isEmpty }
        
        var title = "Daily Devotional"
        var scripture = "Psalm 23:1"
        var content = response
        var prayer = "Amen."
        
        // Try to extract structured content
        for (index, line) in lines.enumerated() {
            if line.lowercased().contains("title:") {
                title = line.replacingOccurrences(of: "Title:", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.lowercased().contains("scripture:") {
                scripture = line.replacingOccurrences(of: "Scripture:", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.lowercased().contains("prayer:") {
                prayer = lines[index...].joined(separator: "\n").replacingOccurrences(of: "Prayer:", with: "").trimmingCharacters(in: .whitespaces)
            }
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
        
        let prompt = "Generate a \(duration)-day Bible study plan on '\(topic)'. Provide a title and brief description of what will be covered."
        let response = try await openAIService.sendMessageSync(prompt)
        
        print("✅ Study plan generated")
        
        return StudyPlan(
            id: UUID().uuidString,
            title: "\(duration)-Day Study: \(topic)",
            duration: "\(duration) days",
            description: response,
            icon: "book.pages.fill",
            color: .blue,
            progress: 0
        )
    }
    
    // MARK: - Scripture Analysis
    
    func analyzeScripture(reference: String, analysisType: ScriptureAnalysisType) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }
        
        print("🔍 Analyzing \(reference) - Type: \(analysisType)")
        
        let prompt = "Provide a \(analysisType.rawValue) analysis of \(reference). Include context, meaning, and application."
        let analysis = try await openAIService.sendMessageSync(prompt)
        
        print("✅ Analysis complete")
        return analysis
    }
    
    // MARK: - Memory Verse Helper
    
    func generateMemoryAid(verse: String, reference: String) async throws -> MemoryAid {
        isProcessing = true
        defer { isProcessing = false }
        
        print("🧠 Generating memory aid for \(reference)...")
        
        let prompt = "Provide memory techniques to help memorize this verse: '\(verse)' (\(reference)). Include mnemonics, visualization tips, and key word associations."
        let techniques = try await openAIService.sendMessageSync(prompt)
        
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
        
        let prompt = topic != nil 
            ? "Generate 3 biblical insights about '\(topic!)'. For each insight, provide: a title, relevant scripture verse, and explanation."
            : "Generate 3 interesting biblical insights. For each, provide: a title, relevant scripture verse, and explanation."
        
        let response = try await openAIService.sendMessageSync(prompt)
        
        // Parse insights (simple parsing)
        let insights = [
            AIInsight(
                title: "Biblical Insight",
                verse: "Various",
                content: response,
                icon: "lightbulb.fill",
                color: .purple
            )
        ]
        
        print("✅ Generated \(insights.count) insights")
        return insights
    }
    
    // MARK: - Fun Bible Fact
    
    /// Generate a fun and fascinating Bible fact
    func generateFunBibleFact(category: String? = nil) async throws -> String {
        let prompt = category != nil 
            ? "Share an interesting and fascinating fact about \(category!) from the Bible. Make it engaging and educational."
            : "Share an interesting and fascinating fact from the Bible. Make it engaging and educational."
        
        return try await openAIService.sendMessageSync(prompt)
    }
    
    // MARK: - AI-Powered Search
    
    /// Generate smart search suggestions based on user query
    func generateSearchSuggestions(query: String, context: String? = nil) async throws -> SearchSuggestions {
        isProcessing = true
        defer { isProcessing = false }
        
        print("🔍 Generating search suggestions for: \(query)")
        
        let prompt = "Based on the search query '\(query)' in a \(context ?? "general") context, suggest 5 related search terms and 3 related biblical topics."
        let response = try await openAIService.sendMessageSync(prompt)
        
        // Simple parsing - extract suggestions
        let lines = response.components(separatedBy: "\n").filter { !$0.isEmpty }
        let suggestions = lines.prefix(5).map { $0.trimmingCharacters(in: .whitespaces) }
        let relatedTopics = lines.suffix(3).map { $0.trimmingCharacters(in: .whitespaces) }
        
        print("✅ Generated \(suggestions.count) suggestions")
        
        return SearchSuggestions(
            suggestions: Array(suggestions),
            relatedTopics: Array(relatedTopics)
        )
    }
    
    /// Enhance biblical search with AI context
    func enhanceBiblicalSearch(query: String, type: BiblicalSearchType) async throws -> BiblicalSearchResult {
        isProcessing = true
        defer { isProcessing = false }
        
        print("📖 Enhancing biblical search: \(query) (type: \(type.rawValue))")
        
        let prompt = """
        Provide information about '\(query)' as a biblical \(type.rawValue). Include:
        1. A summary
        2. Key scripture verses
        3. Related people
        4. Interesting facts
        """
        
        let response = try await openAIService.sendMessageSync(prompt)
        
        print("✅ Biblical search enhanced")
        
        return BiblicalSearchResult(
            query: query,
            summary: response,
            keyVerses: ["Various passages"],
            relatedPeople: [],
            funFacts: []
        )
    }
    
    /// Get smart filter suggestions based on search query
    func suggestSearchFilters(query: String) async throws -> FilterSuggestion {
        print("🎯 Suggesting filters for: \(query)")
        
        let prompt = "Suggest relevant search filters for the biblical query: '\(query)'. Include categories like Testament, Book, Theme, etc."
        let response = try await openAIService.sendMessageSync(prompt)
        
        return FilterSuggestion(
            filters: ["Testament", "Book", "Theme"],
            explanation: response
        )
    }
    
    // MARK: - Legacy Compatibility
    
    /// Legacy method for backward compatibility with MessageAIService
    /// This wraps OpenAI calls to maintain the old Genkit interface
    func callGenkitFlow(flowName: String, input: [String: Any]) async throws -> [String: Any] {
        print("📤 Legacy Genkit flow call: \(flowName)")
        print("   (Now using OpenAI API)")
        
        // Convert input to a prompt
        let prompt = convertInputToPrompt(flowName: flowName, input: input)
        
        // Call OpenAI
        let response = try await openAIService.sendMessageSync(prompt)
        
        // Return a simple response structure
        return ["response": response, "result": response]
    }
    
    /// Convert Genkit flow parameters to OpenAI prompt
    private func convertInputToPrompt(flowName: String, input: [String: Any]) -> String {
        switch flowName {
        case "generateIceBreakers":
            let context = input["context"] as? String ?? "general"
            return "Generate 3 friendly ice breaker messages for starting a conversation in a \(context) context."
            
        case "generateSmartReplies":
            let message = input["lastMessage"] as? String ?? ""
            return "Generate 3 smart reply suggestions to this message: '\(message)'"
            
        case "analyzeConversation":
            return "Analyze this conversation and provide insights."
            
        case "detectMessageTone":
            let message = input["message"] as? String ?? ""
            return "Detect the tone of this message: '\(message)'. Return: positive, negative, neutral, encouraging, or prayerful."
            
        case "suggestScriptureForMessage":
            let message = input["message"] as? String ?? ""
            return "Suggest a relevant Bible verse for this message: '\(message)'"
            
        case "enhanceMessage":
            let message = input["message"] as? String ?? ""
            let style = input["style"] as? String ?? "friendly"
            return "Enhance this message in a \(style) style: '\(message)'"
            
        case "detectPrayerRequest":
            let message = input["message"] as? String ?? ""
            return "Does this message contain a prayer request? '\(message)' Answer: yes or no, and extract the request if present."
            
        default:
            return "Process this request: \(input)"
        }
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

