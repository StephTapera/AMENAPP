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

        // Ensure user is authenticated and has a fresh token before calling the Cloud Function.
        // Without a valid auth token the function will return UNAUTHENTICATED.
        // Force-refresh prevents stale token errors (seen as GTMSessionFetcher duplicate call warnings).
        guard let currentUser = Auth.auth().currentUser else {
            // Unauthenticated — cannot post. Hard block; do not allow content through.
            dlog("❌ Moderation: user not authenticated — blocking content")
            return ModerationDecision(
                action: .holdForReview,
                confidence: 1.0,
                reasons: ["Not authenticated — content blocked"],
                detectedBehaviors: [],
                suggestedRevisions: nil,
                reviewRequired: true,
                appealable: false,
                scores: ModerationScores(
                    toxicity: 0,
                    spam: 0,
                    aiSuspicion: 0,
                    duplicateMatch: 0,
                    authenticity: 0,
                    userRiskScore: 1.0
                )
            )
        }

        // Force-refresh the ID token so the Cloud Function receives a valid auth header
        do {
            _ = try await currentUser.getIDToken(forcingRefresh: true)
        } catch {
            dlog("⚠️ Could not refresh ID token: \(error.localizedDescription) — proceeding anyway")
        }

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
            let msg = error.localizedDescription.lowercased()
            let isExpectedDevError = msg.contains("unauthenticated") || msg.contains("permission")

            #if DEBUG
            // In simulator/DEBUG the Cloud Functions moderation endpoint is often unavailable
            // (App Check 403, auth issues). Allow content through so developers can test posting.
            if isExpectedDevError {
                Logger.debug("Moderation unavailable (expected in dev/simulator): \(error.localizedDescription)")
            } else {
                dlog("❌ Moderation error: \(error)")
            }
            return ModerationDecision(
                action: .allow,
                confidence: 0.5,
                reasons: ["Moderation service unavailable in debug mode — content allowed for testing"],
                detectedBehaviors: [],
                suggestedRevisions: nil,
                reviewRequired: false,
                appealable: false,
                scores: ModerationScores(
                    toxicity: 0,
                    spam: 0,
                    aiSuspicion: 0,
                    duplicateMatch: 0,
                    authenticity: 1,
                    userRiskScore: 0
                )
            )
            #else
            dlog("❌ Moderation error: \(error)")
            // FAIL CLOSED in production: hold for review rather than silently allowing
            // content through. This prevents bypass via network errors.
            return ModerationDecision(
                action: .holdForReview,
                confidence: 1.0,
                reasons: ["Moderation service temporarily unavailable — holding for safety review"],
                detectedBehaviors: [],
                suggestedRevisions: nil,
                reviewRequired: true,
                appealable: true,
                scores: ModerationScores(
                    toxicity: 0,
                    spam: 0,
                    aiSuspicion: 0,
                    duplicateMatch: 0,
                    authenticity: 0,
                    userRiskScore: 0
                )
            )
            #endif
        }
    }
    
    // MARK: - Report Content
    
    static func reportContent(
        contentId: String,
        contentType: ContentCategory,
        reason: String,
        details: String
    ) async throws {
        guard Auth.auth().currentUser?.uid != nil else {
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
        guard Auth.auth().currentUser?.uid != nil else {
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
