// callable.ts — Callable Cloud Functions for Spaces Live Rooms

import * as functions from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";

const db = getFirestore();

// ── Types ─────────────────────────────────────────────────────────────────────

interface CreateLiveRoomRequest {
  spaceId: string;
  eventId?: string;
  mode: "video" | "audioOnly";
}

interface JoinLiveRoomRequest {
  spaceId: string;
  roomId: string;
  displayName: string;
}

interface EndLiveRoomRequest {
  spaceId: string;
  roomId: string;
}

interface RaiseHandRequest {
  spaceId: string;
  roomId: string;
  raised: boolean;
}

interface MuteParticipantRequest {
  spaceId: string;
  roomId: string;
  targetUserId: string;
}

interface LiveRoomDoc {
  hostUserId: string;
  state: string;
  eventId: string | null;
  modIds?: string[];
}

// ── createLiveRoom ────────────────────────────────────────────────────────────

export const createLiveRoom = functions.onCall(
  { enforceAppCheck: false },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as CreateLiveRoomRequest;
    const spaceId = String(data?.spaceId ?? "").trim();
    const mode = data?.mode;
    const eventId = data?.eventId ? String(data.eventId).trim() : undefined;

    if (!spaceId) {
      throw new functions.HttpsError("invalid-argument", "spaceId is required.");
    }
    if (mode !== "video" && mode !== "audioOnly") {
      throw new functions.HttpsError("invalid-argument", 'mode must be "video" or "audioOnly".');
    }

    const roomRef = db.collection("spaces").doc(spaceId).collection("liveRooms").doc();
    const roomId = roomRef.id;

    const roomData: Record<string, unknown> = {
      id: roomId,
      spaceId,
      eventId: eventId ?? null,
      hostUserId: userId,
      mode,
      state: "greenRoom",
      participants: [],
      captionsEnabled: false,
      viewerCount: 0,
      createdAt: FieldValue.serverTimestamp(),
      chapterMarkers: [],
    };

    const batch = db.batch();
    batch.set(roomRef, roomData);

    if (eventId) {
      const eventRef = db.collection("spaces").doc(spaceId).collection("events").doc(eventId);
      batch.update(eventRef, { isLive: true, liveRoomId: roomId });
    }

    await batch.commit();
    logger.info(`createLiveRoom: room ${roomId} created in space ${spaceId} by ${userId}`);

    return { roomId, ok: true };
  }
);

// ── joinLiveRoom ──────────────────────────────────────────────────────────────

export const joinLiveRoom = functions.onCall(
  { enforceAppCheck: false },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as JoinLiveRoomRequest;
    const spaceId = String(data?.spaceId ?? "").trim();
    const roomId = String(data?.roomId ?? "").trim();
    const displayName = String(data?.displayName ?? "").trim();

    if (!spaceId) throw new functions.HttpsError("invalid-argument", "spaceId is required.");
    if (!roomId) throw new functions.HttpsError("invalid-argument", "roomId is required.");
    if (!displayName) throw new functions.HttpsError("invalid-argument", "displayName is required.");
    if (displayName.length > 80) {
      throw new functions.HttpsError("invalid-argument", "displayName must be 80 characters or fewer.");
    }

    const roomRef = db.collection("spaces").doc(spaceId).collection("liveRooms").doc(roomId);
    const roomSnap = await roomRef.get();
    if (!roomSnap.exists) throw new functions.HttpsError("not-found", "Live room not found.");

    const roomData = roomSnap.data() as LiveRoomDoc;
    if (roomData.state === "ended") {
      throw new functions.HttpsError("failed-precondition", "This live room has ended.");
    }

    const participant = {
      id: userId,
      displayName,
      isHost: false,
      isMod: false,
      hasRaisedHand: false,
      isMuted: false,
      joinedAt: Timestamp.now(),
    };

    await roomRef.update({
      participants: FieldValue.arrayUnion(participant),
      viewerCount: FieldValue.increment(1),
    });

    logger.info(`joinLiveRoom: user ${userId} joined room ${roomId} in space ${spaceId}`);

    return { ok: true, roomState: roomData.state };
  }
);

// ── endLiveRoom ───────────────────────────────────────────────────────────────

export const endLiveRoom = functions.onCall(
  { enforceAppCheck: false },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as EndLiveRoomRequest;
    const spaceId = String(data?.spaceId ?? "").trim();
    const roomId = String(data?.roomId ?? "").trim();

    if (!spaceId) throw new functions.HttpsError("invalid-argument", "spaceId is required.");
    if (!roomId) throw new functions.HttpsError("invalid-argument", "roomId is required.");

    const roomRef = db.collection("spaces").doc(spaceId).collection("liveRooms").doc(roomId);
    const roomSnap = await roomRef.get();
    if (!roomSnap.exists) throw new functions.HttpsError("not-found", "Live room not found.");

    const roomData = roomSnap.data() as LiveRoomDoc;
    if (roomData.hostUserId !== userId) {
      throw new functions.HttpsError("permission-denied", "Only the host can end this room.");
    }

    const batch = db.batch();
    batch.update(roomRef, {
      state: "ended",
      endedAt: FieldValue.serverTimestamp(),
    });

    if (roomData.eventId) {
      const eventRef = db
        .collection("spaces").doc(spaceId)
        .collection("events").doc(roomData.eventId);
      batch.update(eventRef, { isLive: false, replayRef: "pending" });
    }

    await batch.commit();
    logger.info(`endLiveRoom: room ${roomId} ended by host ${userId}`);

    return { ok: true };
  }
);

// ── raiseHand ─────────────────────────────────────────────────────────────────

export const raiseHand = functions.onCall(
  { enforceAppCheck: false },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as RaiseHandRequest;
    const spaceId = String(data?.spaceId ?? "").trim();
    const roomId = String(data?.roomId ?? "").trim();
    const raised = Boolean(data?.raised);

    if (!spaceId) throw new functions.HttpsError("invalid-argument", "spaceId is required.");
    if (!roomId) throw new functions.HttpsError("invalid-argument", "roomId is required.");

    const raisedHandRef = db
      .collection("spaces").doc(spaceId)
      .collection("liveRooms").doc(roomId)
      .collection("raisedHands").doc(userId);

    await raisedHandRef.set({
      userId,
      raisedAt: Timestamp.now(),
      active: raised,
    });

    logger.info(`raiseHand: user ${userId} raised=${raised} in room ${roomId}`);

    return { ok: true };
  }
);

// ── muteParticipant ───────────────────────────────────────────────────────────

export const muteParticipant = functions.onCall(
  { enforceAppCheck: false },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as MuteParticipantRequest;
    const spaceId = String(data?.spaceId ?? "").trim();
    const roomId = String(data?.roomId ?? "").trim();
    const targetUserId = String(data?.targetUserId ?? "").trim();

    if (!spaceId) throw new functions.HttpsError("invalid-argument", "spaceId is required.");
    if (!roomId) throw new functions.HttpsError("invalid-argument", "roomId is required.");
    if (!targetUserId) throw new functions.HttpsError("invalid-argument", "targetUserId is required.");

    const roomRef = db.collection("spaces").doc(spaceId).collection("liveRooms").doc(roomId);
    const roomSnap = await roomRef.get();
    if (!roomSnap.exists) throw new functions.HttpsError("not-found", "Live room not found.");

    const roomData = roomSnap.data() as LiveRoomDoc;
    const isHost = roomData.hostUserId === userId;
    const isMod = (roomData.modIds ?? []).includes(userId);

    if (!isHost && !isMod) {
      throw new functions.HttpsError("permission-denied", "Only the host or a moderator can mute participants.");
    }

    const muteSignalRef = db
      .collection("spaces").doc(spaceId)
      .collection("liveRooms").doc(roomId)
      .collection("muteSignals").doc(targetUserId);

    await muteSignalRef.set({
      mutedBy: userId,
      mutedAt: Timestamp.now(),
      active: true,
    });

    logger.info(`muteParticipant: ${userId} muted ${targetUserId} in room ${roomId}`);

    return { ok: true };
  }
);
