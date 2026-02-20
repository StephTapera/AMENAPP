//
//  OpenAIService.swift
//  AMENAPP
//
//  Created by Claude Code on 2/20/26.
//
//  Direct OpenAI API integration for Berean AI

import Foundation
import SwiftUI
import Combine

/// Service for direct OpenAI API communication
@MainActor
class OpenAIService: ObservableObject {
    static let shared = OpenAIService()
    
    @Published var isProcessing = false
    @Published var lastError: Error?
    
    // OpenAI Configuration
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1"
    private let model = "gpt-4o" // Latest GPT-4 Optimized model
    
    // Response cache for faster repeat queries (15-minute TTL)
    private var responseCache: [String: CachedResponse] = [:]
    private let cacheTTL: TimeInterval = 900 // 15 minutes
    
    init() {
        // Get API key from Info.plist or environment
        if let key = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String {
            self.apiKey = key
        } else {
            // Fallback to empty string - will fail gracefully with error message
            self.apiKey = ""
            print("⚠️ OpenAI API key not found in Info.plist")
            print("   Add OPENAI_API_KEY to your Info.plist to enable Berean AI")
        }
        
        print("✅ OpenAIService initialized")
        print("   Model: \(model)")
        print("   API Key: \(apiKey.isEmpty ? "❌ Not configured" : "✓ Configured")")
    }
    
    // MARK: - Chat Completion
    
    /// Send a message to OpenAI and get streaming response
    func sendMessage(_ message: String, conversationHistory: [OpenAIChatMessage] = []) -> AsyncThrowingStream<String, Error> {
        guard !apiKey.isEmpty else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: OpenAIError.missingAPIKey)
            }
        }
        
        // Check cache for instant responses (only for queries without history)
        if conversationHistory.isEmpty, let cached = getCachedResponse(for: message) {
            print("⚡ Cache hit! Returning instant response")
            return AsyncThrowingStream { continuation in
                Task {
                    // Stream cached response word by word for consistent UX
                    let words = cached.split(separator: " ")
                    for word in words {
                        continuation.yield(String(word) + " ")
                        try await Task.sleep(nanoseconds: 8_000_000) // 8ms
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
                    // Build messages array
                    var messages: [[String: String]] = []
                    
                    // System prompt for Berean AI
                    messages.append([
                        "role": "system",
                        "content": """
                        You are Berean, an intelligent Bible study assistant. You provide accurate, thoughtful, and contextual answers about the Bible, theology, and Christian faith.
                        
                        Guidelines:
                        - Provide clear, accurate biblical information
                        - Include relevant scripture references
                        - Explain historical and cultural context when helpful
                        - Be respectful of different theological perspectives
                        - Use accessible language while maintaining depth
                        - Cite specific verses when discussing biblical content
                        
                        Always be helpful, encouraging, and focused on helping users understand Scripture better.
                        """
                    ])
                    
                    // Add conversation history
                    for msg in conversationHistory {
                        messages.append([
                            "role": msg.isFromUser ? "user" : "assistant",
                            "content": msg.content
                        ])
                    }
                    
                    // Add current message
                    messages.append([
                        "role": "user",
                        "content": message
                    ])
                    
                    // Make streaming request
                    let response = try await self.streamChatCompletion(messages: messages)
                    
                    var fullResponse = ""
                    
                    // Stream the response
                    for try await chunk in response {
                        continuation.yield(chunk)
                        fullResponse += chunk
                    }
                    
                    // Cache the complete response
                    if conversationHistory.isEmpty {
                        self.cacheResponse(fullResponse, for: message)
                    }
                    
                    continuation.finish()
                    
                    await MainActor.run {
                        self.isProcessing = false
                    }
                    
                } catch {
                    print("❌ OpenAI error: \(error.localizedDescription)")
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
    func sendMessageSync(_ message: String, conversationHistory: [OpenAIChatMessage] = []) async throws -> String {
        guard !apiKey.isEmpty else {
            throw OpenAIError.missingAPIKey
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Build messages array
        var messages: [[String: String]] = []
        
        // System prompt
        messages.append([
            "role": "system",
            "content": "You are Berean, an intelligent Bible study assistant focused on providing accurate biblical information and insights."
        ])
        
        // Add history
        for msg in conversationHistory {
            messages.append([
                "role": msg.isFromUser ? "user" : "assistant",
                "content": msg.content
            ])
        }
        
        // Add current message
        messages.append([
            "role": "user",
            "content": message
        ])
        
        // Make non-streaming request
        let response = try await chatCompletion(messages: messages)
        return response
    }
    
    // MARK: - Low-Level API Calls
    
    /// Make a streaming chat completion request
    private func streamChatCompletion(messages: [[String: String]]) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = URL(string: "\(baseURL)/chat/completions")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = 30
                    
                    let body: [String: Any] = [
                        "model": model,
                        "messages": messages,
                        "stream": true,
                        "temperature": 0.7,
                        "max_tokens": 2000
                    ]
                    
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    
                    print("📤 OpenAI streaming request")
                    print("   Model: \(model)")
                    print("   Messages: \(messages.count)")
                    
                    // Make streaming request
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw OpenAIError.invalidResponse
                    }
                    
                    guard httpResponse.statusCode == 200 else {
                        print("❌ HTTP Error: \(httpResponse.statusCode)")
                        throw OpenAIError.httpError(statusCode: httpResponse.statusCode)
                    }
                    
                    // Parse SSE stream
                    for try await line in bytes.lines {
                        // Skip empty lines and comments
                        guard !line.isEmpty, !line.hasPrefix(":") else { continue }
                        
                        // Parse SSE data
                        if line.hasPrefix("data: ") {
                            let data = String(line.dropFirst(6))
                            
                            // Check for stream end
                            if data == "[DONE]" {
                                break
                            }
                            
                            // Parse JSON chunk
                            guard let jsonData = data.data(using: .utf8),
                                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                                  let choices = json["choices"] as? [[String: Any]],
                                  let firstChoice = choices.first,
                                  let delta = firstChoice["delta"] as? [String: Any],
                                  let content = delta["content"] as? String else {
                                continue
                            }
                            
                            continuation.yield(content)
                        }
                    }
                    
                    continuation.finish()
                    print("✅ OpenAI streaming complete")
                    
                } catch {
                    print("❌ Streaming error: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Make a non-streaming chat completion request
    private func chatCompletion(messages: [[String: String]]) async throws -> String {
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 2000
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("📤 OpenAI request")
        print("   Model: \(model)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            print("❌ HTTP Error: \(httpResponse.statusCode)")
            if let errorText = String(data: data, encoding: .utf8) {
                print("❌ Error response: \(errorText)")
            }
            throw OpenAIError.httpError(statusCode: httpResponse.statusCode)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.invalidResponse
        }
        
        print("✅ OpenAI request complete")
        return content
    }
    
    // MARK: - Cache Management
    
    private func getCachedResponse(for query: String) -> String? {
        let cacheKey = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let cached = responseCache[cacheKey] else {
            return nil
        }
        
        let age = Date().timeIntervalSince(cached.timestamp)
        if age > cacheTTL {
            responseCache.removeValue(forKey: cacheKey)
            return nil
        }
        
        return cached.response
    }
    
    private func cacheResponse(_ response: String, for query: String) {
        let cacheKey = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        responseCache[cacheKey] = CachedResponse(response: response, timestamp: Date())
        
        // Limit cache size to 50 entries
        if responseCache.count > 50 {
            let sortedKeys = responseCache.sorted { $0.value.timestamp < $1.value.timestamp }
            if let oldestKey = sortedKeys.first?.key {
                responseCache.removeValue(forKey: oldestKey)
            }
        }
        
        print("💾 Cached response for: \(query.prefix(50))...")
    }
}

// MARK: - Supporting Types

struct OpenAIChatMessage {
    let content: String
    let isFromUser: Bool
}

struct CachedResponse {
    let response: String
    let timestamp: Date
}

enum OpenAIError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case httpError(statusCode: Int)
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is not configured. Please add OPENAI_API_KEY to Info.plist."
        case .invalidResponse:
            return "Invalid response from OpenAI API."
        case .httpError(let statusCode):
            return "OpenAI API error (HTTP \(statusCode))"
        }
    }
}
