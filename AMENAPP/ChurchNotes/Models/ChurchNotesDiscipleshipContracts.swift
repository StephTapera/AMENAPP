
//  ChurchNotesDiscipleshipContracts.swift
//  AMENAPP
//
//  W0 — FROZEN contracts for Church Notes Spiritual Action & Accountability System.
//  DO NOT MODIFY after W0 lands without explicit human approval of a contract change.
//  Later waves (W1–W6) consume these types; they must not edit this file.
//
//  Architectural invariant: classify-then-constrain, not detect-then-protect.
//  A note's sensitivity is the FIRST thing this system knows. That class governs
//  (a) where compute runs, (b) what can be generated, (c) what can ever be shared.
//

import Foundation

// MARK: - Feature Flags (all OFF — churchNotes.* namespace)

/// Gate every W1+ surface behind the relevant flag before enabling.
/// Flags are checked at the call site; a false flag means the feature is a no-op.
enum ChurchNotesDiscipleshipFlags {
    /// Master switch. All sub-flags require this to be true AND their own flag.
    static let masterEnabled: Bool = false
    /// W1 — Sensitivity classifier runs on note save.
    static let classificationEnabled: Bool = false
    /// W2 — Action extractor and "Create Spiritual Reminder?" affordance.
    static let extractionEnabled: Bool = false
    /// W3 — Template-based follow-up notifications delivered via NotificationGovernor.
    static let notificationsEnabled: Bool = false
    /// W4 — Per-item sharing with name-aware friction and guardian routing.
    static let sharingEnabled: Bool = false
    /// W5 — Lock-screen widget and Berean Island glanceable card.
    static let surfacesEnabled: Bool = false
    /// W6 — E2EE at rest for confidential notes; no-train server proxy headers.
    static let encryptionEnabled: Bool = false
}

// MARK: - Note Content Bridge (§ bridge)

/// Lightweight, immutable snapshot of note content passed to classifiers and extractors.
/// Contains no user identity. Created from ChurchNote after the note is persisted.
struct NoteContent {
    /// Session-scoped identifier for this snapshot. Links SpiritualAction back to this note.
    let noteID: UUID
    /// Original Firestore DocumentID. Use this for all durable cross-references.
    let firestoreID: String
    let plainText: String
    let tags: [String]
    let blocks: [ChurchNoteBlock]
}

extension NoteContent {
    /// Bridge from existing ChurchNote. Call only after the note is saved (id is non-nil).
    init(note: ChurchNote) {
        self.firestoreID = note.id ?? ""
        // noteID is a session identifier for action-extraction linkage within a single
        // classification round. Extractors must store firestoreID for durable Firestore refs.
        self.noteID = UUID()
        self.plainText = note.content
        self.tags = note.tags
        self.blocks = note.blocks
    }
}

// MARK: - §2.1 Sensitivity Classification

/// Three-level sensitivity class. Governs compute locus, surfacing rights, and sharing friction.
/// A note with no assigned class is treated as .confidential (fail-closed).
enum NoteSensitivity: String, Codable {
    case general        // reflection, sermon notes, general study
    case sensitive      // named people, prayer requests, health mentions
    case confidential   // confession, counseling, recovery, marriage conflict
}

protocol ChurchNotesSensitivityClassifier {
    /// Runs ON-DEVICE ONLY. No network call. Must return before any extraction begins.
    func classify(_ note: NoteContent) -> NoteSensitivity
}

// MARK: - §2.2 Compute Locus

/// Governs where computation may run based on sensitivity class.
enum ComputeLocus {
    case onDeviceOnly
    case serverProxyAllowed
}

/// Returns the allowed compute locus for a given sensitivity class.
/// Callers must check this before invoking any extractor or composer.
func locus(for sensitivity: NoteSensitivity) -> ComputeLocus {
    switch sensitivity {
    case .general:                   return .serverProxyAllowed
    case .sensitive, .confidential:  return .onDeviceOnly
    }
}

// MARK: - §2.3 Action Extraction

/// An immutable spiritual action item detected in a note.
/// `namedPeople` is non-empty when the action references third parties —
/// this triggers name-aware confirmation friction before any sharing (S5).
struct SpiritualAction: Codable, Identifiable {
    let id: UUID
    let kind: ActionKind
    let summary: String           // user-facing copy derived from note text
    let namedPeople: [String]     // third parties referenced; drives W4 sharing friction
    let sourceNoteID: UUID        // matches NoteContent.noteID from the extraction call
    let sensitivity: NoteSensitivity

    /// S5: true when confirmation friction is required before scope > .onlyMe.
    var requiresNameAwareConfirmation: Bool { !namedPeople.isEmpty }
}

enum ActionKind: String, Codable {
    case pray, read, reachOut, fast, memorize, apply, attend
}

protocol ActionExtractor {
    /// Locus is enforced by the caller via `locus(for:)` before this is called.
    /// sensitive / confidential notes MUST NOT call this with .serverProxyAllowed.
    func extract(from note: NoteContent, locus: ComputeLocus) async -> [SpiritualAction]
}

// MARK: - §2.4 Notifications — template + constrained slots

/// Fixed vocabulary of follow-up notification templates.
/// Add templates ONLY via human review. No template may express contingency,
/// shame, streak count, or a correlation between user behavior and standing with God.
enum NotificationTemplate: String, Codable, CaseIterable {
    case continueReadingPlan  // "Would you like to continue your reading plan?"
    case verseReview          // "Would you like to review {verseRef} today?"
    case prayerInvite         // "Take a few minutes to pray for {topic}."
    case eventUpcoming        // "{eventTitle} is coming up."
}

/// Approved slot values an LLM may fill. The LLM CANNOT author free text.
/// Any slot not present in NotificationTemplate is structurally unreachable.
struct NotificationSlots: Codable {
    var verseRef: String?
    var topic: String?
    var eventTitle: String?
}

protocol NotificationComposer {
    /// LLM (if used) may ONLY fill slots defined in NotificationSlots.
    /// It must not produce free text outside those slots. (S8)
    func compose(_ template: NotificationTemplate, slots: NotificationSlots) -> String
}

// MARK: - §2.5 Sharing — per-item, non-sticky, revocable-with-deletion

/// Per-item sharing scope. The DEFAULT is always .onlyMe.
/// No global or relationship-level sharing exists anywhere in this system.
enum ShareScope: String, Codable {
    case onlyMe          // DEFAULT — always the initial value
    case trustedFriend
    case smallGroup
    case churchLeader    // power-asymmetry scope: extra friction + mandatory non-nil expiry (S6)
}

/// A single sharing grant for a single action item.
/// Revocation DELETES from recipient view — it does not flag or soft-delete. (S4)
struct ShareGrant: Codable, Identifiable {
    let id: UUID
    let actionID: UUID           // sharing is always per-ITEM, never per-relationship
    let scope: ShareScope
    let expiresAt: Date?         // non-nil required for .churchLeader (S6)
    let recipientIDs: [String]

    /// S6 guard. Call before persisting any grant.
    func validateChurchLeaderExpiry() throws {
        guard scope == .churchLeader else { return }
        if expiresAt == nil {
            throw ChurchNotesDiscipleshipError.churchLeaderGrantRequiresExpiry
        }
    }
}

protocol SharingService {
    /// Requires an explicit confirmation screen before calling.
    /// Recipients see ONLY the shared action — never the full note or derived insight.
    func grant(_ grant: ShareGrant) async throws

    /// MUST delete from the recipient's view. Soft-delete is not compliant. (S4)
    func revoke(_ grantID: UUID) async throws
}

// MARK: - §2.6 Guardian Routing

protocol GuardianGate {
    /// For minor accounts: any scope beyond .onlyMe is silently rewritten to the guardian path.
    /// Peer and leader sharing without guardian visibility is structurally disallowed. (S7)
    func resolveSharing(for actionID: UUID, requested: ShareScope, isMinor: Bool) -> ShareScope
}

// MARK: - §2.7 Frequency Governor

/// A single delivery event in the notification history.
struct DeliveryRecord: Codable {
    let template: NotificationTemplate
    let deliveredAt: Date
    /// True when the user did not interact within the observation window after delivery.
    let wasIgnored: Bool
}

struct DeliveryHistory: Codable {
    let records: [DeliveryRecord]
}

protocol NotificationGovernor {
    /// Returns false when:
    ///   - Per-day cap is reached, OR
    ///   - 3 or more consecutive deliveries were ignored (ignore-decay back-off).
    /// This system NEVER escalates after ignores. No notification implies urgency
    /// or ties any behavior to the user's standing with God. (S9 adjacent)
    func shouldDeliver(_ candidate: NotificationTemplate, history: DeliveryHistory) -> Bool
}

// MARK: - Typed Error Domain

enum ChurchNotesDiscipleshipError: Error, LocalizedError {
    case churchLeaderGrantRequiresExpiry
    case minorCannotShareWithoutGuardianRouting
    case sensitiveNoteCannotUseServerProxy
    case confidentialNoteCannotProactivelySurface
    case freeTextNotificationForbidden

    var errorDescription: String? {
        switch self {
        case .churchLeaderGrantRequiresExpiry:
            return "Church leader sharing requires an expiry date."
        case .minorCannotShareWithoutGuardianRouting:
            return "Minor accounts must route all sharing through a guardian."
        case .sensitiveNoteCannotUseServerProxy:
            return "Sensitive and confidential notes cannot use the server proxy."
        case .confidentialNoteCannotProactivelySurface:
            return "Confidential notes cannot appear in proactive surfaces."
        case .freeTextNotificationForbidden:
            return "Notifications must use approved templates only."
        }
    }
}
