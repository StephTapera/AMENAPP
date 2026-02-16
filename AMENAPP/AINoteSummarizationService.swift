//
//  AINoteSummarizationService.swift
//  AMENAPP
//
//  Created by Assistant on 2/11/26.
//
//  AI-powered sermon note summarization using Vertex AI
//

import Foundation
import FirebaseFirestore

// MARK: - Note Summary Model

struct NoteSummary: Codable {
    let mainTheme: String
    let scripture: [String]
    let keyPoints: [String]
    let actionSteps: [String]
    let generatedAt: Date
}

// MARK: - AI Note Summarization Service

class AINoteSummarizationService {
    static let shared = AINoteSummarizationService()
    private let db = Firestore.firestore()
    
    private init() {}
    
    /// Generate AI summary of sermon notes
    /// - Parameter noteContent: Raw note content
    /// - Returns: Structured summary with theme, scripture, points, actions (nil if Cloud Function unavailable)
    func summarizeNote(content: String) async -> NoteSummary? {
        
        print("📝 [AI SUMMARY] Generating summary for note (\(content.count) chars)")
        
        // Send to Cloud Function
        let requestData: [String: Any] = [
            "content": content,
            "timestamp": FieldValue.serverTimestamp()
        ]
        
        do {
            print("📤 [AI SUMMARY] Sending request to Cloud Function...")
            let result = try await db.collection("noteSummaryRequests")
                .addDocument(data: requestData)
            
            print("⏳ [AI SUMMARY] Waiting for AI response (request ID: \(result.documentID))...")
            
            // Wait for AI response (max 5 seconds)
            let summary = try await waitForSummary(requestId: result.documentID)
            
            print("✅ [AI SUMMARY] Summary generated: \(summary.mainTheme)")
            return summary
            
        } catch let error as NSError where error.code == 408 {
            // Timeout error - Cloud Function may not be deployed
            print("⚠️ [AI SUMMARY] Timeout - Cloud Function may not be deployed. Summary unavailable.")
            return nil
        } catch {
            print("❌ [AI SUMMARY] Error: \(error)")
            // Return nil for other errors too (graceful degradation)
            return nil
        }
    }
    
    /// Wait for AI summary response
    private func waitForSummary(requestId: String) async throws -> NoteSummary {
        for _ in 0..<10 { // 10 attempts × 0.5s = 5 seconds
            try await Task.sleep(nanoseconds: 500_000_000)
            
            let snapshot = try await db.collection("noteSummaryResults")
                .document(requestId)
                .getDocument()
            
            if snapshot.exists,
               let data = snapshot.data(),
               let mainTheme = data["mainTheme"] as? String,
               let scripture = data["scripture"] as? [String],
               let keyPoints = data["keyPoints"] as? [String],
               let actionSteps = data["actionSteps"] as? [String] {
                
                return NoteSummary(
                    mainTheme: mainTheme,
                    scripture: scripture,
                    keyPoints: keyPoints,
                    actionSteps: actionSteps,
                    generatedAt: Date()
                )
            }
        }
        
        throw NSError(
            domain: "AINoteSummary",
            code: 408,
            userInfo: [NSLocalizedDescriptionKey: "Summary generation timeout"]
        )
    }
    
    /// Quick validation before sending to AI
    func validateNoteContent(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 50 // Minimum 50 characters for meaningful summary
    }
}
