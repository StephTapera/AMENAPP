// volunteer/volunteerLifecycle.ts
// AMEN — Smart Volunteer Board · Wave 0 · event/need/blackout lifecycle callables (us-east1).
// These exist so the board is usable end-to-end: create an event, declare its staffing needs,
// list the events a user can act on, and let a volunteer mark themselves unavailable (I3).
//
// All writes are server-authoritative (admin SDK) so Firestore rules can deny client writes.
// Source of truth for shapes: contracts/volunteer.ts.

import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { ServiceEvent, StaffingNeed } from "../contracts/volunteer";

const REGION = "us-east1";
const callableOpts = { region: REGION, enforceAppCheck: true, timeoutSeconds: 20 } as const;

type Db = FirebaseFirestore.Firestore;

function requireAuth(request: { auth?: { uid: string } | null }): string {
  if (!request.auth) throw new HttpsError("unauthenticated", "Auth required");
  return request.auth.uid;
}

function readString(value: unknown, field: string, max = 200): string {
  if (typeof value !== "string" || !value.trim()) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  const trimmed = value.trim();
  if (trimmed.length > max) throw new HttpsError("invalid-argument", `${field} is too long.`);
  return trimmed;
}

function readPositiveInt(value: unknown, field: string): number {
  const n = typeof value === "number" ? value : Number(value);
  if (!Number.isInteger(n) || n < 1 || n > 1000) {
    throw new HttpsError("invalid-argument", `${field} must be an integer between 1 and 1000.`);
  }
  return n;
}

/** "YYYY-MM-DD" guard for blackout dates. */
function readIsoDate(value: unknown, field: string): string {
  const s = readString(value, field, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) {
    throw new HttpsError("invalid-argument", `${field} must be YYYY-MM-DD.`);
  }
  return s;
}

async function requireEventLeader(db: Db, eventId: string, uid: string): Promise<void> {
  const snap = await db.collection("volunteerEvents").doc(eventId).get();
  if (!snap.exists) throw new HttpsError("not-found", "No such event.");
  const leaderIds = (snap.data()?.leaderIds ?? []) as string[];
  if (!Array.isArray(leaderIds) || !leaderIds.includes(uid)) {
    throw new HttpsError("permission-denied", "Leader role required.");
  }
}

// ════════════════════════════════════════════════════════════════════
// Event + need creation (leader-authored)
// ════════════════════════════════════════════════════════════════════

/** Creates a single dated event; the creator becomes its first leader. */
export const createServiceEvent = onCall({ ...callableOpts, enforceAppCheck: true }, async (request) => {
  const uid = requireAuth(request);
  const db = admin.firestore();

  const title = readString(request.data?.title, "title", 200);
  const startUTC = readString(request.data?.startUTC, "startUTC", 40);
  const timezone = readString(request.data?.timezone, "timezone", 64);
  const location = readString(request.data?.location, "location", 200);

  const ref = db.collection("volunteerEvents").doc();
  const event: ServiceEvent = { id: ref.id, title, startUTC, timezone, location };
  await ref.set({
    ...event,
    leaderIds: [uid],
    createdBy: uid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return event;
});

/** Declares (or updates) a staffing need for a role on an event. Leader-only. */
export const addStaffingNeed = onCall({ ...callableOpts, enforceAppCheck: true }, async (request) => {
  const uid = requireAuth(request);
  const db = admin.firestore();

  const eventId = readString(request.data?.eventId, "eventId", 200);
  const role = readString(request.data?.role, "role", 80);
  const countNeeded = readPositiveInt(request.data?.countNeeded, "countNeeded");

  await requireEventLeader(db, eventId, uid);

  const need: StaffingNeed = { eventId, role, countNeeded, status: "open" };
  await db.collection("volunteerEvents").doc(eventId).collection("needs").doc(role).set({
    ...need,
    updatedBy: uid,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return need;
});

// ════════════════════════════════════════════════════════════════════
// Reads — event + the events a user can act on
// ════════════════════════════════════════════════════════════════════

/** Returns a ServiceEvent and whether the caller is one of its leaders. */
export const getServiceEvent = onCall({ ...callableOpts, enforceAppCheck: true }, async (request) => {
  const uid = requireAuth(request);
  const db = admin.firestore();
  const eventId = readString(request.data?.eventId, "eventId", 200);

  const snap = await db.collection("volunteerEvents").doc(eventId).get();
  if (!snap.exists) throw new HttpsError("not-found", "No such event.");
  const d = snap.data() ?? {};
  const event: ServiceEvent = {
    id: eventId,
    title: (d.title ?? "") as string,
    startUTC: (d.startUTC ?? "") as string,
    timezone: (d.timezone ?? "UTC") as string,
    location: (d.location ?? "") as string,
  };
  const leaderIds = (d.leaderIds ?? []) as string[];
  return { event, isLeader: Array.isArray(leaderIds) && leaderIds.includes(uid) };
});

/** Lists events the user leads or is assigned to, with a per-event isLeader flag. */
export const listVolunteerEventsForUser = onCall({ ...callableOpts, enforceAppCheck: true }, async (request) => {
  const uid = requireAuth(request);
  const db = admin.firestore();

  const ledSnap = await db
    .collection("volunteerEvents")
    .where("leaderIds", "array-contains", uid)
    .get();
  const ledIds = new Set(ledSnap.docs.map((d) => d.id));

  const myAssignmentsSnap = await db
    .collection("volunteerAssignments")
    .where("volunteerId", "==", uid)
    .get();
  const assignedIds = new Set(myAssignmentsSnap.docs.map((d) => (d.data().eventId ?? "") as string));

  // Fetch assigned events not already in the led set.
  const extraIds = [...assignedIds].filter((id) => id && !ledIds.has(id));
  const extraSnaps = await Promise.all(
    extraIds.map((id) => db.collection("volunteerEvents").doc(id).get()),
  );

  const toEvent = (id: string, d: FirebaseFirestore.DocumentData, isLeader: boolean) => ({
    event: {
      id,
      title: (d.title ?? "") as string,
      startUTC: (d.startUTC ?? "") as string,
      timezone: (d.timezone ?? "UTC") as string,
      location: (d.location ?? "") as string,
    } as ServiceEvent,
    isLeader,
  });

  const events = [
    ...ledSnap.docs.map((d) => toEvent(d.id, d.data(), true)),
    ...extraSnaps.filter((s) => s.exists).map((s) => toEvent(s.id, s.data()!, false)),
  ];
  return { events };
});

// ════════════════════════════════════════════════════════════════════
// Blackout (volunteer self-service; I3)
// ════════════════════════════════════════════════════════════════════

/** Marks the calling volunteer unavailable on a date (used by I3 at signup time). */
export const setVolunteerBlackout = onCall({ ...callableOpts, enforceAppCheck: true }, async (request) => {
  const uid = requireAuth(request);
  const db = admin.firestore();
  const date = readIsoDate(request.data?.date, "date");

  await db.collection("volunteerBlackouts").doc(`${uid}_${date}`).set({
    volunteerId: uid,
    date,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { volunteerId: uid, date };
});

/** Clears a previously-set blackout date for the calling volunteer. */
export const clearVolunteerBlackout = onCall({ ...callableOpts, enforceAppCheck: true }, async (request) => {
  const uid = requireAuth(request);
  const db = admin.firestore();
  const date = readIsoDate(request.data?.date, "date");

  await db.collection("volunteerBlackouts").doc(`${uid}_${date}`).delete();
  return { volunteerId: uid, date, cleared: true };
});
