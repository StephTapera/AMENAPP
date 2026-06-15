// searchDiscovery.ts
// AMEN Connect Discovery — Search Cloud Function
// Returns suggested (pre-typing) + browse shelves + Algolia instant results (post-typing)
// Region: us-east1

import * as functions from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

import {
  DiscoveryCard,
  DiscoveryCardType,
  DiscoverySearchResult,
  DiscoveryShelf,
} from "./contracts";
import { filterAndStamp } from "./safetyStamper";
import { Candidate } from "./contracts";
import { freshnessScore } from "./formationRanker";

interface SearchRequest {
  query?: string;           // empty/undefined = pre-typing suggested mode
  geohash?: string;
  interests?: string[];
  limit?: number;
}

export const searchDiscovery = functions.onCall(
  { region: "us-east1", timeoutSeconds: 10, memory: "256MiB" },
  async (request): Promise<DiscoverySearchResult> => {
    if (!request.auth?.uid) {
      throw new functions.HttpsError("unauthenticated", "Must be signed in.");
    }

    const data = request.data as SearchRequest;
    const db = admin.firestore();
    const q = (data.query ?? "").trim().toLowerCase();

    if (!q) {
      return buildPreTypingResult(db, data);
    }

    return buildSearchResult(db, q, data);
  }
);

// ── Pre-typing: suggested + browse ──────────────────────────────────

async function buildPreTypingResult(
  db: admin.firestore.Firestore,
  data: SearchRequest
): Promise<DiscoverySearchResult> {
  const [nearbyChurches, trendingSpaces, liveRooms] = await Promise.all([
    fetchNearbyChurches(db, data.geohash),
    fetchTrendingSpaces(db),
    fetchLiveRoomsSearch(db),
  ]);

  const allCandidates = [...liveRooms, ...nearbyChurches, ...trendingSpaces];
  const stamped = await filterAndStamp(allCandidates);
  const suggested = stamped.slice(0, 6).map(({ candidate, stamp }) =>
    candidateToCard(candidate, stamp)
  );

  const browseShelves: DiscoveryShelf[] = [
    {
      id: "browse-live",
      kind: "liveNow",
      title: "Live Now",
      subtitle: "Rooms happening right now",
      style: "carousel",
      items: stamped
        .filter((s) => s.candidate.type === "audioRoom" || s.candidate.type === "prayerRoom")
        .slice(0, 8)
        .map(({ candidate, stamp }) => candidateToCard(candidate, stamp)),
    },
    {
      id: "browse-communities",
      kind: "newCommunities",
      title: "Communities",
      subtitle: "Spaces, groups, and ministries",
      style: "grid",
      items: stamped
        .filter((s) => s.candidate.type === "space")
        .slice(0, 8)
        .map(({ candidate, stamp }) => candidateToCard(candidate, stamp)),
    },
  ].filter((s) => s.items.length > 0);

  return { suggested, browseShelves, matches: [] };
}

// ── Post-typing: Firestore text search (Algolia fallback) ────────────
// Algolia integration: wire ALGOLIA_APP_ID / ALGOLIA_SEARCH_KEY secrets
// and replace the Firestore text match with an Algolia query.

async function buildSearchResult(
  db: admin.firestore.Firestore,
  query: string,
  data: SearchRequest
): Promise<DiscoverySearchResult> {
  const limit = Math.min(data.limit ?? 20, 40);

  // Simple Firestore text-prefix match (upgrade to Algolia for production)
  const [spaces, churches, discussions] = await Promise.all([
    db.collection("spaces").where("nameLower", ">=", query).where("nameLower", "<", query + "").limit(limit).get(),
    db.collection("churches").where("nameLower", ">=", query).where("nameLower", "<", query + "").limit(limit).get(),
    db.collection("discussions").where("titleLower", ">=", query).where("titleLower", "<", query + "").limit(limit).get(),
  ]);

  const candidates: Candidate[] = [
    ...spaces.docs.map((doc) => docToCandidate(doc, "space")),
    ...churches.docs.map((doc) => docToCandidate(doc, "church")),
    ...discussions.docs.map((doc) => docToCandidate(doc, "discussion")),
  ];

  const stamped = await filterAndStamp(candidates);
  const matches = stamped
    .slice(0, limit)
    .map(({ candidate, stamp }) => candidateToCard(candidate, stamp));

  return { suggested: [], browseShelves: [], matches };
}

// ── Helpers ──────────────────────────────────────────────────────────

async function fetchNearbyChurches(
  db: admin.firestore.Firestore,
  geohash?: string
): Promise<Candidate[]> {
  const snap = await db.collection("churches").where("verified", "==", true).limit(6).get();
  return snap.docs.map((doc) => docToCandidate(doc, "church"));
}

async function fetchTrendingSpaces(db: admin.firestore.Firestore): Promise<Candidate[]> {
  const snap = await db.collection("spaces")
    .where("visibility", "==", "public")
    .orderBy("growth7d", "desc")
    .limit(8)
    .get();
  return snap.docs.map((doc) => docToCandidate(doc, "space"));
}

async function fetchLiveRoomsSearch(db: admin.firestore.Firestore): Promise<Candidate[]> {
  const snap = await db.collection("rooms").where("status", "==", "live").limit(6).get();
  return snap.docs.map((doc) => docToCandidate(doc, "audioRoom"));
}

function docToCandidate(
  doc: admin.firestore.QueryDocumentSnapshot,
  type: DiscoveryCardType
): Candidate {
  const d = doc.data();
  return {
    id: doc.id,
    type,
    sourceData: d,
    features: {
      relevanceScore: 0.7,
      freshnessScore: freshnessScore(d.createdAt?.toMillis() ?? Date.now()),
      friendAffinityScore: 0,
      localProximityScore: 0,
      scriptureContinuityScore: 0,
    },
  };
}

function candidateToCard(
  candidate: Candidate,
  stamp: import("./contracts").SafetyStamp
): DiscoveryCard {
  const d = candidate.sourceData as Record<string, unknown>;
  return {
    id: candidate.id,
    type: candidate.type,
    title: String(d.name ?? d.title ?? ""),
    subtitle: d.tagline != null ? String(d.tagline) : undefined,
    payload: { type: candidate.type as "space", data: { memberCount: 0, growth7d: 0 } } as import("./contracts").CardPayload,
    reason: { kind: "freshForYou", detail: "Matches your search" },
    safety: stamp,
    glassTint: { hex: "#7B5EA7", intensity: 0.15 },
  };
}
