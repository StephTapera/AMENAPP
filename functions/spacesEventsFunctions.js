/**
 * spacesEventsFunctions.js
 * AMEN Spaces — Events callables
 * Handles: createSpaceEvent, rsvpToEvent, sendEventBroadcast, listUpcomingEvents
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");

const db = getFirestore();

// ── createSpaceEvent ─────────────────────────────────────────────────────────

exports.createSpaceEvent = onCall({ enforceAppCheck: true }, async (request) => { // requires App Check token; disable locally via FUNCTIONS_EMULATOR
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { spaceId, title, description, scheduledAt, durationMinutes,
          eventType, isRecurring, recurrenceRule, coverImageURL,
          minimumTierOrder } = request.data ?? {};

  if (!spaceId) throw new HttpsError("invalid-argument", "spaceId is required.");
  if (!title || title.length < 1 || title.length > 100) {
    throw new HttpsError("invalid-argument", "title must be 1-100 chars.");
  }
  if (!scheduledAt || typeof scheduledAt !== "number") {
    throw new HttpsError("invalid-argument", "scheduledAt (epoch ms) is required.");
  }
  if (!eventType || !["livestream", "study", "prayer", "worship", "qa", "other"].includes(eventType)) {
    throw new HttpsError("invalid-argument", "Invalid eventType.");
  }

  const spaceSnap = await db.collection("spaces").doc(spaceId).get();
  if (spaceSnap.data()?.hostUserId !== userId) {
    throw new HttpsError("permission-denied", "Only the host can create events.");
  }

  const eventId = `evt_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
  const eventDoc = {
    id: eventId, spaceId, hostUserId: userId,
    title, description: description ?? "",
    scheduledAt: Timestamp.fromMillis(scheduledAt),
    durationMinutes: durationMinutes ?? 60,
    eventType, isRecurring: Boolean(isRecurring),
    recurrenceRule: recurrenceRule ?? null,
    coverImageURL: coverImageURL ?? null,
    minimumTierOrder: minimumTierOrder ?? 0,
    rsvpCount: 0, isLive: false, liveRoomId: null,
    replayURL: null, hasReplay: false,
    createdAt: FieldValue.serverTimestamp(),
  };

  await db.collection("spaces").doc(spaceId).collection("events").doc(eventId).set(eventDoc);
  return { eventId, ok: true };
});

// ── rsvpToEvent ──────────────────────────────────────────────────────────────

exports.rsvpToEvent = onCall({ enforceAppCheck: true }, async (request) => { // requires App Check token; disable locally via FUNCTIONS_EMULATOR
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { spaceId, eventId, status } = request.data ?? {};
  if (!spaceId || !eventId) {
    throw new HttpsError("invalid-argument", "spaceId and eventId are required.");
  }
  if (!["going", "interested", "not_going"].includes(status)) {
    throw new HttpsError("invalid-argument", "status must be going, interested, or not_going.");
  }

  const eventRef = db.collection("spaces").doc(spaceId).collection("events").doc(eventId);
  const rsvpRef = eventRef.collection("rsvps").doc(userId);

  const existingRSVP = await rsvpRef.get();
  const wasGoing = existingRSVP.exists && existingRSVP.data()?.status === "going";
  const isNowGoing = status === "going";

  const batch = db.batch();
  batch.set(rsvpRef, { userId, status, updatedAt: FieldValue.serverTimestamp() }, { merge: true });

  if (!wasGoing && isNowGoing) {
    batch.update(eventRef, { rsvpCount: FieldValue.increment(1) });
  } else if (wasGoing && !isNowGoing) {
    batch.update(eventRef, { rsvpCount: FieldValue.increment(-1) });
  }

  await batch.commit();
  return { ok: true, status };
});

// ── sendEventBroadcast ───────────────────────────────────────────────────────

exports.sendEventBroadcast = onCall({ enforceAppCheck: true }, async (request) => { // requires App Check token; disable locally via FUNCTIONS_EMULATOR
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { spaceId, eventId, message, channels } = request.data ?? {};
  if (!spaceId || !eventId) {
    throw new HttpsError("invalid-argument", "spaceId and eventId are required.");
  }
  if (!message || message.length < 1 || message.length > 500) {
    throw new HttpsError("invalid-argument", "message must be 1-500 chars.");
  }

  const spaceSnap = await db.collection("spaces").doc(spaceId).get();
  if (spaceSnap.data()?.hostUserId !== userId) {
    throw new HttpsError("permission-denied", "Only the host can send broadcasts.");
  }

  const broadcastId = `bcast_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
  await db.collection("spaces").doc(spaceId).collection("broadcasts").doc(broadcastId).set({
    id: broadcastId, spaceId, eventId,
    message, hostUserId: userId,
    channels: Array.isArray(channels) ? channels : ["push", "inApp"],
    sentAt: FieldValue.serverTimestamp(),
  });

  return { broadcastId, ok: true };
});

// ── listUpcomingEvents ───────────────────────────────────────────────────────

exports.listUpcomingEvents = onCall({ enforceAppCheck: true }, async (request) => { // requires App Check token; disable locally via FUNCTIONS_EMULATOR
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { spaceId, limit: limitVal } = request.data ?? {};
  if (!spaceId) throw new HttpsError("invalid-argument", "spaceId is required.");

  const pageSize = Math.min(Math.max(parseInt(limitVal ?? 10), 1), 50);
  const now = Timestamp.now();

  const snap = await db.collection("spaces").doc(spaceId).collection("events")
    .where("scheduledAt", ">=", now)
    .orderBy("scheduledAt", "asc")
    .limit(pageSize)
    .get();

  const events = snap.docs.map((d) => {
    const data = d.data();
    return { ...data, scheduledAt: data.scheduledAt?.toMillis() ?? null };
  });

  return { events };
});
