/**
 * spatialMessagesFunctions.js
 * Phase 5 — Spatial Social OS: shared viewing rooms + anchored replies.
 *
 * Provides four callables that own the lifecycle of a shared viewing room
 * (ephemeral, host + invited participants, max 8) and the anchored replies
 * that participants post against the media's timeline.
 *
 *  - createSharedViewingRoom({ postId, mediaId })
 *      → creates /sharedViewingRooms/{roomId} with host = uid
 *  - joinSharedViewingRoom({ roomId })
 *      → adds caller to participantUids (atomic, max 8), upserts presence
 *  - leaveSharedViewingRoom({ roomId })
 *      → removes caller from participantUids, ends presence
 *  - postAnchoredReply({ roomId, postId, anchorTimestampMs, message })
 *      → writes /sharedViewingRooms/{roomId}/anchoredReplies/{replyId}
 *
 * Trust contract:
 *   - All collection writes happen here, server-side. Clients never write
 *     /sharedViewingRooms or /presenceSessions directly.
 *   - Participant membership is the only access gate (mirrored by firestore
 *     rules — room read is allowed only for host + participants).
 *   - Anchored replies inherit the room's membership: clients call this
 *     function with a roomId and the function validates membership.
 *   - Messages are rate-limited per uid to prevent flood/grief.
 */

"use strict";

const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {checkRateLimit} = require("./rateLimiter");

const db = () => admin.firestore();
const MAX_PARTICIPANTS = 8;
const REPLY_MAX_CHARS = 1000;

// ─── createSharedViewingRoom ────────────────────────────────────────────────

exports.createSharedViewingRoom = onCall(
    {region: "us-central1", enforceAppCheck: true},
    async (request) => {
      const uid = request.auth && request.auth.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      const {postId, mediaId} = request.data || {};
      if (typeof postId !== "string" || !postId) {
        throw new HttpsError("invalid-argument", "postId required");
      }
      if (typeof mediaId !== "string" || !mediaId) {
        throw new HttpsError("invalid-argument", "mediaId required");
      }

      // 3 rooms per hour cap.
      await checkRateLimit(uid, "create_shared_viewing_room", 3, 3600);

      const postSnap = await db().collection("posts").doc(postId).get();
      if (!postSnap.exists) {
        throw new HttpsError("not-found", "Post not found");
      }

      const ref = db().collection("sharedViewingRooms").doc();
      const now = admin.firestore.FieldValue.serverTimestamp();
      const room = {
        roomId: ref.id,
        hostUid: uid,
        postId,
        mediaId,
        participantUids: [uid],
        active: true,
        createdAt: now,
        updatedAt: now,
      };
      await ref.set(room);

      // Best-effort presence write — Phase 3 PresenceLayer reads from here.
      await db().collection("presenceSessions").doc(`${uid}_${mediaId}`).set({
        uid,
        mediaId,
        roomId: ref.id,
        active: true,
        startedAt: now,
        updatedAt: now,
      }, {merge: true});

      return {roomId: ref.id};
    },
);

// ─── joinSharedViewingRoom ──────────────────────────────────────────────────

exports.joinSharedViewingRoom = onCall(
    {region: "us-central1", enforceAppCheck: true},
    async (request) => {
      const uid = request.auth && request.auth.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      const {roomId} = request.data || {};
      if (typeof roomId !== "string" || !roomId) {
        throw new HttpsError("invalid-argument", "roomId required");
      }

      await checkRateLimit(uid, "join_shared_viewing_room", 30, 3600);

      const ref = db().collection("sharedViewingRooms").doc(roomId);
      const result = await db().runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists) {
          throw new HttpsError("not-found", "Room not found");
        }
        const room = snap.data() || {};
        if (room.active === false) {
          throw new HttpsError("failed-precondition", "Room is closed");
        }
        const participants = Array.isArray(room.participantUids)
          ? room.participantUids
          : [];
        if (participants.includes(uid)) {
          return {mediaId: room.mediaId, alreadyJoined: true};
        }
        if (participants.length >= MAX_PARTICIPANTS) {
          throw new HttpsError("resource-exhausted", "Room is full");
        }
        tx.update(ref, {
          participantUids: admin.firestore.FieldValue.arrayUnion(uid),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return {mediaId: room.mediaId, alreadyJoined: false};
      });

      const mediaId = result.mediaId;
      if (mediaId) {
        await db().collection("presenceSessions").doc(`${uid}_${mediaId}`).set({
          uid,
          mediaId,
          roomId,
          active: true,
          startedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
      }

      return {roomId, joined: !result.alreadyJoined};
    },
);

// ─── leaveSharedViewingRoom ─────────────────────────────────────────────────

exports.leaveSharedViewingRoom = onCall(
    {region: "us-central1", enforceAppCheck: true},
    async (request) => {
      const uid = request.auth && request.auth.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      const {roomId} = request.data || {};
      if (typeof roomId !== "string" || !roomId) {
        throw new HttpsError("invalid-argument", "roomId required");
      }

      const ref = db().collection("sharedViewingRooms").doc(roomId);
      const result = await db().runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists) return {mediaId: null};
        const room = snap.data() || {};
        const participants = Array.isArray(room.participantUids)
          ? room.participantUids
          : [];
        const next = participants.filter((p) => p !== uid);
        const isHost = room.hostUid === uid;
        const updates = {
          participantUids: next,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        if (isHost || next.length === 0) {
          updates.active = false;
          updates.closedAt = admin.firestore.FieldValue.serverTimestamp();
        }
        tx.update(ref, updates);
        return {mediaId: room.mediaId};
      });

      if (result.mediaId) {
        await db().collection("presenceSessions").doc(`${uid}_${result.mediaId}`).set({
          active: false,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
      }

      return {roomId, left: true};
    },
);

// ─── postAnchoredReply ──────────────────────────────────────────────────────

exports.postAnchoredReply = onCall(
    {region: "us-central1", enforceAppCheck: true},
    async (request) => {
      const uid = request.auth && request.auth.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      const {roomId, postId, anchorTimestampMs, message} = request.data || {};
      if (typeof roomId !== "string" || !roomId) {
        throw new HttpsError("invalid-argument", "roomId required");
      }
      if (typeof postId !== "string" || !postId) {
        throw new HttpsError("invalid-argument", "postId required");
      }
      if (typeof anchorTimestampMs !== "number" || anchorTimestampMs < 0) {
        throw new HttpsError("invalid-argument", "anchorTimestampMs required");
      }
      if (typeof message !== "string" || !message.trim()) {
        throw new HttpsError("invalid-argument", "message required");
      }
      const trimmed = message.trim().slice(0, REPLY_MAX_CHARS);

      // Per-room flood control: max 60 messages/hour/uid.
      await checkRateLimit(uid, `anchored_reply:${roomId}`, 60, 3600);

      const roomRef = db().collection("sharedViewingRooms").doc(roomId);
      const roomSnap = await roomRef.get();
      if (!roomSnap.exists) {
        throw new HttpsError("not-found", "Room not found");
      }
      const room = roomSnap.data() || {};
      if (room.active === false) {
        throw new HttpsError("failed-precondition", "Room is closed");
      }
      const participants = Array.isArray(room.participantUids)
        ? room.participantUids
        : [];
      if (!participants.includes(uid)) {
        throw new HttpsError("permission-denied", "Not a participant");
      }

      const replyRef = roomRef.collection("anchoredReplies").doc();
      const now = admin.firestore.FieldValue.serverTimestamp();
      const reply = {
        replyId: replyRef.id,
        roomId,
        postId,
        authorUid: uid,
        anchorTimestampMs,
        message: trimmed,
        createdAt: now,
      };
      await replyRef.set(reply);

      return {replyId: replyRef.id, roomId};
    },
);
