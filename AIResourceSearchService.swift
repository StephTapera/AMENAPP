//
//  AIResourceSearchService.swift
//  AMENAPP
//
//  Created by Assistant on 2/11/26.
//
//  Smart natural language search for resources using Vertex AI
//

import Foundation
import FirebaseFirestore

// MARK: - Search Result Model

struct AISearchResult: Identifiable {
    let id = UUID()
    let resource: ResourceItem
    let relevanceScore: Double
    let reason: String
}

// MARK: - AI Resource Search Service

class AIResourceSearchService {
    static let shared = AIResourceSearchService()
    private let db = Firestore.firestore()
    
    private init() {}
    
    /// Search resources using natural language with AI
    /// - Parameters:
    ///   - query: User's natural language query
    ///   - allResources: All available resources
    /// - Returns: Array of ranked search results
    func searchWithAI(
        query: String,
        allResources: [ResourceItem]
    ) async throws -> [AISearchResult] {
        
        print("🔍 [AI SEARCH] Natural language query: \"\(query)\"")
        
        // Step 1: Call Firebase Cloud Function for AI analysis
        let aiAnalysis = try await analyzeSearchIntent(query: query)
        
        print("🤖 [AI SEARCH] Intent: \(aiAnalysis.intent)")
        print("🤖 [AI SEARCH] Keywords: \(aiAnalysis.keywords.joined(separator: ", "))")
        
        // Step 2: Rank resources based on AI analysis
        let rankedResults = rankResources(
            resources: allResources,
            analysis: aiAnalysis
        )
        
        print("✅ [AI SEARCH] Found \(rankedResults.count) relevant results")
        
        return rankedResults
    }
    
    /// Analyze search intent using Vertex AI
    private func analyzeSearchIntent(query: String) async throws -> SearchIntent {
        
        // Create analysis request
        let requestData: [String: Any] = [
            "query": query,
            "timestamp": FieldValue.serverTimestamp()
        ]
        
        do {
            // Send to Cloud Function
            print("📤 [AI SEARCH] Sending request to Cloud Function...")
            let result = try await db.collection("aiSearchRequests")
                .addDocument(data: requestData)
            
            // Wait for AI response (max 3 seconds)
            let response = try await waitForSearchResponse(requestId: result.documentID)
            
            print("✅ [AI SEARCH] Received AI analysis")
            return response
            
        } catch {
            print("❌ [AI SEARCH] Error: \(error)")
            
            // Fallback: Basic keyword extraction
            return SearchIntent(
                intent: "general",
                keywords: extractBasicKeywords(from: query),
                categories: [],
                sentiment: "neutral",
                urgency: "normal"
            )
        }
    }
    
    /// Wait for AI search analysis response
    private func waitForSearchResponse(requestId: String) async throws -> SearchIntent {
        for _ in 0..<6 { // 6 attempts × 0.5s = 3 seconds
            try await Task.sleep(nanoseconds: 500_000_000)
            
            let snapshot = try await db.collection("aiSearchResults")
                .document(requestId)
                .getDocument()
            
            if snapshot.exists,
               let data = snapshot.data(),
               let intent = data["intent"] as? String,
               let keywords = data["keywords"] as? [String],
               let categories = data["categories"] as? [String],
               let sentiment = data["sentiment"] as? String,
               let urgency = data["urgency"] as? String {
                
                return SearchIntent(
                    intent: intent,
                    keywords: keywords,
                    categories: categories,
                    sentiment: sentiment,
                    urgency: urgency
                )
            }
        }
        
        throw NSError(
            domain: "AIResourceSearch",
            code: 408,
            userInfo: [NSLocalizedDescriptionKey: "AI search timeout"]
        )
    }
    
    /// Rank resources based on AI analysis
    private func rankResources(
        resources: [ResourceItem],
        analysis: SearchIntent
    ) -> [AISearchResult] {
        
        var scoredResults: [(resource: ResourceItem, score: Double, reason: String)] = []
        
        for resource in resources {
            var score: Double = 0
            var reasons: [String] = []
            
            // Category match (highest priority)
            if analysis.categories.contains(where: { $0.lowercased() == resource.category.lowercased() }) {
                score += 50
                reasons.append("Matches \(resource.category)")
            }
            
            // Keyword matches in title
            let titleWords = resource.title.lowercased().split(separator: " ").map { String($0) }
            let titleMatches = analysis.keywords.filter { keyword in
                titleWords.contains(keyword.lowercased())
            }
            score += Double(titleMatches.count) * 20
            if !titleMatches.isEmpty {
                reasons.append("Title contains: \(titleMatches.joined(separator: ", "))")
            }
            
            // Keyword matches in description
            let descWords = resource.description.lowercased()
            let descMatches = analysis.keywords.filter { keyword in
                descWords.contains(keyword.lowercased())
            }
            score += Double(descMatches.count) * 10
            if !descMatches.isEmpty {
                reasons.append("Related to: \(descMatches.joined(separator: ", "))")
            }
            
            // Urgency boost (crisis resources get priority)
            if analysis.urgency == "high" && resource.category == "Crisis" {
                score += 100
                reasons.append("Immediate help available")
            }
            
            // Only include if score > 0
            if score > 0 {
                scoredResults.append((
                    resource: resource,
                    score: score,
                    reason: reasons.joined(separator: " • ")
                ))
            }
        }
        
        // Sort by score (highest first)
        scoredResults.sort { $0.score > $1.score }
        
        // Convert to AISearchResult
        return scoredResults.map { item in
            AISearchResult(
                resource: item.resource,
                relevanceScore: item.score,
                reason: item.reason
            )
        }
    }
    
    /// Basic keyword extraction fallback
    private func extractBasicKeywords(from query: String) -> [String] {
        let lowercased = query.lowercased()
        var keywords: [String] = []
        
        // Common search terms
        let terms = [
            "anxiety", "depression", "mental health", "crisis",
            "prayer", "bible", "church", "counseling",
            "help", "support", "community", "giving",
            "podcast", "sermon", "book", "study"
        ]
        
        for term in terms {
            if lowercased.contains(term) {
                keywords.append(term)
            }
        }
        
        return keywords
    }
}

// MARK: - Search Intent Model

struct SearchIntent {
    let intent: String          // "help_seeking", "learning", "general"
    let keywords: [String]      // Extracted key terms
    let categories: [String]    // Suggested resource categories
    let sentiment: String       // "positive", "neutral", "distressed"
    let urgency: String         // "low", "normal", "high"
}
