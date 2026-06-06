/**
 * functions/intelligence/formationGovernor.js
 *
 * AMEN Living Intelligence — Formation Governor
 *
 * Enforces all 7 formation invariants. All functions are deterministic
 * and have no side effects on Firestore (exception: enforceDigestCadence
 * reads from Firestore to check today's count).
 *
 * Exports:
 *   MAX_CARDS_PER_BRIEF
 *   MAX_BRIEFS_PER_DAY
 *   POLITICS_KEYWORDS
 *   POLITICS_ALLOWED_RUNGS
 *   assertCard(card)
 *   enforceBriefCap(cards)
 *   enforceDigestCadence(userId, db)
 *   stripSpectacleCounters(card)
 *   enforceGeo(card)
 *   enforcePoliticsFilter(card)
 *   assertLoopClosure(cards, priorActions)
 *
 * Formation Invariants:
 *   FI-1  Briefs are finite (MAX_CARDS_PER_BRIEF = 7)
 *   FI-2  DEVELOPING cards are always demoted (never first)
 *   FI-3  No spectacle counters on any card
 *   FI-4  Geo is coarse-only (no precise coordinates)
 *   FI-5  Politics content restricted to specific action rungs
 *   FI-6  No unverified backing entities on any card
 *   FI-7  Prior SHOW_UP/GIVE actions must have a follow-up card
 */

"use strict";

const { assertCard: contractsAssertCard, MAX_CARDS_PER_BRIEF, MAX_BRIEFS_PER_DAY, TRUTH_LEVEL, ACTION_RUNG } = require('./contracts');

// ─── Constants ────────────────────────────────────────────────────────────────

/** Fields that represent spectacle engagement metrics — all must be stripped */
const SPECTACLE_COUNTER_FIELDS = [
  'prayingCount',
  'viewCount',
  'likeCount',
  'shareCount',
  'commentCount',
  'reactionCount',
  'followerCount',
  'engagementCount',
  'impressionCount',
  'repostCount',
  'amenCount',
];

/** Keywords that mark political content requiring action rung filtering */
const POLITICS_KEYWORDS = [
  'election',
  'politics',
  'partisan',
  'vote',
  'candidate',
  'legislation',
];

/** Only these action rungs are permitted for political content */
const POLITICS_ALLOWED_RUNGS = ['PRAY', 'GIVE', 'SHOW_UP', 'DISCUSS'];

/** Action rungs that require loop-closing follow-up */
const LOOP_CLOSING_RUNGS = ['SHOW_UP', 'GIVE'];

// ─── assertCard ───────────────────────────────────────────────────────────────

/**
 * assertCard — delegates to contracts.js assertCard.
 * Re-exported here so formationGovernor is a single import for consumers.
 *
 * @param {object} card
 * @throws {Error}
 */
function assertCard(card) {
  contractsAssertCard(card);
}

// ─── enforceBriefCap ─────────────────────────────────────────────────────────

/**
 * enforceBriefCap — truncate cards to MAX_CARDS_PER_BRIEF.
 *
 * Before truncating, DEVELOPING cards are sorted to the bottom so they are
 * the first to be dropped when the cap is applied.
 *
 * @param {object[]} cards  Array of ranked IntelligenceCards (sorted descending by rankScore)
 * @returns {object[]}      Array of at most MAX_CARDS_PER_BRIEF cards
 */
function enforceBriefCap(cards) {
  if (!Array.isArray(cards)) return [];

  // Separate DEVELOPING from non-DEVELOPING, preserve existing sort order within each group
  const nonDeveloping = cards.filter((c) => c.truthLevel !== TRUTH_LEVEL.DEVELOPING);
  const developing    = cards.filter((c) => c.truthLevel === TRUTH_LEVEL.DEVELOPING);

  // Merge: non-developing first, developing at end
  const ordered = [...nonDeveloping, ...developing];

  // Truncate
  return ordered.slice(0, MAX_CARDS_PER_BRIEF);
}

// ─── enforceDigestCadence ─────────────────────────────────────────────────────

/**
 * enforceDigestCadence — check if a new brief rebuild is permitted today.
 *
 * Reads from intelligence_briefs/{userId} to count briefs built today.
 * Returns true if fewer than MAX_BRIEFS_PER_DAY briefs have been built today.
 *
 * @param {string} userId
 * @param {FirebaseFirestore.Firestore} db  Admin Firestore instance
 * @returns {Promise<boolean>}  true = rebuild permitted
 */
async function enforceDigestCadence(userId, db) {
  try {
    const todayStart = new Date();
    todayStart.setUTCHours(0, 0, 0, 0);

    // Query brief audit sub-collection
    const snap = await db
      .collection('intelligence_briefs')
      .doc(userId)
      .collection('audit')
      .where('builtAt', '>=', todayStart)
      .get();

    return snap.size < MAX_BRIEFS_PER_DAY;
  } catch (err) {
    console.error(`[enforceDigestCadence] Error checking cadence for ${userId}:`, err.message);
    // Fail open here — if we can't check, allow the build (brief is finite anyway)
    return true;
  }
}

// ─── stripSpectacleCounters ───────────────────────────────────────────────────

/**
 * stripSpectacleCounters — remove all engagement counter fields from a card.
 *
 * Mutates a shallow copy, not the original.
 *
 * @param {object} card
 * @returns {object}  New card object without spectacle counter fields
 */
function stripSpectacleCounters(card) {
  if (!card || typeof card !== 'object') return card;
  const clean = { ...card };
  for (const field of SPECTACLE_COUNTER_FIELDS) {
    delete clean[field];
  }
  // Also strip from nested backingEntity if present
  if (clean.backingEntity && typeof clean.backingEntity === 'object') {
    const cleanEntity = { ...clean.backingEntity };
    for (const field of SPECTACLE_COUNTER_FIELDS) {
      delete cleanEntity[field];
    }
    clean.backingEntity = cleanEntity;
  }
  return clean;
}

// ─── enforceGeo ──────────────────────────────────────────────────────────────

/**
 * enforceGeo — ensure geo is coarse-only.
 *
 * If geo is present:
 *   - Round lat/lng to 2 decimal places (approx 1km resolution)
 *   - Ensure coarse: true is set
 *   - Strip any extra fields that could enable precise location
 *
 * If geo is absent, return card unchanged.
 *
 * @param {object} card
 * @returns {object}  New card with coarse geo or no geo
 */
function enforceGeo(card) {
  if (!card || typeof card !== 'object') return card;
  if (!card.geo) return { ...card };

  const { lat, lng } = card.geo;
  if (typeof lat !== 'number' || typeof lng !== 'number') {
    // Invalid geo — strip it entirely
    const clean = { ...card };
    delete clean.geo;
    return clean;
  }

  // Round to 2dp (±0.5km precision), keep only safe fields
  return {
    ...card,
    geo: {
      lat: Math.round(lat * 100) / 100,
      lng: Math.round(lng * 100) / 100,
      coarse: true,
    },
  };
}

// ─── enforcePoliticsFilter ────────────────────────────────────────────────────

/**
 * enforcePoliticsFilter — if political keywords appear in title or summary,
 * restrict actions to POLITICS_ALLOWED_RUNGS only.
 *
 * @param {object} card
 * @returns {object}  New card, potentially with filtered actions
 */
function enforcePoliticsFilter(card) {
  if (!card || typeof card !== 'object') return card;

  const titleAndSummary = [
    card.title || '',
    ...(Array.isArray(card.summary) ? card.summary : []),
  ].join(' ').toLowerCase();

  const isPolitical = POLITICS_KEYWORDS.some((kw) => titleAndSummary.includes(kw));
  if (!isPolitical) return { ...card };

  // Filter actions to allowed rungs only
  const filteredActions = Array.isArray(card.actions)
    ? card.actions.filter((a) => POLITICS_ALLOWED_RUNGS.includes(a.rung))
    : [];

  return {
    ...card,
    actions: filteredActions,
  };
}

// ─── assertLoopClosure ───────────────────────────────────────────────────────

/**
 * assertLoopClosure — ensure prior SHOW_UP/GIVE actions have a follow-up card
 * in the current brief.
 *
 * For each prior action with rung in LOOP_CLOSING_RUNGS, there should be a card
 * in cards with a loopParentId matching that action's id.
 *
 * Does not throw — returns an array of unresolved loop IDs for caller to log.
 *
 * @param {object[]} cards         Current brief's cards
 * @param {string[]} priorActions  IDs of prior actions the user has taken
 * @returns {{ resolved: string[], unresolved: string[] }}
 */
function assertLoopClosure(cards, priorActions) {
  if (!Array.isArray(priorActions) || priorActions.length === 0) {
    return { resolved: [], unresolved: [] };
  }

  if (!Array.isArray(cards)) {
    return { resolved: [], unresolved: priorActions };
  }

  const loopParentIds = new Set(
    cards
      .map((c) => c.formation && c.formation.loopParentId)
      .filter(Boolean),
  );

  const resolved   = priorActions.filter((id) => loopParentIds.has(id));
  const unresolved = priorActions.filter((id) => !loopParentIds.has(id));

  return { resolved, unresolved };
}

// ─── Exports ──────────────────────────────────────────────────────────────────

module.exports = {
  MAX_CARDS_PER_BRIEF,
  MAX_BRIEFS_PER_DAY,
  POLITICS_KEYWORDS,
  POLITICS_ALLOWED_RUNGS,
  assertCard,
  enforceBriefCap,
  enforceDigestCadence,
  stripSpectacleCounters,
  enforceGeo,
  enforcePoliticsFilter,
  assertLoopClosure,
};
