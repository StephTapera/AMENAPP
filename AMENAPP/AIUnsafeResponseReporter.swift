//
//  AIUnsafeResponseReporter.swift
//  AMENAPP
//
//  Phase H3 / App Review Guideline 1.2 — Swift wrapper for the
//  reportUnsafeAIResponse Cloud Function callable.
//
//  This is the iOS half of the "Report this AI response" affordance.
//  Used by ReportUnsafeAIResponseSheet (and any future surface — e.g.
//  Berean Pulse, Daily Verse — that wants to expose the same affordance).
//
//  Privacy invariants:
//    - The user's `details` text is sent to the backend in the report
//      payload but is NEVER logged client-side (no dlog/print, no
//      analytics field containing the text).
//    - The backend rejects oversized details and never logs them either.

import Foundation
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class AIUnsafeResponseReporter {
    static let shared = AIUnsafeResponseReporter()
    private init() {}

    /// Mirrors `VALID_REASONS` on the backend (reportAIFunctions.js).
    /// Raw values MUST stay in sync with the CF's VALID_REASONS array.
    /// The display label is what the user sees in the picker.
    enum Reason: String, CaseIterable, Identifiable {
        case unsafeAdvice           = "unsafe_advice"
        case falseDoctrine          = "false_doctrine"
        case claimsDivineAuthority  = "claims_divine_authority"
        case crisisMishandled       = "crisis_mishandled"
        case harassmentOrHate       = "harassment_or_hate"
        case privateInfoLeak        = "private_info_leak"
        case fabricatedScripture    = "fabricated_scripture"
        case other                  = "other"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .unsafeAdvice:          return "Unsafe medical / legal / mental-health advice"
            case .falseDoctrine:         return "Theologically false or misleading"
            case .claimsDivineAuthority: return "Claims divine authority (prophecy, \u{201C}God told me\u{201D}, etc.)"
            case .crisisMishandled:      return "Crisis or self-harm not handled safely"
            case .harassmentOrHate:      return "Harassment or hate speech"
            case .privateInfoLeak:       return "Exposed personal information"
            case .fabricatedScripture:   return "Fabricated or misquoted scripture"
            case .other:                 return "Other"
            }
        }
    }

    /// Mirrors the backend `ALLOWED_SURFACES` set. Keep these strings
    /// stable; the backend silently degrades unknown values to "other".
    enum Surface: String {
        case bereanChat        = "berean_chat"
        case bereanPulse       = "berean_pulse"
        case dailyVerse        = "daily_verse"
        case churchNotesDraft  = "church_notes_draft"
        case other             = "other"
    }

    enum ReportError: LocalizedError {
        case notSignedIn
        case rateLimited
        case invalidArgument(String)
        case attestation
        case unknown(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn:           return "Please sign in to report this response."
            case .rateLimited:           return "Too many reports recently. Please wait a moment and try again."
            case .invalidArgument(let m): return m
            case .attestation:           return "Could not verify the app. Please try again."
            case .unknown(let m):        return m
            }
        }
    }

    /// Submits an unsafe-response report. Returns the server-assigned
    /// report id on success.
    func submit(
        messageId: String,
        reason: Reason,
        details: String?,
        conversationId: String?,
        surface: Surface
    ) async throws -> String {
        guard let currentUser = Auth.auth().currentUser else {
            throw ReportError.notSignedIn
        }
        do {
            _ = try await currentUser.getIDToken(forcingRefresh: false)
        } catch {
            throw ReportError.notSignedIn
        }

        var params: [String: Any] = [
            "messageId": messageId,
            "reason": reason.rawValue,
            "surface": surface.rawValue,
        ]
        if let trimmed = details?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmed.isEmpty {
            params["details"] = trimmed
        }
        if let conversationId, !conversationId.isEmpty {
            params["conversationId"] = conversationId
        }

        let callable = Functions.functions().httpsCallable("reportUnsafeAIResponse")
        do {
            let response = try await callable.call(params)
            guard
                let dict = response.data as? [String: Any],
                let reportId = dict["reportId"] as? String
            else {
                throw ReportError.unknown("Could not read server response.")
            }
            return reportId
        } catch let error as NSError {
            if error.domain == FunctionsErrorDomain {
                switch FunctionsErrorCode(rawValue: error.code) {
                case .some(.unauthenticated):
                    throw ReportError.attestation
                case .some(.resourceExhausted):
                    throw ReportError.rateLimited
                case .some(.invalidArgument):
                    throw ReportError.invalidArgument(
                        error.localizedDescription
                    )
                default:
                    throw ReportError.unknown("Network error. Please retry.")
                }
            }
            throw ReportError.unknown("Network error. Please retry.")
        }
    }
}
