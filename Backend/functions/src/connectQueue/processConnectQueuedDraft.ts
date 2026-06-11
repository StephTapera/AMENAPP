/**
 * processConnectQueuedDraft.ts — Stage-3 CF deploy item
 *
 * Receives a queued draft from ConnectOfflineQueueManager (iOS Wave 5) and
 * writes it to the appropriate Firestore collection server-side.
 *
 * Idempotency: the `idempotencyKey` (UUID from the iOS queue item) is stored
 * in connect_idempotency/{key}. A second call with the same key returns the
 * cached result without re-writing, preventing duplicate sends.
 *
 * Auth + App Check required. All writes are server-authoritative.
 *
 * Supported draftTypes:
 *   announcement   → spaces/{spaceId}/announcements
 *   dm             → conversations/{conversationId}/messages
 *   rsvp           → spaces/{spaceId}/events/{eventId}/rsvps
 *   spaceMessage   → spaces/{spaceId}/channels/{channelId}/messages
 */

import * as functions from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const db = () => admin.firestore();

interface QueuedDraftPayload {
  idempotencyKey: string;
  draftType: "announcement" | "dm" | "rsvp" | "spaceMessage";
  spaceId?: string;
  channelId?: string;
  conversationId?: string;
  eventId?: string;
  body?: string;
  title?: string;
}

export const processConnectQueuedDraft = functions.onCall(
  { enforceAppCheck: true },
  async (request) => {
    if (!request.auth?.uid) {
      throw new functions.HttpsError("unauthenticated", "Auth required.");
    }
    const uid = request.auth.uid;
    const data = request.data as QueuedDraftPayload;

    if (!data?.idempotencyKey || typeof data.idempotencyKey !== "string") {
      throw new functions.HttpsError("invalid-argument", "idempotencyKey required.");
    }
    if (!data.draftType) {
      throw new functions.HttpsError("invalid-argument", "draftType required.");
    }

    // ── Idempotency check ──────────────────────────────────────────────────
    const idemRef = db().collection("connect_idempotency").doc(data.idempotencyKey);
    const idemSnap = await idemRef.get();
    if (idemSnap.exists) {
      // Already processed — return cached result
      return { status: "already_processed", documentId: idemSnap.data()?.["documentId"] ?? null };
    }

    // ── Route by draftType ─────────────────────────────────────────────────
    let docRef: admin.firestore.DocumentReference;
    const now = admin.firestore.FieldValue.serverTimestamp();

    switch (data.draftType) {
      case "announcement": {
        if (!data.spaceId) throw new functions.HttpsError("invalid-argument", "spaceId required for announcement.");
        docRef = await db()
          .collection("spaces")
          .doc(data.spaceId)
          .collection("announcements")
          .add({
            authorUid: uid,
            title: data.title ?? "",
            body: data.body ?? "",
            status: "pending_moderation",
            fromOfflineQueue: true,
            idempotencyKey: data.idempotencyKey,
            createdAt: now,
          });
        break;
      }
      case "dm": {
        if (!data.conversationId) throw new functions.HttpsError("invalid-argument", "conversationId required for dm.");
        docRef = await db()
          .collection("conversations")
          .doc(data.conversationId)
          .collection("messages")
          .add({
            senderUid: uid,
            body: data.body ?? "",
            fromOfflineQueue: true,
            idempotencyKey: data.idempotencyKey,
            sentAt: now,
          });
        break;
      }
      case "rsvp": {
        if (!data.spaceId || !data.eventId) throw new functions.HttpsError("invalid-argument", "spaceId + eventId required for rsvp.");
        docRef = db()
          .collection("spaces")
          .doc(data.spaceId)
          .collection("events")
          .doc(data.eventId)
          .collection("rsvps")
          .doc(uid); // one rsvp per user — idempotent by path
        await docRef.set({
          uid,
          status: "attending",
          fromOfflineQueue: true,
          idempotencyKey: data.idempotencyKey,
          rsvpedAt: now,
        }, { merge: true });
        break;
      }
      case "spaceMessage": {
        if (!data.spaceId || !data.channelId) throw new functions.HttpsError("invalid-argument", "spaceId + channelId required for spaceMessage.");
        docRef = await db()
          .collection("spaces")
          .doc(data.spaceId)
          .collection("channels")
          .doc(data.channelId)
          .collection("messages")
          .add({
            authorUid: uid,
            body: data.body ?? "",
            fromOfflineQueue: true,
            idempotencyKey: data.idempotencyKey,
            sentAt: now,
          });
        break;
      }
      default:
        throw new functions.HttpsError("invalid-argument", `Unknown draftType: ${data.draftType}`);
    }

    // ── Record idempotency key ─────────────────────────────────────────────
    await idemRef.set({
      uid,
      draftType: data.draftType,
      documentId: docRef.id,
      processedAt: now,
    });

    return { status: "ok", documentId: docRef.id };
  }
);
