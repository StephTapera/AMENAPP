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
    
    private let db = Firestore.firestore()
    private let apiKey: String
    
    private init() {
        self.apiKey = BundleConfig.string(forKey: "GOOGLE_VISION_API_KEY") ?? ""
    }
    
    // MARK: - Main Moderation Function
    
    /// Moderate an image before allowing upload
    func moderateImage(imageData: Data, userId: String, context: ImageContext) async throws -> ImageModerationDecision {
        print("🛡️ [IMAGE MOD] Moderating \(context.rawValue) image for user: \(userId)")

        // If the Vision API key is not configured, we cannot verify image safety.
        // Hold for human review rather than blindly approving unmoderated content.
        guard !apiKey.isEmpty else {
            print("⚠️ [IMAGE MOD] GOOGLE_VISION_API_KEY not set — holding image for human review")
            return .review(reasons: ["Image safety check unavailable — held for review"])
        }
        
        // Convert to base64
        let base64Image = imageData.base64EncodedString()
        
        // Call Vision API SafeSearch
        let safeSearchResult = try await performSafeSearch(base64Image: base64Image)
        
        // Determine action
        if !safeSearchResult.isApproved {
            print("❌ [IMAGE MOD] BLOCKED - \(safeSearchResult.flaggedReasons.joined(separator: ", "))")
            
            // Log to Firestore for admin review
            try await logModerationAction(
                userId: userId,
                context: context,
                result: safeSearchResult,
                action: .blocked
            )
            
            return .blocked(reasons: safeSearchResult.flaggedReasons)
        }
        
        if safeSearchResult.needsReview {
            print("⚠️ [IMAGE MOD] REVIEW NEEDED - borderline content")
            
            try await logModerationAction(
                userId: userId,
                context: context,
                result: safeSearchResult,
                action: .review
            )
            
            return .review(reasons: ["Content requires manual review"])
        }
        
        print("✅ [IMAGE MOD] APPROVED")
        return .approved
    }
    
    // MARK: - Vision API Integration
    
    private func performSafeSearch(base64Image: String) async throws -> SafeSearchResult {
        let endpoint = "https://vision.googleapis.com/v1/images:annotate?key=\(apiKey)"
        
        guard let url = URL(string: endpoint) else {
            throw ImageModerationError.invalidURL
        }
        
        let requestBody: [String: Any] = [
            "requests": [
                [
                    "image": [
                        "content": base64Image
                    ],
                    "features": [
                        [
                            "type": "SAFE_SEARCH_DETECTION"
                        ]
                    ]
                ]
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 10 // 10 second timeout
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ImageModerationError.networkError
        }
        
        guard httpResponse.statusCode == 200 else {
            print("❌ [IMAGE MOD] Vision API error: \(httpResponse.statusCode)")
            if let errorString = String(data: data, encoding: .utf8) {
                print("   Response: \(errorString)")
            }
            throw ImageModerationError.apiError(httpResponse.statusCode)
        }
        
        // Parse SafeSearch response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let responses = json?["responses"] as? [[String: Any]],
              let firstResponse = responses.first,
              let safeSearchAnnotation = firstResponse["safeSearchAnnotation"] as? [String: String] else {
            throw ImageModerationError.parsingError
        }
        
        let result = SafeSearchResult(
            adult: SafeSearchLikelihood(stringValue: safeSearchAnnotation["adult"] ?? "UNKNOWN"),
            spoof: SafeSearchLikelihood(stringValue: safeSearchAnnotation["spoof"] ?? "UNKNOWN"),
            medical: SafeSearchLikelihood(stringValue: safeSearchAnnotation["medical"] ?? "UNKNOWN"),
            violence: SafeSearchLikelihood(stringValue: safeSearchAnnotation["violence"] ?? "UNKNOWN"),
            racy: SafeSearchLikelihood(stringValue: safeSearchAnnotation["racy"] ?? "UNKNOWN")
        )
        
        print("🔍 [IMAGE MOD] SafeSearch: adult=\(result.adult), racy=\(result.racy), violence=\(result.violence)")
        
        return result
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
