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

    private let db = Firestore.firestore()
    private let reports: CollectionReference
    private let userSafetyRecords: CollectionReference
    private let moderationQueue: CollectionReference

    // ── Client-side rate limiting ──────────────────────────────────────────────
    // Prevents report flooding: no more than 10 reports per reporter in any
    // rolling 10-minute window, regardless of target.  Tier 1 reports are
    // always allowed through (urgent safety concerns must not be throttled).
    private var recentReportTimestamps: [Date] = []
    private let rateLimitWindow:   TimeInterval = 600   // 10 minutes
    private let rateLimitMaxCount: Int          = 10    // max reports in window

    private init() {
        reports = db.collection("reports")
        userSafetyRecords = db.collection("userSafetyRecords")
        moderationQueue = db.collection("moderationQueue")
    }

    // MARK: - Submit Report

    /// Submit a block+report. This is the primary entry point from the one-tap UI.
    ///
    /// Steps:
    ///   0. Client-side rate limit (non-Tier-1 only — urgent reports always pass)
    ///   1. Deduplicate (same reporter+reported pair within 24h → skip)
    ///   2. Write report document with evidence snapshot
    ///   3. If blockImmediately: update reporter's block list in Firestore
    ///   4. Execute escalation playbook based on report reason
    func submitReport(_ submission: ReportSubmission) async -> ReportResult {
        // 0. Client-side rate limit — allow Tier 1 (urgent) through unconditionally
        if submission.reason.escalationTier > 1 {
            let now = Date()
            // Drop timestamps outside the rolling window
            recentReportTimestamps = recentReportTimestamps.filter {
                now.timeIntervalSince($0) < rateLimitWindow
            }
            if recentReportTimestamps.count >= rateLimitMaxCount {
                dlog("⚠️ [Safety] Report rate limit hit for reporter \(submission.reporterId) — throttling")
                return .alreadyReported
            }
            recentReportTimestamps.append(now)
        }

        // 1. Deduplicate within 24h
        let isDuplicate = await checkDuplicate(
            reporterId: submission.reporterId,
            reportedUserId: submission.reportedUserId
        )
        if isDuplicate {
            return .alreadyReported
        }

        let reportId = UUID().uuidString

        // 2. Write report document
        let reportData: [String: Any] = [
            "reportId": reportId,
            "reporterId": submission.reporterId,
            "reportedUserId": submission.reportedUserId,
            "conversationId": submission.conversationId,
            "reason": submission.reason.rawValue,
            "escalationTier": submission.reason.escalationTier,
            "priorityLevel": submission.reason.priorityLevel,
            "evidenceMessageIds": submission.evidenceMessageIds,
            "additionalContext": submission.additionalContext ?? "",
            "status": "pending_review",
            "submittedAt": FieldValue.serverTimestamp(),
            "reviewedAt": NSNull(),
            "reviewerId": NSNull(),
            "actionTaken": NSNull()
        ]

        do {
            try await reports.document(reportId).setData(reportData)
        } catch {
            return .failure(error)
        }

        // 3. Immediate block if requested
        if submission.blockImmediately {
            await blockUser(
                blockerId: submission.reporterId,
                blockedId: submission.reportedUserId
            )
        }

        // 4. Execute escalation playbook (async — does not block return)
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.executeEscalationPlaybook(
                reportId: reportId,
                submission: submission
            )
        }

        return .success(reportId: reportId)
    }

    // MARK: - Escalation Playbooks

    /// Executes the appropriate escalation playbook based on report tier and reported user's history.
    private func executeEscalationPlaybook(
        reportId: String,
        submission: ReportSubmission
    ) async {
        let reportedId = submission.reportedUserId

        // Fetch prior report count against this user
        let priorReportCount = await fetchPriorReportCount(userId: reportedId)

        switch submission.reason.escalationTier {

        case 1:
            // TIER 1: Suspected minor exploitation / trafficking / threat / sextortion
            // → Immediate account freeze + preserve evidence + priority 5 queue entry
            await freezeReportedAccount(
                userId: reportedId,
                reason: submission.reason.rawValue,
                reportId: reportId
            )
            await preserveEvidence(
                userId: reportedId,
                conversationId: submission.conversationId,
                evidenceMessageIds: submission.evidenceMessageIds
            )
            await writeEscalationQueueEntry(
                reportId: reportId,
                submission: submission,
                action: "immediate_freeze",
                priority: 5
            )

        case 2:
            // TIER 2: Solicitation / off-platform / financial scam / violence
            // → If 2+ reports: freeze. Otherwise: hold all messages + priority 3 review.
            if priorReportCount >= 2 {
                await freezeReportedAccount(
                    userId: reportedId,
                    reason: "\(submission.reason.rawValue) (multiple reports)",
                    reportId: reportId
                )
            } else {
                await holdAllPendingMessages(userId: reportedId, conversationId: submission.conversationId)
            }
            await writeEscalationQueueEntry(
                reportId: reportId,
                submission: submission,
                action: priorReportCount >= 2 ? "freeze_multi_report" : "hold_messages",
                priority: 3
            )

        default:
            // TIER 3: Harassment / hate / spam / unwanted contact
            // → If 3+ reports: freeze. Otherwise: standard review queue.
            if priorReportCount >= 3 {
                await freezeReportedAccount(
                    userId: reportedId,
                    reason: "Repeated reports: \(submission.reason.rawValue)",
                    reportId: reportId
                )
                await writeEscalationQueueEntry(
                    reportId: reportId,
                    submission: submission,
                    action: "freeze_repeated",
                    priority: 3
                )
            } else {
                await writeEscalationQueueEntry(
                    reportId: reportId,
                    submission: submission,
                    action: "standard_review",
                    priority: 1
                )
            }
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

    private func checkDuplicate(reporterId: String, reportedUserId: String) async -> Bool {
        let cutoff = Date().addingTimeInterval(-86400)  // 24h window
        do {
            let snapshot = try await reports
                .whereField("reporterId", isEqualTo: reporterId)
                .whereField("reportedUserId", isEqualTo: reportedUserId)
                .whereField("submittedAt", isGreaterThan: Timestamp(date: cutoff))
                .limit(to: 1)
                .getDocuments()
            return !snapshot.documents.isEmpty
        } catch {
            // Fail CLOSED on network error — return false to allow the report through.
            // We'd rather accept a rare duplicate than drop a legitimate safety report.
            // The server-side Cloud Function applies its own dedup before acting.
            return false
        }
    }

    private func fetchPriorReportCount(userId: String) async -> Int {
        do {
            let snapshot = try await reports
                .whereField("reportedUserId", isEqualTo: userId)
                .whereField("status", isNotEqualTo: "dismissed")
                .getDocuments()
            return snapshot.documents.count
        } catch {
            return 0
        }
    }

    private func blockUser(blockerId: String, blockedId: String) async {
        guard !blockerId.isEmpty, !blockedId.isEmpty else { return }
        _ = try? await db.collection("users").document(blockerId)
            .collection("blocks").document(blockedId)
            .setData([
                "blockedUserId": blockedId,
                "blockedAt": FieldValue.serverTimestamp()
            ])
    }

    private func freezeReportedAccount(
        userId: String,
        reason: String,
        reportId: String
    ) async {
        guard !userId.isEmpty else { return }
        _ = try? await userSafetyRecords.document(userId).setData([
            "accountStatus": "frozen",
            "frozenUntil": 0,  // Indefinite
            "frozenReason": "Reported: \(reason)",
            "frozenByReportId": reportId,
            "requiresManualReview": true,
            "frozenAt": FieldValue.serverTimestamp(),
            "canDeleteMessages": false,
            "canChangeUsername": false
        ], merge: true)
    }

    private func preserveEvidence(
        userId: String,
        conversationId: String,
        evidenceMessageIds: [String]
    ) async {
        guard !userId.isEmpty else { return }
        _ = try? await db.collection("evidencePreservation").addDocument(data: [
            "userId": userId,
            "conversationId": conversationId,
            "evidenceMessageIds": evidenceMessageIds,
            "preservedAt": FieldValue.serverTimestamp(),
            "retentionDays": 90  // 90-day evidence hold
        ])
    }

    private func holdAllPendingMessages(userId: String, conversationId: String) async {
        guard !userId.isEmpty else { return }
        // Flag all future messages from this user in this conversation as held
        _ = try? await db.collection("userSafetyRecords").document(userId).setData([
            "holdMessagesInConversation": conversationId,
            "messageHoldStartedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    private func writeEscalationQueueEntry(
        reportId: String,
        submission: ReportSubmission,
        action: String,
        priority: Int
    ) async {
        _ = try? await moderationQueue.addDocument(data: [
            "reportId": reportId,
            "reportedUserId": submission.reportedUserId,
            "reporterId": submission.reporterId,
            "conversationId": submission.conversationId,
            "reason": submission.reason.rawValue,
            "escalationTier": submission.reason.escalationTier,
            "action": action,
            "priorityLevel": priority,
            "status": "pending_review",
            "createdAt": FieldValue.serverTimestamp(),
            "reviewedAt": NSNull(),
            "reviewerId": NSNull()
        ])
    }
}
