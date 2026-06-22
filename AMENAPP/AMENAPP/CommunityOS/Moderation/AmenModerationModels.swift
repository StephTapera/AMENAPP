// AmenModerationModels.swift
// AMENAPP — CommunityOS/Moderation
//
// Phase 4 Agent TS-d — Moderation & Governance
//
// Data models for the moderation queue, appeals, and community health signals.
//
// Privacy invariants:
//   - Reporter identity is stored server-side in Firestore but never shown to the content author.
//   - Community health signals are privacy-preserving: no individual user attribution.
//   - All moderation actions are soft-delete only (I-1).
//   - All admin mutations write an audit log entry (I-2).
//
// Queue writes are server-side (CF via onDocumentCreated on /moderationQueue).
// iOS submits the initial report; CF routes it, assigns moderators, and handles counters.
//
// C5 §2o, Invariant I-1, I-2
// Phase 4 Agent TS-d

import Foundation

// MARK: - ModerationActionType

/// All actions a moderator may take on a queue item.
/// Maps to AuditEventType entries in AmenAuditLogService.
enum ModerationActionType: String, Codable, Sendable {
    case remove         = "remove"         // Soft-delete content (set isDeleted: true)
    case warn           = "warn"           // Issue a warning to the author — no content removal
    case ban            = "ban"            // Suspend the author's account
    case escalate       = "escalate"       // Escalate to ExecutiveAdmin / safety team
    case appealGranted  = "appeal_granted" // Appeal was granted; content restored
    case appealDenied   = "appeal_denied"  // Appeal was denied; action stands
    case restore        = "restore"        // Restore previously removed content
    case noAction       = "no_action"      // Reviewed and cleared — no action required

    /// Human-readable label for the moderator dashboard.
    var displayLabel: String {
        switch self {
        case .remove:        return "Remove Content"
        case .warn:          return "Warn Author"
        case .ban:           return "Suspend Account"
        case .escalate:      return "Escalate"
        case .appealGranted: return "Grant Appeal"
        case .appealDenied:  return "Deny Appeal"
        case .restore:       return "Restore Content"
        case .noAction:      return "No Action"
        }
    }

    /// SF Symbol icon for the action in the moderator dashboard UI.
    var symbolName: String {
        switch self {
        case .remove:        return "trash"
        case .warn:          return "exclamationmark.triangle"
        case .ban:           return "person.crop.circle.badge.xmark"
        case .escalate:      return "arrow.up.forward"
        case .appealGranted: return "checkmark.circle"
        case .appealDenied:  return "xmark.circle"
        case .restore:       return "arrow.counterclockwise"
        case .noAction:      return "checkmark"
        }
    }
}

// MARK: - ModerationItemStatus

/// Lifecycle status of a moderation queue item.
enum ModerationItemStatus: String, Codable, Sendable {
    case pending    = "pending"     // Awaiting moderator review
    case reviewed   = "reviewed"    // Reviewed; action taken or cleared
    case escalated  = "escalated"   // Escalated to higher authority
    case resolved   = "resolved"    // Fully resolved
    case appealed   = "appealed"    // Author submitted an appeal; awaiting appeal review

    /// Human-readable label.
    var displayLabel: String {
        switch self {
        case .pending:   return "Pending"
        case .reviewed:  return "Reviewed"
        case .escalated: return "Escalated"
        case .resolved:  return "Resolved"
        case .appealed:  return "Appealed"
        }
    }

    /// Whether this status requires active moderator attention.
    var requiresAttention: Bool {
        self == .pending || self == .escalated || self == .appealed
    }
}

// MARK: - ModerationQueueItem

/// A single item in the moderation queue. Stored at /moderationQueue/{id}.
///
/// PRIVACY: reportedBy is stored here but must NEVER be surfaced to the content author.
///   The moderator UI may show the reporter ID, but the author-facing view must not.
///   Firestore rules enforce that only Moderator+ roles can read moderationQueue documents.
///
/// SOFT-DELETE: Content is never physically removed from Firestore (Invariant I-1).
///   The ModerationService.takeAction() sets isDeleted: true on the content document.
///   Physical deletion is handled by a CF retention job after 30 days.
struct ModerationQueueItem: Codable, Identifiable, Sendable {
    /// Auto-generated Firestore document ID.
    var id: String

    /// Firestore path of the reported content (e.g. "posts/abc123", "comments/xyz789").
    var contentRef: String

    /// Content surface type: "post" | "comment" | "prayer" | "message" | "profile"
    var contentType: String

    /// UID of the user who submitted the report. nil if system-detected (e.g. NeMo Guard).
    /// PRIVACY: Never exposed to content author.
    var reportedBy: String?

    /// The reason for the report (user-supplied or system-generated category).
    var reportReason: String

    /// Risk tier from ContentSafetyResult, if the item was flagged by the AI pipeline.
    var riskTier: String

    /// True for CSAM or immediate safety threats — skips normal queue and goes directly
    /// to safety staff. Triggers the NCMEC escalation pipeline (human authorization required).
    var escalateImmediately: Bool

    /// Current lifecycle status.
    var status: ModerationItemStatus

    /// UID of the moderator assigned to review this item. nil if unassigned.
    var assignedModerator: String?

    /// Internal note from the assigned moderator (not shown to users).
    var moderatorNote: String?

    /// The action taken, set when status transitions to .reviewed or .resolved.
    var actionTaken: ModerationActionType?

    /// Explanation of the action for the audit log and any user-facing notice.
    var actionNote: String?

    /// When the report was created (server timestamp).
    var createdAt: Date

    /// When the item was resolved. nil until status == .resolved.
    var resolvedAt: Date?

    /// Whether the content author may submit an appeal against this decision.
    /// False for CSAM and immediate safety escalations.
    var isAppealable: Bool
}

// MARK: - AmenModerationAppeal

/// An appeal submitted by a content author against a moderation action.
/// Stored at /moderationAppeals/{id}.
struct AmenModerationAppeal: Codable, Identifiable, Sendable {
    /// Auto-generated Firestore document ID.
    var id: String

    /// The ID of the ModerationQueueItem being appealed.
    var queueItemId: String

    /// UID of the user submitting the appeal.
    var appellantId: String

    /// The author's explanation for why the action should be reversed.
    var reason: String

    /// Current status of the appeal.
    var status: AppealStatus

    /// UID of the moderator or admin who reviewed the appeal. nil until reviewed.
    var reviewedBy: String?

    /// Internal note from the reviewer explaining the appeal decision.
    var reviewNote: String?

    /// When the appeal was submitted.
    var createdAt: Date

    /// When the appeal was reviewed. nil until reviewed.
    var reviewedAt: Date?
}

// MARK: - AppealStatus

/// Lifecycle status of a moderation appeal.
enum AppealStatus: String, Codable, Sendable {
    case pending = "pending"   // Submitted; awaiting review
    case granted = "granted"   // Appeal approved; original action reversed
    case denied  = "denied"    // Appeal denied; original action stands

    /// Human-readable label.
    var displayLabel: String {
        switch self {
        case .pending: return "Under Review"
        case .granted: return "Approved"
        case .denied:  return "Denied"
        }
    }
}

// MARK: - CommunityHealthSignal

/// An aggregated, privacy-preserving health signal for a church, space, or org context.
///
/// PRIVACY: Health signals contain ONLY aggregated counts — no individual user attribution.
///   These are safe to display to community leaders and owners.
///   Individual moderation decisions are never surfaced through this type.
///
/// Stored at /communityHealth/{contextType}/{contextId}/signals/{period}.
struct CommunityHealthSignal: Codable, Sendable {
    /// Context type: "church" | "space" | "org"
    var contextType: String

    /// Firestore ID of the church, space, or org.
    var contextId: String

    /// Measurement period: "7d" | "30d" | "90d"
    var period: String

    /// Total number of content reports received in the period.
    var reportCount: Int

    /// Number of reports resolved (any action taken, including no-action clearing).
    var resolvedCount: Int

    /// Number of appeals that were granted (original action reversed).
    var appealGrantedCount: Int

    /// Average time in hours from report creation to resolution.
    var averageResolutionHours: Double

    /// When this signal was last generated.
    var generatedAt: Date

    // NOTE: Health signals are privacy-preserving.
    // No individual reporter, author, or moderator identifiers are included.
    // Firestore rules: readable by Owner, Pastor, ExecutiveAdmin for the context.

    /// Derived: percentage of reports resolved.
    var resolutionRate: Double {
        guard reportCount > 0 else { return 1.0 }
        return Double(resolvedCount) / Double(reportCount)
    }

    /// Derived: whether the community health looks healthy (heuristic threshold).
    var isHealthy: Bool {
        resolutionRate >= 0.8 && averageResolutionHours <= 48
    }
}
