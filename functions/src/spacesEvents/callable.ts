// callable.ts — Spaces Events callable Cloud Functions

import * as functions from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";

const db = getFirestore();

// ── Interfaces ────────────────────────────────────────────────────────────────

interface CreateSpaceEventInput {
  spaceId: string;
  title: string;
  description: string;
  type: string;
  scheduledAt: number;
  durationMinutes: number;
  isRecurring: boolean;
  recurrenceRule?: string;
  maxAttendees?: number;
  requiredTierId?: string;
}

interface RsvpToEventInput {
  spaceId: string;
  eventId: string;
}

interface SendEventBroadcastInput {
  spaceId: string;
  message: string;
  attachedEventId?: string;
}

interface ListUpcomingEventsInput {
  spaceId: string;
  limit?: number;
}

interface EventDoc {
  id: string;
  spaceId: string;
  hostUserId: string;
  title: string;
  eventDescription: string;
  type: string;
  scheduledAt: FirebaseFirestore.Timestamp;
  durationMinutes: number;
  isRecurring: boolean;
  recurrenceRule: string | null;
  rsvpUserIds: string[];
  isLive: boolean;
  maxAttendees: number | null;
  requiredTierId: string | null;
  createdAt: FirebaseFirestore.FieldValue;
  updatedAt: FirebaseFirestore.FieldValue;
}

interface SpaceDoc {
  memberIds?: string[];
  hostUserId?: string;
}

// ── createSpaceEvent ──────────────────────────────────────────────────────────

export const createSpaceEvent = functions.onCall(
  { enforceAppCheck: false },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as CreateSpaceEventInput;

    const spaceId = String(data?.spaceId ?? "").trim();
    if (!spaceId) throw new functions.HttpsError("invalid-argument", "spaceId is required.");

    const title = String(data?.title ?? "").trim();
    if (!title || title.length < 1 || title.length > 100) {
      throw new functions.HttpsError("invalid-argument", "title must be 1–100 characters.");
    }

    const description = String(data?.description ?? "").trim();
    const type = String(data?.type ?? "").trim();
    if (!type) throw new functions.HttpsError("invalid-argument", "type is required.");

    const scheduledAt = Number(data?.scheduledAt ?? 0);
    if (!Number.isFinite(scheduledAt) || scheduledAt <= Date.now()) {
      throw new functions.HttpsError("invalid-argument", "scheduledAt must be a future Unix timestamp in milliseconds.");
    }

    const durationMinutes = Number(data?.durationMinutes ?? 0);
    if (!Number.isInteger(durationMinutes) || durationMinutes < 1 || durationMinutes > 480) {
      throw new functions.HttpsError("invalid-argument", "durationMinutes must be between 1 and 480.");
    }

    const isRecurring = Boolean(data?.isRecurring);
    const recurrenceRule = data?.recurrenceRule ? String(data.recurrenceRule).trim() : null;
    const maxAttendees = data?.maxAttendees != null ? Number(data.maxAttendees) : null;
    const requiredTierId = data?.requiredTierId ? String(data.requiredTierId).trim() : null;

    const eventId = db.collection("spaces").doc(spaceId).collection("events").doc().id;

    const eventDoc: EventDoc = {
      id: eventId,
      spaceId,
      hostUserId: userId,
      title,
      eventDescription: description,
      type,
      scheduledAt: Timestamp.fromMillis(scheduledAt),
      durationMinutes,
      isRecurring,
      recurrenceRule,
      rsvpUserIds: [],
      isLive: false,
      maxAttendees,
      requiredTierId,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };

    await db.collection("spaces").doc(spaceId).collection("events").doc(eventId).set(eventDoc);
    logger.info(`createSpaceEvent: eventId=${eventId} spaceId=${spaceId} userId=${userId}`);

    return { eventId, ok: true };
  }
);

// ── rsvpToEvent ───────────────────────────────────────────────────────────────

export const rsvpToEvent = functions.onCall(
  { enforceAppCheck: false },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as RsvpToEventInput;
    const spaceId = String(data?.spaceId ?? "").trim();
    const eventId = String(data?.eventId ?? "").trim();

    if (!spaceId) throw new functions.HttpsError("invalid-argument", "spaceId is required.");
    if (!eventId) throw new functions.HttpsError("invalid-argument", "eventId is required.");

    const eventRef = db.collection("spaces").doc(spaceId).collection("events").doc(eventId);
    const rsvpRef = db
      .collection("spaces").doc(spaceId)
      .collection("events").doc(eventId)
      .collection("rsvps").doc(userId);

    const batch = db.batch();
    batch.update(eventRef, {
      rsvpUserIds: FieldValue.arrayUnion(userId),
      updatedAt: FieldValue.serverTimestamp(),
    });
    batch.set(rsvpRef, {
      userId,
      eventId,
      spaceId,
      rsvpAt: FieldValue.serverTimestamp(),
      calendarAdded: false,
    });
    await batch.commit();

    logger.info(`rsvpToEvent: userId=${userId} eventId=${eventId} spaceId=${spaceId}`);
    return { ok: true };
  }
);

// ── sendEventBroadcast ────────────────────────────────────────────────────────

export const sendEventBroadcast = functions.onCall(
  { enforceAppCheck: false },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as SendEventBroadcastInput;
    const spaceId = String(data?.spaceId ?? "").trim();
    const message = String(data?.message ?? "").trim();
    const attachedEventId = data?.attachedEventId ? String(data.attachedEventId).trim() : null;

    if (!spaceId) throw new functions.HttpsError("invalid-argument", "spaceId is required.");
    if (!message || message.length < 1 || message.length > 500) {
      throw new functions.HttpsError("invalid-argument", "message must be 1–500 characters.");
    }

    // Fetch space to get memberIds
    const spaceSnap = await db.collection("spaces").doc(spaceId).get();
    if (!spaceSnap.exists) {
      throw new functions.HttpsError("not-found", "Space not found.");
    }
    const spaceData = spaceSnap.data() as SpaceDoc;
    const memberIds: string[] = Array.isArray(spaceData?.memberIds) ? spaceData.memberIds : [];

    const broadcastId = db.collection("spaces").doc(spaceId).collection("broadcasts").doc().id;
    const broadcastRef = db
      .collection("spaces").doc(spaceId)
      .collection("broadcasts").doc(broadcastId);
    const notifRef = db
      .collection("spaces").doc(spaceId)
      .collection("pendingNotifications").doc();

    const batch = db.batch();
    batch.set(broadcastRef, {
      spaceId,
      senderId: userId,
      message,
      attachedEventId,
      recipientCount: memberIds.length,
      sentAt: FieldValue.serverTimestamp(),
    });
    batch.set(notifRef, {
      broadcastId,
      spaceId,
      senderId: userId,
      message,
      attachedEventId,
      memberIds,
      queuedAt: FieldValue.serverTimestamp(),
      processed: false,
    });
    await batch.commit();

    logger.info(`sendEventBroadcast: broadcastId=${broadcastId} spaceId=${spaceId} recipients=${memberIds.length}`);
    return { broadcastId, ok: true, recipientCount: memberIds.length };
  }
);

// ── listUpcomingEvents ────────────────────────────────────────────────────────

export const listUpcomingEvents = functions.onCall(
  { enforceAppCheck: false },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as ListUpcomingEventsInput;
    const spaceId = String(data?.spaceId ?? "").trim();
    if (!spaceId) throw new functions.HttpsError("invalid-argument", "spaceId is required.");

    const rawLimit = data?.limit != null ? Number(data.limit) : 20;
    const limit = Math.min(Math.max(1, rawLimit), 50);

    const now = Timestamp.now();
    const eventsSnap = await db
      .collection("spaces").doc(spaceId)
      .collection("events")
      .where("scheduledAt", ">", now)
      .orderBy("scheduledAt", "asc")
      .limit(limit)
      .get();

    const events = eventsSnap.docs.map((doc) => doc.data() as EventDoc);
    return { events };
  }
);
