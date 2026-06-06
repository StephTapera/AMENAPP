/**
 * worldEventsFunctions.ts
 *
 * Living Intelligence — GLOBAL Tier
 * Cloud Functions for GLOBAL intelligence cards.
 *
 * Exports:
 *   getGlobalIntelligenceCards — callable: fetch current GLOBAL cards for a user
 *   submitWorldEvent           — callable: admin/church-leader submits a world event
 *
 * Security contract:
 *   - Both callables require Firebase Auth
 *   - submitWorldEvent additionally requires isChurchLeader OR isAdmin custom claim
 *   - source + sourceUrl validated before any AI call
 *   - Content moderation before Firestore write
 *   - DEVELOPING cards are never returned as top card
 *   - Sourceless GLOBAL cards are filtered out at read time
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";

import { generateWorldResponse, WorldEventInput, WorldEventType } from "./worldResponseEngine";
import { buildGlobalCard } from "./globalCardBuilder";
import type { IntelligenceCard } from "./contracts";
import { FORMATION_INVARIANTS, MAX_CARDS_PER_BRIEF } from "./contracts";
import { ANTHROPIC_API_KEY } from "./amenRouting";

// ---------------------------------------------------------------------------
// Firestore
// ---------------------------------------------------------------------------

const db = getFirestore();
const CARDS_COLLECTION = "intelligence_cards";
const RATE_LIMITS_COLLECTION = "_rateLimits";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function requireAuth(request: { auth?: { uid: string } | null }): string {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return request.auth.uid;
}

async function requireLeaderOrAdmin(uid: string): Promise<void> {
  try {
    const userRecord = await getAuth().getUser(uid);
    const claims = userRecord.customClaims as Record<string, unknown> | undefined;
    if (!claims?.isChurchLeader && !claims?.isAdmin) {
      throw new HttpsError(
        "permission-denied",
        "Only church leaders or admins may submit world events."
      );
    }
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    throw new HttpsError("internal", "Could not verify role claims.");
  }
}

function isValidUrl(raw: string): boolean {
  try {
    const u = new URL(raw);
    return u.protocol === "https:" || u.protocol === "http:";
  } catch {
    return false;
  }
}

function sanitize(value: unknown, maxLen = 1000): string {
  if (typeof value !== "string") return "";
  return value.replace(/[<>]/g, "").trim().slice(0, maxLen);
}

const VALID_EVENT_TYPES = new Set<WorldEventType>([
  "disaster", "conflict", "persecution", "humanitarian", "global_church", "general",
]);

async function checkSubmitRateLimit(uid: string): Promise<void> {
  const hourKey = new Date().toISOString().slice(0, 13);
  const ref = db
    .collection(RATE_LIMITS_COLLECTION)
    .doc(`worldEventSubmit:${uid}:${hourKey}`);
  const snap = await ref.get();
  const count = snap.exists ? ((snap.data()?.count as number) ?? 0) : 0;
  if (count >= 10) {
    throw new HttpsError(
      "resource-exhausted",
      "World event submission rate limit reached. Try again in an hour."
    );
  }
  await ref.set(
    { count: FieldValue.increment(1), uid, hour: hourKey },
    { merge: true }
  );
}

// ---------------------------------------------------------------------------
// 1. getGlobalIntelligenceCards
// ---------------------------------------------------------------------------

export const getGlobalIntelligenceCards = onCall(
  {
    region: "us-central1",
    enforceAppCheck: true,
  },
  async (request) => {
    requireAuth(request);

    const now = Timestamp.now().toMillis();

    // Query GLOBAL cards that haven't expired
    const snapshot = await db
      .collection(CARDS_COLLECTION)
      .where("tier", "==", "GLOBAL")
      .where("expiresAt", ">", now)
      .orderBy("expiresAt", "desc")
      .limit(MAX_CARDS_PER_BRIEF * 3) // over-fetch before filtering
      .get();

    let cards = snapshot.docs
      .map((doc) => ({ id: doc.id, ...doc.data() }) as IntelligenceCard)
      // Filter: must have a source
      .filter((c) => Boolean(c.source))
      // Filter: remove DEVELOPING cards from the pool unless nothing else available
      // (they will be demoted — not removed — but we apply the top-card rule below)
      .sort((a, b) => b.rankScore - a.rankScore);

    // DEVELOPING_NEVER_TOP: if top card is DEVELOPING, demote it to after first VERIFIED/etc.
    if (
      FORMATION_INVARIANTS.DEVELOPING_NEVER_TOP &&
      cards.length > 1 &&
      cards[0].truthLevel === "DEVELOPING"
    ) {
      const developingCard = cards.shift()!;
      const firstNonDeveloping = cards.findIndex((c) => c.truthLevel !== "DEVELOPING");
      if (firstNonDeveloping !== -1) {
        cards.splice(firstNonDeveloping + 1, 0, developingCard);
      } else {
        cards.push(developingCard);
      }
    }

    // Cap to digest limit
    cards = cards.slice(0, MAX_CARDS_PER_BRIEF);

    logger.info("getGlobalIntelligenceCards", {
      returned: cards.length,
      uid: request.auth?.uid,
    });

    return { cards };
  }
);

// ---------------------------------------------------------------------------
// 2. submitWorldEvent
// ---------------------------------------------------------------------------

export const submitWorldEvent = onCall(
  {
    region: "us-central1",
    enforceAppCheck: true,
    secrets: [ANTHROPIC_API_KEY],
  },
  async (request) => {
    const uid = requireAuth(request);
    await requireLeaderOrAdmin(uid);
    await checkSubmitRateLimit(uid);

    const data = request.data as Record<string, unknown>;

    // --- Validate required fields ---
    const title = sanitize(data.title, 200);
    const description = sanitize(data.description, 3000);
    const source = sanitize(data.source, 200);
    const sourceUrl = sanitize(data.sourceUrl as string | undefined ?? "", 500) || undefined;
    const verifiedBy = sanitize(data.verifiedBy as string | undefined ?? "", 100) || undefined;
    const rawEventType = sanitize(data.eventType, 50);
    const publishedAt =
      typeof data.publishedAt === "number" ? data.publishedAt : Date.now();
    const orgId = sanitize(data.orgId as string | undefined ?? "", 128) || undefined;

    if (!title) {
      throw new HttpsError("invalid-argument", "title is required.");
    }
    if (!source) {
      throw new HttpsError(
        "invalid-argument",
        "source is required for every GLOBAL card."
      );
    }
    if (sourceUrl && !isValidUrl(sourceUrl)) {
      throw new HttpsError("invalid-argument", "sourceUrl must be a valid URL.");
    }
    if (!VALID_EVENT_TYPES.has(rawEventType as WorldEventType)) {
      throw new HttpsError(
        "invalid-argument",
        `eventType must be one of: ${[...VALID_EVENT_TYPES].join(", ")}`
      );
    }

    const event: WorldEventInput = {
      title,
      description,
      source,
      sourceUrl,
      eventType: rawEventType as WorldEventType,
      verifiedBy,
      publishedAt,
    };

    // --- Generate world response via Anthropic ---
    const worldResponse = await generateWorldResponse(event);
    if (!worldResponse) {
      // Fail-closed: no fabricated card
      logger.warn("submitWorldEvent: generateWorldResponse returned null — no card emitted", {
        title,
        uid,
      });
      throw new HttpsError(
        "unavailable",
        "World event processing is temporarily unavailable. Please try again."
      );
    }

    // --- Content moderation ---
    const moderationClear = await moderateWorldCard(worldResponse, uid);
    if (!moderationClear) {
      throw new HttpsError(
        "failed-precondition",
        "The generated content did not pass content moderation."
      );
    }

    // --- Build the card ---
    let card: IntelligenceCard;
    try {
      card = buildGlobalCard(event, worldResponse, orgId);
    } catch (err) {
      logger.error("submitWorldEvent: buildGlobalCard threw:", err, { uid, title });
      throw new HttpsError("internal", "Failed to build the GLOBAL card.");
    }

    // --- Persist to Firestore ---
    const ref = db.collection(CARDS_COLLECTION).doc(card.id);
    await ref.set({
      ...card,
      submittedBy: uid,
      submittedAt: FieldValue.serverTimestamp(),
    });

    logger.info("submitWorldEvent: GLOBAL card created", {
      cardId: card.id,
      truthLevel: card.truthLevel,
      isDeveloping: worldResponse.isDeveloping,
      uid,
    });

    return {
      cardId: card.id,
      truthLevel: card.truthLevel,
      isDeveloping: worldResponse.isDeveloping,
    };
  }
);

// ---------------------------------------------------------------------------
// Content moderation helper
// ---------------------------------------------------------------------------

/**
 * Light rule-based moderation on generated text before writing to Firestore.
 * For deeper scanning the caller can integrate safetyOS moderateContent.
 * Returns true if content is safe to publish.
 */
async function moderateWorldCard(
  worldResponse: {
    whatIsKnown: string;
    whatIsContested: string;
    howToRespond: string;
  },
  uid: string
): Promise<boolean> {
  const combined = [
    worldResponse.whatIsKnown,
    worldResponse.whatIsContested,
    worldResponse.howToRespond,
  ]
    .join(" ")
    .toLowerCase();

  // Hard-block patterns — partisan or fabricated assertion signals
  const hardBlockPatterns = [
    /\b(vote for|vote against|support the [a-z]+ party|oppose the [a-z]+ party)\b/i,
    /\b(confirmed by god|god told us|prophetically proven)\b/i,
    /\bfake news\b/i,
  ];

  for (const pattern of hardBlockPatterns) {
    if (pattern.test(combined)) {
      logger.warn("moderateWorldCard: hard-block pattern matched", { uid });
      return false;
    }
  }

  return true;
}
