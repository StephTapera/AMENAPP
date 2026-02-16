//
//  AIScriptureCrossRefService.swift
//  AMENAPP
//
//  Created by Assistant on 2/11/26.
//
//  AI-powered scripture cross-reference suggestions using Vertex AI
//

import Foundation
import FirebaseFirestore

// MARK: - Scripture Reference Model

struct ScriptureReference: Identifiable, Codable {
    let id = UUID()
    let verse: String           // "Romans 5:8"
    let description: String     // "God's love for us"
    let relevanceScore: Double  // 0-1
    
    private enum CodingKeys: String, CodingKey {
        case verse, description, relevanceScore
    }
}

// MARK: - AI Scripture Cross-Reference Service

class AIScriptureCrossRefService {
    static let shared = AIScriptureCrossRefService()
    private let db = Firestore.firestore()
    
    // Cache to avoid repeated lookups
    private var cache: [String: [ScriptureReference]] = [:]
    
    private init() {}
    
    /// Find related scripture verses using AI
    /// - Parameter verse: The verse reference (e.g., "John 3:16")
    /// - Returns: Array of related scripture references with descriptions
    func findRelatedVerses(for verse: String) async throws -> [ScriptureReference] {
        
        print("📖 [AI SCRIPTURE] Finding related verses for: \(verse)")
        
        // Check cache first
        if let cached = cache[verse] {
            print("✅ [AI SCRIPTURE] Returning cached results for \(verse)")
            return cached
        }
        
        // Send to Cloud Function
        let requestData: [String: Any] = [
            "verse": verse,
            "timestamp": FieldValue.serverTimestamp()
        ]
        
        do {
            print("📤 [AI SCRIPTURE] Sending request to Cloud Function...")
            let result = try await db.collection("scriptureReferenceRequests")
                .addDocument(data: requestData)
            
            print("⏳ [AI SCRIPTURE] Waiting for AI response...")
            
            // Wait for AI response (max 4 seconds)
            let references = try await waitForReferences(requestId: result.documentID)
            
            // Cache the result
            cache[verse] = references
            
            print("✅ [AI SCRIPTURE] Found \(references.count) related verses")
            return references
            
        } catch let error as NSError where error.code == 408 {
            // Timeout error - return empty array instead of throwing
            print("⚠️ [AI SCRIPTURE] Timeout - Cloud Function may not be deployed. Returning empty results.")
            return []
        } catch {
            print("❌ [AI SCRIPTURE] Error: \(error)")
            // Return empty array for other errors too (graceful degradation)
            return []
        }
    }
    
    /// Wait for AI scripture reference response
    private func waitForReferences(requestId: String) async throws -> [ScriptureReference] {
        for _ in 0..<8 { // 8 attempts × 0.5s = 4 seconds
            try await Task.sleep(nanoseconds: 500_000_000)
            
            let snapshot = try await db.collection("scriptureReferenceResults")
                .document(requestId)
                .getDocument()
            
            if snapshot.exists,
               let data = snapshot.data(),
               let referencesData = data["references"] as? [[String: Any]] {
                
                let references = referencesData.compactMap { refData -> ScriptureReference? in
                    guard let verse = refData["verse"] as? String,
                          let description = refData["description"] as? String,
                          let relevanceScore = refData["relevanceScore"] as? Double else {
                        return nil
                    }
                    
                    return ScriptureReference(
                        verse: verse,
                        description: description,
                        relevanceScore: relevanceScore
                    )
                }
                
                return references
            }
        }
        
        throw NSError(
            domain: "AIScriptureCrossRef",
            code: 408,
            userInfo: [NSLocalizedDescriptionKey: "Scripture lookup timeout"]
        )
    }
    
    /// Extract verse references from text
    func extractVerseReferences(from text: String) -> [String] {
        // Regex pattern for Bible verses: "John 3:16", "1 Corinthians 13:4-8", etc.
        let pattern = #"([1-3]?\s?[A-Za-z]+)\s+(\d+):(\d+)(-\d+)?"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        
        return matches.compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }
    
    /// Clear cache (e.g., when user logs out)
    func clearCache() {
        cache.removeAll()
        print("🗑️ [AI SCRIPTURE] Cache cleared")
    }
    
    /// Clear cache for a specific verse
    func clearCache(for verse: String) {
        cache.removeValue(forKey: verse)
        print("🗑️ [AI SCRIPTURE] Cleared cache for: \(verse)")
    }
}
