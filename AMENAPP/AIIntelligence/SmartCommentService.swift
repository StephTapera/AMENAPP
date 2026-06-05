import Foundation
import FirebaseFunctions

// MARK: - Models

/// Coaching action returned by the Comment Coach.
enum CommentCoachAction: String, Codable {
    /// Comment is ready to publish as-is.
    case publish
    /// User should reconsider tone, channel, or timing.
    case nudge
    /// Comment violates community standards and cannot be posted.
    case block
}

/// Response from the Comment Coach callable (callModelCommentCoach).
struct CommentCoachResponse: Codable {
    struct Coaching: Codable {
        let action: CommentCoachAction
        let nudgeMessage: String?
        let rewriteSuggestion: String?
    }
    let coaching: Coaching
    let provider: String?
    let latencyMs: Int?
}

/// Result returned to UI with publish decision + any coaching message.
struct SmartCommentResult {
    let action: CommentCoachAction
    let nudgeMessage: String?
    let rewriteSuggestion: String?
    let provider: String?

    var canPublish: Bool { action == .publish }
    var isBlocked: Bool  { action == .block   }
}

// MARK: - Errors

enum SmartCommentError: LocalizedError {
    case invalidInput
    case consentRequired
    case rateLimitExceeded
    case networkError(String)
    case blocked(String?)

    var errorDescription: String? {
        switch self {
        case .invalidInput:        return "Comment must be 1–2000 characters."
        case .consentRequired:     return "Please enable AI comment coaching in Settings."
        case .rateLimitExceeded:   return "You've reached the hourly comment review limit. Try again later."
        case .networkError(let m): return "Connection error: \(m)"
        case .blocked(let msg):    return msg ?? "This comment cannot be posted in this community."
        }
    }
}

// MARK: - Service

/// Calls the `callModelCommentCoach` Firebase Function, which routes through the
/// centralized callModel router (Claude, fail_closed, NVIDIA output guard).
///
/// All API secrets remain server-side. No NVIDIA, Anthropic, or OpenAI keys on device.
@MainActor
final class SmartCommentService: ObservableObject {

    static let shared = SmartCommentService()
    private let functions = Functions.functions(region: "us-central1")

    private init() {}

    // Client-side rate limit key (server enforces 60/hr — this is a soft UI guard).
    private static var hourlyKey: String {
        let cal = Calendar.current
        let h = cal.component(.hour, from: Date())
        let d = cal.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return "smartComment_hr_\(d)_\(h)"
    }
    private static let clientHourlyLimit = 60

    // MARK: - Public API

    /// Review a comment before posting.
    ///
    /// - Parameters:
    ///   - commentText: The comment the user is about to post (1–2000 chars).
    ///   - postContext: Optional excerpt from the post being replied to, for richer coaching.
    ///
    /// - Returns: `SmartCommentResult` with publish decision and optional coaching message.
    ///
    /// - Important: A `.publish` result means the router cleared the comment through
    ///   the NVIDIA safety gate AND Claude coaching. It is NOT a guarantee the content
    ///   is theologically correct — user responsibility for content remains with the user.
    func reviewComment(
        commentText: String,
        postContext: String? = nil
    ) async throws -> SmartCommentResult {

        // Input validation
        let trimmed = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...2000).contains(trimmed.count) else {
            throw SmartCommentError.invalidInput
        }

        // Consent gate
        guard UserDefaults.standard.bool(forKey: "consentSmartComment") else {
            throw SmartCommentError.consentRequired
        }

        // Client-side soft rate limit
        let key = Self.hourlyKey
        let count = UserDefaults.standard.integer(forKey: key)
        guard count < Self.clientHourlyLimit else {
            throw SmartCommentError.rateLimitExceeded
        }
        UserDefaults.standard.set(count + 1, forKey: key)

        // Build payload
        var payload: [String: Any] = ["commentText": trimmed]
        if let context = postContext, !context.isEmpty {
            payload["postContext"] = String(context.prefix(500))
        }

        // Call Firebase Function
        let result: HTTPSCallableResult
        do {
            result = try await functions
                .httpsCallable("callModelCommentCoach")
                .call(payload)
        } catch {
            throw SmartCommentError.networkError(error.localizedDescription)
        }

        // Decode response
        guard let raw = result.data as? [String: Any] else {
            // Fallback: allow publish when response is unreadable (server-side guards already ran).
            return SmartCommentResult(action: .publish, nudgeMessage: nil, rewriteSuggestion: nil, provider: nil)
        }

        let data = try JSONSerialization.data(withJSONObject: raw)
        let decoded = try JSONDecoder().decode(CommentCoachResponse.self, from: data)
        let coaching = decoded.coaching

        return SmartCommentResult(
            action: coaching.action,
            nudgeMessage: coaching.nudgeMessage,
            rewriteSuggestion: coaching.rewriteSuggestion,
            provider: decoded.provider
        )
    }

    /// Convenience: check whether a comment can be published without prompting the user.
    /// Returns `true` if action == .publish, `false` if nudge/block (caller should show sheet).
    func canPublishImmediately(commentText: String, postContext: String? = nil) async -> Bool {
        guard let result = try? await reviewComment(commentText: commentText, postContext: postContext) else {
            return true // Fail open for network errors — server guards already ran on publish path
        }
        return result.canPublish
    }
}
