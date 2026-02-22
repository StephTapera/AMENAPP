//
//  SmartSuggestionsService.swift
//  AMENAPP
//
//  AI-powered people suggestions using OpenAI GPT-4 mini
//  Generates personalized "why you might know this person" insights
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Smart Suggestion Model

struct SmartSuggestion: Codable {
    let userId: String
    let reason: String // "Shares your interest in worship music"
    let confidence: Double // 0.0 - 1.0
    let generatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case userId
        case reason
        case confidence
        case generatedAt
    }
}

// MARK: - Smart Suggestions Service

@MainActor
class SmartSuggestionsService {
    static let shared = SmartSuggestionsService()
    
    private let db = Firestore.firestore()
    private let openAIKey: String
    private let cacheExpiryDays = 7 // Refresh suggestions weekly
    
    private init() {
        // Use the OpenAI API key
        self.openAIKey = "YOUR_OPENAI_API_KEY_HERE"
    }
    
    // MARK: - Main Suggestion Function
    
    func getSuggestion(for targetUserId: String, currentUserId: String) async throws -> SmartSuggestion? {
        // Check cache first
        if let cached = try? await getCachedSuggestion(targetUserId: targetUserId, currentUserId: currentUserId) {
            // Check if cache is still valid (< 7 days old)
            let daysSinceGenerated = Calendar.current.dateComponents([.day], from: cached.generatedAt, to: Date()).day ?? 0
            if daysSinceGenerated < cacheExpiryDays {
                print("✅ Using cached suggestion for \(targetUserId)")
                return cached
            }
        }
        
        print("🤖 Generating AI suggestion for \(targetUserId)")
        
        // Fetch user profiles
        let currentUser = try await fetchUserProfile(userId: currentUserId)
        let targetUser = try await fetchUserProfile(userId: targetUserId)
        
        // Get mutual connections
        let mutualFollows = try await getMutualFollows(currentUserId: currentUserId, targetUserId: targetUserId)
        
        // Generate AI insight
        let reason = try await generateInsight(
            currentUser: currentUser,
            targetUser: targetUser,
            mutualFollows: mutualFollows
        )
        
        guard !reason.isEmpty else {
            return nil
        }
        
        let suggestion = SmartSuggestion(
            userId: targetUserId,
            reason: reason,
            confidence: 0.8,
            generatedAt: Date()
        )
        
        // Cache result
        try await cacheSuggestion(suggestion, currentUserId: currentUserId)
        
        print("✅ Generated suggestion: \(reason)")
        return suggestion
    }
    
    // MARK: - OpenAI Integration
    
    private func generateInsight(
        currentUser: UserProfile,
        targetUser: UserProfile,
        mutualFollows: Int
    ) async throws -> String {
        let endpoint = "https://api.openai.com/v1/chat/completions"
        
        guard let url = URL(string: endpoint) else {
            throw SuggestionError.invalidURL
        }
        
        // Build prompt
        let prompt = """
        You are a Christian social network assistant. Generate a single, concise reason (max 8 words) why these two believers might connect. Be warm and faith-focused.
        
        User 1: \(currentUser.name)
        - Location: \(currentUser.location ?? "Unknown")
        - Interests: \(currentUser.interests.joined(separator: ", "))
        - Bio: \(currentUser.bio ?? "")
        
        User 2: \(targetUser.name)
        - Location: \(targetUser.location ?? "Unknown")
        - Interests: \(targetUser.interests.joined(separator: ", "))
        - Bio: \(targetUser.bio ?? "")
        
        Mutual follows: \(mutualFollows)
        
        Generate ONE reason starting with a verb or descriptor. Examples:
        - "Shares your love for worship music"
        - "Also from Brooklyn"
        - "Follows 5 of your friends"
        - "Fellow youth group leader"
        - "Both love hiking and nature"
        
        Reason (max 8 words):
        """
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini", // Cheapest model: $0.15 per 1M tokens
            "messages": [
                [
                    "role": "system",
                    "content": "You are a concise, warm Christian community connector. Output ONLY the connection reason, nothing else."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "max_tokens": 20,
            "temperature": 0.7
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SuggestionError.networkError
        }
        
        guard httpResponse.statusCode == 200 else {
            print("❌ OpenAI API error: \(httpResponse.statusCode)")
            if let errorString = String(data: data, encoding: .utf8) {
                print("   Response: \(errorString)")
            }
            throw SuggestionError.apiError(httpResponse.statusCode)
        }
        
        // Parse response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return ""
        }
        
        // Clean up response
        let reason = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "- ", with: "")
        
        return reason
    }
    
    // MARK: - Data Fetching
    
    private func fetchUserProfile(userId: String) async throws -> UserProfile {
        let doc = try await db.collection("users").document(userId).getDocument()
        
        guard let data = doc.data() else {
            throw SuggestionError.userNotFound
        }
        
        return UserProfile(
            id: userId,
            name: data["displayName"] as? String ?? data["name"] as? String ?? "User",
            location: data["location"] as? String ?? data["city"] as? String,
            interests: data["interests"] as? [String] ?? [],
            bio: data["bio"] as? String
        )
    }
    
    private func getMutualFollows(currentUserId: String, targetUserId: String) async throws -> Int {
        // Get current user's following
        let currentFollowing = try await db
            .collection("users")
            .document(currentUserId)
            .collection("following")
            .getDocuments()
        
        let currentFollowingIds = Set(currentFollowing.documents.map { $0.documentID })
        
        // Get target user's followers
        let targetFollowers = try await db
            .collection("users")
            .document(targetUserId)
            .collection("followers")
            .getDocuments()
        
        let targetFollowerIds = Set(targetFollowers.documents.map { $0.documentID })
        
        // Count intersection
        let mutualCount = currentFollowingIds.intersection(targetFollowerIds).count
        
        return mutualCount
    }
    
    // MARK: - Caching
    
    private func getCachedSuggestion(targetUserId: String, currentUserId: String) async throws -> SmartSuggestion? {
        let doc = try await db
            .collection("users")
            .document(currentUserId)
            .collection("smartSuggestions")
            .document(targetUserId)
            .getDocument()
        
        guard doc.exists, let data = doc.data() else {
            return nil
        }
        
        guard let reason = data["reason"] as? String,
              let confidence = data["confidence"] as? Double,
              let timestamp = data["generatedAt"] as? Timestamp else {
            return nil
        }
        
        return SmartSuggestion(
            userId: targetUserId,
            reason: reason,
            confidence: confidence,
            generatedAt: timestamp.dateValue()
        )
    }
    
    private func cacheSuggestion(_ suggestion: SmartSuggestion, currentUserId: String) async throws {
        try await db
            .collection("users")
            .document(currentUserId)
            .collection("smartSuggestions")
            .document(suggestion.userId)
            .setData([
                "reason": suggestion.reason,
                "confidence": suggestion.confidence,
                "generatedAt": Timestamp(date: suggestion.generatedAt)
            ])
    }
    
    // MARK: - Batch Processing
    
    func batchGenerateSuggestions(for currentUserId: String, targetUserIds: [String]) async {
        print("🤖 Generating suggestions for \(targetUserIds.count) users")
        
        for targetUserId in targetUserIds {
            do {
                _ = try await getSuggestion(for: targetUserId, currentUserId: currentUserId)
                
                // Rate limit: 3 requests per second for free tier
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                print("⚠️ Failed to generate suggestion for \(targetUserId): \(error)")
            }
        }
        
        print("✅ Batch suggestion generation complete")
    }
}

// MARK: - Supporting Models

struct UserProfile {
    let id: String
    let name: String
    let location: String?
    let interests: [String]
    let bio: String?
}

// MARK: - Errors

enum SuggestionError: Error {
    case invalidURL
    case networkError
    case apiError(Int)
    case userNotFound
    case parsingError
}
