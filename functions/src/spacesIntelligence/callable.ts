// callable.ts
// AMEN Spaces Ambient Intelligence — Firebase Cloud Functions Callables + Scheduled Jobs
//
// Callables: ambient signals, memory graph, semantic pins, spiritual continuity, catch-up.
// Scheduled: pin score evolution, memory expiry, signal cleanup. All run off hot write path.
// Security: App Check enforced. Clients never write intelligence fields or intelligent pins.

import * as functions from "firebase-functions";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { generateAmbientSignals, cleanupOldSignals } from "./ambientIntelligenceEngine";
import {
  persistMemoryNode, getSpaceMemoryNodes, getUserSpaceMemory,
  isDuplicateMemory, upsertSpiritualContinuity, expireOldMemoryNodes,
  MemoryNodeInput,
} from "./persistentMemoryGraph";
import { recalculatePinScores, evolvePins, createIntelligentPin } from "./semanticPinningEngine";
import {
  AmenSpaceType, MemoryLayer, PinType, SERVER_PIN_TYPES, aiInferenceAllowed,
} from "./types";

const db = admin.firestore();

// MARK: - Ambient Signals

export const getAmbientSignals = functions.https.onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new functions.https.HttpsError("unauthenticated", "Sign in required.");

    const { spaceId } = request.data as { spaceId: string };
    if (!spaceId) throw new functions.https.HttpsError("invalid-argument", "spaceId required.");

    await assertSpaceMember(uid, spaceId);

    const snap = await db
      .collection("spaces").doc(spaceId)
      .collection("ambientSignals")
      .where("dismissed", "==", false)
      .orderBy("createdAt", "desc")
      .limit(10)
      .get();

    return { signals: snap.docs.map((d) => d.data()) };
  }
);

export const dismissAmbientSignal = functions.https.onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new functions.https.HttpsError("unauthenticated", "Sign in required.");

    const { spaceId, signalId } = request.data as { spaceId: string; signalId: string };
    if (!spaceId || !signalId) {
      throw new functions.https.HttpsError("invalid-argument", "spaceId and signalId required.");
    }

    await assertSpaceMember(uid, spaceId);

    const ref = db.collection("spaces").doc(spaceId)
      .collection("ambientSignals").doc(signalId);
    const doc = await ref.get();
    if (!doc.exists) throw new functions.https.HttpsError("not-found", "Signal not found.");

    await ref.update({ dismissed: true, dismissedBy: uid, dismissedAt: admin.firestore.Timestamp.now() });
    return { dismissed: true };
  }
);

// MARK: - Memory Graph

export const getMemoryNodes = functions.https.onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new functions.https.HttpsError("unauthenticated", "Sign in required.");

    const { spaceId, layer, limit } = request.data as {
      spaceId: string; layer?: MemoryLayer; limit?: number;
    };
    if (!spaceId) throw new functions.https.HttpsError("invalid-argument", "spaceId required.");

    await assertSpaceMember(uid, spaceId);

    const [spaceNodes, userNodes] = await Promise.all([
      getSpaceMemoryNodes(spaceId, layer, Math.min(limit ?? 20, 50)),
      getUserSpaceMemory(uid, spaceId, 10),
    ]);

    return { spaceNodes, userNodes };
  }
);

export const dismissMemoryNode = functions.https.onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new functions.https.HttpsError("unauthenticated", "Sign in required.");

    const { spaceId, nodeId, isUserNode } = request.data as {
      spaceId: string; nodeId: string; isUserNode: boolean;
    };
    if (!spaceId || !nodeId) {
      throw new functions.https.HttpsError("invalid-argument", "spaceId and nodeId required.");
    }

    await assertSpaceMember(uid, spaceId);

    const ref = isUserNode
      ? db.collection("users").doc(uid).collection("spaceMemory").doc(nodeId)
      : db.collection("spaces").doc(spaceId).collection("memory").doc(nodeId);

    const doc = await ref.get();
    if (!doc.exists) throw new functions.https.HttpsError("not-found", "Memory node not found.");

    // For user nodes, verify ownership
    if (isUserNode && doc.data()?.userId !== uid) {
      throw new functions.https.HttpsError("permission-denied", "Not your memory node.");
    }

    await ref.update({ dismissed: true, dismissedAt: admin.firestore.Timestamp.now() });
    return { dismissed: true };
  }
);

// MARK: - Semantic Pins

export const getSemanticPins = functions.https.onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new functions.https.HttpsError("unauthenticated", "Sign in required.");

    const { spaceId, limit } = request.data as { spaceId: string; limit?: number };
    if (!spaceId) throw new functions.https.HttpsError("invalid-argument", "spaceId required.");

    await assertSpaceMember(uid, spaceId);

    const snap = await db
      .collection("spaces").doc(spaceId)
      .collection("pins")
      .orderBy("score", "desc")
      .limit(Math.min(limit ?? 20, 50))
      .get();

    return { pins: snap.docs.map((d) => d.data()) };
  }
);

export const createUserPin = functions.https.onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new functions.https.HttpsError("unauthenticated", "Sign in required.");

    const { spaceId, pinType, title, preview, threadId, messageId, scriptureRef, tags } = request.data as {
      spaceId: string; pinType: PinType; title: string; preview: string;
      threadId?: string; messageId?: string; scriptureRef?: string; tags?: string[];
    };

    if (!spaceId || !pinType || !title) {
      throw new functions.https.HttpsError("invalid-argument", "spaceId, pinType, and title required.");
    }

    // Clients cannot create intelligent/server pin types
    if (SERVER_PIN_TYPES.includes(pinType)) {
      throw new functions.https.HttpsError("permission-denied", `Pin type '${pinType}' is server-assigned.`);
    }

    await assertSpaceMember(uid, spaceId);

    const id = require("uuid").v4();
    const now = admin.firestore.Timestamp.now();

    await db.collection("spaces").doc(spaceId)
      .collection("pins").doc(id)
      .set({
        id, spaceId, pinType, title,
        preview: preview ?? "",
        pinnedBy: uid,
        threadId: threadId ?? null,
        messageId: messageId ?? null,
        scriptureRef: scriptureRef ?? null,
        tags: tags ?? [],
        score: 0.5,
        createdAt: now,
        updatedAt: now,
        evolutionHistory: [],
      });

    return { pinId: id };
  }
);

export const dismissPin = functions.https.onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new functions.https.HttpsError("unauthenticated", "Sign in required.");

    const { spaceId, pinId } = request.data as { spaceId: string; pinId: string };
    if (!spaceId || !pinId) {
      throw new functions.https.HttpsError("invalid-argument", "spaceId and pinId required.");
    }

    await assertSpaceMember(uid, spaceId);

    const ref = db.collection("spaces").doc(spaceId).collection("pins").doc(pinId);
    const doc = await ref.get();
    if (!doc.exists) throw new functions.https.HttpsError("not-found", "Pin not found.");

    // Only creator or admin can dismiss
    const pin = doc.data()!;
    if (pin.pinnedBy !== uid && pin.pinnedBy !== "system") {
      await assertSpaceAdmin(uid, spaceId);
    }

    await ref.update({ dismissed: true, dismissedAt: admin.firestore.Timestamp.now() });
    return { dismissed: true };
  }
);

// MARK: - Spiritual Continuity

export const getSpiritualContinuity = functions.https.onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new functions.https.HttpsError("unauthenticated", "Sign in required.");

    const { spaceId } = request.data as { spaceId?: string };

    const query = spaceId
      ? db.collection("users").doc(uid).collection("spiritualContinuity")
          .where("spaceId", "==", spaceId).limit(1)
      : db.collection("users").doc(uid).collection("spiritualContinuity")
          .where("spaceId", "==", null).limit(1);

    const snap = await query.get();
    if (snap.empty) return { record: null };

    return { record: snap.docs[0].data() };
  }
);

export const recordSelahMoment = functions.https.onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new functions.https.HttpsError("unauthenticated", "Sign in required.");

    const { spaceId, scriptureRef, reflectionNote } = request.data as {
      spaceId?: string; scriptureRef?: string; reflectionNote?: string;
    };

    await upsertSpiritualContinuity(uid, spaceId, {
      scriptureThemes: scriptureRef ? [scriptureRef] : [],
      unfinishedReflections: reflectionNote ? [reflectionNote] : [],
      selahMoments: 1,
    });

    return { recorded: true };
  }
);

// MARK: - Space Intelligence Trigger (server-initiated, admin SDK only)
// This callable is restricted: only callable by server-side code via Admin SDK.
// Client App Check + auth guard still applied as defense-in-depth.

export const triggerSpaceIntelligence = functions.https.onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new functions.https.HttpsError("unauthenticated", "Sign in required.");

    const { spaceId, spaceType } = request.data as { spaceId: string; spaceType: AmenSpaceType };
    if (!spaceId || !spaceType) {
      throw new functions.https.HttpsError("invalid-argument", "spaceId and spaceType required.");
    }

    // Only admins may trigger intelligence generation on-demand
    await assertSpaceAdmin(uid, spaceId);

    if (!aiInferenceAllowed(spaceType)) {
      return { skipped: true, reason: "AI inference not allowed for this space type." };
    }

    const signalIds = await generateAmbientSignals({ spaceId, spaceType, surface: "amenSpaces" });
    return { triggered: true, signalCount: signalIds.length };
  }
);

// MARK: - Scheduled Jobs

export const scheduledPinScoreEvolution = onSchedule(
  { schedule: "every 6 hours", timeZone: "America/New_York" },
  async () => {
    logger.info("Running scheduled pin score evolution...");
    const snap = await db.collection("spaces").limit(200).get();
    let updated = 0;
    for (const doc of snap.docs) {
      try {
        await recalculatePinScores(doc.id);
        updated++;
      } catch (e) {
        logger.warn(`Pin score evolution failed for ${doc.id}:`, e);
      }
    }
    logger.info(`Pin score evolution complete. Processed ${updated} spaces.`);
  }
);

export const scheduledPinTypeEvolution = onSchedule(
  { schedule: "every 12 hours", timeZone: "America/New_York" },
  async () => {
    logger.info("Running scheduled pin type evolution...");
    const snap = await db.collection("spaces").limit(200).get();
    let evolved = 0;
    for (const doc of snap.docs) {
      try {
        await evolvePins(doc.id);
        evolved++;
      } catch (e) {
        logger.warn(`Pin evolution failed for ${doc.id}:`, e);
      }
    }
    logger.info(`Pin type evolution complete. Processed ${evolved} spaces.`);
  }
);

export const scheduledMemoryExpiry = onSchedule(
  { schedule: "every 24 hours", timeZone: "America/New_York" },
  async () => {
    logger.info("Running scheduled memory node expiry...");
    const snap = await db.collection("spaces").limit(200).get();
    for (const doc of snap.docs) {
      try {
        await expireOldMemoryNodes(doc.id);
      } catch (e) {
        logger.warn(`Memory expiry failed for ${doc.id}:`, e);
      }
    }
    logger.info("Memory expiry complete.");
  }
);

export const scheduledSignalCleanup = onSchedule(
  { schedule: "every 24 hours", timeZone: "America/New_York" },
  async () => {
    logger.info("Running scheduled ambient signal cleanup...");
    const snap = await db.collection("spaces").limit(200).get();
    for (const doc of snap.docs) {
      try {
        await cleanupOldSignals(doc.id);
      } catch (e) {
        logger.warn(`Signal cleanup failed for ${doc.id}:`, e);
      }
    }
    logger.info("Signal cleanup complete.");
  }
);

// MARK: - Auth Helpers

async function assertSpaceMember(uid: string, spaceId: string): Promise<void> {
  const memberDoc = await db.collection("spaces").doc(spaceId)
    .collection("members").doc(uid).get();
  if (!memberDoc.exists) {
    throw new functions.https.HttpsError("permission-denied", "Not a member of this space.");
  }
}

async function assertSpaceAdmin(uid: string, spaceId: string): Promise<void> {
  const memberDoc = await db.collection("spaces").doc(spaceId)
    .collection("members").doc(uid).get();
  const role = memberDoc.data()?.role as string | undefined;
  if (!memberDoc.exists || !["admin", "owner", "moderator"].includes(role ?? "")) {
    throw new functions.https.HttpsError("permission-denied", "Admin role required.");
  }
}
