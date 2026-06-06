/**
 * digestBuilder.ts
 *
 * Scheduled digest builder for AMEN Living Intelligence.
 * Runs at most 2x/day (FORMATION_INVARIANTS.DIGEST_CADENCE_MAX_PER_DAY).
 *
 * Storage layout:
 *   intelligence_cards/{cardId}                    — global card store
 *   users/{uid}/intelligence_brief/current         — per-user current brief
 *
 * Key invariant: pull-to-refresh does NOT trigger a new build.
 * It re-reads the existing brief at users/{uid}/intelligence_brief/current.
 * A new brief is only built by the scheduled function or the admin-only callable.
 */

import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { enforceRateLimit } from "../rateLimit";
import { buildAndValidateBrief } from "./formationGovernor";
import { rankCards, UserContext } from "./rankingEngine";
import { matchOpportunitiesToUser } from "./opportunityGraph";
import { callModel, moderateContent } from "./amenRouting";
import {
  IntelligenceCard,
  BackingEntity,
  CardAction,
  ActionRung,
  Tier,
  TruthLevel,
  MAX_CARDS_PER_BRIEF,
  FORMATION_INVARIANTS,
} from "./contracts";

// ─── Constants ─────────────────────────────────────────────────────────────────

const BRIEF_STALE_AFTER_MS = 12 * 60 * 60 * 1000; // 12 hours
const CARDS_COLLECTION = "intelligence_cards";
const BRIEF_PATH = (uid: string) => `users/${uid}/intelligence_brief/current`;
const SUBSCRIPTIONS_COLLECTION = "intelligence_subscriptions";

// ─── Stored brief shape ────────────────────────────────────────────────────────

interface StoredBrief {
  uid: string;
  cards: IntelligenceCard[];
  builtAt: number;
  isStale: boolean;
  invariantViolations: string[];
  cardCount: number;
}

// ─── User brief subscription shape ────────────────────────────────────────────

interface BriefSubscription {
  uid: string;
  active: boolean;
  followedChurchIds: string[];
  seasonOfLife?: string;
  capacitySignal?: "free" | "busy" | "unknown";
  liturgicalSeason?: string;
  upcomingFeast?: string;
  coarseGeoLat?: number;
  coarseGeoLng?: number;
  actedOnCardIds?: string[];
}

// ─── Build a brief for a single user ──────────────────────────────────────────

async function buildBriefForUser(
  uid: string,
  db: admin.firestore.Firestore
): Promise<StoredBrief> {
  // 1. Load subscription/context for this user
  const subSnap = await db.doc(`${SUBSCRIPTIONS_COLLECTION}/${uid}`).get();
  const sub = (subSnap.exists ? subSnap.data() : null) as BriefSubscription | null;

  const ctx: UserContext = {
    uid,
    followedChurchIds: sub?.followedChurchIds ?? [],
    seasonOfLife: sub?.seasonOfLife,
    capacitySignal: sub?.capacitySignal ?? "unknown",
    actedOnCardIds: sub?.actedOnCardIds ?? [],
    coarseGeo:
      sub?.coarseGeoLat !== undefined && sub?.coarseGeoLng !== undefined
        ? { lat: sub.coarseGeoLat, lng: sub.coarseGeoLng }
        : undefined,
    liturgicalCalendarData:
      sub?.liturgicalSeason
        ? { currentSeason: sub.liturgicalSeason, upcomingFeast: sub.upcomingFeast }
        : undefined,
  };

  // 2. Get opportunity matches from the graph
  const matches = await matchOpportunitiesToUser(uid, ctx);

  // 3. Convert matched opportunities into IntelligenceCards
  const candidateCards: IntelligenceCard[] = [];

  for (const { node, matchScore, matchReasons } of matches.slice(0, MAX_CARDS_PER_BRIEF * 2)) {
    // Summarize via Berean (fail-closed — skip card if unavailable)
    const summaryResult = await callModel({
      task: "intelligence.summarize",
      input: `Opportunity: ${node.title}. Needs: ${node.needs.join(", ")}. Provides: ${node.provides.join(", ")}.`,
      context: { kind: node.kind, tier: node.tier },
      userId: uid,
    });

    if (summaryResult.error) {
      // fail-closed: skip this card rather than fabricate a summary
      continue;
    }

    const summaryText =
      typeof summaryResult.result === "string"
        ? summaryResult.result
        : JSON.stringify(summaryResult.result ?? "");

    // Convert bullets to array (max 3)
    const summaryBullets: string[] = summaryText
      .split("\n")
      .map((l) => l.replace(/^[-•*]\s*/, "").trim())
      .filter((l) => l.length > 0)
      .slice(0, 3);

    if (summaryBullets.length === 0) continue;

    // Moderate the summary — fail-closed
    for (const bullet of summaryBullets) {
      const mod = await moderateContent(bullet);
      if (!mod.safe) {
        // Skip the whole card if any bullet fails moderation
        continue;
      }
    }

    // Build backing entity
    const backingEntity: BackingEntity = {
      kind: node.kind,
      id: node.id,
      verified: node.churchIds.length > 0, // verified if church-backed
    };

    // Build default action based on kind
    const defaultAction = buildDefaultAction(node.kind, node.id, node.title);

    // Determine truthLevel
    const truthLevel: TruthLevel = node.churchIds.length > 0
      ? "CHURCH_CONFIRMED"
      : "COMMUNITY_CONFIRMED";

    // Determine tier
    const tier: Tier = node.tier;

    const card: IntelligenceCard = {
      id: `card_${node.id}_${uid}`,
      tier,
      title: node.title,
      summary: summaryBullets,
      backingEntity,
      truthLevel,
      matchScore,
      matchReasons,
      actions: [defaultAction],
      rankScore: 0,      // will be set by rankCards below
      rankReasons: [],   // will be set by rankCards below
      geo: node.geo,
      formation: {
        finite: true,
        spectacleCounters: false,
      },
      createdAt: Date.now(),
      expiresAt: node.expiresAt,
    };

    candidateCards.push(card);
  }

  // 4. Rank cards using the ranking engine
  const rankedCards = rankCards(candidateCards, ctx);

  // 5. Enforce formation governor (cap + sort + validate)
  const { cards: finalCards, violations } = buildAndValidateBrief(rankedCards);

  // 6. Persist each card to intelligence_cards collection
  const batch = db.batch();
  for (const card of finalCards) {
    const cardRef = db.collection(CARDS_COLLECTION).doc(card.id);
    batch.set(cardRef, { ...card, ownerUid: uid });
  }

  // 7. Write the brief to users/{uid}/intelligence_brief/current
  const brief: StoredBrief = {
    uid,
    cards: finalCards,
    builtAt: Date.now(),
    isStale: false,
    invariantViolations: violations,
    cardCount: finalCards.length,
  };

  const briefRef = db.doc(BRIEF_PATH(uid));
  batch.set(briefRef, brief);

  await batch.commit();
  return brief;
}

// ─── Default action builder ────────────────────────────────────────────────────

function buildDefaultAction(
  kind: string,
  id: string,
  title: string
): CardAction {
  const kindToRung: Record<string, ActionRung> = {
    CHURCH: "SHOW_UP",
    EVENT: "SHOW_UP",
    PRAYER_REQUEST: "PRAY",
    NEED: "GIVE",
    STUDY: "LEARN",
    ORG: "LEARN",
  };

  const kindToHandler: Record<string, string> = {
    CHURCH: "action.openChurch",
    EVENT: "action.rsvpEvent",
    PRAYER_REQUEST: "action.addToPrayer",
    NEED: "action.giveToNeed",
    STUDY: "action.openStudy",
    ORG: "action.openOrg",
  };

  return {
    rung: kindToRung[kind] ?? "NOTICE",
    label: kindToRung[kind] === "PRAY" ? "Pray for this" :
           kindToRung[kind] === "GIVE" ? "Give to this need" :
           kindToRung[kind] === "SHOW_UP" ? "Show up" :
           kindToRung[kind] === "LEARN" ? "Learn more" : "View",
    handler: kindToHandler[kind] ?? "action.openOrg",
    target: id,
  };
}

// ─── Mark stale briefs ─────────────────────────────────────────────────────────

async function markStaleBriefs(db: admin.firestore.Firestore): Promise<number> {
  const cutoff = Date.now() - BRIEF_STALE_AFTER_MS;

  const staleSnap = await db
    .collectionGroup("intelligence_brief")
    .where("isStale", "==", false)
    .where("builtAt", "<", cutoff)
    .limit(200)
    .get();

  if (staleSnap.empty) return 0;

  const batch = db.batch();
  for (const doc of staleSnap.docs) {
    batch.update(doc.ref, { isStale: true });
  }
  await batch.commit();
  return staleSnap.size;
}

// ─── Scheduled function ────────────────────────────────────────────────────────

/**
 * Scheduled digest builder — runs every 12 hours.
 * Enforces FORMATION_INVARIANTS.DIGEST_CADENCE_MAX_PER_DAY = 2.
 *
 * Pull-to-refresh on the client DOES NOT call this function —
 * it re-reads users/{uid}/intelligence_brief/current.
 */
export const buildIntelligenceBriefs = onSchedule(
  {
    schedule: "every 12 hours",
    timeZone: "America/New_York",
    memory: "1GiB",
    timeoutSeconds: 540,
  },
  async (_event) => {
    const firestore = admin.firestore();

    // 1. Mark any briefs older than 12 hours as stale
    const markedStale = await markStaleBriefs(firestore);
    console.log(`[buildIntelligenceBriefs] Marked ${markedStale} briefs as stale`);

    // 2. Fetch all active subscriptions
    const subsSnap = await firestore
      .collection(SUBSCRIPTIONS_COLLECTION)
      .where("active", "==", true)
      .limit(500) // process up to 500 users per invocation
      .get();

    console.log(`[buildIntelligenceBriefs] Building briefs for ${subsSnap.size} subscribers`);

    let built = 0;
    let skipped = 0;
    let errors = 0;

    for (const subDoc of subsSnap.docs) {
      const uid = subDoc.id;

      try {
        // Check if a brief was already built in the last 11.5 hours
        // (prevents double-build on overlapping schedules)
        const existingBriefSnap = await firestore.doc(BRIEF_PATH(uid)).get();
        if (existingBriefSnap.exists) {
          const existing = existingBriefSnap.data() as StoredBrief;
          const ageSinceLastBuild = Date.now() - (existing.builtAt ?? 0);
          const minBuildIntervalMs = (24 / FORMATION_INVARIANTS.DIGEST_CADENCE_MAX_PER_DAY) * 60 * 60 * 1000 - 30 * 60 * 1000;

          if (ageSinceLastBuild < minBuildIntervalMs) {
            skipped++;
            continue;
          }
        }

        await buildBriefForUser(uid, firestore);
        built++;
      } catch (err) {
        console.error(`[buildIntelligenceBriefs] Error building brief for ${uid}:`, err);
        errors++;
      }
    }

    console.log(
      `[buildIntelligenceBriefs] Done. built=${built} skipped=${skipped} errors=${errors}`
    );
  }
);

// ─── Admin-only callable trigger ──────────────────────────────────────────────

/**
 * triggerIntelligenceBriefForUser — admin-only callable for testing/manual trigger.
 * Requires the caller to have isAdmin: true in their Firestore user doc.
 *
 * Input: { uid: string } — the user to build a brief for
 * Returns: { built: true, cardCount: number, violations: string[] }
 */
export const triggerIntelligenceBriefForUser = onCall(
  {
    memory: "1GiB",
    timeoutSeconds: 120,
    enforceAppCheck: false, // admin tool — App Check not required
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const callerUid = request.auth.uid;

    // Rate limit the admin callable
    await enforceRateLimit(callerUid, [
      { name: "trigger_brief_1min", windowMs: 60_000, maxCalls: 5 },
      { name: "trigger_brief_1hour", windowMs: 3_600_000, maxCalls: 20 },
    ]);

    // Admin gate: verify caller has isAdmin flag
    const firestore = admin.firestore();
    const callerDoc = await firestore.doc(`users/${callerUid}`).get();
    if (!callerDoc.exists || callerDoc.data()?.isAdmin !== true) {
      throw new HttpsError(
        "permission-denied",
        "Only admins may trigger manual intelligence brief builds."
      );
    }

    const data = request.data as { uid?: string };
    const targetUid = data?.uid;

    if (!targetUid || typeof targetUid !== "string" || targetUid.trim().length === 0) {
      throw new HttpsError("invalid-argument", "uid is required.");
    }

    // Verify target user exists
    const targetDoc = await firestore.doc(`users/${targetUid}`).get();
    if (!targetDoc.exists) {
      throw new HttpsError("not-found", `User ${targetUid} not found.`);
    }

    const brief = await buildBriefForUser(targetUid, firestore);

    return {
      built: true,
      cardCount: brief.cardCount,
      violations: brief.invariantViolations,
      isStale: brief.isStale,
    };
  }
);
