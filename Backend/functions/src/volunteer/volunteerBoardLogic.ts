// volunteer/volunteerBoardLogic.ts
// AMEN — Smart Volunteer Board · Wave 0 · pure decision logic (no Firestore, no I/O).
// These functions are the load-bearing cores for invariants I1 (no overfill), I2 (derived
// board) and I3 (blackout respected). They are pure so they can be unit-tested directly and
// reused verbatim inside the transactional callable (volunteerCallables.ts).
//
// Source of truth for the shapes: contracts/volunteer.ts.

import {
  Assignment,
  AssignmentStatus,
  BoardRoleStatus,
  SignUpDecision,
  StaffingNeed,
  VolunteerBoard,
  VolunteerBoardRole,
} from "../contracts/volunteer";

/** An assignment counts toward a role's `filled` only while it is signedUp or confirmed. */
export function isActiveAssignment(status: AssignmentStatus): boolean {
  return status === "signedUp" || status === "confirmed";
}

/**
 * I2 — Derive a single role's rollup from the live assignment list. `filled` is COUNTED here,
 * never read from a stored counter, so the board can never drift from the assignments.
 *
 * Status precedence (capacity is derived; leader intent only refines a full/closed role):
 *   closed              → need.status === "closed"
 *   needsBackup         → capacity met AND leader flagged the role needsBackup
 *   full                → capacity met (filled >= countNeeded)
 *   open                → capacity not yet met
 */
export function deriveRoleStatus(need: StaffingNeed, filled: number): BoardRoleStatus {
  if (need.status === "closed") return "closed";
  if (filled >= need.countNeeded) {
    return need.status === "needsBackup" ? "needsBackup" : "full";
  }
  return "open";
}

/**
 * I2 — Compute the whole board as a pure projection over StaffingNeeds + Assignments.
 * The board is a derived read model; nothing here mutates or stores a counter.
 */
export function computeBoard(
  eventId: string,
  needs: StaffingNeed[],
  assignments: Assignment[],
): VolunteerBoard {
  const roles: VolunteerBoardRole[] = needs
    .filter((need) => need.eventId === eventId)
    .map((need) => {
      const filled = assignments.filter(
        (a) =>
          a.eventId === eventId &&
          a.role === need.role &&
          isActiveAssignment(a.status),
      ).length;
      return {
        role: need.role,
        filled,
        needed: need.countNeeded,
        status: deriveRoleStatus(need, filled),
      };
    });
  return { eventId, roles };
}

/** Inputs the slot-fill decision needs — all read INSIDE the transaction at commit-snapshot time. */
export interface SignUpState {
  countNeeded: number;
  activeFilled: number;          // active (signedUp|confirmed) assignments for this role, right now
  isBlackedOut: boolean;         // volunteer has a BlackoutDate on this event's date (I3)
  volunteerAlreadyActive: boolean; // volunteer already holds an active slot on this role
}

export interface SignUpOutcome {
  decision: SignUpDecision;
  resultingStatus: AssignmentStatus | null;
}

/**
 * I1 + I3 — The single decision the slot-fill transaction commits. Pure and total.
 *
 * Order matters:
 *   1. blackout      → reject (I3), no write.
 *   2. duplicate     → reject, so a volunteer can never inflate `filled` past their one slot.
 *   3. capacity met  → waitlist (never overfill — I1).
 *   4. otherwise     → fill as signedUp.
 *
 * Because the caller reads `activeFilled` INSIDE a Firestore transaction, two concurrent
 * last-slot signups serialize: the second re-reads activeFilled === countNeeded and waitlists.
 */
export function evaluateSignup(state: SignUpState): SignUpOutcome {
  if (state.isBlackedOut) {
    return { decision: "reject_blackout", resultingStatus: null };
  }
  if (state.volunteerAlreadyActive) {
    return { decision: "reject_duplicate", resultingStatus: null };
  }
  if (state.activeFilled >= state.countNeeded) {
    return { decision: "waitlist", resultingStatus: "waitlisted" };
  }
  return { decision: "fill", resultingStatus: "signedUp" };
}
