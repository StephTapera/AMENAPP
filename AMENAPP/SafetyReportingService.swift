//
//  SafetyReportingService.swift
//  AMENAPP
//
//  One-tap block+report, quick report reasons, in-chat safety prompts,
//  and escalation playbook triggers for the messaging safety pipeline.
//
//  Responsibilities:
//    1. Receive report submissions from UI (reason + optional context)
//    2. Immediately block sender from further contact
//    3. Write to reports collection with evidence snapshot
//    4. Trigger escalation playbook based on report category + user history
//    5. Provide in-chat prompt logic (when to surface safety nudges)
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

// MARK: - Report Reason

/// Quick-select report reasons surfaced in the one-tap report sheet.
/// Ordered from most to least severe for priority assignment.
enum ReportReason: String, CaseIterable, Identifiable {
    // Tier 1 — Immediate escalation (freeze + priority review)
    case groomingOrTrafficking      = "grooming_or_trafficking"
    case childSafetyViolation       = "child_safety"
    case threatOrBlackmail          = "threat_or_blackmail"
    case sextortion                 = "sextortion"

    // Tier 2 — Same-day review (block + hold)
    case solicitation               = "solicitation"
    case offPlatformPressure        = "off_platform_pressure"
    case financialScam              = "financial_scam"
    case violenceOrSelfHarm         = "violence_or_self_harm"

    // Tier 3 — Standard review (24–48h)
    case harassment                 = "harassment"
    case hateSpeech                 = "hate_speech"
    case unwantedContact            = "unwanted_contact"
    case spam                       = "spam"
    case impersonation              = "impersonation"
    case other                      = "other"

    var id: String { rawValue }

    /// Human-readable label shown in report sheet
    var displayLabel: String {
        switch self {
        case .groomingOrTrafficking:   return "Grooming or trafficking concern"
        case .childSafetyViolation:    return "Child safety violation"
        case .threatOrBlackmail:       return "Threat or blackmail"
        case .sextortion:              return "Sextortion (threatened photo/video leak)"
        case .solicitation:            return "Sexual solicitation"
        case .offPlatformPressure:     return "Pressure to move off this platform"
        case .financialScam:           return "Financial scam or fraud"
        case .violenceOrSelfHarm:      return "Violence or self-harm"
        case .harassment:              return "Harassment or bullying"
        case .hateSpeech:              return "Hate speech or discrimination"
        case .unwantedContact:         return "Unwanted contact"
        case .spam:                    return "Spam or fake account"
        case .impersonation:           return "Impersonation"
        case .other:                   return "Something else"
        }
    }

    /// Tier 1 = immediate freeze + priority; Tier 2 = hold; Tier 3 = standard
    var escalationTier: Int {
        switch self {
        case .groomingOrTrafficking, .childSafetyViolation, .threatOrBlackmail, .sextortion:
            return 1
        case .solicitation, .offPlatformPressure, .financialScam, .violenceOrSelfHarm:
            return 2
        case .harassment, .hateSpeech, .unwantedContact, .spam, .impersonation, .other:
            return 3
        }
    }

    var priorityLevel: Int {
        switch escalationTier {
        case 1: return 5  // Highest — reviewed within 1 hour
        case 2: return 3  // High — same-day
        default: return 1 // Standard
        }
    }
}

// MARK: - Report Submission

struct ReportSubmission {
    let reporterId: String
    let reportedUserId: String
    let conversationId: String
    let reason: ReportReason
    /// Up to 5 most recent message IDs included as evidence
    let evidenceMessageIds: [String]
    /// Additional free-text context (optional, 500 char limit)
    let additionalContext: String?
    /// Whether to also block the reported user immediately
    let blockImmediately: Bool
}

// MARK: - Report Result

enum ReportResult {
    case success(reportId: String)
    case alreadyReported
    case failure(Error)
}

// MARK: - Safety Prompt Trigger

/// Conditions under which an in-chat safety nudge should be surfaced.
struct SafetyPromptTrigger {
    let shouldShow: Bool
    let promptType: SafetyPromptType
    let triggeringSignals: [SafetySignal]
}

enum SafetyPromptType {
    /// "This person is asking you to move to another app. You don't have to."
    case offPlatformPressure
    /// "Someone is asking for your personal contact info."
    case contactInfoRequest
    /// "You've received a request for money or gift cards."
    case financialRequest
    /// "If you're feeling unsafe, you can block and report in one tap."
    case generalSafetyReminder
    /// "This person may be pushing you to do something you're not comfortable with."
    case coercionWarning
    /// "There are resources available if you're going through a difficult time."
    case crisisResource
}

// MARK: - Safety Reporting Service

/// Singleton that handles all report submissions and escalation playbook execution.
@MainActor
final class SafetyReportingService {
    static let shared = SafetyReportingService()

    private lazy var db = Firestore.firestore()
    // HIGH-3 FIX: Reports are no longer written directly to Firestore from the client.
    // The submitReport Cloud Function handles all validation, escalation tier computation,
    // deduplication, rate limiting, and the Firestore write via admin SDK.
    // Direct client writes to userReports are now blocked (allow create: if false).
    private lazy var functions = Functions.functions()

    private init() {}

    // MARK: - Submit Report

    /// Submit a block+report. This is the primary entry point from the one-tap UI.
    ///
    /// Steps:
    ///   1. Call submitReport Cloud Function — validates reason, deduplicates, verifies
    ///      evidence, computes escalationTier + priority server-side, writes the report,
    ///      and triggers the escalation playbook on the server.
    ///   2. If blockImmediately: write the local block record (client-owned collection).
    func submitReport(_ submission: ReportSubmission) async -> ReportResult {
        let payload: [String: Any] = [
            "reportedUserId":    submission.reportedUserId,
            "conversationId":    submission.conversationId,
            "reason":            submission.reason.rawValue,
            "evidenceMessageIds": submission.evidenceMessageIds,
            "additionalContext": submission.additionalContext ?? "",
            "blockImmediately":  submission.blockImmediately
        ]

        do {
            let callable = functions.httpsCallable("submitReport")
            let result = try await callable.call(payload)

            // Extract the server-assigned reportId from the response
            guard let data = result.data as? [String: Any],
                  let reportId = data["reportId"] as? String else {
                // Function succeeded but returned an unexpected shape; treat as success
                // with a fallback ID so callers aren't blocked.
                dlog("⚠️ [Safety] submitReport returned unexpected data shape")
                return .success(reportId: UUID().uuidString)
            }

            // Immediate block is applied client-side (reporter owns their own block list)
            if submission.blockImmediately {
                await blockUser(
                    blockerId: submission.reporterId,
                    blockedId: submission.reportedUserId
                )
            }

            return .success(reportId: reportId)

        } catch let error as NSError {
            // Map well-known HttpsError codes to meaningful results
            if error.domain == FunctionsErrorDomain {
                let code = FunctionsErrorCode(rawValue: error.code)
                if code == .alreadyExists {
                    // Server dedup: same reporter+reported pair within 24h
                    return .alreadyReported
                }
                if code == .resourceExhausted {
                    // Server rate limit: > 10 reports / hour
                    dlog("⚠️ [Safety] submitReport rate-limited by server")
                    return .alreadyReported
                }
            }
            dlog("❌ [Safety] submitReport failed: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    // MARK: - In-Chat Safety Prompt Logic

    /// Determines whether a safety prompt should be surfaced to the recipient after receiving a message.
    /// Called with the signals detected by MessageSafetyGateway for messages already delivered (warnRecipient tier).
    func safetyPromptForSignals(_ signals: [SafetySignal]) -> SafetyPromptTrigger {
        // Priority order: highest severity first
        if signals.contains(.selfHarmCrisis) {
            return SafetyPromptTrigger(
                shouldShow: true,
                promptType: .crisisResource,
                triggeringSignals: signals
            )
        }
        if signals.contains(.offPlatformMigration) || signals.contains(.urgencyPressure) {
            return SafetyPromptTrigger(
                shouldShow: true,
                promptType: .offPlatformPressure,
                triggeringSignals: signals
            )
        }
        if signals.contains(.contactExchange) || signals.contains(.locationRequest) {
            return SafetyPromptTrigger(
                shouldShow: true,
                promptType: .contactInfoRequest,
                triggeringSignals: signals
            )
        }
        if signals.contains(.moneyTransferRequest) || signals.contains(.giftCardRequest) {
            return SafetyPromptTrigger(
                shouldShow: true,
                promptType: .financialRequest,
                triggeringSignals: signals
            )
        }
        if signals.contains(.isolationLanguage) || signals.contains(.loveBombing) {
            return SafetyPromptTrigger(
                shouldShow: true,
                promptType: .coercionWarning,
                triggeringSignals: signals
            )
        }
        if signals.contains(.persistentHarassment) || signals.contains(.slursHate) {
            return SafetyPromptTrigger(
                shouldShow: true,
                promptType: .generalSafetyReminder,
                triggeringSignals: signals
            )
        }
        return SafetyPromptTrigger(shouldShow: false, promptType: .generalSafetyReminder, triggeringSignals: [])
    }

    // MARK: - Helpers

    private func blockUser(blockerId: String, blockedId: String) async {
        guard !blockerId.isEmpty, !blockedId.isEmpty else { return }
        // The reporter's own block subcollection is client-owned — the reporter
        // can only write to their own userId path (enforced by Firestore rules).
        do {
            try await db.collection("users").document(blockerId)
                .collection("blocks").document(blockedId)
                .setData([
                    "blockedUserId": blockedId,
                    "blockedAt": FieldValue.serverTimestamp()
                ])
        } catch {
            print("SafetyReportingService: failed to write block record — \(error.localizedDescription)")
        }
    }
}
