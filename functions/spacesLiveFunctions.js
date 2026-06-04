/**
 * spacesLiveFunctions.js
 * AMEN Spaces — Live room callables
 * Handles: createLiveRoom, joinLiveRoom, endLiveRoom, raiseHand, muteParticipant
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");

const db = getFirestore();

// ── createLiveRoom ────────────────────────────────────────────────────────────

exports.createLiveRoom = onCall({ enforceAppCheck: true }, async (request) => { // requires App Check token; disable locally via FUNCTIONS_EMULATOR
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { spaceId, eventId, mode } = request.data ?? {};
  if (!spaceId) throw new HttpsError("invalid-argument", "spaceId is required.");
  if (!mode || !["video", "audioOnly"].includes(mode)) {
    throw new HttpsError("invalid-argument", "mode must be video or audioOnly.");
  }

  const spaceSnap = await db.collection("spaces").doc(spaceId).get();
  if (spaceSnap.data()?.hostUserId !== userId) {
    throw new HttpsError("permission-denied", "Only the host can create a live room.");
  }

  const roomId = `room_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
  const roomDoc = {
    id: roomId, spaceId,
    eventId: eventId ?? null,
    hostUserId: userId,
    mode, state: "greenRoom",
    participants: [],
    captionsEnabled: false,
    viewerCount: 0,
    chapterMarkers: [],
    createdAt: FieldValue.serverTimestamp(),
  };

  const batch = db.batch();
  batch.set(db.collection("spaces").doc(spaceId).collection("liveRooms").doc(roomId), roomDoc);

  if (eventId) {
    batch.update(db.collection("spaces").doc(spaceId).collection("events").doc(eventId), {
      isLive: true,
      liveRoomId: roomId,
    });
  }

  await batch.commit();
  return { roomId, ok: true };
});

// ── joinLiveRoom ──────────────────────────────────────────────────────────────

exports.joinLiveRoom = onCall({ enforceAppCheck: true }, async (request) => { // requires App Check token; disable locally via FUNCTIONS_EMULATOR
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { spaceId, roomId, displayName } = request.data ?? {};
  if (!spaceId || !roomId || !displayName) {
    throw new HttpsError("invalid-argument", "spaceId, roomId, and displayName are required.");
  }

  const roomRef = db.collection("spaces").doc(spaceId).collection("liveRooms").doc(roomId);
  const roomSnap = await roomRef.get();
  if (!roomSnap.exists) throw new HttpsError("not-found", "Live room not found.");

  const participant = {
    id: userId,
    displayName,
    isHost: roomSnap.data()?.hostUserId === userId,
    isMod: false,
    hasRaisedHand: false,
    isMuted: false,
    joinedAt: Timestamp.now(),
  };

  await roomRef.update({
    participants: FieldValue.arrayUnion(participant),
    viewerCount: FieldValue.increment(1),
  });

  return { ok: true, roomState: roomSnap.data()?.state ?? "greenRoom" };
});

// ── endLiveRoom ───────────────────────────────────────────────────────────────

exports.endLiveRoom = onCall({ enforceAppCheck: true }, async (request) => { // requires App Check token; disable locally via FUNCTIONS_EMULATOR
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { spaceId, roomId, replayURL } = request.data ?? {};
  if (!spaceId || !roomId) {
    throw new HttpsError("invalid-argument", "spaceId and roomId are required.");
  }

  const roomRef = db.collection("spaces").doc(spaceId).collection("liveRooms").doc(roomId);
  const roomSnap = await roomRef.get();
  if (!roomSnap.exists) throw new HttpsError("not-found", "Live room not found.");
  if (roomSnap.data()?.hostUserId !== userId) {
    throw new HttpsError("permission-denied", "Only the host can end the room.");
  }

  const batch = db.batch();
  batch.update(roomRef, {
    state: "ended",
    endedAt: FieldValue.serverTimestamp(),
    replayURL: replayURL ?? null,
    hasReplay: Boolean(replayURL),
  });

  const eventId = roomSnap.data()?.eventId;
  if (eventId) {
    batch.update(db.collection("spaces").doc(spaceId).collection("events").doc(eventId), {
      isLive: false,
      replayURL: replayURL ?? null,
      hasReplay: Boolean(replayURL),
    });
  }

  await batch.commit();
  return { ok: true };
});

// ── raiseHand ─────────────────────────────────────────────────────────────────

exports.raiseHand = onCall({ enforceAppCheck: true }, async (request) => { // requires App Check token; disable locally via FUNCTIONS_EMULATOR
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { spaceId, roomId, raised } = request.data ?? {};
  if (!spaceId || !roomId || typeof raised !== "boolean") {
    throw new HttpsError("invalid-argument", "spaceId, roomId, and raised (boolean) are required.");
  }

  const roomRef = db.collection("spaces").doc(spaceId).collection("liveRooms").doc(roomId);
  const roomSnap = await roomRef.get();
  if (!roomSnap.exists) throw new HttpsError("not-found", "Live room not found.");

  const participants = (roomSnap.data()?.participants ?? []).map((p) =>
    p.id === userId ? { ...p, hasRaisedHand: raised } : p
  );
  await roomRef.update({ participants });

  return { ok: true, raised };
});

// ── muteParticipant ───────────────────────────────────────────────────────────

exports.muteParticipant = onCall({ enforceAppCheck: true }, async (request) => { // requires App Check token; disable locally via FUNCTIONS_EMULATOR
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { spaceId, roomId, targetUserId } = request.data ?? {};
  if (!spaceId || !roomId || !targetUserId) {
    throw new HttpsError("invalid-argument", "spaceId, roomId, and targetUserId are required.");
  }

  const roomRef = db.collection("spaces").doc(spaceId).collection("liveRooms").doc(roomId);
  const roomSnap = await roomRef.get();
  if (!roomSnap.exists) throw new HttpsError("not-found", "Live room not found.");

  const data = roomSnap.data() ?? {};
  const isHostOrMod = data.hostUserId === userId ||
    (data.participants ?? []).some((p) => p.id === userId && p.isMod);
  if (!isHostOrMod) {
    throw new HttpsError("permission-denied", "Only the host or mods can mute participants.");
  }

  const participants = (data.participants ?? []).map((p) =>
    p.id === targetUserId ? { ...p, isMuted: true } : p
  );
  await roomRef.update({ participants });

  return { ok: true, targetUserId };
});
