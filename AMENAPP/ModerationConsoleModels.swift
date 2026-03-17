//
//  ModerationConsoleModels.swift
//  AMENAPP
//
//  Data models for the human moderation review console.
//  These structures are designed to be fetched from Firestore and
//  rendered in a future moderation dashboard (web or admin iOS target).
//
//  Covers:
//    - ModeratorReviewCase: the primary unit of work in the moderation queue
//    - ConversationTimeline: ordered message events with risk markers
//    - UserHistorySummary: reports, blocks, strikes, trust tier for a subject
//    - NetworkContactSummary: unique recipients, overlap with other flagged users
//    - QuickAction: freeze / ban / preserve evidence / dismiss
//    - EscalationPlaybook: named playbooks with pre-defined action sequences
//

import Foundation
import FirebaseFirestore

// MARK: - Moderation Case Status

enum ModerationCaseStatus: String, Codable {
    case pendingReview   = "pending_review"
    case inReview        = "in_review"
    case actionTaken     = "action_taken"
    case dismissed       = "dismissed"
    case escalated       = "escalated"
}

// MARK: - Moderation Action

/// Actions a moderator can take on a case.
enum ConsoleAction: String, Codable, CaseIterable {
    case freezeAccount      = "freeze_account"          // Temp freeze (7 days default)
    case permanentBan       = "permanent_ban"           // Permanent removal
    case suspendAccount     = "suspend_account"         // 30-day suspension
    case warnUser           = "warn_user"               // Warning + required acknowledgment
    case restrictMessaging  = "restrict_messaging"      // Can read, cannot send
    case preserveEvidence   = "preserve_evidence"       // Lock messages for legal hold
    case reportToNCMEC      = "report_to_ncmec"         // CSAM → NCMEC CyberTipline
    case contactAuthorities = "contact_authorities"     // Threat → law enforcement referral
    case dismissCase        = "dismiss_case"            // No violation found
    case escalateCase       = "escalate_case"           // Needs senior reviewer

    var displayLabel: String {
        switch self {
        case .freezeAccount:      return "Freeze Account (7 days)"
        case .permanentBan:       return "Permanent Ban"
        case .suspendAccount:     return "Suspend Account (30 days)"
        case .warnUser:           return "Issue Warning"
        case .restrictMessaging:  return "Restrict Messaging"
        case .preserveEvidence:   return "Preserve Evidence"
        case .reportToNCMEC:      return "Report to NCMEC"
        case .contactAuthorities: return "Law Enforcement Referral"
        case .dismissCase:        return "Dismiss — No Violation"
        case .escalateCase:       return "Escalate to Senior Reviewer"
        }
    }

    /// Whether this action requires a second moderator to confirm
    var requiresSecondApproval: Bool {
        switch self {
        case .permanentBan, .reportToNCMEC, .contactAuthorities:
            return true
        default:
            return false
        }
    }
}

// MARK: - Moderator Review Case

/// The primary work unit in the moderation queue.
/// Maps 1:1 with a `moderationQueue` Firestore document.
struct ModeratorReviewCase: Identifiable {
    let id: String                          // Firestore document ID (= messageId or reportId)
    let caseType: ModerationCaseType
    let senderId: String
    let recipientId: String
    let conversationId: String
    let signals: [SafetySignal]
    let riskScore: Double
    let priorityLevel: Int                  // 1–5; 5 = review within 1 hour
    var status: ModerationCaseStatus
    let createdAt: Date
    var reviewedAt: Date?
    var reviewerId: String?
    var actionTaken: ConsoleAction?
    var notes: String?

    // Context loaded on demand
    var conversationTimeline: ConversationTimeline?
    var senderHistory: UserHistorySummary?
    var networkSummary: NetworkContactSummary?
}

enum ModerationCaseType: String, Codable {
    case messageSafetyViolation = "message_safety"
    case mediaViolation         = "media_safety"
    case userReport             = "user_report"
    case patternBehavior        = "pattern_behavior"
}

// MARK: - Conversation Timeline

/// An ordered sequence of message events in a conversation, annotated with risk markers.
/// Designed for a moderator to read the conversation in context.
struct ConversationTimeline {
    let conversationId: String
    let participants: [TimelineParticipant]
    let events: [TimelineEvent]
    let riskAnnotations: [RiskAnnotation]
}

struct TimelineParticipant: Identifiable {
    let id: String              // userId
    let displayName: String
    let trustTier: UserTrustTier
    let isMinorOrUnknown: Bool
    let accountCreatedAt: Date?
    let verifiedIdentity: Bool
}

struct TimelineEvent: Identifiable {
    let id: String              // messageId
    let senderId: String
    let timestamp: Date
    let messageText: String     // Redacted for CSAM — replaced with "[Content removed]"
    let signals: [SafetySignal]
    let riskScore: Double
    let gatewayDecision: String // Raw decision string from GatewayDecision
    let isHeld: Bool
    let mediaAttached: Bool
    let mediaRejected: Bool
}

struct RiskAnnotation {
    let messageId: String
    let annotationType: AnnotationType
    let description: String
}

enum AnnotationType: String {
    case grooming           = "grooming_pattern"
    case escalation         = "risk_escalation"
    case isolation          = "isolation_attempt"
    case offPlatform        = "off_platform_push"
    case financialRequest   = "financial_request"
    case ageRisk            = "age_risk"
    case mediaRisk          = "media_risk"
}

// MARK: - User History Summary

/// Subject's full moderation history — used in the "User History" panel of the console.
struct UserHistorySummary {
    let userId: String
    let displayName: String
    let accountCreatedAt: Date?
    let trustTier: UserTrustTier
    let ageVerificationStatus: AgeVerificationStatus
    let totalStrikes: Int
    let totalReportsReceived: Int
    let totalReportsSubmitted: Int
    let priorActions: [PriorConsoleAction]
    let currentAccountStatus: String    // "active" | "frozen" | "suspended" | "banned"
    let uniqueConversationCount: Int    // Total DM conversations
    let uniqueRecipientsWithFlags: Int  // Conversations that triggered gateway flags
}

struct PriorConsoleAction: Identifiable {
    let id: String
    let action: ConsoleAction
    let reason: String
    let takenAt: Date
    let reviewerId: String
    let caseId: String
}

// MARK: - Network Contact Summary

/// Cross-user view: how many other users has the subject contacted, and how many were flagged.
/// Used to identify potential mass-targeting or trafficking network patterns.
struct NetworkContactSummary {
    let subjectUserId: String
    /// All unique recipient UIDs the subject has messaged in the past 90 days
    let uniqueRecipients: Int
    /// Recipients who also received gateway-flagged messages from this subject
    let recipientsWithFlags: Int
    /// Other users flagged for the same signal types (potential network)
    let relatedFlaggedUsers: [RelatedFlaggedUser]
    /// How many of the recipients are minors or age-unknown
    let minorOrUnknownRecipients: Int
    /// Broadcast pattern: same pHash image sent to N recipients
    let broadcastMediaInstances: [BroadcastMediaSummary]
}

struct RelatedFlaggedUser: Identifiable {
    let id: String          // userId
    let sharedSignals: [SafetySignal]
    let overlapConversationCount: Int
    let accountStatus: String
}

struct BroadcastMediaSummary: Identifiable {
    let id: String          // pHash
    let recipientCount: Int
    let firstSeenAt: Date
    let mediaDecision: String
}

// MARK: - Quick Action

/// Pre-built action bundles for common moderation scenarios.
/// A quick action can execute multiple `ConsoleAction` steps in sequence.
struct QuickAction: Identifiable {
    let id: String
    let name: String
    let description: String
    let actions: [ConsoleAction]
    let requiresConfirmation: Bool

    static let standardPresets: [QuickAction] = [
        QuickAction(
            id: "freeze_preserve",
            name: "Freeze + Preserve Evidence",
            description: "Freeze account for 7 days and lock all messages for legal hold.",
            actions: [.freezeAccount, .preserveEvidence],
            requiresConfirmation: true
        ),
        QuickAction(
            id: "ban_preserve",
            name: "Permanent Ban + Preserve",
            description: "Permanently ban account and preserve all evidence. Requires second approver.",
            actions: [.permanentBan, .preserveEvidence],
            requiresConfirmation: true
        ),
        QuickAction(
            id: "csam_response",
            name: "CSAM Response",
            description: "Immediately freeze, preserve evidence, and report to NCMEC CyberTipline.",
            actions: [.freezeAccount, .preserveEvidence, .reportToNCMEC],
            requiresConfirmation: true
        ),
        QuickAction(
            id: "threat_response",
            name: "Credible Threat Response",
            description: "Freeze account, preserve evidence, and flag for law enforcement referral.",
            actions: [.freezeAccount, .preserveEvidence, .contactAuthorities],
            requiresConfirmation: true
        ),
        QuickAction(
            id: "warn_restrict",
            name: "Warn + Restrict Messaging",
            description: "Issue a formal warning and restrict the user from sending new messages.",
            actions: [.warnUser, .restrictMessaging],
            requiresConfirmation: false
        ),
        QuickAction(
            id: "dismiss",
            name: "Dismiss — No Violation",
            description: "Mark case as reviewed with no action required.",
            actions: [.dismissCase],
            requiresConfirmation: false
        )
    ]
}

// MARK: - Escalation Playbook

/// Named playbook that maps a signal pattern or report type to a recommended action sequence.
/// Moderators see the recommended playbook highlighted at the top of each case.
struct EscalationPlaybook: Identifiable {
    let id: String
    let name: String
    let triggerCondition: PlaybookTrigger
    let recommendedQuickActionId: String
    let slaHours: Int           // Service level: review within N hours
    let autoActions: [ConsoleAction]  // Actions taken automatically before human review

    static let allPlaybooks: [EscalationPlaybook] = [

        // Child safety — highest priority
        EscalationPlaybook(
            id: "minor_exploitation",
            name: "Suspected Minor Exploitation",
            triggerCondition: .signalDetected(.ageMentionWithSexual),
            recommendedQuickActionId: "ban_preserve",
            slaHours: 1,
            autoActions: [.freezeAccount, .preserveEvidence]
        ),

        // Trafficking pattern
        EscalationPlaybook(
            id: "trafficking_pattern",
            name: "Potential Trafficking Pattern",
            triggerCondition: .reportReasonTier(1),
            recommendedQuickActionId: "ban_preserve",
            slaHours: 1,
            autoActions: [.freezeAccount, .preserveEvidence]
        ),

        // Credible threat
        EscalationPlaybook(
            id: "credible_threat",
            name: "Credible Threat of Violence",
            triggerCondition: .signalDetected(.violenceIntent),
            recommendedQuickActionId: "threat_response",
            slaHours: 1,
            autoActions: [.freezeAccount, .preserveEvidence]
        ),

        // Sextortion / blackmail
        EscalationPlaybook(
            id: "sextortion",
            name: "Sextortion or Blackmail",
            triggerCondition: .signalDetected(.threatsBlackmail),
            recommendedQuickActionId: "freeze_preserve",
            slaHours: 2,
            autoActions: [.freezeAccount, .preserveEvidence]
        ),

        // Repeated harassment
        EscalationPlaybook(
            id: "repeated_harassment",
            name: "Repeated Harassment (3+ Reports)",
            triggerCondition: .reportCountExceeds(3),
            recommendedQuickActionId: "warn_restrict",
            slaHours: 8,
            autoActions: []
        ),

        // Standard flag
        EscalationPlaybook(
            id: "standard_review",
            name: "Standard Safety Review",
            triggerCondition: .priorityLevel(1),
            recommendedQuickActionId: "dismiss",
            slaHours: 48,
            autoActions: []
        )
    ]
}

enum PlaybookTrigger {
    case signalDetected(SafetySignal)
    case reportReasonTier(Int)
    case reportCountExceeds(Int)
    case priorityLevel(Int)
    case networkPatternDetected
}

// MARK: - Firestore Fetch Helpers

/// Lightweight async helpers for loading moderation console data.
/// These are used by the future moderator dashboard, not by the main app UI.
@MainActor
final class ModerationConsoleService {
    static let shared = ModerationConsoleService()
    private let db = Firestore.firestore()

    private init() {}

    /// Fetch the next N pending cases, sorted by priority descending then createdAt ascending.
    func fetchPendingCases(limit: Int = 50) async -> [ModeratorReviewCase] {
        do {
            let snapshot = try await db.collection("moderationQueue")
                .whereField("status", isEqualTo: ModerationCaseStatus.pendingReview.rawValue)
                .order(by: "priorityLevel", descending: true)
                .order(by: "createdAt", descending: false)
                .limit(to: limit)
                .getDocuments()

            return snapshot.documents.compactMap { doc in
                buildReviewCase(from: doc)
            }
        } catch {
            print("⚠️ [Moderation] Failed to fetch pending cases: \(error)")
            return []
        }
    }

    /// Fetch conversation timeline for a specific conversation.
    func fetchConversationTimeline(conversationId: String, limit: Int = 100) async -> ConversationTimeline? {
        do {
            // Fetch last N messages ordered by timestamp
            let messagesSnapshot = try await db
                .collection("conversations").document(conversationId)
                .collection("messages")
                .order(by: "timestamp", descending: false)
                .limit(to: limit)
                .getDocuments()

            let events: [TimelineEvent] = messagesSnapshot.documents.compactMap { doc in
                let data = doc.data()
                guard let senderId = data["senderId"] as? String,
                      let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else {
                    return nil
                }
                let signalStrings = data["safetySignals"] as? [String] ?? []
                let signals = signalStrings.compactMap { SafetySignal(rawValue: $0) }

                return TimelineEvent(
                    id: doc.documentID,
                    senderId: senderId,
                    timestamp: timestamp,
                    messageText: data["text"] as? String ?? "[No text]",
                    signals: signals,
                    riskScore: data["safetyRiskScore"] as? Double ?? 0,
                    gatewayDecision: data["safetyStatus"] as? String ?? "unknown",
                    isHeld: data["isHeld"] as? Bool ?? false,
                    mediaAttached: data["mediaURL"] != nil,
                    mediaRejected: data["mediaRejected"] as? Bool ?? false
                )
            }

            // Build risk annotations from flagged messages
            let annotations: [RiskAnnotation] = events
                .filter { !$0.signals.isEmpty }
                .flatMap { event -> [RiskAnnotation] in
                    event.signals.compactMap { signal -> RiskAnnotation? in
                        guard let type = annotationType(for: signal) else { return nil }
                        return RiskAnnotation(
                            messageId: event.id,
                            annotationType: type,
                            description: annotationDescription(for: signal)
                        )
                    }
                }

            return ConversationTimeline(
                conversationId: conversationId,
                participants: [],  // Populated separately via fetchParticipants
                events: events,
                riskAnnotations: annotations
            )
        } catch {
            print("⚠️ [Moderation] Failed to fetch timeline: \(error)")
            return nil
        }
    }

    /// Fetch user history summary for a subject user.
    func fetchUserHistory(userId: String) async -> UserHistorySummary? {
        guard !userId.isEmpty else { return nil }
        do {
            async let userDoc = db.collection("users").document(userId).getDocument()
            async let safetyDoc = db.collection("userSafetyRecords").document(userId).getDocument()
            async let reportsSnapshot = db.collection("reports")
                .whereField("reportedUserId", isEqualTo: userId).getDocuments()

            let (user, safety, reports) = try await (userDoc, safetyDoc, reportsSnapshot)

            let userData = user.data() ?? [:]
            let safetyData = safety.data() ?? [:]

            let priorActions: [PriorConsoleAction] = [] // Future: fetch from enforcementHistory

            return UserHistorySummary(
                userId: userId,
                displayName: userData["username"] as? String ?? "Unknown",
                accountCreatedAt: (userData["createdAt"] as? Timestamp)?.dateValue(),
                trustTier: .newAccount, // Future: compute from MinorSafetyService
                ageVerificationStatus: .unknown,
                totalStrikes: safetyData["strikes"] as? Int ?? 0,
                totalReportsReceived: reports.documents.count,
                totalReportsSubmitted: 0, // Future: query by reporterId
                priorActions: priorActions,
                currentAccountStatus: safetyData["accountStatus"] as? String ?? "active",
                uniqueConversationCount: 0,
                uniqueRecipientsWithFlags: 0
            )
        } catch {
            print("⚠️ [Moderation] Failed to fetch user history: \(error)")
            return nil
        }
    }

    /// Record a moderator action on a case.
    func recordAction(
        caseId: String,
        action: ConsoleAction,
        reviewerId: String,
        notes: String?
    ) async {
        let updateData: [String: Any] = [
            "status": ModerationCaseStatus.actionTaken.rawValue,
            "actionTaken": action.rawValue,
            "reviewerId": reviewerId,
            "reviewedAt": FieldValue.serverTimestamp(),
            "moderatorNotes": notes ?? ""
        ]
        _ = try? await db.collection("moderationQueue").document(caseId).updateData(updateData)
    }

    // MARK: - Private Helpers

    private func buildReviewCase(from doc: QueryDocumentSnapshot) -> ModeratorReviewCase? {
        let data = doc.data()
        guard let senderId = data["senderId"] as? String,
              let recipientId = data["recipientId"] as? String ?? (data["reportedUserId"] as? String),
              let conversationId = data["conversationId"] as? String,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() else {
            return nil
        }

        let signalStrings = data["signals"] as? [String] ?? []
        let signals = signalStrings.compactMap { SafetySignal(rawValue: $0) }
        let statusRaw = data["status"] as? String ?? "pending_review"
        let actionRaw = data["actionTaken"] as? String
        let caseTypeRaw = data["caseType"] as? String ?? "message_safety"

        return ModeratorReviewCase(
            id: doc.documentID,
            caseType: ModerationCaseType(rawValue: caseTypeRaw) ?? .messageSafetyViolation,
            senderId: senderId,
            recipientId: recipientId,
            conversationId: conversationId,
            signals: signals,
            riskScore: data["riskScore"] as? Double ?? 0,
            priorityLevel: data["priorityLevel"] as? Int ?? 1,
            status: ModerationCaseStatus(rawValue: statusRaw) ?? .pendingReview,
            createdAt: createdAt,
            reviewedAt: (data["reviewedAt"] as? Timestamp)?.dateValue(),
            reviewerId: data["reviewerId"] as? String,
            actionTaken: actionRaw.flatMap { ConsoleAction(rawValue: $0) },
            notes: data["moderatorNotes"] as? String
        )
    }

    private func annotationType(for signal: SafetySignal) -> AnnotationType? {
        switch signal {
        case .groomingIntent, .isolationLanguage, .loveBombing:
            return .grooming
        case .offPlatformMigration, .urgencyPressure:
            return .offPlatform
        case .contactExchange, .locationRequest:
            return .isolation
        case .moneyTransferRequest, .giftCardRequest, .modelingScam:
            return .financialRequest
        case .ageMentionWithSexual, .sexualSolicitation:
            return .ageRisk
        default:
            return nil
        }
    }

    private func annotationDescription(for signal: SafetySignal) -> String {
        switch signal {
        case .ageMentionWithSexual:   return "Age + sexual content detected — child safety risk"
        case .groomingIntent:         return "Grooming language pattern detected"
        case .isolationLanguage:      return "Isolation attempt: asked recipient to keep secret"
        case .offPlatformMigration:   return "Attempted to move conversation off platform"
        case .contactExchange:        return "Requested or shared contact information"
        case .locationRequest:        return "Requested meeting location or physical address"
        case .moneyTransferRequest:   return "Requested money transfer"
        case .giftCardRequest:        return "Requested gift cards"
        case .threatsBlackmail:       return "Threats or blackmail detected"
        case .violenceIntent:         return "Credible threat of violence"
        case .selfHarmCrisis:         return "Self-harm or crisis language detected"
        default:                      return signal.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
