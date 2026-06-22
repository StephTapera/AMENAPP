//
//  CommentQualityGateway.swift
//  AMENAPP
//
//  Smart Comment Quality + Safety Gateway — iOS layer.
//
//  Wraps the `checkCommentQuality` Cloud Function callable.
//  Must be called BEFORE any comment write path (addComment / NestedCommentService).
//
//  CONTRACT:
//    1. Call `checkCommentQuality(text:postId:clientCommentId:)`.
//    2. Switch on the returned `Decision`:
//       • .publish  → write immediately
//       • .nudge    → show NudgeSheet to the user; they may dismiss and post anyway
//       • .block    → show error, do NOT write
//    3. If decision is .nudge and user dismisses, call `addComment` as normal
//       (the decision record already exists on the server).
//
//  FAILURE BEHAVIOR:
//    Network / server errors return `.serverError`. The call site MUST treat
//    serverError as fail-closed (do not write). This mirrors ThinkFirstServerValidator.
//
//  NUDGE UX:
//    The primary compose path (CommentService.addComment → PostDetailView) fully
//    handles the nudge sheet via CommentNudgeRequired error + CommentNudgeSheet.
//
//  Secondary paths (FollowThroughInteractions, TestimoniesView, PostInteractionsViewModel,
//  PrayerView) catch CommentNudgeRequired generically and show a generic toast; the full
//  nudge sheet can be wired in a later pass.
//

import Foundation
import FirebaseAuth
import FirebaseFunctions

// MARK: - Response model

struct CommentQualityResponse {
    enum Decision: String {
        case publish
        case nudge
        case block
    }

    enum SafetyDecision: String {
        case allow
        case warn
        case block
    }

    let decision: Decision
    let nudges: [String]
    let safetyDecision: SafetyDecision
}

// MARK: - Gateway

@MainActor
final class CommentQualityGateway {
    static let shared = CommentQualityGateway()
    private init() {}

    // MARK: - Public types

    enum GatewayOutcome {
        /// Server returned a structured verdict. Honor `response.decision`.
        case decided(CommentQualityResponse)
        /// Network / auth / server error. Treat as fail-closed: do not write.
        case serverError(message: String)
    }

    // MARK: - Public API

    /// Call before any comment write. Returns a verdict or a fail-closed error.
    ///
    /// - Parameters:
    ///   - text:            The comment text.
    ///   - postId:          The post being commented on.
    ///   - clientCommentId: The same UUID that will be sent to `addComment`
    ///                      for idempotency. The server ties the decision record
    ///                      to this ID.
    func check(
        text: String,
        postId: String,
        clientCommentId: String
    ) async -> GatewayOutcome {

        // Quick local guard — never reach the network for obviously empty input
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .serverError(message: "Please write something before posting.")
        }

        // Auth presence check
        guard Auth.auth().currentUser != nil else {
            return .serverError(message: "Please sign in to comment.")
        }

        let callable = Functions.functions().httpsCallable("checkCommentQuality")
        let params: [String: Any] = [
            "text": trimmed,
            "postId": postId,
            "clientCommentId": clientCommentId,
        ]

        do {
            let result = try await callable.call(params)
            guard let dict = result.data as? [String: Any] else {
                return .serverError(message: "Unexpected response from quality check.")
            }
            guard let response = Self.parse(dict) else {
                return .serverError(message: "Could not read quality check response.")
            }
            return .decided(response)

        } catch let error as NSError {
            if error.domain == FunctionsErrorDomain {
                let code = FunctionsErrorCode(rawValue: error.code)
                switch code {
                case .some(.unauthenticated):
                    return .serverError(message: "Sign-in required before commenting.")
                case .some(.resourceExhausted):
                    return .serverError(
                        message: "Too many comment checks. Please wait a moment before posting again."
                    )
                case .some(.invalidArgument):
                    return .serverError(
                        message: "This comment content cannot be checked. Please revise and try again."
                    )
                default:
                    return .serverError(message: "Quality check unavailable. Please try again.")
                }
            }
            return .serverError(message: "Network error during quality check. Please retry.")
        }
    }

    // MARK: - Parsing

    private static func parse(_ dict: [String: Any]) -> CommentQualityResponse? {
        guard
            let decisionRaw = dict["decision"] as? String,
            let decision = CommentQualityResponse.Decision(rawValue: decisionRaw),
            let safetyRaw = dict["safetyDecision"] as? String,
            let safetyDecision = CommentQualityResponse.SafetyDecision(rawValue: safetyRaw)
        else {
            return nil
        }
        let nudges = dict["nudges"] as? [String] ?? []
        return CommentQualityResponse(
            decision: decision,
            nudges: nudges,
            safetyDecision: safetyDecision
        )
    }
}
