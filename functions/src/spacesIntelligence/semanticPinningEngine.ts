// semanticPinningEngine.ts
// AMEN Spaces Ambient Intelligence — Semantic Pinning Engine
//
// Server-side logic for intelligent pin creation, evolution, and scoring.
// Clients can create user pins (spiritual/org types) but not intelligent pins.
// Score evolution runs on a schedule, not on every message write.

import * as admin from "firebase-admin";
import { v4 as uuidv4 } from "uuid";
import { SemanticPin, PinType, SERVER_PIN_TYPES, PinEvolutionEvent } from "./types";

const db = admin.firestore();

// MARK: - Pin Scoring

/**
 * Recalculates pin scores based on reference frequency, recency, and participant engagement.
 * Runs as a scheduled job — not on hot write path.
 */
export async function recalculatePinScores(spaceId: string): Promise<void> {
  const pinsSnap = await db
    .collection("spaces").doc(spaceId)
    .collection("pins")
    .orderBy("score", "desc")
    .get();

  if (pinsSnap.empty) return;

  const batch = db.batch();
  const windowStart = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);

  for (const doc of pinsSnap.docs) {
    const pin = doc.data() as SemanticPin;
    const newScore = await computePinScore(pin, windowStart);

    if (Math.abs(newScore - pin.score) > 0.05) {
      batch.update(doc.ref, {
        score: newScore,
        updatedAt: admin.firestore.Timestamp.now(),
      });
    }
  }

  await batch.commit();
}

async function computePinScore(pin: SemanticPin, since: Date): Promise<number> {
  let score = 0.5;

  // Boost for recent thread activity
  if (pin.threadId) {
    const threadActivity = await db
      .collection("spaces").doc(pin.spaceId)
      .collection("messages")
      .where("threadId", "==", pin.threadId)
      .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(since))
      .get();
    score += Math.min(threadActivity.size * 0.03, 0.3);
  }

  // Boost for message references
  if (pin.messageId) {
    const refs = await db
      .collection("spaces").doc(pin.spaceId)
      .collection("messages")
      .where("referencedMessageIds", "array-contains", pin.messageId)
      .get();
    score += Math.min(refs.size * 0.05, 0.2);
  }

  // Decay for age
  const createdAt = (pin.createdAt as unknown as admin.firestore.Timestamp).toDate();
  const ageDays = (Date.now() - createdAt.getTime()) / (1000 * 60 * 60 * 24);
  score *= Math.max(1 - ageDays * 0.01, 0.3);

  return Math.min(Math.max(score, 0.1), 1.0);
}

// MARK: - Pin Evolution

/**
 * Evaluates whether intelligent pins should evolve to a new type.
 * Example: unresolved → resolved, momentum_building → fading_urgency
 */
export async function evolvePins(spaceId: String): Promise<void> {
  const pinsSnap = await db
    .collection("spaces").doc(spaceId)
    .collection("pins")
    .where("pinType", "in", SERVER_PIN_TYPES)
    .get();

  if (pinsSnap.empty) return;

  const batch = db.batch();

  for (const doc of pinsSnap.docs) {
    const pin = doc.data() as SemanticPin;
    const evolution = await computeEvolution(pin);
    if (!evolution) continue;

    const evt: PinEvolutionEvent = {
      fromType: pin.pinType,
      toType: evolution.newType,
      reason: evolution.reason,
      occurredAt: admin.firestore.Timestamp.now(),
    };

    batch.update(doc.ref, {
      pinType: evolution.newType,
      evolutionHistory: admin.firestore.FieldValue.arrayUnion(evt),
      score: evolution.newScore,
      updatedAt: admin.firestore.Timestamp.now(),
    });
  }

  await batch.commit();
}

async function computeEvolution(
  pin: SemanticPin
): Promise<{ newType: PinType; reason: string; newScore: number } | null> {
  switch (pin.pinType) {
    case "unresolved": {
      // Check if follow-up happened
      if (!pin.threadId) return null;
      const recent = await db
        .collection("spaces").doc(pin.spaceId)
        .collection("messages")
        .where("threadId", "==", pin.threadId)
        .orderBy("createdAt", "desc")
        .limit(1)
        .get();
      if (recent.empty) return null;
      const lastMsg = recent.docs[0].data();
      const isRecent = (lastMsg.createdAt as admin.firestore.Timestamp).toDate() > new Date(Date.now() - 48 * 60 * 60 * 1000);
      if (isRecent) {
        return { newType: "resolved", reason: "Recent activity suggests this item was addressed.", newScore: 0.3 };
      }
      return null;
    }

    case "momentum_building": {
      const windowStart = new Date(Date.now() - 3 * 24 * 60 * 60 * 1000);
      if (!pin.threadId) return null;
      const recentActivity = await db
        .collection("spaces").doc(pin.spaceId)
        .collection("messages")
        .where("threadId", "==", pin.threadId)
        .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(windowStart))
        .get();
      if (recentActivity.size < 2) {
        return { newType: "fading_urgency", reason: "Activity has slowed.", newScore: 0.35 };
      }
      return null;
    }

    default:
      return null;
  }
}

// MARK: - Server-Generated Intelligent Pins

export async function createIntelligentPin(
  spaceId: string,
  pinType: PinType,
  title: string,
  preview: string,
  options: {
    threadId?: string;
    messageId?: string;
    scriptureRef?: string;
    tags?: string[];
    score?: number;
  } = {}
): Promise<string> {
  if (!SERVER_PIN_TYPES.includes(pinType)) {
    throw new Error(`createIntelligentPin: ${pinType} is not a server pin type.`);
  }

  const id = uuidv4();
  const now = admin.firestore.Timestamp.now();

  const pin: SemanticPin = {
    id,
    spaceId,
    threadId: options.threadId,
    messageId: options.messageId,
    pinnedBy: "system",
    pinType,
    title,
    preview,
    tags: options.tags ?? [],
    scriptureRef: options.scriptureRef,
    score: options.score ?? 0.75,
    createdAt: now,
    updatedAt: now,
    evolutionHistory: [],
  };

  await db
    .collection("spaces").doc(spaceId)
    .collection("pins").doc(id)
    .set(pin);

  return id;
}
