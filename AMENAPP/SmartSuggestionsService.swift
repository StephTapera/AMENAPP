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
import FirebaseFunctions

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
    private let functions = Functions.functions()
    private let cacheExpiryDays = 7 // Refresh suggestions weekly

    private init() {}
    
    // MARK: - Main Suggestion Function
    
    func getSuggestion(for targetUserId: String, currentUserId: String) async throws -> SmartSuggestion? {
        // Check cache first
        if let cached = try? await getCachedSuggestion(targetUserId: targetUserId, currentUserId: currentUserId) {
            // Check if cache is still valid (< 7 days old)
            let daysSinceGenerated = Calendar.current.dateComponents([.day], from: cached.generatedAt, to: Date()).day ?? 0
            if daysSinceGenerated < cacheExpiryDays {
                dlog("✅ Using cached suggestion for \(targetUserId)")
                return cached
            }
        }
        
        dlog("🤖 Generating AI suggestion for \(targetUserId)")
        
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
        
        dlog("✅ Generated suggestion: \(reason)")
        return suggestion
    }
    
    // MARK: - Cloud Function Proxy

    /// Calls the "smartSuggestionsProxy" Firebase callable.
    /// The OPENAI_API_KEY never touches the device.
    private func generateInsight(
        currentUser: SuggestionUserProfile,
        targetUser: SuggestionUserProfile,
        mutualFollows: Int
    ) async throws -> String {
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

        let payload: [String: Any] = ["prompt": prompt, "maxTokens": 20]

        let result = try await functions.httpsCallable("smartSuggestionsProxy").call(payload)
        guard let data = result.data as? [String: Any],
              let content = data["text"] as? String else {
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
    
    private func fetchUserProfile(userId: String) async throws -> SuggestionUserProfile {
        let doc = try await db.collection("users").document(userId).getDocument()
        
        guard let data = doc.data() else {
            throw SuggestionError.userNotFound
        }
        
        return SuggestionUserProfile(
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
        dlog("🤖 Generating suggestions for \(targetUserIds.count) users")
        
        for targetUserId in targetUserIds {
            do {
                _ = try await getSuggestion(for: targetUserId, currentUserId: currentUserId)
                
                // Rate limit: 3 requests per second for free tier
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                dlog("⚠️ Failed to generate suggestion for \(targetUserId): \(error)")
            }
        }
        
        dlog("✅ Batch suggestion generation complete")
    }
}

// MARK: - Supporting Models

struct SuggestionUserProfile {
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
