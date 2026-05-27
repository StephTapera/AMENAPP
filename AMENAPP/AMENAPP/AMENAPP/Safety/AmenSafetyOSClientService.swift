import Foundation
import FirebaseAuth
import FirebaseFunctions

// MARK: - Moderation Response Types

struct TextModerationResult: Codable {
    let allowed: Bool
    let moderationStatus: String
    let harmCategoryId: String?
    let userFacingMessage: String?
    let contentWarning: String?
    let requiresHumanReview: Bool
    let policyVersion: String
}

struct ImageModerationResult: Codable {
    let allowed: Bool
    let moderationStatus: String
    let harmCategoryId: String?
    let userFacingMessage: String?
    let requiresHumanReview: Bool
    let policyVersion: String
}

struct VideoModerationResult: Codable {
    let allowed: Bool
    let moderationStatus: String
    let harmCategoryId: String?
    let userFacingMessage: String?
    let requiresHumanReview: Bool
    let framesAnalyzed: Int?
    let policyVersion: String
}

struct SafetyOSLinkCheckResult: Codable {
    let safe: Bool
    let reason: String?
    let userFacingMessage: String?
    let expandedUrl: String?
}

struct YouthSafetyCheckResult: Codable {
    let allowed: Bool
    let reason: String?
}

struct ReportAbuseResult: Codable {
    let success: Bool
    let reportId: String
    let escalationTier: Int
    let message: String
}

struct GuardianConnectionResult: Codable {
    let success: Bool
    let connectionId: String?
    let message: String?
}

// MARK: - Rewrite Response Types

struct TextRewriteResult: Codable {
    let suggestions: [String]
    let rationale: String
    let harmCategoryId: String
}

struct SafetyToneCheckResult: Codable {
    let suggestion: String?
    let reason: String?
}

struct RewriteOutcomeResult: Codable {
    let recorded: Bool
}

// MARK: - Progressive Trust Types

struct TrustCapabilities: Codable {
    let canDM: Bool
    let dmScope: String        // "none" | "verified_only" | "unrestricted"
    let canUploadMedia: Bool
    let mediaScope: String     // "none" | "image" | "image_and_video"
    let canCreateGroup: Bool
    let canPostPublicly: Bool
    let canMentor: Bool
    let maxDailyComments: Int
}

struct TrustProfileResult: Codable {
    let trustLevel: Int
    let trustPoints: Int
    let trustCapabilities: TrustCapabilities
    let nextLevelRequirement: Int?
    let recentEvents: [[String: String]]?
}

// MARK: - Interaction Mode Types

enum InteractionMode: String, Codable, CaseIterable {
    case social, discussion, study, quiet, youth, campus, family

    var displayName: String {
        switch self {
        case .social:     return "Social"
        case .discussion: return "Discussion"
        case .study:      return "Study"
        case .quiet:      return "Quiet"
        case .youth:      return "Youth"
        case .campus:     return "Campus"
        case .family:     return "Family"
        }
    }

    var description: String {
        switch self {
        case .social:     return "Full platform — posting, media, and discovery"
        case .discussion: return "Text conversations and comments only"
        case .study:      return "Groups, notes, and mentorship"
        case .quiet:      return "Trusted circle only — no public broadcasting"
        case .youth:      return "Higher protections and moderated discovery"
        case .campus:     return "Campus hubs, local events, and study groups"
        case .family:     return "Parent-linked, family-safe environment"
        }
    }
}

struct InteractionModeResult: Codable {
    let mode: String
    let capabilities: [String: Bool]
}

// MARK: - Mentorship Types

struct MentorshipResult: Codable {
    let success: Bool
    let connectionId: String?
    let message: String?
}

struct MentorshipConnection: Codable, Identifiable {
    let id: String
    let mentorUid: String
    let menteeUid: String
    let status: String
    let context: String?
}

struct MyMentorshipsResult: Codable {
    let connections: [MentorshipConnection]
}

// MARK: - Church Verification Types

struct ChurchVerificationResult: Codable {
    let success: Bool
    let churchName: String?
    let message: String?
}

struct VerifiedChurch: Codable, Identifiable {
    let id: String
    let churchId: String
    let churchName: String
}

struct ChurchVerificationStatusResult: Codable {
    let verifiedChurches: [VerifiedChurch]
}

// MARK: - Error Type

enum SafetyOSError: LocalizedError {
    case contentBlocked(message: String)
    case unauthenticated
    case callFailed(underlying: Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .contentBlocked(let message): return message
        case .unauthenticated: return "Please sign in to continue."
        case .callFailed(let err): return err.localizedDescription
        case .invalidResponse: return "Unexpected response from safety service."
        }
    }
}

// MARK: - AmenSafetyOSClientService

/// iOS-side client for all Amen Safety OS backend callables.
/// Every UGC surface must call the relevant moderation method before distributing content.
@MainActor
final class AmenSafetyOSClientService {
    static let shared = AmenSafetyOSClientService()
    private let functions = Functions.functions()
    private init() {}

    // MARK: - Text Moderation

    /// Call before submitting any user-generated text (posts, comments, DMs, profiles).
    func moderateText(
        text: String,
        contentType: String,
        contentId: String? = nil,
        isMinor: Bool = false
    ) async throws -> TextModerationResult {
        var params: [String: Any] = ["text": text, "contentType": contentType, "isMinor": isMinor]
        if let contentId { params["contentId"] = contentId }
        return try await call("moderateTextCallable", params: params)
    }

    // MARK: - Image Moderation

    /// Call after uploading to Storage. Content must stay pending until this returns `allowed: true`.
    func moderateImage(
        storageUri: String,
        contentId: String? = nil,
        contentType: String = "post_image",
        isMinor: Bool = false
    ) async throws -> ImageModerationResult {
        var params: [String: Any] = ["storageUri": storageUri, "contentType": contentType, "isMinor": isMinor]
        if let contentId { params["contentId"] = contentId }
        return try await call("moderateImageCallable", params: params)
    }

    // MARK: - Video Moderation

    /// Call after uploading a video. Shows "processing" UI — callable has a 300-second timeout.
    func moderateVideo(
        storageUri: String,
        contentId: String? = nil,
        contentType: String = "post_video",
        durationSeconds: Int? = nil,
        isMinor: Bool = false
    ) async throws -> VideoModerationResult {
        var params: [String: Any] = ["storageUri": storageUri, "contentType": contentType, "isMinor": isMinor]
        if let contentId { params["contentId"] = contentId }
        if let duration = durationSeconds { params["durationSeconds"] = duration }
        return try await call("moderateVideoCallable", params: params)
    }

    // MARK: - Audio Moderation

    /// Call after uploading audio. Transcribes then moderates — transcript is never returned.
    func moderateAudio(
        storageUri: String,
        contentId: String? = nil,
        contentType: String = "message_audio",
        isMinor: Bool = false
    ) async throws -> TextModerationResult {
        var params: [String: Any] = ["storageUri": storageUri, "contentType": contentType, "isMinor": isMinor]
        if let contentId { params["contentId"] = contentId }
        return try await call("moderateAudioCallable", params: params)
    }

    // MARK: - Link Safety

    /// Check a URL before rendering or sharing. Returns `safe: false` for phishing, malware, adult domains.
    func checkLinkSafety(url: String) async throws -> SafetyOSLinkCheckResult {
        return try await call("checkLinkSafetyCallable", params: ["url": url])
    }

    // MARK: - Youth Safety

    /// Validate whether an action is permitted for a minor account.
    /// Actions: "dm", "follow", "view_location", "post_media", "join_group", "react"
    func checkYouthSafety(targetUid: String, action: String, contentType: String? = nil) async throws -> YouthSafetyCheckResult {
        var params: [String: Any] = ["targetUid": targetUid, "action": action]
        if let ct = contentType { params["contentType"] = ct }
        return try await call("checkYouthSafetyCallable", params: params)
    }

    // MARK: - Text Rewrite ("Rewrite Instead")

    /// Request AI-suggested alternative phrasings when text is blocked by moderation.
    /// Returns up to 2 suggestions and a rationale. Rate-limited to 10/hour.
    func requestTextRewrite(
        text: String,
        harmCategoryId: String,
        contentType: String
    ) async throws -> TextRewriteResult {
        return try await call("requestTextRewrite", params: [
            "text": text,
            "harmCategoryId": harmCategoryId,
            "contentType": contentType,
        ])
    }

    /// Proactively check tone before submitting — returns a suggestion if the text could be more constructive.
    /// Returns `suggestion: nil` when the text is already healthy. Rate-limited to 30/hour.
    func getToneCheckSuggestion(text: String, contentType: String) async throws -> SafetyToneCheckResult {
        return try await call("getToneCheckSuggestion", params: [
            "text": text,
            "contentType": contentType,
        ])
    }

    // MARK: - Rewrite Outcome Tracking

    /// Report whether the user accepted or dismissed a text rewrite suggestion.
    /// Used for product analytics only — no content is stored.
    func reportRewriteOutcome(accepted: Bool, harmCategoryId: String, contentType: String) async throws -> RewriteOutcomeResult {
        return try await call("reportRewriteOutcome", params: [
            "accepted": accepted,
            "harmCategoryId": harmCategoryId,
            "contentType": contentType,
        ])
    }

    // MARK: - Progressive Trust

    /// Get the authenticated user's trust level, capabilities, and earning history.
    func getMyTrustProfile() async throws -> TrustProfileResult {
        return try await call("getTrustProfile", params: [:])
    }

    // MARK: - Interaction Mode

    /// Set the user's interaction mode. Cannot set "youth" manually — assigned automatically.
    func setInteractionMode(_ mode: InteractionMode) async throws -> InteractionModeResult {
        return try await call("setInteractionMode", params: ["mode": mode.rawValue])
    }

    /// Get the user's current interaction mode and capabilities.
    func getInteractionMode() async throws -> InteractionModeResult {
        return try await call("getInteractionMode", params: [:])
    }

    // MARK: - Mentorship

    /// Request a mentorship connection. The mentor will receive a notification to approve.
    func requestMentorship(mentorUid: String, context: String? = nil) async throws -> MentorshipResult {
        var params: [String: Any] = ["mentorUid": mentorUid]
        if let context { params["context"] = context }
        return try await call("requestMentorship", params: params)
    }

    /// Approve a pending mentorship request (must be called by the mentor).
    func approveMentorship(connectionId: String) async throws -> MentorshipResult {
        return try await call("approveMentorship", params: ["connectionId": connectionId])
    }

    /// End an active or pending mentorship connection.
    func endMentorship(connectionId: String) async throws -> MentorshipResult {
        return try await call("endMentorship", params: ["connectionId": connectionId])
    }

    /// Get active mentorship connections. Pass `role: "mentor"` or `"mentee"` to filter.
    func getMyMentorships(role: String? = nil) async throws -> MyMentorshipsResult {
        var params: [String: Any] = [:]
        if let role { params["role"] = role }
        return try await call("getMyMentorships", params: params)
    }

    // MARK: - Church Verification

    /// Verify your membership at a church using a 6-digit code from a church admin.
    func requestChurchVerification(churchId: String, verificationCode: String) async throws -> ChurchVerificationResult {
        return try await call("requestChurchVerification", params: [
            "churchId": churchId,
            "verificationCode": verificationCode,
        ])
    }

    /// Church admins: issue a one-time verification code for a new member.
    func issueChurchVerificationCode(churchId: String, expiresInHours: Int = 48) async throws -> [String: Any] {
        let callable = functions.httpsCallable("issueChurchVerificationCode")
        let result = try await callable.call(["churchId": churchId, "expiresInHours": expiresInHours])
        guard let data = result.data as? [String: Any] else { throw SafetyOSError.invalidResponse }
        return data
    }

    /// Get all churches you've been verified at.
    func getChurchVerificationStatus() async throws -> ChurchVerificationStatusResult {
        return try await call("getChurchVerificationStatus", params: [:])
    }

    // MARK: - Report Abuse

    /// Submit a user-initiated abuse report. Deduplication and rate-limiting are server-side.
    func reportAbuse(
        reportedUid: String,
        reportReason: String,
        contentId: String? = nil,
        contentType: String? = nil,
        additionalContext: String? = nil,
        evidenceMessageIds: [String]? = nil
    ) async throws -> ReportAbuseResult {
        var params: [String: Any] = ["reportedUid": reportedUid, "reportReason": reportReason]
        if let contentId { params["contentId"] = contentId }
        if let contentType { params["contentType"] = contentType }
        if let context = additionalContext { params["additionalContext"] = context }
        if let msgIds = evidenceMessageIds { params["evidenceMessageIds"] = msgIds }
        return try await call("reportAbuse", params: params)
    }

    // MARK: - Guardian Connection

    func requestGuardianConnection(minorUid: String) async throws -> GuardianConnectionResult {
        return try await call("requestGuardianConnection", params: ["minorUid": minorUid])
    }

    func approveGuardianConnection(connectionId: String) async throws -> GuardianConnectionResult {
        return try await call("approveGuardianConnection", params: ["connectionId": connectionId])
    }

    func revokeGuardianConnection(connectionId: String) async throws -> GuardianConnectionResult {
        return try await call("revokeGuardianConnection", params: ["connectionId": connectionId])
    }

    // MARK: - My Reports

    func getMyReports(limit: Int = 20) async throws -> [[String: Any]] {
        let callable = functions.httpsCallable("getMyReports")
        let result = try await callable.call(["limit": limit])
        guard let data = result.data as? [String: Any],
              let reports = data["reports"] as? [[String: Any]] else {
            throw SafetyOSError.invalidResponse
        }
        return reports
    }

    // MARK: - Private Helper

    private func call<T: Decodable>(_ name: String, params: [String: Any]) async throws -> T {
        do {
            let callable = functions.httpsCallable(name)
            let result = try await callable.call(params)
            guard let raw = result.data as? [String: Any] else { throw SafetyOSError.invalidResponse }
            let jsonData = try JSONSerialization.data(withJSONObject: raw)
            return try JSONDecoder().decode(T.self, from: jsonData)
        } catch let error as SafetyOSError {
            throw error
        } catch {
            throw SafetyOSError.callFailed(underlying: error)
        }
    }
}
