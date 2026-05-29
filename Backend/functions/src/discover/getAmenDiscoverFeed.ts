import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { applyDiversity } from "./discoverDiversity";
import { retrieveDiscoverCandidates } from "./discoverCandidateRetrieval";
import { rankScore } from "./discoverRanking";
import { isDiscoverEligible } from "./discoverSafety";
import { DiscoverItemDoc, DiscoverMetadata } from "./discoverTypes";
import { logDiscoverTelemetry } from "./discoverTelemetry";

function requireAuth(request: { auth?: { uid?: string } }): string {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");
  return uid;
}

function assertInput(data: any): void {
  if (data?.surface !== "discover") throw new HttpsError("invalid-argument", "surface must be discover");
}

async function checkRate(uid: string): Promise<void> {
  const db = admin.firestore();
  const since = admin.firestore.Timestamp.fromMillis(Date.now() - 60_000);
  const count = await db.collection(`users/${uid}/discoverEvents`).where("createdAt", ">=", since).count().get();
  if (count.data().count > 80) throw new HttpsError("resource-exhausted", "Rate limit exceeded.");
}

async function readMetadata(itemId: string): Promise<DiscoverMetadata | null> {
  const db = admin.firestore();
  const snap = await db.doc(`recommendationMetadata/discover/items/${itemId}`).get();
  if (!snap.exists) return null;
  return snap.data() as DiscoverMetadata;
}

function toResponseItem(item: DiscoverItemDoc, meta: DiscoverMetadata): Record<string, unknown> {
  const badges = new Set<string>(item.badges ?? []);
  if (meta.aiAssisted) badges.add("ai_assisted");
  if (meta.scriptureRefsApproved) badges.add("scripture_linked");
  if (meta.bereanReviewed) badges.add("berean_reviewed");

  return {
    id: item.id,
    sourceId: item.sourceId,
    sourceType: item.sourceType,
    type: item.type,
    title: item.title,
    subtitle: item.subtitle ?? null,
    caption: item.caption ?? null,
    media: item.media ?? {},
    author: item.author ?? null,
    church: item.church ?? null,
    topics: item.topics ?? [],
    scriptureRefs: item.scriptureRefs ?? [],
    badges: Array.from(badges),
    createdAtSeconds: item.createdAt?.seconds ?? Math.floor(Date.now() / 1000),
  };
}

export const getAmenDiscoverFeed = onCall({ enforceAppCheck: true, timeoutSeconds: 30, memory: "512MiB" }, async (request) => {
  const uid = requireAuth(request);
  assertInput(request.data);
  await checkRate(uid);

  const start = Date.now();
  const rawCandidates = await retrieveDiscoverCandidates();

  const defaultMeta: DiscoverMetadata = {
    qualityScore: 0.65,
    safetyScore: 0.80,
    originalityScore: 0.55,
    spiritualUsefulnessScore: 0.70,
    creatorTrustScore: 0.70,
    freshnessScore: 0.60,
    moderationStatus: "approved",
    recommendationEligible: true,
  };

  const ranked: Array<{ item: DiscoverItemDoc; score: number }> = [];
  let filteredSafety = 0;

  for (const item of rawCandidates) {
    const meta = await readMetadata(item.id) ?? defaultMeta;
    if (!isDiscoverEligible(item, meta)) {
      filteredSafety += 1;
      continue;
    }
    ranked.push({ item, score: rankScore(meta) });
  }

  ranked.sort((a, b) => b.score - a.score);
  const diversified = applyDiversity(ranked.map((r) => r.item)).slice(0, 36);

  const items = [] as Record<string, unknown>[];
  for (const item of diversified) {
    const meta = await readMetadata(item.id) ?? defaultMeta;
    items.push(toResponseItem(item, meta));
  }

  logDiscoverTelemetry("feed_generated", {
    uid,
    candidate_count: rawCandidates.length,
    filtered_count: rawCandidates.length - items.length,
    safety_filtered_count: filteredSafety,
    ranking_count: ranked.length,
    latency_ms: Date.now() - start,
  });

  const sessionId = String(request.data?.sessionId ?? admin.firestore().collection("discoverSessions").doc().id);
  await admin.firestore().doc(`discoverSessions/${sessionId}`).set({
    uid,
    surface: "discover",
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  return {
    sessionId,
    items,
    nextCursor: null,
    rankingContext: { strategy: "deterministic_baseline_v1" },
    feedbackAffordances: ["not_for_me", "too_intense", "repetitive", "theologically_unclear", "report"],
    layout: { style: "adaptive_grid" },
  };
});
