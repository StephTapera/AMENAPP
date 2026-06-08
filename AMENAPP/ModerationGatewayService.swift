//
//  ModerationGatewayService.swift
//  AMENAPP
//
//  Thin Swift client for the `checkContentSafety` Cloud Function.
//
//  Usage:
//    let result = try await ModerationGatewayService.check(
//        content: text,
//        contentType: .comment,
//        contextId: postId
//    )
//    guard result.canProceed else { /* show result.userFacingReason */ return }
//    if result.crisisEscalated { /* show CrisisSupportSheet */ }
//
//  Every call writes a `moderationDecisions/{decisionId}` record server-side.
//  Self-harm detection writes `crisisEscalations/{uid}/{timestamp}` and
//  returns crisis resources for display.
//

import Foundation
import FirebaseAuth
import FirebaseFunctions

// MARK: - Result

struct ModerationGatewayResult {
    /// "allow" | "warn" | "block" | "review"
    let decision: String
    /// Human-readable reason (nil when decision == "allow")
    let reason: String?
    /// True when self-harm language was detected and crisis escalation was triggered
    let crisisEscalated: Bool
    /// Crisis resource list (only present when crisisEscalated == true)
    let crisisResources: [[String: String]]?
    /// ID of the moderationDecisions Firestore record
    let decisionId: String?

    /// Whether the content can proceed to the Firestore write.
    /// "allow" and "warn" proceed. "block" and "review" do not.
    var canProceed: Bool {
        return decision == "allow" || decision == "warn"
    }

    /// User-facing message to show when content is blocked/held.
    var userFacingReason: String {
        if crisisEscalated {
            return "You're not alone. We care about you. Please see the resources below."
        }
        switch decision {
        case "block":
            return reason ?? "This content doesn't meet AMEN community standards. Please revise and try again."
        case "review":
            return reason ?? "Your content is being reviewed. This usually takes a few minutes."
        case "warn":
            return reason ?? "Heads up — this content contains something that may concern others."
        default:
            return ""
        }
    }
}

// MARK: - Service

final class ModerationGatewayService {

    static let shared = ModerationGatewayService()
    // Functions client is thread-safe; no MainActor isolation needed.
    private let functions = Functions.functions(region: "us-central1")

    private init() {}

    // MARK: - Primary Entry Point

    /// Call `checkContentSafety` before any Firestore content write.
    ///
    /// - Parameters:
    ///   - content: The raw text to moderate.
    ///   - contentType: Which surface the content is from.
    ///   - contextId: Optional ID of the parent document (postId, conversationId, etc.)
    /// - Returns: `ModerationGatewayResult` — check `canProceed` before writing.
    /// - Throws: Only if the user is not authenticated. Network errors fail closed
    ///           (returns a "review" result) rather than throwing.
    static func check(
        content: String,
        contentType: ModerationContentType,
        contextId: String? = nil
    ) async throws -> ModerationGatewayResult {
        return try await shared.check(
            content: content,
            contentType: contentType,
            contextId: contextId
        )
    }

    func check(
        content: String,
        contentType: ModerationContentType,
        contextId: String? = nil
    ) async throws -> ModerationGatewayResult {

        guard Auth.auth().currentUser?.uid != nil else {
            throw NSError(
                domain: "ModerationGatewayService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
            )
        }

        var params: [String: Any] = [
            "content": content,
            "contentType": contentType.rawValue,
        ]
        if let cid = contextId {
            params["contextId"] = cid
        }

        do {
            // Hard 8-second timeout: if the CF hasn't responded, fail closed.
            let callable = functions.httpsCallable("checkContentSafety")
            callable.timeoutInterval = 8
            let result = try await callable.call(params)
            guard let data = result.data as? [String: Any] else {
                return failClosed(reason: "Unexpected response format")
            }
            return parse(data)
        } catch let error as NSError {
            let msg = error.localizedDescription.lowercased()
            let isRateLimit = msg.contains("resource-exhausted") || msg.contains("rate limit")
            if isRateLimit {
                dlog("⚠️ [ModerationGateway] Rate limited — blocking submission")
                return ModerationGatewayResult(
                    decision: "block",
                    reason: "You're posting too quickly. Please wait a moment and try again.",
                    crisisEscalated: false,
                    crisisResources: nil,
                    decisionId: nil
                )
            }

            #if DEBUG
            // In DEBUG/simulator, Cloud Functions may be unavailable — allow through for testing
            dlog("⚠️ [ModerationGateway] CF unavailable in DEBUG — allowing (error: \(error.localizedDescription))")
            return ModerationGatewayResult(
                decision: "allow",
                reason: nil,
                crisisEscalated: false,
                crisisResources: nil,
                decisionId: nil
            )
            #else
            // In production, fail closed
            dlog("❌ [ModerationGateway] CF error — failing closed: \(error.localizedDescription)")
            return failClosed(reason: "Safety check temporarily unavailable — your content is being reviewed.")
            #endif
        }
    }

    // MARK: - Private Helpers

    private func parse(_ data: [String: Any]) -> ModerationGatewayResult {
        let decision       = data["decision"] as? String ?? "review"
        let reason         = data["reason"] as? String
        let crisisEscalated = data["crisisEscalated"] as? Bool ?? false
        let crisisResources = data["crisisResources"] as? [[String: String]]
        let decisionId     = data["decisionId"] as? String

        return ModerationGatewayResult(
            decision: decision,
            reason: reason,
            crisisEscalated: crisisEscalated,
            crisisResources: crisisResources,
            decisionId: decisionId
        )
    }

    private func failClosed(reason: String) -> ModerationGatewayResult {
        return ModerationGatewayResult(
            decision: "review",
            reason: reason,
            crisisEscalated: false,
            crisisResources: nil,
            decisionId: nil
        )
    }
}
