//
//  MessageAIService.swift
//  AMENAPP
//
//  Created by AI Assistant on 1/24/26.
//
//  AI-powered messaging features using Genkit
//

import Foundation
import SwiftUI
import Combine

// MARK: - AI Message Models

struct MessageSuggestion: Identifiable {
    let id = UUID()
    let text: String
    let type: SuggestionType
    let icon: String
    let color: Color
    
    enum SuggestionType {
        case iceBreaker      // First message suggestions
        case response        // Smart reply to received message
        case scriptural      // Bible verse reference
        case question        // Follow-up question
        case encouragement   // Encouraging message
    }
}

struct ConversationInsight: Identifiable {
    let id = UUID()
    let title: String
    let insight: String
    let scriptureReference: String?
    let actionItems: [String]
    let tone: ConversationTone
    
    enum ConversationTone {
        case encouraging
        case prayerful
        case friendly
        case supportive
        case conversational
    }
}

struct IceBreakerSuggestion: Identifiable {
    let id = UUID()
    let message: String
    let context: String
    let sharedInterest: String?
}

// MARK: - Message AI Service

@MainActor
class MessageAIService: ObservableObject {
    static let shared = MessageAIService()
    
    @Published var isGenerating = false
    @Published var currentSuggestions: [MessageSuggestion] = []
    @Published var conversationInsights: [ConversationInsight] = []
    @Published var error: String?
    
    private let genkitService = BereanGenkitService.shared
    private var suggestionTask: Task<Void, Never>?
    
    private init() {}
    
    // MARK: - Ice Breaker Generation
    
    /// Generate AI-powered ice breaker messages for starting conversations
    func generateIceBreakers(
        recipientName: String,
        recipientBio: String?,
        sharedInterests: [String],
        context: String = "first message"
    ) async throws -> [IceBreakerSuggestion] {
        
        isGenerating = true
        defer { isGenerating = false }
        
        print("🤖 Generating ice breakers for: \(recipientName)")
        
        let input: [String: Any] = [
            "recipientName": recipientName,
            "recipientBio": recipientBio ?? "",
            "sharedInterests": sharedInterests,
            "context": context
        ]
        
        let response = try await genkitService.callGenkitFlow(
            flowName: "generateIceBreakers",
            input: input
        )
        
        guard let suggestions = response["suggestions"] as? [[String: String]] else {
            throw MessageAIError.invalidResponse
        }
        
        let iceBreakers = suggestions.map { dict in
            IceBreakerSuggestion(
                message: dict["message"] ?? "",
                context: dict["context"] ?? "",
                sharedInterest: dict["sharedInterest"]
            )
        }
        
        print("✅ Generated \(iceBreakers.count) ice breakers")
        return iceBreakers
    }
    
    // MARK: - Smart Reply Suggestions
    
    /// Generate AI-powered reply suggestions based on received message
    func generateSmartReplies(
        to message: String,
        conversationHistory: [AppMessage]? = nil,
        recipientName: String? = nil
    ) async throws -> [MessageSuggestion] {
        
        // Cancel any ongoing task
        suggestionTask?.cancel()
        
        isGenerating = true
        defer { isGenerating = false }
        
        print("💬 Generating smart replies to: \"\(message.prefix(50))...\"")
        
        // Prepare conversation history
        let history = conversationHistory?.suffix(5).map { msg in
            ["role": msg.isFromCurrentUser ? "user" : "assistant",
             "content": msg.text] as [String: Any]
        } ?? []
        
        let input: [String: Any] = [
            "message": message,
            "conversationHistory": history,
            "recipientName": recipientName ?? "them"
        ]
        
        let response = try await genkitService.callGenkitFlow(
            flowName: "generateSmartReplies",
            input: input
        )
        
        guard let replies = response["replies"] as? [[String: String]] else {
            throw MessageAIError.invalidResponse
        }
        
        let suggestions = replies.compactMap { dict -> MessageSuggestion? in
            guard let text = dict["text"],
                  let typeStr = dict["type"] else {
                return nil
            }
            
            let type = suggestionType(from: typeStr)
            
            return MessageSuggestion(
                text: text,
                type: type,
                icon: iconForType(type),
                color: colorForType(type)
            )
        }
        
        await MainActor.run {
            self.currentSuggestions = suggestions
        }
        
        print("✅ Generated \(suggestions.count) smart replies")
        return suggestions
    }
    
    // MARK: - Conversation Analysis
    
    /// Analyze conversation and provide insights
    func analyzeConversation(
        messages: [AppMessage],
        participants: [String]
    ) async throws -> ConversationInsight {
        
        isGenerating = true
        defer { isGenerating = false }
        
        print("🔍 Analyzing conversation with \(messages.count) messages")
        
        // Prepare messages for analysis (last 50 messages)
        let recentMessages = messages.suffix(50).map { msg in
            [
                "sender": msg.isFromCurrentUser ? "current_user" : "other_user",
                "text": msg.text,
                "timestamp": msg.timestamp.timeIntervalSince1970
            ] as [String: Any]
        }
        
        let input: [String: Any] = [
            "messages": recentMessages,
            "participants": participants
        ]
        
        let response = try await genkitService.callGenkitFlow(
            flowName: "analyzeConversation",
            input: input
        )
        
        guard let title = response["title"] as? String,
              let insightText = response["insight"] as? String,
              let toneStr = response["tone"] as? String else {
            throw MessageAIError.invalidResponse
        }
        
        let scriptureRef = response["scriptureReference"] as? String
        let actionItems = response["actionItems"] as? [String] ?? []
        let tone = conversationTone(from: toneStr)
        
        let insight = ConversationInsight(
            title: title,
            insight: insightText,
            scriptureReference: scriptureRef,
            actionItems: actionItems,
            tone: tone
        )
        
        print("✅ Conversation analysis complete")
        return insight
    }
    
    // MARK: - Message Tone Detection
    
    /// Detect the tone of a message (helpful for understanding context)
    func detectMessageTone(_ message: String) async throws -> MessageTone {
        let input: [String: Any] = ["message": message]
        
        let response = try await genkitService.callGenkitFlow(
            flowName: "detectMessageTone",
            input: input
        )
        
        guard let toneStr = response["tone"] as? String,
              let confidence = response["confidence"] as? Double,
              let suggestions = response["suggestions"] as? [String] else {
            throw MessageAIError.invalidResponse
        }
        
        return MessageTone(
            tone: toneStr,
            confidence: confidence,
            suggestions: suggestions
        )
    }
    
    // MARK: - Scripture Suggestions
    
    /// Suggest relevant scripture for conversation context
    func suggestScripture(
        conversationContext: String,
        mood: String? = nil
    ) async throws -> [ScriptureSuggestion] {
        
        print("📖 Finding relevant scripture for context")
        
        let input: [String: Any] = [
            "context": conversationContext,
            "mood": mood ?? "encouraging"
        ]
        
        let response = try await genkitService.callGenkitFlow(
            flowName: "suggestScriptureForMessage",
            input: input
        )
        
        guard let verses = response["verses"] as? [[String: String]] else {
            throw MessageAIError.invalidResponse
        }
        
        return verses.compactMap { dict in
            guard let reference = dict["reference"],
                  let text = dict["text"],
                  let reason = dict["reason"] else {
                return nil
            }
            
            return ScriptureSuggestion(
                reference: reference,
                text: text,
                reason: reason
            )
        }
    }
    
    // MARK: - Message Enhancement
    
    /// Enhance a message to be more encouraging/friendly/spiritual
    func enhanceMessage(
        _ message: String,
        style: EnhancementStyle
    ) async throws -> String {
        
        print("✨ Enhancing message with style: \(style.rawValue)")
        
        let input: [String: Any] = [
            "message": message,
            "style": style.rawValue
        ]
        
        let response = try await genkitService.callGenkitFlow(
            flowName: "enhanceMessage",
            input: input
        )
        
        guard let enhanced = response["enhancedMessage"] as? String else {
            throw MessageAIError.invalidResponse
        }
        
        return enhanced
    }
    
    // MARK: - Prayer Request Detection
    
    /// Detect if a message contains a prayer request
    func detectPrayerRequest(in message: String) async throws -> PrayerRequestDetection {
        let input: [String: Any] = ["message": message]
        
        let response = try await genkitService.callGenkitFlow(
            flowName: "detectPrayerRequest",
            input: input
        )
        
        guard let isPrayerRequest = response["isPrayerRequest"] as? Bool,
              let confidence = response["confidence"] as? Double else {
            throw MessageAIError.invalidResponse
        }
        
        let suggestedResponse = response["suggestedResponse"] as? String
        let prayerPoints = response["prayerPoints"] as? [String]
        
        return PrayerRequestDetection(
            isPrayerRequest: isPrayerRequest,
            confidence: confidence,
            suggestedResponse: suggestedResponse,
            prayerPoints: prayerPoints ?? []
        )
    }
    
    // MARK: - Helper Functions
    
    private func suggestionType(from string: String) -> MessageSuggestion.SuggestionType {
        switch string.lowercased() {
        case "icebreaker": return .iceBreaker
        case "response": return .response
        case "scriptural": return .scriptural
        case "question": return .question
        case "encouragement": return .encouragement
        default: return .response
        }
    }
    
    private func iconForType(_ type: MessageSuggestion.SuggestionType) -> String {
        switch type {
        case .iceBreaker: return "hand.wave"
        case .response: return "bubble.left"
        case .scriptural: return "book.closed"
        case .question: return "questionmark.bubble"
        case .encouragement: return "hands.sparkles"
        }
    }
    
    private func colorForType(_ type: MessageSuggestion.SuggestionType) -> Color {
        switch type {
        case .iceBreaker: return .blue
        case .response: return .green
        case .scriptural: return .purple
        case .question: return .orange
        case .encouragement: return .pink
        }
    }
    
    private func conversationTone(from string: String) -> ConversationInsight.ConversationTone {
        switch string.lowercased() {
        case "encouraging": return .encouraging
        case "prayerful": return .prayerful
        case "friendly": return .friendly
        case "supportive": return .supportive
        default: return .conversational
        }
    }
    
    func clearSuggestions() {
        suggestionTask?.cancel()
        currentSuggestions = []
        conversationInsights = []
    }
}

// MARK: - Supporting Models

struct MessageTone {
    let tone: String
    let confidence: Double
    let suggestions: [String]
}

struct ScriptureSuggestion: Identifiable {
    let id = UUID()
    let reference: String
    let text: String
    let reason: String
}

struct PrayerRequestDetection {
    let isPrayerRequest: Bool
    let confidence: Double
    let suggestedResponse: String?
    let prayerPoints: [String]
}

enum EnhancementStyle: String {
    case encouraging = "encouraging"
    case friendly = "friendly"
    case spiritual = "spiritual"
    case professional = "professional"
}

enum MessageAIError: LocalizedError {
    case invalidResponse
    case genkitUnavailable
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from AI service"
        case .genkitUnavailable:
            return "AI service is currently unavailable"
        }
    }
}

// Note: AppMessage model is defined in Message.swift

