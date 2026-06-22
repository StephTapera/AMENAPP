// assembleDiscoveryFeed.ts
// AMEN Connect Discovery Engine — Main Cloud Function
// Region: us-east1 (us-central1 is at quota limit per CLAUDE.md)
// Pipeline: candidate generation → feature assembly → formation rank →
//           diversify → dedupe → safety stamp → shelf assembly → CalmCap

import * as functions from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { v4 as uuidv4 } from "uuid";

import {
  CALM_CAP_V1,
  Candidate,
  CandidateFeatures,
  CardPayload,
  DiscoveryCard,
  DiscoveryCardType,
  DiscoveryFeed,
  DiscoveryShelf,
  GlassTint,
  HeroCandidate,
  ShelfKind,
  WhyShown,
  AdaptiveBackground,
} from "./contracts";
import { dedup, diversifyAndRank, freshnessScore } from "./formationRanker";
import { filterAndStamp } from "./safetyStamper";

// ── Request / Response ──────────────────────────────────────────────

interface AssembleRequest {
  uid: string;
  geohash?: string;             // first 6 chars of user geohash (optional)
  interests?: string[];         // user interest tag IDs
  feedToken?: string;           // for "load a little more" (NOT infinite scroll)
  categoryFilter?: string;      // pill selection — re-queries server
}

// ── Entry point ─────────────────────────────────────────────────────

export const assembleDiscoveryFeed = functions.onCall({ enforceAppCheck: true, region: "us-east1", timeoutSeconds: 15, memory: "256MiB" }, async (request): Promise<DiscoveryFeed> => {
    const data = request.data as AssembleRequest;
    if (!request.auth?.uid) {
      throw new functions.HttpsError("unauthenticated", "Must be signed in.");
    }

    const uid = request.auth.uid;
    const db = admin.firestore();

    // 1. Candidate generation (parallel sources)
    const [
      liveCandidates,
      discussionCandidates,
      churchCandidates,
      eventCandidates,
      spaceCandidates,
      prayerRoomCandidates,
    ] = await Promise.all([
      fetchLiveRooms(db),
      fetchDiscussions(db, data.interests),
      fetchChurches(db, data.geohash),
      fetchEvents(db),
      fetchSpaces(db, data.interests),
      fetchPrayerRooms(db),
    ]);

    // 2. Merge, dedupe, rank, diversify
    const allCandidates = dedup([
      ...liveCandidates,
      ...prayerRoomCandidates,
      ...discussionCandidates,
      ...spaceCandidates,
      ...eventCandidates,
      ...churchCandidates,
    ]);

    const ranked = diversifyAndRank(allCandidates);

    // 3. Safety pass — drop anything without a stamp
    const stamped = await filterAndStamp(ranked);
    if (stamped.length === 0) {
      return emptyFeed();
    }

    // 4. Shelf assembly
    const calmCap = CALM_CAP_V1;
    const shelves = assembleShelves(stamped, calmCap.maxShelves, calmCap.maxItemsPerShelf);
    const hero = assembleHero(stamped);

    return {
      generatedAt: new Date().toISOString(),
      hero,
      shelves,
      calmCap,
      feedToken: uuidv4(),
    };
  }
);

// ── Candidate generators ─────────────────────────────────────────────

async function fetchLiveRooms(db: admin.firestore.Firestore): Promise<Candidate[]> {
  const snap = await db.collection("rooms")
    .where("status", "==", "live")
    .orderBy("lastActiveAt", "desc")
    .limit(10)
    .get();

  return snap.docs.map((doc) => {
    const d = doc.data();
    return {
      id: doc.id,
      type: "audioRoom" as DiscoveryCardType,
      sourceData: d,
      features: buildFeatures({ freshCreatedAt: d.startedAt?.toMillis() ?? Date.now(), relevance: 0.9 }),
    };
  });
}

async function fetchDiscussions(
  db: admin.firestore.Firestore,
  interests?: string[]
): Promise<Candidate[]> {
  let q: admin.firestore.Query = db.collection("discussions")
    .where("visibility", "==", "public")
    .orderBy("lastActivityAt", "desc")
    .limit(20);

  if (interests?.length) {
    q = q.where("topicTags", "array-contains-any", interests.slice(0, 10));
  }

  const snap = await q.get();
  return snap.docs.map((doc) => {
    const d = doc.data();
    return {
      id: doc.id,
      type: "discussion" as DiscoveryCardType,
      sourceData: d,
      features: buildFeatures({
        freshCreatedAt: d.createdAt?.toMillis() ?? Date.now(),
        relevance: interests?.length ? 0.8 : 0.5,
      }),
    };
  });
}

async function fetchChurches(
  db: admin.firestore.Firestore,
  geohash?: string
): Promise<Candidate[]> {
  let q: admin.firestore.Query = db.collection("churches")
    .where("verified", "==", true)
    .limit(8);

  if (geohash) {
    // Geohash range query for nearby (precision 4 = ~40km cell)
    const prefix = geohash.substring(0, 4);
    q = q.where("geohash4", ">=", prefix).where("geohash4", "<", prefix + "");
  }

  const snap = await q.get();
  return snap.docs.map((doc) => {
    const d = doc.data();
    return {
      id: doc.id,
      type: "church" as DiscoveryCardType,
      sourceData: d,
      features: buildFeatures({
        freshCreatedAt: d.createdAt?.toMillis() ?? Date.now(),
        relevance: geohash ? 0.85 : 0.5,
        localProximity: geohash ? 0.9 : 0,
      }),
    };
  });
}

async function fetchEvents(db: admin.firestore.Firestore): Promise<Candidate[]> {
  const now = admin.firestore.Timestamp.now();
  const weekOut = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() + 7 * 24 * 3_600_000)
  );

  const snap = await db.collection("events")
    .where("startsAt", ">=", now)
    .where("startsAt", "<=", weekOut)
    .orderBy("startsAt")
    .limit(10)
    .get();

  return snap.docs.map((doc) => {
    const d = doc.data();
    return {
      id: doc.id,
      type: "event" as DiscoveryCardType,
      sourceData: d,
      features: buildFeatures({ freshCreatedAt: d.createdAt?.toMillis() ?? Date.now(), relevance: 0.7 }),
    };
  });
}

async function fetchSpaces(
  db: admin.firestore.Firestore,
  interests?: string[]
): Promise<Candidate[]> {
  let q: admin.firestore.Query = db.collection("spaces")
    .where("visibility", "==", "public")
    .orderBy("memberCount", "desc")
    .limit(15);

  if (interests?.length) {
    q = db.collection("spaces")
      .where("interests", "array-contains-any", interests.slice(0, 10))
      .limit(15);
  }

  const snap = await q.get();
  return snap.docs.map((doc) => {
    const d = doc.data();
    return {
      id: doc.id,
      type: "space" as DiscoveryCardType,
      sourceData: d,
      features: buildFeatures({
        freshCreatedAt: d.createdAt?.toMillis() ?? Date.now(),
        relevance: interests?.length ? 0.8 : 0.55,
      }),
    };
  });
}

async function fetchPrayerRooms(db: admin.firestore.Firestore): Promise<Candidate[]> {
  const snap = await db.collection("rooms")
    .where("roomType", "==", "prayer")
    .where("status", "in", ["live", "open"])
    .orderBy("lastActiveAt", "desc")
    .limit(8)
    .get();

  return snap.docs.map((doc) => {
    const d = doc.data();
    return {
      id: doc.id,
      type: "prayerRoom" as DiscoveryCardType,
      sourceData: d,
      features: buildFeatures({ freshCreatedAt: d.startedAt?.toMillis() ?? Date.now(), relevance: 0.85 }),
    };
  });
}

// ── Feature helper ───────────────────────────────────────────────────

function buildFeatures(opts: {
  freshCreatedAt: number;
  relevance?: number;
  localProximity?: number;
}): CandidateFeatures {
  return {
    relevanceScore: opts.relevance ?? 0.5,
    freshnessScore: freshnessScore(opts.freshCreatedAt),
    friendAffinityScore: 0,           // upgraded when user graph is available
    localProximityScore: opts.localProximity ?? 0,
    scriptureContinuityScore: 0,      // upgraded when reading progress is available
  };
}

// ── Shelf assembly ───────────────────────────────────────────────────

function assembleShelves(
  stamped: Array<{ candidate: Candidate; stamp: import("./contracts").SafetyStamp }>,
  maxShelves: number,
  maxPerShelf: number
): DiscoveryShelf[] {
  const byType = new Map<DiscoveryCardType, typeof stamped>();

  for (const item of stamped) {
    const bucket = byType.get(item.candidate.type) ?? [];
    bucket.push(item);
    byType.set(item.candidate.type, bucket);
  }

  const shelfDefs: Array<{ kind: ShelfKind; types: DiscoveryCardType[]; title: string; subtitle?: string }> = [
    { kind: "liveNow",           types: ["audioRoom", "prayerRoom"], title: "Live Now",              subtitle: "Happening right now" },
    { kind: "prayerRooms",       types: ["prayerRoom"],              title: "Prayer Rooms",          subtitle: "Join others in prayer" },
    { kind: "trendingDiscussions", types: ["discussion"],            title: "Active Discussions",    subtitle: "Conversations gaining momentum" },
    { kind: "recommended",       types: ["space", "bibleStudy"],     title: "For You",               subtitle: "Based on your interests" },
    { kind: "nearbyChurches",    types: ["church"],                  title: "Churches Near You",     subtitle: undefined },
    { kind: "eventsThisWeek",    types: ["event"],                   title: "This Week",             subtitle: "Events coming up" },
    { kind: "newCommunities",    types: ["space"],                   title: "New Communities",       subtitle: "Just getting started" },
    { kind: "friendsActive",     types: ["audioRoom", "space"],      title: "Friends Are In",        subtitle: "See where your connections are" },
  ];

  const shelves: DiscoveryShelf[] = [];

  for (const def of shelfDefs) {
    if (shelves.length >= maxShelves) break;

    const items: DiscoveryCard[] = [];
    for (const type of def.types) {
      const bucket = byType.get(type) ?? [];
      items.push(...bucket.slice(0, Math.ceil(maxPerShelf / def.types.length)).map(({ candidate, stamp }) =>
        candidateToCard(candidate, stamp)
      ));
    }

    if (items.length === 0) continue;

    shelves.push({
      id: `shelf-${def.kind}`,
      kind: def.kind,
      title: def.title,
      subtitle: def.subtitle,
      style: def.kind === "nearbyChurches" ? "mapBacked" : "carousel",
      items: items.slice(0, maxPerShelf),
    });
  }

  return shelves;
}

// ── Hero assembly ────────────────────────────────────────────────────

function assembleHero(
  stamped: Array<{ candidate: Candidate; stamp: import("./contracts").SafetyStamp }>
): HeroCandidate[] {
  // Pick top 3 formation-scored candidates as hero candidates
  const topItems = stamped.slice(0, 3);
  return topItems.map(({ candidate, stamp }) => ({
    id: candidate.id,
    card: candidateToCard(candidate, stamp),
    backgroundHint: backgroundForType(candidate.type),
  }));
}

// ── Card builder ─────────────────────────────────────────────────────

function candidateToCard(
  candidate: Candidate,
  stamp: import("./contracts").SafetyStamp
): DiscoveryCard {
  const d = candidate.sourceData as Record<string, unknown>;

  return {
    id: candidate.id,
    type: candidate.type,
    title: String(d.name ?? d.title ?? ""),
    subtitle: d.tagline != null ? String(d.tagline) : d.description != null ? String(d.description) : undefined,
    payload: buildPayload(candidate),
    reason: buildReason(candidate),
    safety: stamp,
    glassTint: glassTintForType(candidate.type),
  };
}

function buildPayload(candidate: Candidate): CardPayload {
  const d = candidate.sourceData as Record<string, unknown>;

  switch (candidate.type) {
    case "bibleStudy":
      return { type: "bibleStudy", data: { verseRef: String(d.verseRef ?? ""), passagePreview: String(d.passagePreview ?? "") } };
    case "prayerRoom":
      return { type: "prayerRoom", data: { liveCount: Number(d.liveCount ?? 0), activeRequests: Number(d.activeRequests ?? 0), speakerIds: (d.speakerIds as string[]) ?? [] } };
    case "church":
      return { type: "church", data: { serviceTimes: (d.serviceTimes as string[]) ?? [], denomination: d.denomination as string | undefined, latitude: Number(d.latitude ?? 0), longitude: Number(d.longitude ?? 0), distanceMeters: d.distanceMeters as number | undefined } };
    case "event":
      return { type: "event", data: { startsAt: (d.startsAt as admin.firestore.Timestamp)?.toDate().toISOString() ?? "", rsvpState: "none", speakerIds: (d.speakerIds as string[]) ?? [] } };
    case "discussion":
      return { type: "discussion", data: { replyCount: Number(d.replyCount ?? 0), lastActivityAt: (d.lastActivityAt as admin.firestore.Timestamp)?.toDate().toISOString() ?? "", topicTags: (d.topicTags as string[]) ?? [] } };
    case "space":
      return { type: "space", data: { memberCount: Number(d.memberCount ?? 0), growth7d: Number(d.growth7d ?? 0), latestTopic: d.latestTopic as string | undefined } };
    case "audioRoom":
      return { type: "audioRoom", data: { liveCount: Number(d.liveCount ?? 0), speakerIds: (d.speakerIds as string[]) ?? [], waveformSeed: Number(d.waveformSeed ?? Math.floor(Math.random() * 1000)) } };
  }
}

function buildReason(candidate: Candidate): WhyShown {
  switch (candidate.type) {
    case "prayerRoom": return { kind: "followedInterest", detail: "Active prayer community" };
    case "church":     return { kind: "nearYou", detail: "Church near your location" };
    case "event":      return { kind: "freshForYou", detail: "Happening this week" };
    case "audioRoom":  return { kind: "trending", detail: "Live right now" };
    case "bibleStudy": return { kind: "continueReading", detail: "Continue your reading journey" };
    case "discussion": return { kind: "followedInterest", detail: "Active in your areas of interest" };
    case "space":      return { kind: "freshForYou", detail: "Community matching your interests" };
  }
}

function glassTintForType(type: DiscoveryCardType): import("./contracts").GlassTint {
  const tints: Record<DiscoveryCardType, { hex: string; intensity: number }> = {
    prayerRoom:  { hex: "#D9A441", intensity: 0.18 },
    bibleStudy:  { hex: "#7B5EA7", intensity: 0.18 },
    church:      { hex: "#245B8F", intensity: 0.15 },
    event:       { hex: "#4A7C59", intensity: 0.15 },
    discussion:  { hex: "#6B7280", intensity: 0.12 },
    space:       { hex: "#7B5EA7", intensity: 0.15 },
    audioRoom:   { hex: "#D9A441", intensity: 0.20 },
  };
  return tints[type];
}

function backgroundForType(type: DiscoveryCardType): AdaptiveBackground {
  switch (type) {
    case "prayerRoom": return "prayerWarm";
    case "bibleStudy": return "parchment";
    case "church":     return "neutral";
    case "event":      return "eventBrand";
    case "audioRoom":  return "worshipGradient";
    default:           return "neutral";
  }
}

function emptyFeed(): DiscoveryFeed {
  return {
    generatedAt: new Date().toISOString(),
    hero: [],
    shelves: [],
    calmCap: CALM_CAP_V1,
    feedToken: uuidv4(),
  };
}
