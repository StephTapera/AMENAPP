/**
 * functions/intelligence/rankingBrain.js
 *
 * AMEN Living Intelligence — Ranking Brain
 *
 * Exports:
 *   rankCard(card, context) → { rankScore: number, rankReasons: string[] }
 *
 * Scoring formula (0-100 scale):
 *   base  = actionabilityScore * 30 + truthLevelScore * 20 + tierScore * 10
 *   boosts = contextual signals (+5 to +15 each)
 *   penalties = developing demote, incomplete geo logic, etc.
 *
 * rankReasons are always emitted in plain English for human auditability.
 */

"use strict";

const { TRUTH_LEVEL, TRUTH_LEVEL_SCORE, ACTION_RUNG_ORDER, TIER_ORDER } = require('./contracts');

// ─── Constants ────────────────────────────────────────────────────────────────

/** Base score weights */
const WEIGHT_ACTIONABILITY = 30;
const WEIGHT_TRUTH_LEVEL   = 20;
const WEIGHT_TIER          = 10;

/** Max raw base (before normalization) */
// actionability max = 1.0 * 30 = 30
// truth level max = (4/4) * 20 = 20
// tier max = (5/5) * 10 = 10
// Total base max = 60; with boosts max = 60 + 73 = 133 → clamped to 100

/** Boost magnitudes */
const BOOST_YOUR_CHURCH    = 15;
const BOOST_LIFE_STAGE     = 10;
const BOOST_LITURGICAL     = 10;
const BOOST_CAPACITY       = 8;
const BOOST_LOOP_PARENT    = 15;
const BOOST_NEAR_YOU       = 10;

/** Penalty magnitudes */
const PENALTY_DEVELOPING   = 30;
const PENALTY_LAMENT_FRAME = 5;

/** Geo proximity threshold in km */
const GEO_RADIUS_KM = 10;

// ─── Helpers ─────────────────────────────────────────────────────────────────

/**
 * Score how actionable a card is, based on what rungs exist.
 * Higher rungs (GIVE, SHOW_UP, START) = more actionable = higher score.
 * Returns 0.0 – 1.0.
 */
function actionabilityScore(actions) {
  if (!Array.isArray(actions) || actions.length === 0) return 0;

  // Weight by highest rung present
  let maxRungIndex = 0;
  for (const action of actions) {
    const idx = ACTION_RUNG_ORDER.indexOf(action.rung);
    if (idx > maxRungIndex) maxRungIndex = idx;
  }

  // Normalize to 0-1: max index is 6 (START)
  return maxRungIndex / (ACTION_RUNG_ORDER.length - 1);
}

/**
 * Score the tier (lower TIER_ORDER index = closer to spiritual core = slightly higher).
 * Returns 0.0 – 1.0.
 */
function tierScore(tier) {
  const idx = TIER_ORDER.indexOf(tier);
  if (idx === -1) return 0.5;
  // SPIRITUAL (0) → 1.0, GLOBAL (4) → 0.2 (still some score for global)
  return 1.0 - (idx * 0.2);
}

/**
 * Haversine distance in km between two lat/lng points.
 */
function haversineKm(lat1, lng1, lat2, lng2) {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) *
    Math.cos((lat2 * Math.PI) / 180) *
    Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/**
 * Check if a card's geo is within GEO_RADIUS_KM of the user's location.
 */
function isNearUser(cardGeo, userLocation) {
  if (!cardGeo || !userLocation) return false;
  if (typeof cardGeo.lat !== 'number' || typeof cardGeo.lng !== 'number') return false;
  if (typeof userLocation.lat !== 'number' || typeof userLocation.lng !== 'number') return false;
  return haversineKm(cardGeo.lat, cardGeo.lng, userLocation.lat, userLocation.lng) <= GEO_RADIUS_KM;
}

/**
 * Check if the card's matchReasons include a reference to the user's season of life.
 */
function matchesLifeStage(card, seasonOfLife) {
  if (!seasonOfLife || !Array.isArray(card.matchReasons)) return false;
  const lower = seasonOfLife.toLowerCase();
  return card.matchReasons.some((r) => r.toLowerCase().includes(lower));
}

/**
 * Check liturgical season alignment.
 * Simple keyword match between card tags/summary and the liturgical season.
 */
function hasLiturgicalAlignment(card, liturgicalSeason) {
  if (!liturgicalSeason) return false;
  const lower = liturgicalSeason.toLowerCase();
  const searchText = [
    card.title || '',
    ...(card.summary || []),
    ...(card.matchReasons || []),
  ].join(' ').toLowerCase();
  return searchText.includes(lower);
}

// ─── Main export ──────────────────────────────────────────────────────────────

/**
 * rankCard — scores and explains a single IntelligenceCard.
 *
 * @param {object} card     IntelligenceCard (pre-assertCard)
 * @param {object} context  { userId, churchIds, followedChurchIds, seasonOfLife,
 *                            liturgicalSeason, userCapacity, location, priorActions }
 * @returns {{ rankScore: number, rankReasons: string[] }}
 */
function rankCard(card, context) {
  if (!card || typeof card !== 'object') {
    return { rankScore: 0, rankReasons: ['Card is missing or invalid'] };
  }

  const ctx = context || {};
  const reasons = [];
  let score = 0;

  // ── Base ────────────────────────────────────────────────────────────────────

  // 1. Actionability contribution
  const actScore = actionabilityScore(card.actions);
  const actContribution = actScore * WEIGHT_ACTIONABILITY;
  score += actContribution;
  if (actContribution >= 20) {
    reasons.push('Strong commitment ladder with high-effort action rungs');
  } else if (actContribution >= 10) {
    reasons.push('Moderate engagement options available');
  } else {
    reasons.push('Awareness-level card with low commitment ask');
  }

  // 2. Truth level contribution
  const tlScore = TRUTH_LEVEL_SCORE[card.truthLevel] || 1;
  const tlContribution = (tlScore / 4) * WEIGHT_TRUTH_LEVEL;
  score += tlContribution;

  const tlLabels = {
    [TRUTH_LEVEL.VERIFIED]: 'Information is independently verified',
    [TRUTH_LEVEL.CHURCH_CONFIRMED]: 'Confirmed by a church source',
    [TRUTH_LEVEL.COMMUNITY_CONFIRMED]: 'Community-confirmed information',
    [TRUTH_LEVEL.DEVELOPING]: 'Information is still developing',
  };
  if (tlLabels[card.truthLevel]) {
    reasons.push(tlLabels[card.truthLevel]);
  }

  // 3. Tier contribution
  const tContribution = tierScore(card.tier) * WEIGHT_TIER;
  score += tContribution;
  // (no separate reason — tier is implied by context)

  // ── Boosts ──────────────────────────────────────────────────────────────────

  // Followed church match
  const followedChurchIds = Array.isArray(ctx.followedChurchIds) ? ctx.followedChurchIds : [];
  if (
    card.backingEntity &&
    card.backingEntity.kind === 'CHURCH' &&
    followedChurchIds.includes(card.backingEntity.id)
  ) {
    score += BOOST_YOUR_CHURCH;
    reasons.push('Your church');
  }

  // Season of life relevance
  if (matchesLifeStage(card, ctx.seasonOfLife)) {
    score += BOOST_LIFE_STAGE;
    reasons.push('Relevant to your life stage');
  }

  // Liturgical season alignment
  if (hasLiturgicalAlignment(card, ctx.liturgicalSeason)) {
    score += BOOST_LITURGICAL;
    reasons.push('Seasonally relevant');
  }

  // User capacity
  if (ctx.userCapacity === 'available') {
    score += BOOST_CAPACITY;
    reasons.push('You have capacity to act now');
  }

  // Loop parent follow-up
  const priorActions = Array.isArray(ctx.priorActions) ? ctx.priorActions : [];
  if (card.formation && card.formation.loopParentId && priorActions.includes(card.formation.loopParentId)) {
    score += BOOST_LOOP_PARENT;
    reasons.push('Follows up on your prior action');
  }

  // Geographic proximity
  if (isNearUser(card.geo, ctx.location)) {
    score += BOOST_NEAR_YOU;
    reasons.push('Near you');
  }

  // ── Penalties ───────────────────────────────────────────────────────────────

  // DEVELOPING truthLevel — demote to bottom
  if (card.truthLevel === TRUTH_LEVEL.DEVELOPING) {
    score -= PENALTY_DEVELOPING;
    reasons.push('Developing story — score reduced until verified');
  }

  // Lament frame without disaster context
  if (card.formation && card.formation.lamentFrame) {
    const priorStr = priorActions.join(' ').toLowerCase();
    const hasDisasterContext =
      priorStr.includes('disaster') ||
      priorStr.includes('crisis') ||
      priorStr.includes('emergency') ||
      priorStr.includes('grief');
    if (!hasDisasterContext) {
      score -= PENALTY_LAMENT_FRAME;
      reasons.push('Lament framing without confirmed crisis context');
    }
  }

  // GLOBAL with missing source — hard reject at card level (returns 0 score)
  if (card.tier === 'GLOBAL' && (!card.source || card.source.trim() === '')) {
    return {
      rankScore: 0,
      rankReasons: ['GLOBAL tier card rejected: source is required but missing'],
    };
  }

  // ── Clamp and finalize ───────────────────────────────────────────────────────

  const rankScore = Math.max(0, Math.min(100, Math.round(score)));

  // Guarantee at least one reason is always present
  if (reasons.length === 0) {
    reasons.push('Standard relevance score');
  }

  return { rankScore, rankReasons: reasons };
}

module.exports = { rankCard };
