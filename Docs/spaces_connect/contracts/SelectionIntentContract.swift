// SelectionIntentContract.swift
// AMEN — SPACES_CONNECT_V1 / Phase −1 Contracts
//
// FROZEN 2026-05-31. Do not edit without SpacesConnect-Phase0 authorization.
//
// THE CORE CONTRACT — the highlight→Ask payload.
//
// ─── What SelectionIntent models ─────────────────────────────────────────────
//
//  Every text selection anywhere in AMEN produces a SelectionIntent value.
//  The SelectionIntentMenu reads (intent + orgType + userRole) to resolve
//  which actions to show and in what order.
//
//  ┌──────────────────────────────────────────────────────────────────────┐
//  │  ALWAYS-PRESENT actions (shown regardless of context):              │
//  │    .askBerean   — route to Berean AI with selectedText as query     │
//  │    .copy        — copy text to clipboard                            │
//  │    .saveToNotes — save to the user's Church Notes / Selah journal   │
//  │    .shareToSpace — share selection into a Space thread              │
//  └──────────────────────────────────────────────────────────────────────┘
//
//  ┌──────────────────────────────────────────────────────────────────────┐
//  │  CONTEXT-RESOLVED human route (one per orgType):                    │
//  │    church           → .askChurch     "Ask a Pastor / Leader"        │
//  │    business         → .askTeam       "Find an Expert"               │
//  │    school           → .askTeacher    "Ask a Teacher"                │
//  │    family           → .askFamily     "Ask Your Family"              │
//  │    ministry/nonprofit → .askLeader   "Ask a Leader"                 │
//  │    sports           → .askCoach      "Ask a Coach"                  │
//  │    network/nil      → nil (no human route shown)                    │
//  └──────────────────────────────────────────────────────────────────────┘
//
//  ┌──────────────────────────────────────────────────────────────────────┐
//  │  Berean 2I routing — auto-pick mode from selectedText signal:       │
//  │    .ask      — factual / lookup query                               │
//  │    .discern  — ethical / spiritual discernment                      │
//  │    .build    — action plan / project / creation                     │
//  │    .guard    — safety / crisis / content moderation flag            │
//  │    .reflect  — personal reflection / journal prompt                 │
//  └──────────────────────────────────────────────────────────────────────┘
//
// ─── Firestore / Storage note ────────────────────────────────────────────────
//
//  SelectionIntent is a SHORT-LIVED in-memory value.
//  It is NOT persisted to Firestore by default.
//  If `resolvedBereanMode` is set, the AI proxy callable receives the full
//  intent as a payload parameter so the server can log it in:
//    /users/{uid}/selectionIntentLog/{logId}
//      selectedText, sourceContext, spaceID, orgType, userRole,
//      resolvedBereanMode, confidenceScore, humanRouteAction, timestamp
//  Logging is opt-in per user (privacy setting: analyticsConsent).
//
// ─── Naming Conflicts ────────────────────────────────────────────────────────
//
//  CONFLICT: `BereanPersonalityMode` already exists in
//    AMENAPP/BereanAIAssistantView.swift
//    Cases: shepherd, scholar, coach, builder, strategist, creator, debater,
//           askBerean, scriptureStudy, prayerCompanion, deepStudy, discernment,
//           mediaInsight, workLifeWisdom, safetyReview
//    `BereanMode` (this contract) is DISTINCT — it is the 2I routing mode,
//    not the personality persona. BereanMode drives the server-side inference
//    intent category; BereanPersonalityMode drives the conversational style.
//    Agents must never conflate the two.
//
//  CONFLICT: `OrgType` defined in OrgSpaceHierarchyContract.swift.
//    SelectionIntentContract imports OrgType by reference — do NOT redeclare it.
//    (In the compiled Xcode target both files will be in the same module.)
//
//  CONFLICT: `SpaceRole` defined in OrgSpaceHierarchyContract.swift.
//    Same as above — import by reference, do not redeclare.
//
// ─────────────────────────────────────────────────────────────────────────────

import Foundation

// MARK: - SelectionSource

/// Where in the app the text selection occurred.
/// Drives default Berean mode and note-save destination.
enum SelectionSource: String, Codable, CaseIterable, Hashable {
    /// A Church Note or sermon note block.
    case sermonNote      = "sermon_note"
    /// A direct message or Space thread message.
    case message
    /// A Standard Operating Procedure doc in an org Space.
    case sop
    /// A Testimony post or testimony record.
    case testimony
    /// A study lesson block in a bibleStudy Space.
    case lesson
    /// Any other surface (feed post, profile bio, etc.).
    case general
}

// MARK: - BereanMode

/// 2I inference routing mode for Berean AI.
///
/// Named `BereanMode` (NOT `BereanPersonalityMode`) — these are distinct types.
/// BereanMode = server-side intent category for the AI request.
/// BereanPersonalityMode = conversational persona style (defined elsewhere).
///
/// The 2I router auto-picks the mode from the selected text signal and
/// writes the result into `SelectionIntent.resolvedBereanMode`.
enum BereanMode: String, Codable, CaseIterable, Hashable {
    /// Factual lookup, definition, or informational query.
    case ask
    /// Ethical or spiritual discernment question.
    case discern
    /// Action plan, project scaffolding, or creative build request.
    case build
    /// Safety, crisis, or content moderation flag.
    case `guard`
    /// Personal reflection, journaling, or contemplation prompt.
    case reflect
}

// MARK: - HumanRouteAction

/// The human-expert routing action surfaced by SelectionIntentMenu.
/// Resolved from `OrgType` via `orgActionMap` at menu render time.
///
/// One of these (or nil) is shown as the context-sensitive CTA below the
/// four always-present actions.
enum HumanRouteAction: String, Codable, CaseIterable, Hashable {
    /// Church orgs: route to a pastor or lay leader.
    case askChurch     = "ask_church"
    /// Business orgs: route to an internal subject-matter expert.
    case askTeam       = "ask_team"
    /// School orgs: route to a teacher or professor.
    case askTeacher    = "ask_teacher"
    /// Family orgs: route to a family group thread.
    case askFamily     = "ask_family"
    /// Ministry / nonprofit orgs: route to a leader or director.
    case askLeader     = "ask_leader"
    /// Sports orgs: route to a coach or trainer.
    case askCoach      = "ask_coach"
}

// MARK: - AlwaysPresentAction

/// The four actions always shown in every SelectionIntentMenu.
enum AlwaysPresentAction: String, CaseIterable, Hashable {
    case askBerean
    case copy
    case saveToNotes
    case shareToSpace
}

// MARK: - orgActionMap

/// Pure-function mapping from OrgType to the appropriate HumanRouteAction.
/// Returns nil if no human route is appropriate for the org type.
///
/// Usage in menu resolution:
///   let humanRoute = orgActionMap(orgType: intent.orgType)
func orgActionMap(orgType: OrgType?) -> HumanRouteAction? {
    guard let orgType else { return nil }
    switch orgType {
    case .church:              return .askChurch
    case .business:            return .askTeam
    case .school:              return .askTeacher
    case .family:              return .askFamily
    case .ministry, .nonprofit: return .askLeader
    case .sports:              return .askCoach
    case .network:             return nil
    }
}

// MARK: - SelectionIntent

/// The canonical highlight→Ask payload. Created on every text selection event
/// that the user elevates to an action (long-press → menu appears).
///
/// Short-lived: lives in memory from tap to resolution. Optionally logged to
/// Firestore at /users/{uid}/selectionIntentLog/{logId} if analyticsConsent is on.
///
/// Fields filled at creation time: selectedText, sourceContext, spaceID, orgType,
///   userRole, surroundingContext, timestamp.
/// Fields filled after 2I routing: resolvedBereanMode, confidenceScore.
/// Fields filled at menu render: humanRouteAction (via orgActionMap).
struct SelectionIntent: Codable, Hashable {

    // ── Filled at selection time ──────────────────────────────────────────

    /// The exact string the user highlighted. Non-empty.
    var selectedText: String

    /// Surface context where the selection occurred.
    var sourceContext: SelectionSource

    /// The Space (spaceId) in which the selection occurred, if applicable.
    var spaceID: String?

    /// The org type of the org containing the Space, if applicable.
    /// Used by the menu to resolve `humanRouteAction`.
    var orgType: OrgType?

    /// The current user's role in the Space, if applicable.
    /// Used by menu to gate leader-only actions.
    var userRole: SpaceRole?

    /// A window of surrounding text (max 500 chars) provided to the AI for context.
    /// Typically ±2 sentences around the selection.
    var surroundingContext: String?

    /// Client-side UTC timestamp of when the selection was made.
    var timestamp: Date

    // ── Filled after 2I routing ───────────────────────────────────────────

    /// The Berean inference mode chosen by the 2I router.
    /// `nil` until the router resolves it (async, may be < 200 ms).
    var resolvedBereanMode: BereanMode?

    /// Confidence score from the 2I router (0.0–1.0).
    /// `nil` until resolved. Values < 0.5 fall back to `.ask`.
    var confidenceScore: Double?

    // ── Filled at menu render time ────────────────────────────────────────

    /// Human expert route resolved from `orgType` via `orgActionMap`.
    /// `nil` if no org context or org type maps to nil route.
    var humanRouteAction: HumanRouteAction?
}

// MARK: - SelectionIntentMenuActions

/// The ordered action list rendered by SelectionIntentMenu.
/// Always-present actions come first, human route (if any) appended.
struct SelectionIntentMenuActions {
    let alwaysPresent: [AlwaysPresentAction]
    let humanRoute: HumanRouteAction?

    /// Build the standard action list from a resolved intent.
    static func from(intent: SelectionIntent) -> SelectionIntentMenuActions {
        SelectionIntentMenuActions(
            alwaysPresent: AlwaysPresentAction.allCases,
            humanRoute: intent.humanRouteAction
        )
    }
}

// MARK: - SelectionIntentServiceProtocol

/// Contract for the 2I routing service that resolves BereanMode from a raw SelectionIntent.
/// Implementation is server-side; this protocol defines the callable proxy seam.
protocol SelectionIntentServiceProtocol {
    /// Route a selection intent through the 2I classifier.
    /// Fills `resolvedBereanMode` and `confidenceScore` on return.
    func resolveMode(for intent: SelectionIntent) async throws -> SelectionIntent

    /// Log a completed intent to Firestore (only if analyticsConsent is true).
    func logIntent(_ intent: SelectionIntent, uid: String) async throws
}
