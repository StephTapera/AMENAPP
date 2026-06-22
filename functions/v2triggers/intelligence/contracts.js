/**
 * functions/intelligence/contracts.js
 *
 * AMEN Living Intelligence — Frozen Contracts
 *
 * All constants, enum tables, and the canonical assertCard validator.
 * Other agents import from here — do not change exported names.
 *
 * Formation invariants enforced by assertCard:
 *   I-1  backingEntity present and verified === true
 *   I-2  rankReasons non-empty array
 *   I-3  formation.finite === true
 *   I-4  formation.spectacleCounters === false
 *   I-5  summary.length <= 3
 *   I-6  GLOBAL tier cards must have a source
 *   I-7  actions non-empty
 *   I-8  expiresAt > createdAt
 *   I-9  DEVELOPING truthLevel cannot exceed rankScore 80
 *   I-10 geo (if present) must have coarse: true
 */

"use strict";

// ─── Tier Order ──────────────────────────────────────────────────────────────
const TIER_ORDER = ['SPIRITUAL', 'COMMUNITY', 'FAMILY', 'LOCAL', 'GLOBAL'];

// ─── Truth Level ─────────────────────────────────────────────────────────────
const TRUTH_LEVEL = {
  VERIFIED:             'VERIFIED',
  CHURCH_CONFIRMED:     'CHURCH_CONFIRMED',
  COMMUNITY_CONFIRMED:  'COMMUNITY_CONFIRMED',
  DEVELOPING:           'DEVELOPING',
};

const TRUTH_LEVEL_SCORE = {
  VERIFIED:             4,
  CHURCH_CONFIRMED:     3,
  COMMUNITY_CONFIRMED:  2,
  DEVELOPING:           1,
};

// ─── Action Rung ─────────────────────────────────────────────────────────────
const ACTION_RUNG = {
  NOTICE:   'NOTICE',
  PRAY:     'PRAY',
  LEARN:    'LEARN',
  DISCUSS:  'DISCUSS',
  GIVE:     'GIVE',
  SHOW_UP:  'SHOW_UP',
  START:    'START',
};

const ACTION_RUNG_ORDER = ['NOTICE', 'PRAY', 'LEARN', 'DISCUSS', 'GIVE', 'SHOW_UP', 'START'];

// ─── Backing Kind ─────────────────────────────────────────────────────────────
const BACKING_KIND = {
  CHURCH:          'CHURCH',
  ORG:             'ORG',
  EVENT:           'EVENT',
  PRAYER_REQUEST:  'PRAYER_REQUEST',
  STUDY:           'STUDY',
  NEED:            'NEED',
};

// ─── Brief Caps ───────────────────────────────────────────────────────────────
const MAX_CARDS_PER_BRIEF = 7;
const MAX_BRIEFS_PER_DAY  = 2;

// ─── Validator ────────────────────────────────────────────────────────────────

/**
 * assertCard — throws a descriptive Error if any formation invariant is violated.
 *
 * @param {object} card  IntelligenceCard candidate object
 * @throws {Error}       Descriptive message naming the violated invariant
 */
function assertCard(card) {
  if (!card || typeof card !== 'object') {
    throw new Error('assertCard: card must be a non-null object');
  }

  // I-1: backingEntity must be present and verified
  if (!card.backingEntity || typeof card.backingEntity !== 'object') {
    throw new Error('assertCard I-1: backingEntity is required');
  }
  if (card.backingEntity.verified !== true) {
    throw new Error('assertCard I-1: backingEntity.verified must be true — unverified entities cannot render');
  }
  if (!card.backingEntity.kind || !card.backingEntity.id) {
    throw new Error('assertCard I-1: backingEntity must have kind and id');
  }

  // I-2: rankReasons must be a non-empty array
  if (!Array.isArray(card.rankReasons) || card.rankReasons.length === 0) {
    throw new Error('assertCard I-2: rankReasons must be a non-empty array');
  }

  // I-3: formation.finite must be true
  if (!card.formation || card.formation.finite !== true) {
    throw new Error('assertCard I-3: formation.finite must be true — briefs are always finite');
  }

  // I-4: formation.spectacleCounters must be false
  if (card.formation.spectacleCounters !== false) {
    throw new Error('assertCard I-4: formation.spectacleCounters must be false — no engagement counters');
  }

  // I-5: summary must be array of <= 3 bullets
  if (!Array.isArray(card.summary) || card.summary.length > 3) {
    throw new Error(`assertCard I-5: summary must be an array with at most 3 bullets, got ${Array.isArray(card.summary) ? card.summary.length : typeof card.summary}`);
  }

  // I-6: GLOBAL tier cards must have a source
  if (card.tier === 'GLOBAL' && (!card.source || typeof card.source !== 'string' || card.source.trim() === '')) {
    throw new Error('assertCard I-6: GLOBAL tier cards must have a source field');
  }

  // I-7: actions must be non-empty
  if (!Array.isArray(card.actions) || card.actions.length === 0) {
    throw new Error('assertCard I-7: actions must be a non-empty array');
  }

  // I-8: expiresAt must be after createdAt
  if (typeof card.expiresAt !== 'number' || typeof card.createdAt !== 'number') {
    throw new Error('assertCard I-8: expiresAt and createdAt must be numbers (epoch ms)');
  }
  if (card.expiresAt <= card.createdAt) {
    throw new Error(`assertCard I-8: expiresAt (${card.expiresAt}) must be greater than createdAt (${card.createdAt})`);
  }

  // I-9: DEVELOPING cannot have rankScore > 80
  if (card.truthLevel === TRUTH_LEVEL.DEVELOPING && typeof card.rankScore === 'number' && card.rankScore > 80) {
    throw new Error(`assertCard I-9: DEVELOPING truthLevel card cannot have rankScore > 80, got ${card.rankScore}`);
  }

  // I-10: geo if present must have coarse: true
  if (card.geo !== undefined && card.geo !== null) {
    if (typeof card.geo !== 'object' || card.geo.coarse !== true) {
      throw new Error('assertCard I-10: geo must have coarse: true — precise location is not permitted');
    }
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

/**
 * buildCardId — deterministic, stable card ID for a given kind/entityId/userId tuple.
 * Stable across re-generations so loop-closing can match prior actions.
 *
 * @param {string} kind     — e.g. 'event', 'prayer', 'need'
 * @param {string} entityId — backing entity's Firestore doc id
 * @param {string} userId   — current user's uid
 * @returns {string}
 */
function buildCardId(kind, entityId, userId) {
  if (!kind || !entityId || !userId) {
    throw new Error('buildCardId: kind, entityId, and userId are all required');
  }
  return `${kind}_${entityId}_${userId}`;
}

// ─── Exports ──────────────────────────────────────────────────────────────────

module.exports = {
  TIER_ORDER,
  TRUTH_LEVEL,
  TRUTH_LEVEL_SCORE,
  ACTION_RUNG,
  ACTION_RUNG_ORDER,
  BACKING_KIND,
  MAX_CARDS_PER_BRIEF,
  MAX_BRIEFS_PER_DAY,
  assertCard,
  buildCardId,
};
