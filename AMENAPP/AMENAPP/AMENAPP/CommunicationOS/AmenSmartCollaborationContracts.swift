// AmenSmartCollaborationContracts.swift
// AMEN App — Smart Collaboration Layer: Phase 0 Contracts
//
// Single source of truth for all Firestore-persisted smart collaboration types,
// Firestore path helpers, and the pure SmartContextSafety utility.
//
// Non-negotiable design rules enforced here:
//   1. No client-written AI context — all AI fields are server-written, read-only on client.
//   2. Membership verified server-side; no trust in client-supplied IDs.
//   3. No raw message text in analytics or logs.
//   4. Sensitive prayer requests never auto-amplified.
//   5. All AI output labeled with a sourceMessageId citation anchor.
//   6. Every feature behind a remote kill-switch flag (default OFF in RemoteKillSwitch.swift).
//   7. Reuse existing AMEN models — this file adds, never duplicates.
//
// Note on naming:
//   AmenSmartCollabAction  — Firestore-backed counterpart to the UI model AmenThreadAction
//   AmenSmartCollabSummary — Firestore-backed counterpart to the UI model AmenThreadSummary
//   AmenThreadSmartContext — Firestore-backed counterpart to the UI model AmenThreadSmartContextUI
//   GroupDiscussionPulse   — Firestore-backed counterpart to the UI model GroupDiscussionPulseUI

import Foundation
import FirebaseFirestore

// MARK: - AmenSmartThreadType

/// Discriminates which Firestore sub-tree smart context is stored under.
enum AmenSmartThreadType: String, Codable {
    case dm
    case channel
    case discussion
}

// MARK: - AmenThreadSmartContext
// Stored at: conversations/{id}/smartContext/main
//            spaces/{spaceId}/channels/{channelId}/smartContext/main
//
// IMPORTANT: All fields except `id` and `threadId` are written exclusively by
// server-side Cloud Functions using a service account. Client code reads only.

struct AmenThreadSmartContext: Identifiable, Codable {
    /// Document ID — always "main" for the singleton document at this path.
    var id: String
    var threadId: String
    var threadType: AmenSmartThreadType
    /// Service account ID that generated this context. Never a user UID.
    var generatedBy: String
    var generatedAt: Timestamp
    var modelVersion: String
    /// AI-generated summary text. Written server-side only.
    var summaryText: String
    var keyThemes: [String]
    var participantCount: Int
    var messageCount: Int
    /// Citation anchor — the messageId that was the last source for generation.
    var lastSourceMessageId: String
    /// True when new messages have arrived since the last generation pass.
    var isStale: Bool
}

// MARK: - AmenSmartActionType

enum AmenSmartActionType: String, Codable {
    case followUp
    case decision
    case commitment
    case openQuestion
    case reminder
}

// MARK: - AmenSmartActionStatus

enum AmenSmartActionStatus: String, Codable {
    case suggested
    case accepted
    case dismissed
    case completed
}

// MARK: - AmenSmartCollabAction
// Stored at: conversations/{id}/smartActions/{actionId}
//            spaces/{spaceId}/channels/{channelId}/smartActions/{actionId}
//
// Named AmenSmartCollabAction to avoid collision with the UI model AmenThreadAction.
// The UI model lives in AmenThreadAction.swift and is used by ThreadSummaryPanel.

struct AmenSmartCollabAction: Identifiable, Codable {
    var id: String
    var threadId: String
    var actionType: AmenSmartActionType
    /// Always framed as "possible: …" — use SmartContextSafety.labelAsSuggested().
    var suggestedText: String
    /// Never forced — always optional. Do not surface as an assignment in UI.
    var assigneeSuggestion: String?
    /// Always optional. Never treat as a hard deadline.
    var dueDateSuggestion: Timestamp?
    /// Citation anchor — which message triggered this action detection.
    var sourceMessageId: String
    /// Confidence score 0.0–1.0. Values below 0.5 should not be auto-surfaced.
    var confidence: Double
    var status: AmenSmartActionStatus
    /// Service account ID. Never a user UID.
    var generatedBy: String
    var generatedAt: Timestamp
    var modelVersion: String
}

// MARK: - AmenSignalModerationStatus

enum AmenSignalModerationStatus: String, Codable {
    case pending
    case approved
    case rejected
    case escalated
}

// MARK: - AmenThreadPrayerSignal
// Stored at: conversations/{id}/prayerSignals/{signalId}
//            spaces/{spaceId}/channels/{channelId}/prayerSignals/{signalId}
//
// Privacy contract:
//   - requestorId is NEVER exposed in public or group UI.
//   - Raw prayer text is never stored here — only a prayerTheme category string.
//   - Auto-amplification requires explicit opt-in (see SmartContextSafety.requiresExplicitOptIn).

struct AmenThreadPrayerSignal: Identifiable, Codable {
    var id: String
    var threadId: String
    /// Never exposed in public or group-level UI. Server-only read.
    var requestorId: String
    /// Category label only (e.g. "health", "family") — never raw prayer text.
    var prayerTheme: String
    var isAnonymous: Bool
    var sourceMessageId: String
    var moderationStatus: AmenSignalModerationStatus
    /// Service account ID. Never a user UID.
    var generatedBy: String
    var generatedAt: Timestamp
    var modelVersion: String
}

// MARK: - AmenSmartCollabSummary
// Stored at: conversations/{id}/summary/main
//            spaces/{spaceId}/channels/{channelId}/summary/main
//
// Named AmenSmartCollabSummary to avoid collision with the rich UI model AmenThreadSummary
// which lives in AmenThreadSummary.swift and is actively used by ThreadSummaryPanel.

struct AmenSmartCollabSummary: Identifiable, Codable {
    var id: String
    var threadId: String
    /// AI-generated summary. Written server-side only.
    var summaryText: String
    var bulletPoints: [String]
    var messageRangeStart: Timestamp
    var messageRangeEnd: Timestamp
    /// Evidence citations — messageIds used to produce this summary.
    var sourceMessageIds: [String]
    /// Service account ID. Never a user UID.
    var generatedBy: String
    var generatedAt: Timestamp
    var modelVersion: String
    /// True when new messages have arrived since the last summary pass.
    var isStale: Bool
}

// MARK: - AmenSmartPresenceState

/// Approximate presence states — no exact behavioral tracking.
/// States expire after a maximum of 30 minutes (see AmenThreadPresenceSnapshot.expiresAt).
enum AmenSmartPresenceState: String, Codable, CaseIterable {
    case activeNow
    case recentlyActive
    case mayReplyLater
    case focus
    case quiet
}

// MARK: - AmenThreadPresenceSnapshot
// Stored at: conversations/{id}/presence/{userId}
//            spaces/{spaceId}/channels/{channelId}/presence/{userId}
//
// Security rule: self-write only. A user may only write their own document.
// States are approximate — max 30-minute TTL enforced by expiresAt.

struct AmenThreadPresenceSnapshot: Codable {
    var userId: String
    var state: AmenSmartPresenceState
    var updatedAt: Timestamp
    /// Approximate presence expires — Cloud Function or client must stop showing after this.
    /// Maximum duration: 30 minutes from updatedAt.
    var expiresAt: Timestamp
}

// MARK: - AmenPulseUrgency

enum AmenPulseUrgency: String, Codable {
    case normal
    case elevated
    case urgent
}

// MARK: - GroupDiscussionPulse
// Stored at: spaces/{spaceId}/channels/{channelId}/pulse/main
//
// Named GroupDiscussionPulse to match the canonical Firestore shape.
// The lightweight UI coordination model is GroupDiscussionPulseUI in GroupDiscussionPulse.swift.

struct GroupDiscussionPulse: Identifiable, Codable {
    var id: String
    var channelId: String
    var urgency: AmenPulseUrgency
    var activeParticipantCount: Int
    /// Topic momentum 0.0–1.0. Server-computed.
    var topicMomentum: Double
    /// nil unless strong evidence exists. Never inferred or assumed.
    var isAligned: Bool?
    /// Evidence citations for any alignment assessment.
    var alignmentEvidenceMessageIds: [String]
    /// Service account ID. Never a user UID.
    var generatedBy: String
    var generatedAt: Timestamp
    var modelVersion: String
    /// True when new messages have arrived since the last pulse pass.
    var isStale: Bool
}

// MARK: - AmenSmartCollaborationPaths
// Single source of truth for Firestore path strings.
// Mirrored in functions/src/smartCollaboration/contracts.ts (SmartPaths).

struct AmenSmartCollaborationPaths {
    private init() {}  // Namespace only — all members are static.

    // MARK: DM thread sub-collections

    static func dmSmartContext(conversationId: String) -> String {
        "conversations/\(conversationId)/smartContext/main"
    }

    static func dmSmartActions(conversationId: String) -> String {
        "conversations/\(conversationId)/smartActions"
    }

    static func dmPrayerSignals(conversationId: String) -> String {
        "conversations/\(conversationId)/prayerSignals"
    }

    static func dmSummary(conversationId: String) -> String {
        "conversations/\(conversationId)/summary/main"
    }

    static func dmPresence(conversationId: String, userId: String) -> String {
        "conversations/\(conversationId)/presence/\(userId)"
    }

    // MARK: Channel sub-collections

    static func channelSmartContext(spaceId: String, channelId: String) -> String {
        "spaces/\(spaceId)/channels/\(channelId)/smartContext/main"
    }

    static func channelSmartActions(spaceId: String, channelId: String) -> String {
        "spaces/\(spaceId)/channels/\(channelId)/smartActions"
    }

    static func channelPrayerSignals(spaceId: String, channelId: String) -> String {
        "spaces/\(spaceId)/channels/\(channelId)/prayerSignals"
    }

    static func channelSummary(spaceId: String, channelId: String) -> String {
        "spaces/\(spaceId)/channels/\(channelId)/summary/main"
    }

    static func channelPresence(spaceId: String, channelId: String, userId: String) -> String {
        "spaces/\(spaceId)/channels/\(channelId)/presence/\(userId)"
    }

    static func channelPulse(spaceId: String, channelId: String) -> String {
        "spaces/\(spaceId)/channels/\(channelId)/pulse/main"
    }
}

// MARK: - AmenSmartSignalCategory

/// Categories that drive safety routing and opt-in requirements.
enum AmenSmartSignalCategory {
    case summary
    case action
    case prayerSignal
    case pulse
    case smartReply
    case catchUp
}

// MARK: - SmartContextSafety
// Pure helper — no Firebase imports, no side effects, no stored state.
// Mirrors functions/src/smartCollaboration/safety.ts

enum SmartContextSafety {

    // MARK: - Sanitize for Analytics

    /// Returns a flat [String: Any] with all body-text-like keys stripped.
    /// Only scalar analytics-safe types (String IDs, counts, booleans, enum rawValues)
    /// survive — no message body, no summary text, no suggested text.
    static func sanitizeForAnalytics<T: Encodable>(_ value: T) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(value),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        // Keys whose values may contain free-form text — always strip.
        let sensitiveKeyPrefixes = ["summaryText", "suggestedText", "bulletPoints",
                                    "keyThemes", "prayerTheme", "body", "text",
                                    "description", "content", "draft"]
        return raw.filter { entry in
            let lower = entry.key.lowercased()
            return !sensitiveKeyPrefixes.contains { lower.hasPrefix($0.lowercased()) }
        }.mapValues { value -> Any in
            // Allow only analytics-safe primitive types.
            switch value {
            case is String, is Int, is Double, is Bool, is NSNumber: return value
            default: return "[redacted]"
            }
        }
    }

    // MARK: - AI Output Labeling

    /// Frames AI-suggested text with "possible: …" prefix so users always know it is a suggestion.
    static func labelAsSuggested(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return "possible: \(trimmed)"
    }

    /// Frames AI output with a source citation so the origin message is always traceable.
    static func labelWithSource(_ text: String, messageId: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return "\(trimmed) [source: \(messageId)]"
    }

    // MARK: - Opt-In Gate

    /// Returns true for categories that must NEVER be auto-amplified or persisted
    /// without an explicit user opt-in action. Callers must check this before
    /// displaying, persisting, or broadcasting any signal in these categories.
    static func requiresExplicitOptIn(_ category: AmenSmartSignalCategory) -> Bool {
        switch category {
        case .prayerSignal:
            // Prayer signals contain sensitive personal information and must
            // never be auto-amplified, pushed, or shown to non-requestors
            // without an explicit opt-in from the requestor.
            return true
        case .summary, .action, .pulse, .smartReply, .catchUp:
            return false
        }
    }
}
