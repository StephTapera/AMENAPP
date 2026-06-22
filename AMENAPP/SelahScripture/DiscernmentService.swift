//
//  DiscernmentService.swift
//  AMENAPP
//
//  Firebase callable bridge for the Berean Discernment pipeline.
//
//  Contracts (selah.contracts.ts):
//    - CF "runDiscernmentCheck" → DiscernmentCheckResult
//    - CF "shareDiscernmentCheck" → updated DiscernmentCheckResult
//    - Visibility always defaults to "private"; sharing is ALWAYS explicit.
//    - citations contain ONLY open-licensed text (BSB/WEB/KJV).
//    - Hard-delete forbidden: deletedAt is the only removal mechanism.
//

import Foundation
import FirebaseAuth
import FirebaseFunctions

// MARK: - DiscernmentError

enum DiscernmentError: LocalizedError {
    case notAuthenticated
    case checkRefused(String)   // carries refusalReason from the CF
    case networkError(Error)
    case parseError

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to run a Berean check."
        case .checkRefused(let reason):
            return reason.isEmpty
                ? "Unable to assess this claim against Scripture at this time."
                : reason
        case .networkError(let underlying):
            return "Could not reach the Berean service. \(underlying.localizedDescription)"
        case .parseError:
            return "Received an unexpected response from the Berean service."
        }
    }
}

// MARK: - DiscernmentClaim

struct DiscernmentClaim: Codable {
    let text: String
    /// "doctrinal" | "ethical" | "historical" | "devotional" | "unverifiable"
    let classification: String
}

// MARK: - DiscernmentCitation

/// A Bible citation backed by an open-licensed translation only (BSB/WEB/KJV).
/// HARD CONTRACT: licensed translations (ESV, NIV, NLT, etc.) must never appear here.
struct DiscernmentCitation: Codable {
    let reference: String
    /// "BSB" | "WEB" | "KJV" — no other values permitted
    let translation: String
    let text: String
}

// MARK: - DiscernmentPerspective

struct DiscernmentPerspective: Codable {
    let tradition: String
    let summary: String
    let citations: [DiscernmentCitation]
}

// MARK: - DiscernmentCheckResult

/// Swift mirror of the DiscernmentCheck type from selah.contracts.ts.
///
/// Invariants (from contract):
///   status == "refused"  ⟹  verdict is nil, citations is empty, refusalReason is set
///   status == "grounded" ⟹  verdict is non-nil
///   perspectives populated only when verdict == "contested"
///   citations contain ONLY open-licensed text (BSB/WEB/KJV)
///   deletedAt is the ONLY removal mechanism; hard-delete is forbidden
struct DiscernmentCheckResult: Codable, Identifiable {
    let id: String
    let sourceType: String
    let sourceRef: String?
    let inputText: String
    /// "grounded" | "refused"  — fail-closed: refused is the safe default
    let status: String
    /// "aligns" | "diverges" | "contested" | "insufficient" | nil (when refused)
    let verdict: String?
    let claims: [DiscernmentClaim]
    let citations: [DiscernmentCitation]
    let perspectives: [DiscernmentPerspective]
    let refusalReason: String?
    /// "private" | "shared"  — private-first
    let visibility: String
    let createdBy: String
    let createdAt: TimeInterval
    var updatedAt: TimeInterval
    var deletedAt: TimeInterval?
}

// MARK: - DiscernmentService

/// Singleton that bridges the iOS app to the Berean discernment Cloud Functions.
///
/// Usage:
///   let result = try await DiscernmentService.shared.runCheck(
///       inputText: "...",
///       sourceType: "post",
///       sourceRef: postId
///   )
///
/// Visibility is ALWAYS "private" from this service. Sharing is initiated
/// explicitly via `shareCheck(checkId:)` after user confirmation.
@MainActor
final class DiscernmentService: ObservableObject {

    // MARK: Singleton

    static let shared = DiscernmentService()
    private init() {}

    // MARK: Published State

    @Published var isChecking = false
    @Published var currentCheck: DiscernmentCheckResult? = nil
    @Published var error: String? = nil

    // MARK: Private

    private let functions = Functions.functions(region: "us-central1")

    // MARK: - Auth Guard

    private func requireUID() throws -> String {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            throw DiscernmentError.notAuthenticated
        }
        return uid
    }

    // MARK: - Run Check

    /// Submits text to the `runDiscernmentCheck` Cloud Function and returns a result.
    ///
    /// - Parameters:
    ///   - inputText: The passage or claim text to check.
    ///   - sourceType: Origin surface — "comment" | "post" | "space_message" | "verse" | "selah_note"
    ///   - sourceRef: ID of the originating object (post id, comment id, etc.), or nil for pasted text.
    ///
    /// - Important: Visibility is hardcoded to "private". Never pass "shared" here.
    /// - Throws: `DiscernmentError` on auth failure, network failure, or parse failure.
    func runCheck(
        inputText: String,
        sourceType: String,
        sourceRef: String?
    ) async throws -> DiscernmentCheckResult {
        _ = try requireUID()

        isChecking = true
        error = nil
        defer { isChecking = false }

        let payload: [String: Any] = [
            "inputText":  inputText,
            "sourceType": sourceType,
            "sourceRef":  sourceRef ?? NSNull(),
            "visibility": "private"    // NEVER "shared" — sharing is always an explicit user action
        ]

        let rawResult: HTTPSCallableResult
        do {
            rawResult = try await functions.httpsCallable("runDiscernmentCheck").call(payload)
        } catch {
            self.error = DiscernmentError.networkError(error).localizedDescription
            throw DiscernmentError.networkError(error)
        }

        guard let data = rawResult.data as? [String: Any] else {
            self.error = DiscernmentError.parseError.localizedDescription
            throw DiscernmentError.parseError
        }

        let result = try parseCheckResult(from: data)
        currentCheck = result
        return result
    }

    // MARK: - Share Check

    /// Explicitly shares an existing private check via `shareDiscernmentCheck`.
    ///
    /// This call MUST be preceded by an explicit user confirmation dialog.
    /// Never call this automatically or without user intent.
    ///
    /// - Parameter checkId: The ID of the check to share.
    /// - Returns: The updated `DiscernmentCheckResult` with `visibility == "shared"`.
    func shareCheck(checkId: String) async throws -> DiscernmentCheckResult {
        _ = try requireUID()

        let rawResult: HTTPSCallableResult
        do {
            rawResult = try await functions.httpsCallable("shareDiscernmentCheck").call(["checkId": checkId])
        } catch {
            self.error = DiscernmentError.networkError(error).localizedDescription
            throw DiscernmentError.networkError(error)
        }

        guard let data = rawResult.data as? [String: Any] else {
            self.error = DiscernmentError.parseError.localizedDescription
            throw DiscernmentError.parseError
        }

        let updated = try parseCheckResult(from: data)

        // Update currentCheck only if it is the same check.
        if currentCheck?.id == updated.id {
            currentCheck = updated
        }

        return updated
    }

    // MARK: - Private: Parse

    private func parseCheckResult(from data: [String: Any]) throws -> DiscernmentCheckResult {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            let decoder = JSONDecoder()
            return try decoder.decode(DiscernmentCheckResult.self, from: jsonData)
        } catch {
            throw DiscernmentError.parseError
        }
    }
}
