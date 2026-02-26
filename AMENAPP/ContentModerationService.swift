//
//  ContentModerationService.swift
//  AMENAPP
//
//  Client-side service for content moderation
//  Calls Firebase Cloud Functions moderation endpoint
//

import Foundation
import FirebaseAuth
import FirebaseFunctions

class ContentModerationService {
    static let shared = ContentModerationService()
    private let functions = Functions.functions()
    
    // MARK: - Main Moderation Method
    
    /// Moderate content before posting
    static func moderateContent(
        text: String,
        category: ContentCategory,
        signals: AuthenticitySignals,
        parentContentId: String? = nil
    ) async throws -> ModerationDecision {
        
        let functions = Functions.functions()
        
        let data: [String: Any] = [
            "contentText": text,
            "contentType": category.rawValue,
            "authenticitySignals": [
                "typedCharacters": signals.typedCharacters,
                "pastedCharacters": signals.pastedCharacters,
                "typedVsPastedRatio": signals.typedVsPastedRatio,
                "largestPasteLength": signals.largestPasteLength,
                "pasteEventCount": signals.pasteEventCount,
                "typingDurationSeconds": signals.typingDurationSeconds,
                "hasLargePaste": signals.hasLargePaste
            ],
            "parentContentId": parentContentId as Any
        ]
        
        do {
            let result = try await functions.httpsCallable("moderateContent").call(data)
            let resultData = result.data as? [String: Any] ?? [:]
            
            return ModerationDecision(
                action: ContentIntegrityAction(rawValue: resultData["decision"] as? String ?? "allow") ?? .allow,
                confidence: resultData["confidence"] as? Double ?? 0,
                reasons: resultData["reasons"] as? [String] ?? [],
                detectedBehaviors: [],  // Not returned from server
                suggestedRevisions: resultData["suggestedRevisions"] as? [String],
                reviewRequired: resultData["reviewRequired"] as? Bool ?? false,
                appealable: resultData["appealable"] as? Bool ?? false,
                scores: ModerationScores(
                    toxicity: 0,
                    spam: 0,
                    aiSuspicion: 0,
                    duplicateMatch: 0,
                    authenticity: 0,
                    userRiskScore: 0
                )  // Scores not returned to client
            )
            
        } catch {
            print("❌ Moderation error: \(error)")
            // Fail open - allow content but log error
            return ModerationDecision(
                action: .allow,
                confidence: 0,
                reasons: ["Moderation service unavailable"],
                detectedBehaviors: [],
                suggestedRevisions: nil,
                reviewRequired: false,
                appealable: false,
                scores: ModerationScores(
                    toxicity: 0,
                    spam: 0,
                    aiSuspicion: 0,
                    duplicateMatch: 0,
                    authenticity: 1.0,
                    userRiskScore: 0
                )
            )
        }
    }
    
    // MARK: - Report Content
    
    static func reportContent(
        contentId: String,
        contentType: ContentCategory,
        reason: String,
        details: String
    ) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ContentModeration", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let functions = Functions.functions()
        
        let data: [String: Any] = [
            "contentId": contentId,
            "contentType": contentType.rawValue,
            "reportReason": reason,
            "reportDetails": details
        ]
        
        _ = try await functions.httpsCallable("reportContent").call(data)
    }
    
    // MARK: - Submit Appeal
    
    static func submitAppeal(
        contentId: String,
        appealReason: String
    ) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ContentModeration", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let functions = Functions.functions()
        
        let data: [String: Any] = [
            "contentId": contentId,
            "appealReason": appealReason
        ]
        
        _ = try await functions.httpsCallable("submitAppeal").call(data)
    }
}
