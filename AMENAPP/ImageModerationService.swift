//
//  ImageModerationService.swift
//  AMENAPP
//
//  Cloud Vision SafeSearch Detection for image moderation
//  Protects platform from inappropriate visual content
//

import Foundation
import FirebaseFirestore
import FirebaseStorage

// MARK: - SafeSearch Result Model

struct SafeSearchResult: Codable {
    let adult: SafeSearchLikelihood
    let spoof: SafeSearchLikelihood
    let medical: SafeSearchLikelihood
    let violence: SafeSearchLikelihood
    let racy: SafeSearchLikelihood
    
    var isApproved: Bool {
        // Strict thresholds for faith platform
        return adult.severityScore < 3 &&      // Block at POSSIBLE+
               racy.severityScore < 3 &&       // Block at POSSIBLE+
               violence.severityScore < 4 &&   // Block at LIKELY+
               spoof.severityScore < 4         // Block at LIKELY+
    }
    
    var needsReview: Bool {
        // Send to review queue if borderline
        return medical.severityScore >= 4 ||   // LIKELY+ medical content
               spoof.severityScore == 3        // POSSIBLE spoof
    }
    
    var flaggedReasons: [String] {
        var reasons: [String] = []
        
        if adult.severityScore >= 3 {
            reasons.append("Inappropriate content detected")
        }
        if racy.severityScore >= 3 {
            reasons.append("Suggestive content detected")
        }
        if violence.severityScore >= 4 {
            reasons.append("Violent imagery detected")
        }
        if medical.severityScore >= 4 {
            reasons.append("Medical/graphic content")
        }
        if spoof.severityScore >= 4 {
            reasons.append("Potentially fake/edited content")
        }
        
        return reasons
    }
}

enum SafeSearchLikelihood: String, Codable, Comparable {
    case unknown = "UNKNOWN"
    case veryUnlikely = "VERY_UNLIKELY"
    case unlikely = "UNLIKELY"
    case possible = "POSSIBLE"
    case likely = "LIKELY"
    case veryLikely = "VERY_LIKELY"
    
    var severityScore: Int {
        switch self {
        case .unknown: return 0
        case .veryUnlikely: return 1
        case .unlikely: return 2
        case .possible: return 3
        case .likely: return 4
        case .veryLikely: return 5
        }
    }
    
    static func < (lhs: SafeSearchLikelihood, rhs: SafeSearchLikelihood) -> Bool {
        return lhs.severityScore < rhs.severityScore
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let stringValue = try container.decode(String.self)
        self = SafeSearchLikelihood(stringValue: stringValue)
    }
    
    init(stringValue: String) {
        switch stringValue {
        case "VERY_UNLIKELY": self = .veryUnlikely
        case "UNLIKELY": self = .unlikely
        case "POSSIBLE": self = .possible
        case "LIKELY": self = .likely
        case "VERY_LIKELY": self = .veryLikely
        default: self = .unknown
        }
    }
}

// MARK: - Image Moderation Service

@MainActor
class ImageModerationService {
    static let shared = ImageModerationService()
    
    private lazy var db = Firestore.firestore()
    // SECURITY: API key is NOT stored on the client.
    // Image moderation is handled server-side via Cloud Functions (moderateImage callable).

    private init() {}

    // MARK: - Main Moderation Function

    /// Moderate an image before allowing upload.
    ///
    /// Server-side pipeline (functions/imageModeration.js — `moderateUploadedImage` Storage trigger):
    ///   Layer 1 — Google Cloud Vision SafeSearch: blocks adult/racy (≥ POSSIBLE) and violent (≥ LIKELY) content.
    ///   Layer 2 — NVIDIA NIM vision LLM (meta/llama-3.2-11b-vision-instruct): faith-context second pass;
    ///             can approve SafeSearch over-flags on biblical art or block contextually inappropriate content.
    ///   Fail-closed: if both checks error out the image stays in the review queue; it is never silently approved.
    ///   NCMEC mandatory reporting fires on any confirmed-blocked image (18 U.S.C. § 2258A).
    ///
    /// The client returns `.review` so the UI can surface "pending review" state while the Storage trigger runs.
    func moderateImage(imageData: Data, userId: String, context: ImageContext) async throws -> ImageModerationDecision {
        dlog("🛡️ [IMAGE MOD] Moderating \(context.rawValue) image for user: \(userId)")
        dlog("ℹ️ [IMAGE MOD] Deferring to Storage trigger (moderateUploadedImage) for server-side safety check")
        // Hold for server-side processing. Final decision comes from the Storage-triggered Cloud Function.
        return .review(reasons: ["Image safety check pending server-side moderation"])
    }

    // MARK: - (Disabled) Vision API Integration
    // SECURITY: Direct Vision API calls from the client are disabled.
    // performSafeSearch is a stub that always throws — Vision API must be proxied
    // through a Firebase Cloud Function (moderateImage callable) on the server side.
    private func performSafeSearch(base64Image: String) async throws -> SafeSearchResult {
        throw NSError(
            domain: "ImageModerationService",
            code: 501,
            userInfo: [NSLocalizedDescriptionKey: "Vision API moderation must be invoked via Cloud Function proxy"]
        )
    }
    
    // MARK: - Logging
    
    private func logModerationAction(
        userId: String,
        context: ImageContext,
        result: SafeSearchResult,
        action: ModerationAction
    ) async throws {
        try await db.collection("imageModerationLogs").addDocument(data: [
            "userId": userId,
            "context": context.rawValue,
            "action": action.rawValue,
            "adult": result.adult.rawValue,
            "racy": result.racy.rawValue,
            "violence": result.violence.rawValue,
            "medical": result.medical.rawValue,
            "spoof": result.spoof.rawValue,
            "flaggedReasons": result.flaggedReasons,
            "timestamp": FieldValue.serverTimestamp()
        ])
        
        // Alert moderators for blocked content
        if action == .blocked {
            try await db.collection("moderatorAlerts").addDocument(data: [
                "type": "image_blocked",
                "userId": userId,
                "context": context.rawValue,
                "reasons": result.flaggedReasons,
                "timestamp": FieldValue.serverTimestamp(),
                "status": "pending"
            ])
        }
    }
}

// MARK: - Supporting Types

enum ImageContext: String {
    case profilePicture = "profile_picture"
    case postImage = "post_image"
    case messageImage = "message_image"
    case churchNote = "church_note"
}

enum ImageModerationDecision {
    case approved
    case blocked(reasons: [String])
    case review(reasons: [String])
    
    var isApproved: Bool {
        if case .approved = self {
            return true
        }
        return false
    }
    
    var userMessage: String {
        switch self {
        case .approved:
            return ""
        case .blocked(let reasons):
            let reason = reasons.first ?? "inappropriate content"
            return "This image cannot be uploaded: \(reason). Please choose a different image that aligns with our community guidelines."
        case .review:
            return "Your image is being reviewed and will appear shortly if approved."
        }
    }
}

enum ModerationAction: String {
    case approved = "approved"
    case blocked = "blocked"
    case review = "review"
}

// MARK: - Errors

enum ImageModerationError: Error {
    case invalidURL
    case networkError
    case apiError(Int)
    case parsingError
    case moderationFailed
    
    var userMessage: String {
        switch self {
        case .networkError:
            return "Network connection issue. Please try again."
        case .apiError:
            return "Unable to verify image safety. Please try again."
        default:
            return "Something went wrong. Please try again."
        }
    }
}
