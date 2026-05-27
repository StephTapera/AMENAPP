// persistentMemoryGraph.ts
// AMEN Spaces Ambient Intelligence — Persistent Memory Graph
//
// Writes layered memory nodes to Firestore.
// Confidence/provenance are always server-assigned.
// Clients read but never write to intelligence fields.

import * as admin from "firebase-admin";
import { v4 as uuidv4 } from "uuid";
import { MemoryNode, MemoryLayer, SpiritualContinuityRecord } from "./types";

const db = admin.firestore();

// MARK: - Memory Node Writes

export interface MemoryNodeInput {
  spaceId: string;
  userId?: string;
  layer: MemoryLayer;
  title: string;
  body: string;
  tags: string[];
  scriptureRefs?: string[];
  relatedNodeIds?: string[];
  confidence: number;
  expiresInDays?: number;
}

/**
 * Persist a memory node to the appropriate Firestore path based on layer.
 * User memory goes to users/{uid}/spaceMemory/{id}.
 * Group/org memory goes to spaces/{spaceId}/memory/{id}.
 */
export async function persistMemoryNode(input: MemoryNodeInput): Promise<string> {
  const id = uuidv4();
  const now = admin.firestore.Timestamp.now();

  let expiresAt: admin.firestore.Timestamp | undefined;
  if (input.expiresInDays) {
    const exp = new Date(Date.now() + input.expiresInDays * 24 * 60 * 60 * 1000);
    expiresAt = admin.firestore.Timestamp.fromDate(exp);
  }

  const node: MemoryNode = {
    id,
    spaceId: input.spaceId,
    userId: input.userId,
    layer: input.layer,
    title: input.title,
    body: input.body,
    tags: input.tags,
    scriptureRefs: input.scriptureRefs ?? [],
    relatedNodeIds: input.relatedNodeIds ?? [],
    confidence: input.confidence,
    generatedAt: now,
    expiresAt,
    dismissed: false,
    provenance: "persistent_memory_graph_v1",
  };

  if (input.userId && (input.layer === "user" || input.layer === "relationship")) {
    await db
      .collection("users").doc(input.userId)
      .collection("spaceMemory").doc(id)
      .set(node);
  } else {
    await db
      .collection("spaces").doc(input.spaceId)
      .collection("memory").doc(id)
      .set(node);
  }

  return id;
}

// MARK: - Memory Node Reads

export async function getSpaceMemoryNodes(
  spaceId: string,
  layer?: MemoryLayer,
  limit = 20
): Promise<MemoryNode[]> {
  let query = db
    .collection("spaces").doc(spaceId)
    .collection("memory")
    .where("dismissed", "==", false)
    .orderBy("confidence", "desc")
    .limit(limit);

  if (layer) {
    query = db
      .collection("spaces").doc(spaceId)
      .collection("memory")
      .where("layer", "==", layer)
      .where("dismissed", "==", false)
      .orderBy("confidence", "desc")
      .limit(limit);
  }

  const snap = await query.get();
  return snap.docs.map((d) => d.data() as MemoryNode);
}

export async function getUserSpaceMemory(
  userId: string,
  spaceId: string,
  limit = 10
): Promise<MemoryNode[]> {
  const snap = await db
    .collection("users").doc(userId)
    .collection("spaceMemory")
    .where("spaceId", "==", spaceId)
    .where("dismissed", "==", false)
    .orderBy("generatedAt", "desc")
    .limit(limit)
    .get();

  return snap.docs.map((d) => d.data() as MemoryNode);
}

// MARK: - Semantic Deduplication

/**
 * Check if a near-duplicate memory node already exists for this space.
 * Uses tag overlap as a cheap similarity proxy (embedding not required).
 */
export async function isDuplicateMemory(spaceId: string, tags: string[]): Promise<boolean> {
  if (tags.length === 0) return false;

  const snap = await db
    .collection("spaces").doc(spaceId)
    .collection("memory")
    .where("dismissed", "==", false)
    .where("tags", "array-contains-any", tags.slice(0, 10))
    .limit(3)
    .get();

  for (const doc of snap.docs) {
    const existing = doc.data() as MemoryNode;
    const overlap = tags.filter((t) => existing.tags.includes(t)).length;
    if (overlap >= Math.ceil(tags.length * 0.6)) return true;
  }

  return false;
}

// MARK: - Spiritual Continuity

export async function upsertSpiritualContinuity(
  userId: string,
  spaceId: string | undefined,
  updates: {
    scriptureThemes?: string[];
    prayerTopics?: string[];
    unfinishedReflections?: string[];
    selahMoments?: number;
  }
): Promise<void> {
  const query = spaceId
    ? db.collection("users").doc(userId).collection("spiritualContinuity")
        .where("spaceId", "==", spaceId).limit(1)
    : db.collection("users").doc(userId).collection("spiritualContinuity")
        .where("spaceId", "==", null).limit(1);

  const snap = await query.get();

  if (!snap.empty) {
    const ref = snap.docs[0].ref;
    const existing = snap.docs[0].data() as SpiritualContinuityRecord;

    const mergedScriptures = [...new Set([...existing.scriptureJourney, ...(updates.scriptureThemes ?? [])])].slice(0, 20);
    const mergedPrayer = [...new Set([...existing.recurringPrayerTopics, ...(updates.prayerTopics ?? [])])].slice(0, 20);
    const mergedReflections = [...new Set([...existing.unfinishedReflections, ...(updates.unfinishedReflections ?? [])])].slice(0, 10);

    await ref.update({
      scriptureJourney: mergedScriptures,
      recurringPrayerTopics: mergedPrayer,
      unfinishedReflections: mergedReflections,
      selahMoments: (existing.selahMoments ?? 0) + (updates.selahMoments ?? 0),
      lastActivityAt: admin.firestore.Timestamp.now(),
    });
  } else {
    const id = uuidv4();
    const record: SpiritualContinuityRecord = {
      id,
      userId,
      spaceId,
      theme: (updates.scriptureThemes ?? [])[0] ?? "Faith journey",
      scriptureJourney: updates.scriptureThemes ?? [],
      recurringPrayerTopics: updates.prayerTopics ?? [],
      unfinishedReflections: updates.unfinishedReflections ?? [],
      selahMoments: updates.selahMoments ?? 0,
      discipleshipContinuityScore: 0.5,
      lastActivityAt: admin.firestore.Timestamp.now(),
      generatedAt: admin.firestore.Timestamp.now(),
      provenance: "persistent_memory_graph_v1",
    };

    await db.collection("users").doc(userId)
      .collection("spiritualContinuity").doc(id)
      .set(record);
  }
}

// MARK: - Expire Old Nodes

export async function expireOldMemoryNodes(spaceId: string): Promise<void> {
  const now = admin.firestore.Timestamp.now();
  const snap = await db
    .collection("spaces").doc(spaceId)
    .collection("memory")
    .where("expiresAt", "<=", now)
    .where("dismissed", "==", false)
    .get();

  const batch = db.batch();
  snap.docs.forEach((doc) => batch.update(doc.ref, { dismissed: true }));
  await batch.commit();
}
