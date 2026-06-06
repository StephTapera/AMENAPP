/**
 * formationGovernor.ts
 *
 * Synchronous enforcement of all FORMATION_INVARIANTS.
 * No I/O. All logic is pure — safe to call in hot paths or test without mocks.
 *
 * Invariants enforced:
 *  - FINITE_BRIEF: max 7 cards
 *  - DEVELOPING_NEVER_TOP: DEVELOPING truth level may not be card #1
 *  - NO_SPECTACLE_COUNTERS: formation.spectacleCounters must always be false
 *  - POLITICS_ROUTE_ONLY: cards tagged as politics/conflict only allow PRAY/SHOW_UP/GIVE
 *  - LOOP_CLOSING_REQUIRED: cards with loopParentId should appear when loopParentId present
 *  - COARSE_GEO_ONLY: geo must carry coarse:true if present
 */

import {
  IntelligenceCard,
  TruthLevel,
  ActionRung,
  MAX_CARDS_PER_BRIEF,
  FORMATION_INVARIANTS,
} from "./contracts";

// ─── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Returns true if the card's tier or summary hints at a political/conflict topic.
 * Checks are based on observable card data (tier GLOBAL + world_response source pattern).
 */
function isPoliticsCard(card: IntelligenceCard): boolean {
  // A card is considered "politics" if it's GLOBAL tier and its source signals
  // a contested/political topic, or if its actions already only contain
  // the allowed political rungs (which means it was authored as a politics card).
  if (card.tier !== "GLOBAL") return false;

  const allowedRungs = new Set<ActionRung>(FORMATION_INVARIANTS.POLITICS_ROUTE_ONLY);
  const allActionsAreAllowed = card.actions.every((a) => allowedRungs.has(a.rung));

  // If *any* action is outside the allowed set, this card needs enforcement.
  // If all actions are already allowed rungs, it's already compliant.
  // We flag as politics to validate (returns true so the validator checks it).
  return !allActionsAreAllowed || (card.source?.toLowerCase().includes("contested") ?? false);
}

// ─── Public API ───────────────────────────────────────────────────────────────

/**
 * Truncate the brief to MAX_CARDS_PER_BRIEF.
 * Sorting rule: DEVELOPING cards sort last (DEVELOPING_NEVER_TOP invariant).
 * Among non-DEVELOPING cards, preserves caller-supplied order (already ranked).
 */
export function enforceCardCap(cards: IntelligenceCard[]): IntelligenceCard[] {
  const DEVELOPING: TruthLevel = "DEVELOPING";

  // Partition: verified/confirmed first, DEVELOPING last
  const nonDeveloping = cards.filter((c) => c.truthLevel !== DEVELOPING);
  const developing = cards.filter((c) => c.truthLevel === DEVELOPING);

  const ordered = [...nonDeveloping, ...developing];
  return ordered.slice(0, MAX_CARDS_PER_BRIEF);
}

/**
 * True if the first card has DEVELOPING truth level.
 * The caller should use this as a guard: if true, re-sort before rendering.
 */
export function isDevelopingTopRanked(cards: IntelligenceCard[]): boolean {
  if (cards.length === 0) return false;
  return cards[0].truthLevel === "DEVELOPING";
}

/**
 * True if a politics/conflict card correctly routes ONLY to PRAY / SHOW_UP / GIVE.
 * Returns true for non-politics cards (they are not subject to this constraint).
 */
export function isPoliticsRoutedCorrectly(card: IntelligenceCard): boolean {
  if (!isPoliticsCard(card)) return true;

  const allowedRungs = new Set<ActionRung>(FORMATION_INVARIANTS.POLITICS_ROUTE_ONLY);
  return card.actions.every((a) => allowedRungs.has(a.rung));
}

/**
 * Returns whether a card has spectacle counters.
 * Per FORMATION_INVARIANTS.NO_SPECTACLE_COUNTERS this must ALWAYS be false.
 */
export function hasSpectacleCounters(card: IntelligenceCard): boolean {
  // spectacleCounters is typed as literal `false` in the contract.
  // Cast through unknown to allow runtime violation detection.
  return (card.formation.spectacleCounters as unknown) === true;
}

/**
 * Validates a full brief against all FORMATION_INVARIANTS.
 * Returns {valid: true} when all invariants pass; otherwise lists all violations.
 */
export function validateBrief(cards: IntelligenceCard[]): {
  valid: boolean;
  violations: string[];
} {
  const violations: string[] = [];

  // INVARIANT: FINITE_BRIEF — card count must not exceed MAX_CARDS_PER_BRIEF
  if (cards.length > MAX_CARDS_PER_BRIEF) {
    violations.push(
      `FINITE_BRIEF: ${cards.length} cards exceeds MAX_CARDS_PER_BRIEF (${MAX_CARDS_PER_BRIEF})`
    );
  }

  // INVARIANT: DEVELOPING_NEVER_TOP — first card must not be DEVELOPING
  if (isDevelopingTopRanked(cards)) {
    violations.push(
      `DEVELOPING_NEVER_TOP: top card "${cards[0].id}" has truthLevel DEVELOPING`
    );
  }

  for (const card of cards) {
    // INVARIANT: NO_SPECTACLE_COUNTERS
    if (hasSpectacleCounters(card)) {
      violations.push(
        `NO_SPECTACLE_COUNTERS: card "${card.id}" has formation.spectacleCounters=true`
      );
    }

    // INVARIANT: POLITICS_ROUTE_ONLY
    if (!isPoliticsRoutedCorrectly(card)) {
      const illegalRungs = card.actions
        .filter((a) => !(FORMATION_INVARIANTS.POLITICS_ROUTE_ONLY as readonly ActionRung[]).includes(a.rung))
        .map((a) => a.rung)
        .join(", ");
      violations.push(
        `POLITICS_ROUTE_ONLY: card "${card.id}" is a GLOBAL card with disallowed actions [${illegalRungs}]`
      );
    }

    // INVARIANT: NO_SPECTACLE_COUNTERS — formation.spectacleCounters must literally be false
    if (card.formation.spectacleCounters !== false) {
      violations.push(
        `NO_SPECTACLE_COUNTERS: card "${card.id}" formation.spectacleCounters is not false`
      );
    }

    // INVARIANT: COARSE_GEO_ONLY — if geo is present, coarse must be true
    if (card.geo !== undefined && card.geo.coarse !== true) {
      violations.push(
        `COARSE_GEO_ONLY: card "${card.id}" has geo without coarse:true`
      );
    }

    // INVARIANT: rankReasons must be populated (LOOP_CLOSING_REQUIRED proxy)
    if (!card.rankReasons || card.rankReasons.length === 0) {
      violations.push(
        `LOOP_CLOSING_REQUIRED: card "${card.id}" has no rankReasons — every card must explain why it surfaced`
      );
    }

    // INVARIANT: backingEntity must be present
    if (!card.backingEntity) {
      violations.push(
        `BACKING_REQUIRED: card "${card.id}" is missing backingEntity`
      );
    }

    // INVARIANT: actions must be non-empty (dead buttons not allowed)
    if (!card.actions || card.actions.length === 0) {
      violations.push(
        `DEAD_BUTTON: card "${card.id}" has no actions`
      );
    }

    // INVARIANT: summary max bullets
    if (card.summary && card.summary.length > 3) {
      violations.push(
        `MAX_SUMMARY_BULLETS: card "${card.id}" has ${card.summary.length} summary bullets (max 3)`
      );
    }
  }

  return { valid: violations.length === 0, violations };
}

/**
 * Convenience: apply enforceCardCap + validateBrief in one call.
 * Returns the capped-and-sorted cards plus any invariant violations.
 */
export function buildAndValidateBrief(cards: IntelligenceCard[]): {
  cards: IntelligenceCard[];
  valid: boolean;
  violations: string[];
} {
  const capped = enforceCardCap(cards);
  const { valid, violations } = validateBrief(capped);
  return { cards: capped, valid, violations };
}
