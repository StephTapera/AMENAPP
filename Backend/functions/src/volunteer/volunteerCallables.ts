// volunteer/volunteerCallables.ts
// AMEN — Smart Volunteer Board · Wave 0 · Cloud Functions (us-east1).
// Source of truth for shapes: contracts/volunteer.ts. Pure logic: volunteerBoardLogic.ts.
//
// Callables:
//   assembleVolunteerBoard(eventId)            → derived board rollup (I2)
//   signUpForSlot(eventId, role, volunteerId)  → transactional atomic fill (I1) + blackout (I3) + waitlist
//   leaderApprove(assignmentId)                → status transition (leader-only)
//   getLeaderPrivateNote / setLeaderPrivateNote → leader-only + access-logged (I4)
//   scheduleVolunteerReminders(eventId)        → enqueue push + email reminders (NO SMS)
//
// Firestore model (Wave 0, single-event):
//   volunteerEvents/{eventId}            ServiceEvent + leaderIds: string[]
//   volunteerEvents/{eventId}/needs/{role}   StaffingNeed (doc id = role)
//   volunteerAssignments/{assignmentId}  Assignment (top-level so leaderApprove(id) is addressable)
//   volunteerBlackouts/{volunteerId}_{YYYY-MM-DD}   BlackoutDate (single-doc lookup)
//   volunteerLeaderNotes/{eventId}_{volunteerId}    LeaderPrivateNote
//   volunteerNoteAccessLogs/{auto}       access-log entries (I4)
//   scheduledNotifications/{auto}        reminder queue (existing infra; push+email channels)
//
// NOTE: timezone-aware blackout expansion is Wave 1. Wave 0 derives the event calendar date
// from the UTC date of startUTC (no hand-rolled tz math — see spec §DEFERRED).

import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import {
  Assignment,
  SignUpForSlotResult,
  StaffingNeed,
} from "../contracts/volunteer";
import { computeBoard, evaluateSignup, isActiveAssignment } from "./volunteerBoardLogic";

// us-central1 quota exhausted — new functions deploy to us-east1 (CLAUDE.md / FUNCTION_INVENTORY).
const REGION = "us-east1";
const callableOpts = { region: REGION, enforceAppCheck: true, timeoutSeconds: 20 } as const;

// A minimal structural type so the transactional core can run against the live Admin SDK
// in production AND an in-memory OCC simulator in the concurrency test, with no `any`.
type Db = FirebaseFirestore.Firestore;

function requireAuth(request: { auth?: { uid: string } | null }): string {
  if (!request.auth) throw new HttpsError("unauthenticated", "Auth required");
  return request.auth.uid;
}

function readString(value: unknown, field: string): string {
  if (typeof value !== "string" || !value.trim()) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return value.trim();
}

/** Event calendar date (UTC) used for blackout matching. Wave 0: UTC date of startUTC. */
export function eventCalendarDate(startUTC: string): string {
  // "2026-06-21T18:00:00Z" → "2026-06-21". No tz expansion in Wave 0.
  return startUTC.slice(0, 10);
}

function blackoutDocId(volunteerId: string, date: string): string {
  return `${volunteerId}_${date}`;
}

// ════════════════════════════════════════════════════════════════════
// Transactional slot-fill core — exported & db-injected so it is testable
// against an OCC simulator (see __tests__/volunteer.concurrency.test.ts).
// ════════════════════════════════════════════════════════════════════

export async function runSignUpTransaction(
  db: Db,
  params: { eventId: string; role: string; volunteerId: string; eventDate: string },
): Promise<SignUpForSlotResult> {
  const { eventId, role, volunteerId, eventDate } = params;

  const needRef = db.collection("volunteerEvents").doc(eventId).collection("needs").doc(role);
  const blackoutRef = db.collection("volunteerBlackouts").doc(blackoutDocId(volunteerId, eventDate));
  const assignmentsQuery = db
    .collection("volunteerAssignments")
    .where("eventId", "==", eventId)
    .where("role", "==", role);

  return db.runTransaction(async (tx) => {
    // ---- READS (all reads precede all writes — Firestore transaction rule) ----
    const needSnap = await tx.get(needRef);
    if (!needSnap.exists) {
      throw new HttpsError("not-found", "No such staffing need for this event/role.");
    }
    const need = needSnap.data() as StaffingNeed;

    const blackoutSnap = await tx.get(blackoutRef);
    const assignmentsSnap = await tx.get(assignmentsQuery);

    let activeFilled = 0;
    let volunteerAlreadyActive = false;
    assignmentsSnap.docs.forEach((d) => {
      const a = d.data() as Assignment;
      if (isActiveAssignment(a.status)) {
        activeFilled += 1;
        if (a.volunteerId === volunteerId) volunteerAlreadyActive = true;
      }
    });

    // ---- DECISION (pure; I1 no-overfill, I3 blackout) ----
    const outcome = evaluateSignup({
      countNeeded: need.countNeeded,
      activeFilled,
      isBlackedOut: blackoutSnap.exists,
      volunteerAlreadyActive,
    });

    if (outcome.decision === "reject_blackout" || outcome.decision === "reject_duplicate") {
      return { decision: outcome.decision, assignmentId: null, resultingStatus: null };
    }

    // ---- WRITE (single assignment doc; never mutates a board counter — I2) ----
    const newRef = db.collection("volunteerAssignments").doc();
    const assignment: Assignment = {
      id: newRef.id,
      eventId,
      role,
      volunteerId,
      status: outcome.resultingStatus!,
    };
    tx.set(newRef, {
      ...assignment,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      decision: outcome.decision,
      assignmentId: newRef.id,
      resultingStatus: outcome.resultingStatus,
    };
  });
}

// ════════════════════════════════════════════════════════════════════
// Leadership check
// ════════════════════════════════════════════════════════════════════

async function requireEventLeader(db: Db, eventId: string, uid: string): Promise<void> {
  const snap = await db.collection("volunteerEvents").doc(eventId).get();
  if (!snap.exists) throw new HttpsError("not-found", "No such event.");
  const leaderIds = (snap.data()?.leaderIds ?? []) as string[];
  if (!Array.isArray(leaderIds) || !leaderIds.includes(uid)) {
    throw new HttpsError("permission-denied", "Leader role required.");
  }
}

/**
 * IDOR guard for signUpForSlot. A volunteer may only sign *themselves* up: the assignment is always
 * bound to the caller's uid. A client-supplied volunteerId is honored ONLY when it differs from the
 * caller AND the caller is a verified event leader signing another person up; otherwise we never
 * trust a client-supplied identity. Exported so the binding rule is unit-testable in isolation.
 */
export async function resolveSignupVolunteerId(
  db: Db,
  uid: string,
  rawVolunteerId: unknown,
  eventId: string,
): Promise<string> {
  const requested =
    typeof rawVolunteerId === "string" && rawVolunteerId.trim() ? rawVolunteerId.trim() : uid;
  if (requested === uid) return uid;
  await requireEventLeader(db, eventId, uid); // throws permission-denied for non-leaders
  return requested;
}

// ════════════════════════════════════════════════════════════════════
// Callables
// ════════════════════════════════════════════════════════════════════

/** §2 — Derived board rollup, computed from StaffingNeeds + Assignments (I2). */
export const assembleVolunteerBoard = onCall({ ...callableOpts, enforceAppCheck: true }, async (request) => {
  requireAuth(request);
  const db = admin.firestore();
  const eventId = readString(request.data?.eventId, "eventId");

  const needsSnap = await db.collection("volunteerEvents").doc(eventId).collection("needs").get();
  const assignmentsSnap = await db
    .collection("volunteerAssignments")
    .where("eventId", "==", eventId)
    .get();

  const needs = needsSnap.docs.map((d) => d.data() as StaffingNeed);
  const assignments = assignmentsSnap.docs.map((d) => d.data() as Assignment);

  return computeBoard(eventId, needs, assignments);
});

/** §2 — Transactional atomic fill: blackout-aware, waitlists when full, never overfills (I1/I3). */
export const signUpForSlot = onCall({ ...callableOpts, enforceAppCheck: true }, async (request) => {
  const uid = requireAuth(request);
  const db = admin.firestore();
  const eventId = readString(request.data?.eventId, "eventId");
  const role = readString(request.data?.role, "role");

  // Identity binding (IDOR guard): bind the assignment to the caller; only leaders may sign others up.
  // This callable is the sole write path for volunteerAssignments (firestore.rules: `allow write: if
  // false`), so resolveSignupVolunteerId is the only enforcement point for who an assignment is for.
  const volunteerId = await resolveSignupVolunteerId(db, uid, request.data?.volunteerId, eventId);

  const eventSnap = await db.collection("volunteerEvents").doc(eventId).get();
  if (!eventSnap.exists) throw new HttpsError("not-found", "No such event.");
  const startUTC = (eventSnap.data()?.startUTC ?? "") as string;
  const eventDate = eventCalendarDate(startUTC);

  return runSignUpTransaction(db, { eventId, role, volunteerId, eventDate });
});

/** §2 — Leader-only status transition: signedUp → confirmed. */
export const leaderApprove = onCall({ ...callableOpts, enforceAppCheck: true }, async (request) => {
  const uid = requireAuth(request);
  const db = admin.firestore();
  const assignmentId = readString(request.data?.assignmentId, "assignmentId");

  const ref = db.collection("volunteerAssignments").doc(assignmentId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "No such assignment.");
  const assignment = snap.data() as Assignment;

  await requireEventLeader(db, assignment.eventId, uid);

  if (assignment.status !== "signedUp") {
    throw new HttpsError("failed-precondition", `Cannot approve an assignment that is ${assignment.status}.`);
  }
  await ref.update({ status: "confirmed", confirmedAt: admin.firestore.FieldValue.serverTimestamp() });
  return { assignmentId, status: "confirmed" as const };
});

/** §Notes — Leader-only read of a private note. Every read is access-logged (I4). */
export const getLeaderPrivateNote = onCall({ ...callableOpts, enforceAppCheck: true }, async (request) => {
  const uid = requireAuth(request);
  const db = admin.firestore();
  const eventId = readString(request.data?.eventId, "eventId");
  const volunteerId = readString(request.data?.volunteerId, "volunteerId");

  await requireEventLeader(db, eventId, uid);

  // I4: log the access BEFORE returning the note — every read leaves an audit trail.
  await db.collection("volunteerNoteAccessLogs").add({
    eventId,
    volunteerId,
    accessedBy: uid,
    action: "read_leader_private_note",
    at: admin.firestore.FieldValue.serverTimestamp(),
  });

  const noteSnap = await db
    .collection("volunteerLeaderNotes")
    .doc(`${eventId}_${volunteerId}`)
    .get();

  if (!noteSnap.exists) {
    return { volunteerId, note: "", leaderOnly: true as const };
  }
  return {
    volunteerId,
    note: (noteSnap.data()?.note ?? "") as string,
    leaderOnly: true as const,
  };
});

/** §Notes — Leader-only write of a private note. Audited as a write (I4 consistency). */
export const setLeaderPrivateNote = onCall({ ...callableOpts, enforceAppCheck: true }, async (request) => {
  const uid = requireAuth(request);
  const db = admin.firestore();
  const eventId = readString(request.data?.eventId, "eventId");
  const volunteerId = readString(request.data?.volunteerId, "volunteerId");
  const note = typeof request.data?.note === "string" ? (request.data.note as string).trim() : "";

  await requireEventLeader(db, eventId, uid);

  await db.collection("volunteerNoteAccessLogs").add({
    eventId,
    volunteerId,
    accessedBy: uid,
    action: "write_leader_private_note",
    at: admin.firestore.FieldValue.serverTimestamp(),
  });

  await db.collection("volunteerLeaderNotes").doc(`${eventId}_${volunteerId}`).set(
    {
      volunteerId,
      note,
      leaderOnly: true,
      updatedBy: uid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return { volunteerId, leaderOnly: true as const };
});

/**
 * §Reminders — Enqueue push + email reminders for every active assignee of an event.
 * NO SMS in Wave 0 (TCPA consent + provider gated). Reminders are useful, not naggy:
 * one reminder record per assignee per call; the existing scheduledNotifications worker delivers.
 */
export const scheduleVolunteerReminders = onCall({ ...callableOpts, enforceAppCheck: true }, async (request) => {
  const uid = requireAuth(request);
  const db = admin.firestore();
  const eventId = readString(request.data?.eventId, "eventId");

  await requireEventLeader(db, eventId, uid);

  const eventSnap = await db.collection("volunteerEvents").doc(eventId).get();
  if (!eventSnap.exists) throw new HttpsError("not-found", "No such event.");
  const event = eventSnap.data() ?? {};
  const title = (event.title ?? "your serving slot") as string;
  const startUTC = (event.startUTC ?? "") as string;

  const assignmentsSnap = await db
    .collection("volunteerAssignments")
    .where("eventId", "==", eventId)
    .get();

  const active = assignmentsSnap.docs
    .map((d) => d.data() as Assignment)
    .filter((a) => isActiveAssignment(a.status));

  const batch = db.batch();
  for (const a of active) {
    const ref = db.collection("scheduledNotifications").doc();
    batch.set(ref, {
      userId: a.volunteerId,
      type: "volunteer_reminder",
      eventId,
      assignmentId: a.id,
      role: a.role,
      // Wave 0 channels: push + email only. SMS is intentionally absent (gated).
      channels: ["push", "email"],
      scheduledAt: startUTC || null,
      delivered: false,
      deepLinkRoute: `amen://volunteer/board/${eventId}`,
      title: "You're serving soon",
      body: `Reminder: you signed up to help with ${title}.`,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();

  return { eventId, scheduled: active.length, channels: ["push", "email"], sms: false };
});
