//
//  ContentModerationService.swift
//  AMENAPP
//
//  AI-powered content moderation using Firebase AI Logic
//  Filters posts, comments, testimonies for harmful content
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Moderation Models

/// Content moderation result from AI analysis
struct ModerationResult: Codable {
    let isApproved: Bool
    let flaggedReasons: [String]
    let severityLevel: SeverityLevel
    let suggestedAction: ModerationAction
    let confidence: Double
    
    enum SeverityLevel: String, Codable {
        case safe = "safe"
        case warning = "warning"
        case blocked = "blocked"
        case review = "review"
    }
    
    enum ModerationAction: String, Codable {
        case approve = "approve"
        case flag = "flag"
        case block = "block"
        case humanReview = "human_review"
    }
}

/// Content types for moderation
enum ContentType: String {
    case post = "post"
    case comment = "comment"
    case testimony = "testimony"
    case prayerRequest = "prayer_request"
    case message = "message"
    case churchNote = "church_note"
}

// MARK: - Content Moderation Service

/// Service for AI-powered content moderation
class ContentModerationService {
    static let shared = ContentModerationService()
    private let db = Firestore.firestore()
    
    private init() {}
    
    // MARK: - Public Moderation Methods
    
    /// Moderate content before it's posted to the feed
    /// - Parameters:
    ///   - content: The text content to moderate
    ///   - type: Type of content being moderated
    ///   - userId: ID of user posting content
    /// - Returns: ModerationResult with approval status and flags
    func moderateContent(
        _ content: String,
        type: ContentType,
        userId: String
    ) async throws -> ModerationResult {
        
        print("🛡️ [MODERATION] Checking \(type.rawValue) content...")
        
        // Step 1: Local quick checks (instant)
        if let quickResult = performQuickLocalCheck(content) {
            print("🛡️ [MODERATION] Quick check: \(quickResult.severityLevel.rawValue)")
            return quickResult
        }
        
        // Step 2: Call Firebase AI Logic for deep analysis
        let aiResult = try await callFirebaseAIModerationAPI(
            content: content,
            type: type,
            userId: userId
        )
        
        // Step 3: Log result for analytics
        await logModerationResult(
            content: content,
            type: type,
            userId: userId,
            result: aiResult
        )
        
        print("🛡️ [MODERATION] AI check: \(aiResult.severityLevel.rawValue) (confidence: \(aiResult.confidence))")
        
        return aiResult
    }
    
    /// Check if content passes moderation (convenience method)
    func isContentSafe(_ content: String, type: ContentType, userId: String) async throws -> Bool {
        let result = try await moderateContent(content, type: type, userId: userId)
        return result.isApproved
    }
    
    // MARK: - Quick Local Checks
    
    /// Perform instant local checks before calling AI
    private func performQuickLocalCheck(_ content: String) -> ModerationResult? {
        let lowercased = content.lowercased()
        
        // Check 1: Empty or too short
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ModerationResult(
                isApproved: false,
                flaggedReasons: ["Empty content"],
                severityLevel: .blocked,
                suggestedAction: .block,
                confidence: 1.0
            )
        }
        
        // Check 2: Excessive caps (spam indicator)
        let capsRatio = Double(content.filter { $0.isUppercase }.count) / Double(content.count)
        if capsRatio > 0.7 && content.count > 20 {
            return ModerationResult(
                isApproved: false,
                flaggedReasons: ["Excessive capitalization (spam indicator)"],
                severityLevel: .blocked,
                suggestedAction: .block,
                confidence: 0.85
            )
        }
        
        // Check 3: Excessive special characters (spam)
        let specialCharsCount = content.filter { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }.count
        if specialCharsCount > content.count / 2 {
            return ModerationResult(
                isApproved: false,
                flaggedReasons: ["Excessive special characters"],
                severityLevel: .blocked,
                suggestedAction: .block,
                confidence: 0.8
            )
        }
        
        // Check 4: Known profanity patterns (basic)
        let profanityPatterns = [
            "f***", "s***", "b****", "damn", "hell",
            "wtf", "stfu", "omfg"
        ]
        
        for pattern in profanityPatterns {
            if lowercased.contains(pattern) {
                return ModerationResult(
                    isApproved: false,
                    flaggedReasons: ["Profanity detected"],
                    severityLevel: .blocked,
                    suggestedAction: .block,
                    confidence: 0.9
                )
            }
        }
        
        // Check 5: Hate speech indicators (basic)
        let hateSpeechIndicators = [
            "hate", "kill", "die", "death to", "murder"
        ]
        
        for indicator in hateSpeechIndicators {
            if lowercased.contains(indicator) {
                // Flag for AI review (might be false positive)
                return ModerationResult(
                    isApproved: false,
                    flaggedReasons: ["Potential hate speech detected"],
                    severityLevel: .review,
                    suggestedAction: .humanReview,
                    confidence: 0.6
                )
            }
        }
        
        // Passed quick checks - proceed to AI moderation
        return nil
    }
    
    // MARK: - Firebase AI Logic API
    
    /// Call Firebase AI Logic extension for deep content analysis
    private func callFirebaseAIModerationAPI(
        content: String,
        type: ContentType,
        userId: String
    ) async throws -> ModerationResult {
        
        // Prepare request payload for Firebase AI Logic
        let requestData: [String: Any] = [
            "content": content,
            "contentType": type.rawValue,
            "userId": userId,
            "timestamp": FieldValue.serverTimestamp()
        ]
        
        do {
            // Call Firebase AI Logic Cloud Function
            // This will use the Firebase AI Logic extension you enable in Firebase Console
            let result = try await db.collection("moderationRequests")
                .addDocument(data: requestData)
            
            // Wait for AI response (processed by Firebase AI Logic trigger)
            let response = try await waitForModerationResponse(requestId: result.documentID)
            
            return response
            
        } catch {
            print("❌ [MODERATION] AI API error: \(error)")
            
            // Fallback: If AI fails, apply conservative moderation
            return ModerationResult(
                isApproved: true, // Allow but flag for human review
                flaggedReasons: ["AI moderation unavailable"],
                severityLevel: .review,
                suggestedAction: .humanReview,
                confidence: 0.5
            )
        }
    }
    
    /// Wait for Firebase AI Logic to process and return moderation result
    private func waitForModerationResponse(requestId: String) async throws -> ModerationResult {
        // Poll for response from Firebase AI Logic
        for _ in 0..<10 { // Max 10 attempts (5 seconds)
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            let snapshot = try await db.collection("moderationResults")
                .document(requestId)
                .getDocument()
            
            if snapshot.exists,
               let data = snapshot.data(),
               let isApproved = data["isApproved"] as? Bool,
               let severityRaw = data["severityLevel"] as? String,
               let actionRaw = data["suggestedAction"] as? String,
               let confidence = data["confidence"] as? Double {
                
                let flaggedReasons = data["flaggedReasons"] as? [String] ?? []
                
                return ModerationResult(
                    isApproved: isApproved,
                    flaggedReasons: flaggedReasons,
                    severityLevel: ModerationResult.SeverityLevel(rawValue: severityRaw) ?? .review,
                    suggestedAction: ModerationResult.ModerationAction(rawValue: actionRaw) ?? .humanReview,
                    confidence: confidence
                )
            }
        }
        
        // Timeout - return conservative result
        throw NSError(
            domain: "ContentModeration",
            code: 408,
            userInfo: [NSLocalizedDescriptionKey: "Moderation timeout"]
        )
    }
    
    // MARK: - Logging & Analytics
    
    /// Log moderation result for analytics and improvement
    private func logModerationResult(
        content: String,
        type: ContentType,
        userId: String,
        result: ModerationResult
    ) async {
        
        let logData: [String: Any] = [
            "userId": userId,
            "contentType": type.rawValue,
            "contentLength": content.count,
            "isApproved": result.isApproved,
            "severityLevel": result.severityLevel.rawValue,
            "flaggedReasons": result.flaggedReasons,
            "confidence": result.confidence,
            "timestamp": FieldValue.serverTimestamp()
        ]
        
        do {
            try await db.collection("moderationLogs")
                .addDocument(data: logData)
        } catch {
            print("⚠️ [MODERATION] Failed to log result: \(error)")
        }
    }
    
    // MARK: - Admin Functions
    
    /// Get flagged content for admin review
    func getFlaggedContent() async throws -> [FlaggedContent] {
        let snapshot = try await db.collection("moderationLogs")
            .whereField("severityLevel", isEqualTo: "review")
            .order(by: "timestamp", descending: true)
            .limit(to: 50)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: FlaggedContent.self)
        }
    }
}

// MARK: - Flagged Content Model

struct FlaggedContent: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String
    let contentType: String
    let contentLength: Int
    let isApproved: Bool
    let severityLevel: String
    let flaggedReasons: [String]
    let confidence: Double
    let timestamp: Date?
}
