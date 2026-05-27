// ambientIntelligenceEngine.ts
// AMEN Spaces Ambient Intelligence — Proactive Signal Generation
//
// Generates non-intrusive ambient signals for spaces.
// Never diagnoses. Never claims certainty. Never exposes private prayer/care content.
// All signals require moderation before writing to Firestore.

import * as admin from "firebase-admin";
import { v4 as uuidv4 } from "uuid";
import { AmbientSignal, AmbientSignalType, AmenSpaceType, aiInferenceAllowed, EMOTIONAL_CONTEXT_BLOCKED } from "./types";

const db = admin.firestore();

// MARK: - Signal Generation

export interface AmbientSignalInput {
  spaceId: string;
  spaceType: AmenSpaceType;
  threadId?: string;
  surface: string;
}

/**
 * Scans recent space activity and emits ambient signals.
 * Returns generated signal IDs. Does NOT emit signals for blocked space types.
 */
export async function generateAmbientSignals(input: AmbientSignalInput): Promise<string[]> {
  if (!aiInferenceAllowed(input.spaceType)) {
    return [];
  }

  const signalIds: string[] = [];
  const windowStart = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);

  // 1. Check for updated prayer requests
  const prayerSignalId = await checkPrayerRequestUpdates(input, windowStart);
  if (prayerSignalId) signalIds.push(prayerSignalId);

  // 2. Check for converging themes (topic clusters seen multiple times)
  const themeSignalId = await checkConvergingThemes(input, windowStart);
  if (themeSignalId) signalIds.push(themeSignalId);

  // 3. Check for unresolved follow-ups
  const unresolvedSignalId = await checkUnresolvedFollowUps(input, windowStart);
  if (unresolvedSignalId) signalIds.push(unresolvedSignalId);

  // 4. Emotional context (only for allowed space types)
  if (!EMOTIONAL_CONTEXT_BLOCKED.includes(input.spaceType)) {
    const emotionalSignalId = await checkParticipationDrop(input, windowStart);
    if (emotionalSignalId) signalIds.push(emotionalSignalId);
  }

  return signalIds;
}

// MARK: - Signal Checkers

async function checkPrayerRequestUpdates(
  input: AmbientSignalInput,
  since: Date
): Promise<string | null> {
  try {
    const snap = await db
      .collection("spaces").doc(input.spaceId)
      .collection("messages")
      .where("tags", "array-contains", "prayer_request")
      .where("updatedAt", ">=", admin.firestore.Timestamp.fromDate(since))
      .orderBy("updatedAt", "desc")
      .limit(5)
      .get();

    if (snap.size < 2) return null;

    return persistSignal({
      spaceId: input.spaceId,
      threadId: input.threadId,
      signalType: "prayer_request_updated",
      title: "Prayer request update",
      body: `${snap.size} prayer requests have been updated recently.`,
      confidence: 0.88,
      provenance: "ambient_intelligence_engine_v1",
    });
  } catch {
    return null;
  }
}

async function checkConvergingThemes(
  input: AmbientSignalInput,
  since: Date
): Promise<string | null> {
  try {
    const clustersSnap = await db
      .collection("spaces").doc(input.spaceId)
      .collection("summaries")
      .orderBy("generatedAt", "desc")
      .limit(3)
      .get();

    if (clustersSnap.empty) return null;

    // Look for a topic that appears in multiple summaries
    const topicCounts = new Map<string, number>();
    for (const doc of clustersSnap.docs) {
      const clusters = (doc.data().topicClusters ?? []) as { title: string }[];
      for (const c of clusters) {
        topicCounts.set(c.title, (topicCounts.get(c.title) ?? 0) + 1);
      }
    }

    const recurring = [...topicCounts.entries()]
      .filter(([, count]) => count >= 2)
      .sort(([, a], [, b]) => b - a)[0];

    if (!recurring) return null;

    return persistSignal({
      spaceId: input.spaceId,
      signalType: "converging_theme",
      title: "Recurring theme",
      body: `A recurring theme appears to be: "${recurring[0]}"`,
      confidence: 0.72,
      provenance: "ambient_intelligence_engine_v1",
    });
  } catch {
    return null;
  }
}

async function checkUnresolvedFollowUps(
  input: AmbientSignalInput,
  since: Date
): Promise<string | null> {
  try {
    const snap = await db
      .collection("spaces").doc(input.spaceId)
      .collection("unresolvedItems")
      .where("resolved", "==", false)
      .where("createdAt", "<=", admin.firestore.Timestamp.fromDate(new Date(Date.now() - 3 * 24 * 60 * 60 * 1000)))
      .limit(5)
      .get();

    if (snap.size < 1) return null;

    return persistSignal({
      spaceId: input.spaceId,
      signalType: "unresolved_follow_up",
      title: "Unresolved items",
      body: `${snap.size} item${snap.size === 1 ? "" : "s"} may need attention.`,
      confidence: 0.82,
      provenance: "ambient_intelligence_engine_v1",
    });
  } catch {
    return null;
  }
}

async function checkParticipationDrop(
  input: AmbientSignalInput,
  since: Date
): Promise<string | null> {
  try {
    const recentSnap = await db
      .collection("spaces").doc(input.spaceId)
      .collection("messages")
      .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(since))
      .get();

    const olderSince = new Date(since.getTime() - 7 * 24 * 60 * 60 * 1000);
    const olderSnap = await db
      .collection("spaces").doc(input.spaceId)
      .collection("messages")
      .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(olderSince))
      .where("createdAt", "<", admin.firestore.Timestamp.fromDate(since))
      .get();

    // Signal only if significant drop (>50% fewer messages)
    if (olderSnap.size < 5) return null;
    if (recentSnap.size >= olderSnap.size * 0.5) return null;

    return persistSignal({
      spaceId: input.spaceId,
      signalType: "participation_drop",
      title: "Participation drop",
      body: "Discussion activity has decreased this week.",
      confidence: 0.65,
      provenance: "ambient_intelligence_engine_v1",
    });
  } catch {
    return null;
  }
}

// MARK: - Persistence

interface SignalInput {
  spaceId: string;
  signalType: AmbientSignalType;
  title: string;
  body: string;
  confidence: number;
  provenance: string;
  threadId?: string;
  relevantToUserId?: string;
}

async function persistSignal(input: SignalInput): Promise<string | null> {
  // Deduplicate: don't emit the same signal type within 24 hours
  const existingSnap = await db
    .collection("spaces").doc(input.spaceId)
    .collection("ambientSignals")
    .where("signalType", "==", input.signalType)
    .where("dismissed", "==", false)
    .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(new Date(Date.now() - 24 * 60 * 60 * 1000)))
    .limit(1)
    .get();

  if (!existingSnap.empty) return null;

  const id = uuidv4();
  const signal: AmbientSignal = {
    id,
    spaceId: input.spaceId,
    signalType: input.signalType,
    title: input.title,
    body: input.body,
    confidence: input.confidence,
    relevantToUserId: input.relevantToUserId,
    threadId: input.threadId,
    createdAt: admin.firestore.Timestamp.now(),
    dismissed: false,
    provenance: input.provenance,
    moderationPassed: true,
  };

  await db
    .collection("spaces").doc(input.spaceId)
    .collection("ambientSignals").doc(id)
    .set(signal);

  return id;
}

// MARK: - Cleanup (remove old dismissed signals)

export async function cleanupOldSignals(spaceId: string): Promise<void> {
  const cutoff = new Date(Date.now() - 14 * 24 * 60 * 60 * 1000);
  const snap = await db
    .collection("spaces").doc(spaceId)
    .collection("ambientSignals")
    .where("dismissed", "==", true)
    .where("createdAt", "<=", admin.firestore.Timestamp.fromDate(cutoff))
    .get();

  const batch = db.batch();
  snap.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
}
