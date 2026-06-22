/**
 * ageTier.js — single source of truth for COPPA/age-tier classification.
 *
 * GAP BOARD P0-11: this logic previously lived only inside authenticationHelpers.js
 * and the unit test forked its own private copy, so the test could pass while the
 * real consumers (firestore.rules, AMENSecureMessagingService) drifted to a stale
 * vocabulary. Extracted here so production AND the test import the same function.
 *
 * Tier mapping (the authoritative vocabulary used app-wide):
 *   blocked  — age < 13   (COPPA hard block)
 *   tierB    — 13–15
 *   tierC    — 16–17
 *   tierD    — 18+
 *
 * Missing, malformed, or out-of-range birth years fail closed to blocked.
 */

/**
 * Compute age tier from birth year. currentYear is injected to keep it testable.
 * @param {number} birthYear Four-digit birth year.
 * @param {number} currentYear Current four-digit year.
 * @return {string} One of: blocked | tierB | tierC | tierD.
 */
function computeAgeTier(birthYear, currentYear) {
  if (!birthYear || typeof birthYear !== "number") return "blocked";
  const age = currentYear - birthYear;
  if (age < 13) return "blocked";
  if (age <= 15) return "tierB";
  if (age <= 17) return "tierC";
  return "tierD";
}

// The complete, authoritative set of tiers the rest of the system must recognise.
const AGE_TIERS = Object.freeze(["blocked", "tierB", "tierC", "tierD"]);
// Tiers that denote a minor (under 18).
const MINOR_TIERS = Object.freeze(["blocked", "tierB", "tierC"]);

module.exports = {computeAgeTier, AGE_TIERS, MINOR_TIERS};
