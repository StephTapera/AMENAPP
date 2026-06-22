/**
 * prayerGraph.js
 * AMEN Living Intelligence — Prayer Graph Supply/Demand Routing
 *
 * routePrayerSupplyDemand(userId, db) → IntelligenceCard[]
 *
 * Privacy invariants (hard):
 *   - NO user identity exposed unless prayer author made it public
 *   - NO "N people praying" or any count-based language
 *   - Cards always reference "Someone in your community" for private requests
 *   - Loop-closing follow-ups set loopParentId to original card id
 *
 * Fail policy: fail_closed — any error returns []
 */

"use strict";

const { callModel }   = require("../router/callModel");
const { buildCardId } = require("./contracts");

// Max prayer requests to surface per call
const MAX_PRAYER_CARDS = 5;

// Expiry window for prayer requests (7 days)
const PRAYER_EXPIRY_MS = 7 * 24 * 60 * 60 * 1000;

// Crisis/grief prayer types that warrant a lament frame
const LAMENT_TYPES = new Set(["crisis", "grief", "loss", "illness", "trauma"]);

/**
 * routePrayerSupplyDemand
 *
 * @param {string}   userId
 * @param {FirebaseFirestore.Firestore} db
 * @returns {Promise<import('./contracts').IntelligenceCard[]>}
 */
async function routePrayerSupplyDemand(userId, db) {
  try {
    const now   = Date.now();
    const cards = [];

    // ── 1. Fetch user's followed users ────────────────────────────────────
    const userDoc = await db.collection("users").document(userId).get().catch(() => null)
      ?? await db.collection("users").doc(userId).get();

    const followedUsers = userDoc?.data()?.following ?? [];
    const prayerOptIn   = userDoc?.data()?.prayerGraphOptIn ?? false;

    // Privacy gate: only surface network prayer requests if user has opted in
    let networkPrayers = [];

    if (prayerOptIn && followedUsers.length > 0) {
      // Firestore IN supports up to 30; take first 30 followed users
      const followedChunk = followedUsers.slice(0, 30);

      const networkSnap = await db.collection("prayers")
        .where("authorUID", "in", followedChunk)
        .where("isAnswered", "==", false)
        .where("isPublic", "==", true)
        .orderBy("createdAt", "desc")
        .limit(20)
        .get();

      networkSnap.forEach(doc => {
        networkPrayers.push({ id: doc.id, ...doc.data() });
      });
    }

    // ── 2. Fetch user's own expiring unanswered prayers ───────────────────
    const expiryThreshold = new Date(now + 3 * 24 * 60 * 60 * 1000); // expiring in 3 days
    const ownPrayerSnap = await db.collection("prayers")
      .where("authorUID", "==", userId)
      .where("isAnswered", "==", false)
      .where("expiresAt", "<=", expiryThreshold)
      .orderBy("expiresAt", "asc")
      .limit(5)
      .get();

    const ownPrayers = [];
    ownPrayerSnap.forEach(doc => ownPrayers.push({ id: doc.id, ...doc.data(), isOwn: true }));

    // ── 3. Fetch user's prior prayer actions for loop-closing ─────────────
    const actedOnSnap = await db.collection("users")
      .doc(userId)
      .collection("intelligence_brief")
      .doc("actedOnCards")
      .get()
      .catch(() => null);

    const actedOnData     = actedOnSnap?.data() ?? {};
    const actedOnCardIds  = new Set(Object.keys(actedOnData));

    // ── 4. Build cards for network prayers ───────────────────────────────
    for (const prayer of networkPrayers.slice(0, MAX_PRAYER_CARDS)) {
      try {
        const card = await buildPrayerCard({
          prayer,
          userId,
          isOwn: false,
          actedOnCardIds,
          now,
        });
        if (card) cards.push(card);
      } catch (cardErr) {
        console.error("[prayerGraph] network prayer card error", { prayerId: prayer.id, err: cardErr.message });
      }
    }

    // ── 5. Build cards for own expiring prayers ───────────────────────────
    for (const prayer of ownPrayers) {
      try {
        const card = await buildPrayerCard({
          prayer,
          userId,
          isOwn: true,
          actedOnCardIds,
          now,
        });
        if (card) cards.push(card);
      } catch (cardErr) {
        console.error("[prayerGraph] own prayer card error", { prayerId: prayer.id, err: cardErr.message });
      }
    }

    return cards.slice(0, MAX_PRAYER_CARDS);

  } catch (err) {
    console.error("[prayerGraph] routePrayerSupplyDemand failed — returning []", err.message);
    return [];
  }
}

// ── Card Builder ─────────────────────────────────────────────────────────────

async function buildPrayerCard({ prayer, userId, isOwn, actedOnCardIds, now }) {
  const prayerType  = prayer.prayerType ?? prayer.category ?? "general";
  const isLament    = LAMENT_TYPES.has(prayerType.toLowerCase());
  const isPublic    = prayer.isPublic ?? false;

  // Privacy: never reveal identity of private prayers
  const displayTitle = isOwn
    ? `Your prayer: ${prayer.title ?? "Personal request"}`
    : isPublic && prayer.authorDisplayName
      ? `Prayer request from your community`
      : "Prayer request from your community";

  // Berean-generate empathy summary — no PII, no names if private
  let summaryBullets = [prayer.body ? prayer.body.slice(0, 120) : "A community prayer need."];

  try {
    const summaryResult = await callModel({
      task:        "berean_summarize",
      input:       prayer.body ?? prayer.title ?? "",
      systemPrompt: isPublic
        ? "Write 1-3 compassionate, brief bullets summarizing this prayer request. Remove any personally identifying information. Be pastoral and gentle."
        : "Write 1-2 compassionate bullets about the general nature of this prayer need without revealing any personal details. Be pastoral and anonymous.",
      userId,
    });

    if (!summaryResult.blocked && summaryResult.output) {
      const bullets = summaryResult.output
        .split("\n")
        .map(l => l.replace(/^[-•*]\s*/, "").trim())
        .filter(l => l.length > 0)
        .slice(0, isPublic ? 3 : 2);
      if (bullets.length > 0) summaryBullets = bullets;
    }
  } catch {
    // Fall back to derived summary
  }

  // Match reasons — no identity, no counts
  const matchReasons = isOwn
    ? ["Your unanswered prayer is expiring soon", "Continue this conversation with God"]
    : ["Someone in your church community", "Active prayer request"];

  // Actions
  const actions = [
    {
      rung:    "PRAY",
      label:   "Pray",
      handler: "intelligence.pray",
      target:  prayer.id,
    },
  ];

  // DISCUSS only if from connected community (not own, not anonymous)
  if (!isOwn && isPublic) {
    actions.push({
      rung:    "DISCUSS",
      label:   "Encourage",
      handler: "intelligence.pray_discuss",
      target:  prayer.id,
    });
  }

  // Loop-closing: check if user prayed for this before
  const parentCardId = buildCardId("prayer", prayer.id, userId);
  const isFollowUp   = actedOnCardIds.has(parentCardId);

  const title = isFollowUp
    ? `Follow up: ${displayTitle}`
    : displayTitle;

  const expiresAt = prayer.expiresAt?._seconds
    ? prayer.expiresAt._seconds * 1000
    : prayer.expiresAt?.toMillis?.() ?? (now + PRAYER_EXPIRY_MS);

  return {
    id:            parentCardId,
    tier:          "SPIRITUAL",
    title,
    summary:       summaryBullets,
    backingEntity: { kind: "PRAYER_REQUEST", id: prayer.id, verified: true },
    truthLevel:    "COMMUNITY_CONFIRMED",
    matchScore:    null,
    matchReasons,
    actions,
    rankScore:     isOwn ? 0.9 : 0.7,
    rankReasons:   matchReasons.slice(0, 2),
    geo:           null,
    formation: {
      finite:           true,
      spectacleCounters: false,
      lamentFrame:      isLament ? true : null,
      loopParentId:     isFollowUp ? parentCardId : null,
    },
    source:    "prayer_graph",
    createdAt: now,
    expiresAt,
  };
}

module.exports = { routePrayerSupplyDemand };
