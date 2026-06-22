//
//  ThinkFirstServerValidator.swift
//  AMENAPP
//
//  Phase P1-4 (iOS half) — server-authoritative Think-First / Tone Checker.
//
//  The on-device ThinkFirstGuardrailsService.checkContent(_:context:) remains
//  the FIRST pass and provides instant user feedback. This service is the
//  AUTHORITATIVE second pass: every publish path (CreatePost / comments /
//  replies / any user-authored content) must call validate(_:surface:) AFTER
//  the local check returns .allow or .softPrompt, and must honor the server
//  verdict over the client one.
//
//  The server endpoint:
//    Backend/functions/src/thinkFirst/validateThinkFirstCheck.ts
//    - Auth + App Check required
//    - 4000-char input cap
//    - Per-user rate limit shared with other AI callables
//    - Never logs raw text
//
//  Fail-closed: if the server call fails (network, App Check, rate-limit,
//  internal error), this service returns .serverError. The publish path MUST
//  treat that as "do not publish; show retry" — it must NOT silently fall
//  back to allowing the post, because that would defeat the point of
//  server-authoritative validation.

import Foundation
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class ThinkFirstServerValidator {
    static let shared = ThinkFirstServerValidator()

    private init() {}

    // MARK: - Public types

    /// Mirrors the backend `ThinkFirstAction` union.
    enum Action: String {
        case allow
        case softPrompt
        case requireEdit
        case block
    }

    /// Mirrors the backend `ThinkFirstSeverity` union.
    enum Severity: String {
        case info
        case warning
        case error
        case critical
    }

    /// Mirrors the backend `ThinkFirstCategory` union. Unknown server values
    /// are mapped to .other so a future server-side category addition does
    /// not crash older clients.
    enum Category: String {
        case pii
        case hate
        case harassment
        case threats
        case sexualMinors = "sexual_minors"
        case selfHarm = "self_harm"
        case violence
        case scam
        case spam
        case heated
        case other
    }

    /// Surface label sent to the server for analytics-safe logging. The
    /// backend caps this at 64 chars; keep these short and stable.
    enum Surface: String {
        case createPost = "create_post"
        case postComment = "post_comment"
        case postReply = "post_reply"
        case messageCompose = "message_compose"
        case bereanChat = "berean_chat"
    }

    /// Structured server result. `allowed` is the convenience flag the
    /// publish path should check first.
    struct Result {
        let action: Action
        let allowed: Bool
        let maxSeverity: Severity
        let categories: [Category]
        /// User-facing message. Safe to display verbatim. NEVER contains the
        /// user's original input text.
        let userMessage: String
        let suggestedRevision: String?
    }

    enum ValidationOutcome {
        /// Server returned a structured verdict. Honor `result.action`.
        case decided(Result)
        /// Auth / App Check / network / rate-limit / internal error. The
        /// publish path MUST treat this as fail-closed (do not publish).
        case serverError(message: String)
        /// Input rejected before the network call (e.g., empty / oversized).
        case inputRejected(message: String)
    }

    // MARK: - Public API

    /// Maximum characters accepted by the backend. Mirror of
    /// `THINK_FIRST_MAX_INPUT_CHARS` in `thinkFirst/validator.ts`.
    static let maxInputChars = 4000

    /// Call the server validator. The publish path should invoke this AFTER
    /// the local advisory check has cleared (`.allow` / `.softPrompt`); a
    /// local `.requireEdit` / `.block` should not have proceeded this far.
    ///
    /// - Parameters:
    ///   - text: The content the user is about to publish.
    ///   - surface: A short, stable label for analytics-safe logging.
    /// - Returns: `.decided(Result)` on a successful server verdict;
    ///   `.serverError` on any failure (fail-closed for the publish path);
    ///   `.inputRejected` for client-side guard rejections.
    func validate(_ text: String, surface: Surface) async -> ValidationOutcome {
        if text.isEmpty {
            return .inputRejected(message: "Please write something before publishing.")
        }
        if text.count > Self.maxInputChars {
            return .inputRejected(
                message: "Content exceeds the \(Self.maxInputChars)-character limit. Please shorten and try again."
            )
        }

        // Ensure Firebase Auth identity is current. The callable requires
        // Auth; missing identity is fail-closed.
        guard let currentUser = Auth.auth().currentUser else {
            return .serverError(message: "Please sign in to publish.")
        }
        do {
            _ = try await currentUser.getIDToken(forcingRefresh: false)
        } catch {
            return .serverError(message: "Auth refresh failed. Please try again.")
        }

        let callable = Functions.functions().httpsCallable("validateThinkFirstCheck")
        let params: [String: Any] = [
            "text": text,
            "surface": surface.rawValue,
        ]

        do {
            let response = try await callable.call(params)
            guard let dict = response.data as? [String: Any] else {
                return .serverError(message: "Unexpected validator response.")
            }
            guard let result = Self.parse(dict) else {
                return .serverError(message: "Could not read validator response.")
            }
            return .decided(result)
        } catch let error as NSError {
            // FunctionsErrorCode bridging via NSError.domain / code.
            // We deliberately do NOT log the request text. The user-facing
            // message is generic.
            if error.domain == FunctionsErrorDomain {
                let code = FunctionsErrorCode(rawValue: error.code)
                switch code {
                case .some(.unauthenticated):
                    return .serverError(message: "Sign-in or attestation required.")
                case .some(.resourceExhausted):
                    return .serverError(message: "Too many checks just now. Please wait a moment and retry.")
                case .some(.invalidArgument):
                    return .inputRejected(message: "This content cannot be checked. Please revise.")
                default:
                    return .serverError(message: "Safety check unavailable. Please retry.")
                }
            }
            return .serverError(message: "Network error. Please retry.")
        }
    }

    // MARK: - Parsing

    private static func parse(_ dict: [String: Any]) -> Result? {
        guard
            let actionRaw = dict["action"] as? String,
            let action = Action(rawValue: actionRaw),
            let allowed = dict["allowed"] as? Bool,
            let severityRaw = dict["maxSeverity"] as? String,
            let severity = Severity(rawValue: severityRaw),
            let userMessage = dict["userMessage"] as? String
        else {
            return nil
        }
        let categoriesRaw = dict["categories"] as? [String] ?? []
        let categories = categoriesRaw.map { Category(rawValue: $0) ?? .other }
        let suggestedRevision = dict["suggestedRevision"] as? String
        return Result(
            action: action,
            allowed: allowed,
            maxSeverity: severity,
            categories: categories,
            userMessage: userMessage,
            suggestedRevision: suggestedRevision
        )
    }
}
