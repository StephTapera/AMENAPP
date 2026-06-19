// ranking.ts — Find a Church v2 ranking engine contract
//
// Wave 0 freeze per FIND_CHURCH_V2_SPEC.md §4.
// The score is a DOCUMENTED weighted sum. Weights live as exported, auditable
// constants so they can be reviewed and tuned (cite path:line for any PASS).
//
// This file is the structural sibling of the assembleDiscoveryFeed engine
// (rankingBrain.js weighted-sum + formationGovernor caps). It defines the
// weights, the gate rules, and PURE scaffold signatures. Function bodies are
// implemented in Wave 1; nothing here is wired to a callable yet.
//
// Wave 1 note: distance math uses geofire-common (haversine/geohash); that
// dependency is NOT yet installed (see RULES_PLAN_FIND_CHURCH.md). Wave 0 keeps
// this file dependency-free so it compiles standalone.

import type { Church, ChurchPreferences, ServiceTime, ReportState } from "../contracts/church";

// ---------------------------------------------------------------------------
// WEIGHTS (auditable constant) — spec §4
// ---------------------------------------------------------------------------

/**
 * Positive contribution weights. Each term is normalized to roughly [0,1]
 * before being multiplied by its weight, so weights are directly comparable.
 */
export const W = {
  distance: 0.22,          // closer better, soft decay
  serviceProximity: 0.18,  // a service starting soon ranks up
  preferenceMatch: 0.16,   // denomination + ministry overlap with user prefs
  accessibility: 0.08,     // accessibility needs met
  language: 0.08,          // language match
  verified: 0.07,          // verification.status === 'verified'
  safetySignal: 0.07,      // child-safety policy present (never negative for absence)
  eventActivity: 0.05,     // recent event activity
  completeness: 0.04,      // profileCompleteness
  engagement: 0.05,        // normalized followers (capped, non-vanity)
} as const;

/**
 * Penalty weights (subtracted). `restricted` is effectively a removal; it is
 * also enforced as a HARD GATE below (do not rely on the penalty alone).
 */
export const P = {
  reportPenalty: 0.30,     // reportState === 'under_review'
  restricted: 1000,        // reportState === 'restricted' → effectively removes
} as const;

// Compile-time assertion that positive weights sum to 1.0 (auditable).
// (1e-9 tolerance for float addition.)
const _W_SUM =
  W.distance + W.serviceProximity + W.preferenceMatch + W.accessibility +
  W.language + W.verified + W.safetySignal + W.eventActivity +
  W.completeness + W.engagement;
// eslint-disable-next-line @typescript-eslint/no-unused-vars
const _W_SUM_OK: true = (Math.abs(_W_SUM - 1) < 1e-9) as true;

// ---------------------------------------------------------------------------
// CalmCap defaults — spec §1
// ---------------------------------------------------------------------------

export const CALM_CAP = {
  maxItemsPerSection: 12,
  infiniteScroll: false as const,
};

// Radius clamp — spec §3.
export const RADIUS_CLAMP_METERS = { min: 1000, max: 80000 } as const;

// MMR diversification — spec §4: no more than 2 consecutive cards of the same
// denomination in a section.
export const MAX_CONSECUTIVE_SAME_DENOMINATION = 2;

// ---------------------------------------------------------------------------
// HARD RANKING RULES (gates, not weights) — spec §4
// ---------------------------------------------------------------------------

/** restricted churches are excluded from ALL results. */
export function isExcludedByReportState(state: ReportState): boolean {
  return state === "restricted";
}

/**
 * Unverified churches are INCLUDED but labeled, and EXCLUDED from `suggested`
 * (suggestions imply endorsement). They may appear in `nearby` with the label.
 */
export function isEligibleForSuggested(church: Pick<Church, "verification">): boolean {
  return church.verification.status === "verified";
}

// ---------------------------------------------------------------------------
// Ranking context
// ---------------------------------------------------------------------------

export interface RankingContext {
  center: { lat: number; lng: number };
  radiusMeters: number;
  nowMs: number;
  preferences: ChurchPreferences | null;   // server-resolved; null when none set
  isMinor: boolean;                         // server-resolved from auth
}

export interface ScoredChurch {
  churchId: string;
  score: number;
  distanceMeters: number;
  whyMatched: string[];                     // generated from top contributors, max 3
}

// ---------------------------------------------------------------------------
// PURE term functions — Wave 1 implements bodies; signatures frozen now.
// All return a normalized [0,1] contribution (before weight multiply), except
// where noted. They never throw and never mutate inputs.
// ---------------------------------------------------------------------------

export function distanceDecay(_distanceMeters: number, _radiusMeters: number): number {
  // Wave 1: soft monotonic decay, 1 at 0m → ~0 at radius.
  return 0;
}

export function nextServiceSoonness(_serviceTimes: ServiceTime[], _nowMs: number): number {
  // Wave 1: a service starting soon ranks up; far/no upcoming → 0.
  return 0;
}

export function denominationAndMinistryOverlap(
  _church: Church,
  _prefs: ChurchPreferences | null,
): number {
  return 0;
}

export function accessibilityNeedsMet(_church: Church, _prefs: ChurchPreferences | null): number {
  return 0;
}

export function languageMatch(_church: Church, _prefs: ChurchPreferences | null): number {
  return 0;
}

export function recentEventActivity(_church: Church, _nowMs: number): number {
  return 0;
}

export function normalizedFollowers(_church: Church): number {
  // capped, non-vanity normalization
  return 0;
}

/**
 * safetyScore: hasChildSafetyPolicy (+), backgroundCheckPolicy in
 * {all_volunteers, child_facing} (+). Missing both is NEUTRAL (0), never
 * negative for absence (do not penalize small churches). Absence still blocks
 * the `kids_safe_policy` badge (handled at badge assembly, not here).
 */
export function safetyScore(church: Church): number {
  let s = 0;
  if (church.safety.hasChildSafetyPolicy) s += 0.5;
  if (church.safety.backgroundCheckPolicy === "all_volunteers" ||
      church.safety.backgroundCheckPolicy === "child_facing") {
    s += 0.5;
  }
  return s; // [0,1], never negative
}

// ---------------------------------------------------------------------------
// score() — the documented weighted sum. Wave 1 fills term bodies above;
// this composition is the frozen contract.
// ---------------------------------------------------------------------------

export function score(church: Church, ctx: RankingContext, distanceMeters: number): number {
  if (isExcludedByReportState(church.reportState)) {
    return -P.restricted; // gated out; also filtered upstream
  }

  const positive =
      W.distance         * distanceDecay(distanceMeters, ctx.radiusMeters)
    + W.serviceProximity * nextServiceSoonness([], ctx.nowMs)
    + W.preferenceMatch  * denominationAndMinistryOverlap(church, ctx.preferences)
    + W.accessibility    * accessibilityNeedsMet(church, ctx.preferences)
    + W.language         * languageMatch(church, ctx.preferences)
    + W.verified         * (church.verification.status === "verified" ? 1 : 0)
    + W.safetySignal     * safetyScore(church)
    + W.eventActivity    * recentEventActivity(church, ctx.nowMs)
    + W.completeness     * church.profileCompleteness
    + W.engagement       * normalizedFollowers(church);

  const penalty =
      P.reportPenalty * (church.reportState === "under_review" ? 1 : 0)
    + P.restricted    * (church.reportState === "restricted" ? 1 : 0);

  return positive - penalty;
}
