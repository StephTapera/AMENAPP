// contracts/volunteer.ts
// AMEN — Smart Volunteer Board · Wave 0 · TypeScript source of truth.
// FROZEN: 2026-06-19. Swift side (VolunteerContracts.swift) mirrors this field-for-field.
// Any change requires a contract-change note + re-freeze before parallel work resumes.
//
// SCOPE (Wave 0): a single dated event only. NO recurrence/RRULE, NO swaps, NO check-in,
// NO no-show tracking, NO .ics export, NO SMS. Those are explicitly deferred (see spec §DEFERRED).
//
// SAFETY / INTEGRITY INVARIANTS (server-enforced in-function; client re-asserts):
//   • I1 No overfill — a role never exceeds countNeeded; signUpForSlot is transactional.
//   • I2 Derived board — VolunteerBoard is COMPUTED from Assignments; `filled` is never a stored counter.
//   • I3 Blackout respected — a blacked-out volunteer cannot sign up for that date.
//   • I4 Notes gated — LeaderPrivateNote is leader-only and every read is access-logged.

// ════════════════════════════════════════════════════════════════════
// §1 — ServiceEvent  (single dated event; no recurrence in Wave 0)
// ════════════════════════════════════════════════════════════════════

/** A single dated service/event volunteers staff. No RRULE — Wave 0 is single-event only. */
export interface ServiceEvent {
  id: string;
  title: string;
  startUTC: string;   // ISO8601 instant (UTC). Display localizes via `timezone`.
  timezone: string;   // IANA tz id, e.g. "America/New_York" — display-only in Wave 0.
  location: string;
}

// ════════════════════════════════════════════════════════════════════
// §2 — StaffingNeed  (a role to fill for one event)
// ════════════════════════════════════════════════════════════════════

/** Leader-declared lifecycle of a role. Capacity (filled/needed) is always DERIVED, never this. */
export type StaffingNeedStatus = "open" | "full" | "needsBackup" | "closed";

/** How many of `role` an event needs. `countNeeded` is the hard cap enforced by I1. */
export interface StaffingNeed {
  eventId: string;
  role: string;
  countNeeded: number;
  status: StaffingNeedStatus;
}

// ════════════════════════════════════════════════════════════════════
// §3 — Assignment  (one volunteer ↔ one role on one event)
// ════════════════════════════════════════════════════════════════════

/** Lifecycle of a single volunteer's commitment to a role. `signedUp`/`confirmed` count toward filled. */
export type AssignmentStatus = "signedUp" | "confirmed" | "declined" | "waitlisted";

/** A volunteer's slot on a role. `id` is the document id (needed by leaderApprove). */
export interface Assignment {
  id: string;
  eventId: string;
  role: string;
  volunteerId: string;
  status: AssignmentStatus;
}

// ════════════════════════════════════════════════════════════════════
// §4 — VolunteerBoard  (DERIVED read model — never a mutable counter; I2)
// ════════════════════════════════════════════════════════════════════

/** Per-role rollup status surfaced on the board. Derived from capacity + leader intent. */
export type BoardRoleStatus = "open" | "full" | "needsBackup" | "closed";

/** Computed per-role rollup. `filled` is COUNTED from Assignments at read time, never stored. */
export interface VolunteerBoardRole {
  role: string;
  filled: number;   // count of active (signedUp|confirmed) assignments — derived
  needed: number;   // mirrors StaffingNeed.countNeeded
  status: BoardRoleStatus;
}

/** The whole board for one event: a derived projection over StaffingNeeds + Assignments. */
export interface VolunteerBoard {
  eventId: string;
  roles: VolunteerBoardRole[];
}

// ════════════════════════════════════════════════════════════════════
// §5 — BlackoutDate  (volunteer unavailable on a date; simple list in V0)
// ════════════════════════════════════════════════════════════════════

/** A date a volunteer is unavailable. Wave 0 is a flat list — no recurrence/expansion (I3). */
export interface BlackoutDate {
  volunteerId: string;
  date: string;   // "YYYY-MM-DD" (event-local calendar date)
}

// ════════════════════════════════════════════════════════════════════
// §6 — LeaderPrivateNote  (leader-only; access-logged on every read; I4)
// ════════════════════════════════════════════════════════════════════

/** A private leader note about a volunteer. NEVER public. Every read is access-logged (I4). */
export interface LeaderPrivateNote {
  volunteerId: string;
  note: string;
  leaderOnly: true;   // invariant marker — always true; reads require leader role + audit log.
}

// ════════════════════════════════════════════════════════════════════
// Request/response envelopes for the Wave 0 callables.
// ════════════════════════════════════════════════════════════════════

export interface AssembleVolunteerBoardRequest {
  eventId: string;
}

export interface SignUpForSlotRequest {
  eventId: string;
  role: string;
  volunteerId: string;
}

/** Discriminated outcome of a transactional slot-fill (mirrors evaluateSignup). */
export type SignUpDecision =
  | "fill"             // a slot was open → assignment created as signedUp
  | "waitlist"         // role already full → assignment created as waitlisted
  | "reject_blackout"  // volunteer is blacked out on this date → no write (I3)
  | "reject_duplicate";// volunteer already actively assigned → no double-count

export interface SignUpForSlotResult {
  decision: SignUpDecision;
  assignmentId: string | null;   // null when rejected
  resultingStatus: AssignmentStatus | null;
}

export interface LeaderApproveRequest {
  assignmentId: string;
}

export interface GetLeaderPrivateNoteRequest {
  eventId: string;
  volunteerId: string;
}

// ── Lifecycle envelopes (event/need/blackout creation + discovery) ──

export interface CreateServiceEventRequest {
  title: string;
  startUTC: string;
  timezone: string;
  location: string;
}

export interface AddStaffingNeedRequest {
  eventId: string;
  role: string;
  countNeeded: number;
}

/** A ServiceEvent paired with whether the caller leads it. */
export interface VolunteerEventRef {
  event: ServiceEvent;
  isLeader: boolean;
}

export interface GetServiceEventResult {
  event: ServiceEvent;
  isLeader: boolean;
}

export interface ListVolunteerEventsResult {
  events: VolunteerEventRef[];
}

export interface BlackoutRequest {
  date: string; // "YYYY-MM-DD"
}
