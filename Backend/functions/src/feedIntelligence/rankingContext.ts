import * as admin from "firebase-admin";
import type { FeedIntelligenceProfile } from "./types";

export async function buildRankingContext(uid: string): Promise<Record<string, unknown>> {
  const db = admin.firestore();
  const profileSnap = await db.doc(`users/${uid}/feedIntelligence/profile/main`).get();

  if (!profileSnap.exists) {
    return {
      activePreferenceSignalIds: [],
      activeModes: [],
      suppressedTopics: [],
      boostedTopics: [],
      feedHealthMode: null,
    };
  }

  const profile = profileSnap.data() as FeedIntelligenceProfile;
  const now = new Date();

  // Fetch active signals
  const signalsSnap = await db
    .collection(`users/${uid}/feedIntelligence/signals`)
    .where("status", "==", "active")
    .orderBy("createdAt", "desc")
    .limit(20)
    .get();

  const activeSignalIds: string[] = [];
  for (const doc of signalsSnap.docs) {
    const data = doc.data();
    if (data.expiresAt && data.expiresAt.toDate() < now) {
      // Mark expired
      await doc.ref.update({ status: "expired", updatedAt: admin.firestore.FieldValue.serverTimestamp() });
    } else {
      activeSignalIds.push(doc.id);
    }
  }

  const feedHealthMode = profile.feedHealth.preferCalmContent
    ? "calm"
    : profile.feedHealth.reduceOutrage
    ? "reduced_outrage"
    : null;

  return {
    activePreferenceSignalIds: activeSignalIds,
    activeModes: profile.activeModes ?? [],
    suppressedTopics: Object.keys(profile.suppressedTopics ?? {}),
    boostedTopics: Object.keys(profile.boostedTopics ?? {}),
    feedHealthMode,
  };
}

export function scorePostForUser(
  profile: FeedIntelligenceProfile,
  postMetadata: Record<string, number>
): number {
  let adjustment = 0;

  // Topic boosts
  for (const [topic, boost] of Object.entries(profile.boostedTopics ?? {})) {
    const postScore = postMetadata[topic] ?? 0;
    adjustment += boost * postScore;
  }

  // Topic suppressions
  for (const [topic, suppress] of Object.entries(profile.suppressedTopics ?? {})) {
    const postScore = postMetadata[topic] ?? 0;
    adjustment -= suppress * postScore;
  }

  // Feed health
  if (profile.feedHealth.reduceOutrage) {
    adjustment -= (postMetadata["outrageScore"] ?? 0) * 2.0;
    adjustment -= (postMetadata["conflictScore"] ?? 0) * 1.5;
  }
  if (profile.feedHealth.preferCalmContent) {
    adjustment -= (postMetadata["emotionalIntensity"] ?? 0) * 1.5;
    adjustment += (postMetadata["worshipScore"] ?? 0) * 0.8;
    adjustment += (postMetadata["devotionalScore"] ?? 0) * 0.8;
  }

  return adjustment;
}
