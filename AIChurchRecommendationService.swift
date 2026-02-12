//
//  AIChurchRecommendationService.swift
//  AMENAPP
//
//  Created by Assistant on 2/11/26.
//
//  AI-powered personalized church recommendations using Vertex AI
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Church Recommendation Model

struct ChurchRecommendation: Identifiable, Codable {
    let id: String
    let churchName: String
    let address: String
    let distance: Double        // in miles
    let matchScore: Double      // 0-100
    let reasons: [String]       // Why recommended
    let highlights: [String]    // Key features
    let worshipStyle: String?
    let size: String?
    
    // For integration with existing Church model
    var churchId: String { id }
}

// MARK: - User Profile for Recommendations

struct UserRecommendationProfile: Codable {
    let userId: String
    let interests: [String]          // From user profile
    let recentPrayerTopics: [String] // Last 30 days
    let recentPostTopics: [String]   // Analyzed from posts
    let familyStatus: String?        // Single, married, family with kids
    let preferredWorshipStyle: String? // Contemporary, traditional, blended
}

// MARK: - AI Church Recommendation Service

class AIChurchRecommendationService {
    static let shared = AIChurchRecommendationService()
    private let db = Firestore.firestore()
    
    private init() {}
    
    /// Get personalized church recommendations
    /// - Parameters:
    ///   - nearbyChurches: Churches within user's search radius
    ///   - userLocation: User's current location
    /// - Returns: Array of recommended churches with match scores and reasons
    func getRecommendations(
        nearbyChurches: [[String: Any]],
        userLocation: [String: Double]
    ) async throws -> [ChurchRecommendation] {
        
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "AIChurchRecs", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("⛪ [AI CHURCH] Getting recommendations for \(nearbyChurches.count) churches")
        
        // Build user profile
        let userProfile = try await buildUserProfile(userId: userId)
        
        // Send to Cloud Function
        let requestData: [String: Any] = [
            "userId": userId,
            "userProfile": try userProfile.asDictionary(),
            "churches": nearbyChurches,
            "userLocation": userLocation,
            "timestamp": FieldValue.serverTimestamp()
        ]
        
        do {
            print("📤 [AI CHURCH] Sending request to Cloud Function...")
            let result = try await db.collection("churchRecommendationRequests")
                .addDocument(data: requestData)
            
            print("⏳ [AI CHURCH] Waiting for AI analysis...")
            
            // Wait for AI response (max 6 seconds)
            let recommendations = try await waitForRecommendations(requestId: result.documentID)
            
            print("✅ [AI CHURCH] Received \(recommendations.count) recommendations")
            return recommendations
            
        } catch {
            print("❌ [AI CHURCH] Error: \(error)")
            throw error
        }
    }
    
    /// Build user profile for recommendations
    private func buildUserProfile(userId: String) async throws -> UserRecommendationProfile {
        
        // Fetch user data
        let userDoc = try await db.collection("users").document(userId).getDocument()
        guard let userData = userDoc.data() else {
            throw NSError(domain: "AIChurchRecs", code: 404, userInfo: [NSLocalizedDescriptionKey: "User profile not found"])
        }
        
        // Get interests from profile
        let interests = userData["interests"] as? [String] ?? []
        let familyStatus = userData["familyStatus"] as? String
        let preferredWorshipStyle = userData["preferredWorshipStyle"] as? String
        
        // Analyze recent prayers (last 30 days)
        let prayerTopics = try await analyzePrayerTopics(userId: userId)
        
        // Analyze recent posts
        let postTopics = try await analyzePostTopics(userId: userId)
        
        return UserRecommendationProfile(
            userId: userId,
            interests: interests,
            recentPrayerTopics: prayerTopics,
            recentPostTopics: postTopics,
            familyStatus: familyStatus,
            preferredWorshipStyle: preferredWorshipStyle
        )
    }
    
    /// Analyze user's recent prayer topics
    private func analyzePrayerTopics(userId: String) async throws -> [String] {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        let snapshot = try await db.collection("prayers")
            .whereField("userId", isEqualTo: userId)
            .whereField("createdAt", isGreaterThan: Timestamp(date: thirtyDaysAgo))
            .limit(to: 20)
            .getDocuments()
        
        let prayerTexts = snapshot.documents.compactMap { $0.data()["content"] as? String }
        
        // Extract common topics (simplified - AI will do deep analysis)
        return extractTopics(from: prayerTexts)
    }
    
    /// Analyze user's recent post topics
    private func analyzePostTopics(userId: String) async throws -> [String] {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        let snapshot = try await db.collection("posts")
            .whereField("authorId", isEqualTo: userId)
            .whereField("createdAt", isGreaterThan: Timestamp(date: thirtyDaysAgo))
            .limit(to: 20)
            .getDocuments()
        
        let postTexts = snapshot.documents.compactMap { $0.data()["content"] as? String }
        
        return extractTopics(from: postTexts)
    }
    
    /// Extract topics from text array (basic keyword extraction)
    private func extractTopics(from texts: [String]) -> [String] {
        let combinedText = texts.joined(separator: " ").lowercased()
        var topics: [String] = []
        
        let keywords = [
            "family", "youth", "worship", "music", "bible study",
            "prayer", "community", "mission", "children", "kids",
            "marriage", "singles", "seniors", "recovery", "counseling"
        ]
        
        for keyword in keywords {
            if combinedText.contains(keyword) {
                topics.append(keyword)
            }
        }
        
        return Array(Set(topics)) // Remove duplicates
    }
    
    /// Wait for AI recommendation response
    private func waitForRecommendations(requestId: String) async throws -> [ChurchRecommendation] {
        for _ in 0..<12 { // 12 attempts × 0.5s = 6 seconds
            try await Task.sleep(nanoseconds: 500_000_000)
            
            let snapshot = try await db.collection("churchRecommendationResults")
                .document(requestId)
                .getDocument()
            
            if snapshot.exists,
               let data = snapshot.data(),
               let recommendationsData = data["recommendations"] as? [[String: Any]] {
                
                let recommendations = recommendationsData.compactMap { recData -> ChurchRecommendation? in
                    guard let id = recData["id"] as? String,
                          let churchName = recData["churchName"] as? String,
                          let address = recData["address"] as? String,
                          let distance = recData["distance"] as? Double,
                          let matchScore = recData["matchScore"] as? Double,
                          let reasons = recData["reasons"] as? [String],
                          let highlights = recData["highlights"] as? [String] else {
                        return nil
                    }
                    
                    return ChurchRecommendation(
                        id: id,
                        churchName: churchName,
                        address: address,
                        distance: distance,
                        matchScore: matchScore,
                        reasons: reasons,
                        highlights: highlights,
                        worshipStyle: recData["worshipStyle"] as? String,
                        size: recData["size"] as? String
                    )
                }
                
                // Sort by match score
                return recommendations.sorted { $0.matchScore > $1.matchScore }
            }
        }
        
        throw NSError(
            domain: "AIChurchRecs",
            code: 408,
            userInfo: [NSLocalizedDescriptionKey: "Recommendation timeout"]
        )
    }
}

// MARK: - Encodable Extension

extension Encodable {
    func asDictionary() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        guard let dictionary = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any] else {
            throw NSError(domain: "Encoding", code: 0, userInfo: nil)
        }
        return dictionary
    }
}
