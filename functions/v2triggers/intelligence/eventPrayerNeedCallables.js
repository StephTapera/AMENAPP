/**
 * eventPrayerNeedCallables.js
 * AMEN Living Intelligence — Event, Prayer, and Need Detection Callables
 *
 * Exports three Firebase v2 onCall functions:
 *   getEventIntelligence   — Matched event cards for the authenticated user
 *   getPrayerMatchCards    — Prayer graph supply/demand cards
 *   getNeedDetectionCards  — Community need detection cards
 *
 * Security:
 *   - Auth required on every call
 *   - Per-user rate limit: 20 calls/hour per callable
 *   - All underlying logic is fail-closed (errors return [])
 *
 * REQUIRED: Add the following to functions/index.js to export these callables:
 *   const epn = require('./intelligence/eventPrayerNeedCallables');
 *   exports.getEventIntelligence  = epn.getEventIntelligence;
 *   exports.getPrayerMatchCards   = epn.getPrayerMatchCards;
 *   exports.getNeedDetectionCards = epn.getNeedDetectionCards;
 */

"use strict";

const { onCall, HttpsError }   = require("firebase-functions/v2/https");
const admin                    = require("firebase-admin");
const logger                   = require("firebase-functions/logger");
const { enforceRateLimit }     = require("../rateLimiter");
const { matchEventsForUser }   = require("./eventMatching");
const { routePrayerSupplyDemand } = require("./prayerGraph");
const { detectNeedsFromContent }  = require("./needDetection");

// ── Shared helpers ────────────────────────────────────────────────────────────

function requireAuth(request) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return request.auth.uid;
}

function getDb() {
  return admin.firestore();
}

/**
 * Fetch the user's intelligence context from Firestore.
 * Returns a safe default if the doc doesn't exist.
 */
async function getUserContext(userId, db) {
  try {
    const doc = await db.collection("users").doc(userId).get();
    const data = doc.data() ?? {};

    return {
      churchIds:         data.churchIds         ?? [],
      followedChurchIds: data.followedChurchIds ?? data.followingChurches ?? [],
      seasonOfLife:      data.seasonOfLife      ?? null,
      capacity:          data.prayerCapacity    ?? null,
      location:          data.locationOptIn     === true ? (data.coarseLocation ?? null) : null,
    };
  } catch {
    return {
      churchIds:         [],
      followedChurchIds: [],
      seasonOfLife:      null,
      capacity:          null,
      location:          null,
    };
  }
}

// ── getEventIntelligence ──────────────────────────────────────────────────────

/**
 * getEventIntelligence
 *
 * Returns IntelligenceCard[] for upcoming events matching the user's church
 * connections and (if geo opted-in) location.
 *
 * Input: {} (no parameters required — user context loaded server-side)
 * Output: { cards: IntelligenceCard[] }
 */
exports.getEventIntelligence = onCall(
  { region: "us-central1", timeoutSeconds: 60, memory: "256MiB" },
  async (request) => {
    const userId = requireAuth(request);
    await enforceRateLimit(userId, "getEventIntelligence", 20, 3600);

    logger.info("getEventIntelligence", { userId });

    const db      = getDb();
    const context = await getUserContext(userId, db);

    // Fail-closed: matchEventsForUser always returns [] on error
    const cards = await matchEventsForUser(userId, context, db);

    logger.info("getEventIntelligence complete", { userId, cardCount: cards.length });
    return { cards };
  }
);

// ── getPrayerMatchCards ───────────────────────────────────────────────────────

/**
 * getPrayerMatchCards
 *
 * Returns IntelligenceCard[] for prayer requests from the user's network
 * that match their prayer capacity, plus their own expiring prayer requests.
 *
 * Privacy: no identity in cards, opt-in gated, no counts.
 *
 * Input: {} (no parameters required — user context loaded server-side)
 * Output: { cards: IntelligenceCard[] }
 */
exports.getPrayerMatchCards = onCall(
  { region: "us-central1", timeoutSeconds: 60, memory: "256MiB" },
  async (request) => {
    const userId = requireAuth(request);
    await enforceRateLimit(userId, "getPrayerMatchCards", 20, 3600);

    logger.info("getPrayerMatchCards", { userId });

    const db = getDb();

    // Fail-closed: routePrayerSupplyDemand always returns [] on error
    const cards = await routePrayerSupplyDemand(userId, db);

    logger.info("getPrayerMatchCards complete", { userId, cardCount: cards.length });
    return { cards };
  }
);

// ── getNeedDetectionCards ─────────────────────────────────────────────────────

/**
 * getNeedDetectionCards
 *
 * Scans recent public posts from the user's network for expressed needs,
 * classifies them (RESOURCE/VOLUNTEER/PRAYER/MENTOR), and returns
 * privacy-first IntelligenceCard[] linking to matching opportunities.
 *
 * Privacy: "Someone in your community" — no names, no PII.
 *
 * Input: {} (no parameters required — user context loaded server-side)
 * Output: { cards: IntelligenceCard[] }
 */
exports.getNeedDetectionCards = onCall(
  { region: "us-central1", timeoutSeconds: 90, memory: "512MiB" },
  async (request) => {
    const userId = requireAuth(request);
    await enforceRateLimit(userId, "getNeedDetectionCards", 10, 3600);

    logger.info("getNeedDetectionCards", { userId });

    const db = getDb();

    // Fail-closed: detectNeedsFromContent always returns [] on error
    const cards = await detectNeedsFromContent(userId, db);

    logger.info("getNeedDetectionCards complete", { userId, cardCount: cards.length });
    return { cards };
  }
);
