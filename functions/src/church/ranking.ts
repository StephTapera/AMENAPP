// ranking.ts — Find a Church v2 ranking engine (Wave 1 implementation)
//
// The score is a DOCUMENTED weighted sum. Weights live as exported, auditable
// constants (W/P) so they can be reviewed and tuned. Structural sibling of the
// assembleDiscoveryFeed engine (rankingBrain weighted-sum + formationGovernor
// caps). Pure and side-effect-free: the engine computes features (distance,
// next-service) and passes them in; this module never touches Firestore, geo,
// or timezone libraries.
//
// `whyMatched` is generated from the ACTUAL top-contributing terms (spec §4) —
// it is an explanation of the score, not marketing copy.

import type { Church, ChurchPreferences, ReportState } from "../contracts/church";

// ---------------------------------------------------------------------------
// WEIGHTS (auditable constant) — spec §4
// ---------------------------------------------------------------------------

/** Positive contribution weights. Each term is normalized to [0,1] before the
 *  multiply, so weights are directly comparable. They sum to 1.0. */
export const W = {
  distance: 0.22,
  serviceProximity: 0.18,
  preferenceMatch: 0.16,
  accessibility: 0.08,
  language: 0.08,
  verified: 0.07,
  safetySignal: 0.07,
  eventActivity: 0.05,
  completeness: 0.04,
  engagement: 0.05,
} as const;

/** Penalty weights (subtracted). `restricted` is also a HARD GATE below. */
export const P = {
  reportPenalty: 0.30,
  restricted: 1000,
} as const;

const _W_SUM =
  W.distance + W.serviceProximity + W.preferenceMatch + W.accessibility +
  W.language + W.verified + W.safetySignal + W.eventActivity +
  W.completeness + W.engagement;
// eslint-disable-next-line @typescript-eslint/no-unused-vars
const _W_SUM_OK: true = (Math.abs(_W_SUM - 1) < 1e-9) as true;

// ---------------------------------------------------------------------------
// CalmCap / clamps / MMR — spec §1, §3, §4
// ---------------------------------------------------------------------------

export const CALM_CAP = { maxItemsPerSection: 12, infiniteScroll: false as const };
export const RADIUS_CLAMP_METERS = { min: 1000, max: 80000 } as const;
export const MAX_CONSECUTIVE_SAME_DENOMINATION = 2;

// ---------------------------------------------------------------------------
// HARD RANKING RULES (gates, not weights) — spec §4
// ---------------------------------------------------------------------------

/** restricted churches are excluded from ALL results. */
export function isExcludedByReportState(state: ReportState): boolean {
  return state === "restricted";
}

/** Unverified churches are INCLUDED but labeled, and EXCLUDED from `suggested`. */
export function isEligibleForSuggested(church: Pick<Church, "verification">): boolean {
  return church.verification.status === "verified";
}

// ---------------------------------------------------------------------------
// Ranking context + features
// ---------------------------------------------------------------------------

export interface RankingContext {
  center: { lat: number; lng: number };
  radiusMeters: number;
  nowMs: number;
  preferences: ChurchPreferences | null;
  isMinor: boolean;
}

/** Per-church features the engine precomputes (no geo/tz logic lives here). */
export interface ChurchFeatures {
  distanceMeters: number;
  /** minutes until the next upcoming service occurrence, or null if none soon. */
  nextServiceMinutes: number | null;
  /** number of events in the church's recent/upcoming window. */
  recentEventCount: number;
}

interface Contributor {
  key: keyof typeof W;
  label: string;     // concrete, human-readable explanation
  weighted: number;  // weight * normalized term, used to rank contributors
}

// ---------------------------------------------------------------------------
// PURE term functions — return a normalized [0,1] contribution.
// ---------------------------------------------------------------------------

export function distanceDecay(distanceMeters: number, radiusMeters: number): number {
  if (radiusMeters <= 0) return 0;
  // soft exponential decay: 1 at 0m, ~0.37 at half-radius, → 0 by radius.
  const x = Math.min(1, Math.max(0, distanceMeters / radiusMeters));
  return Math.exp(-2 * x);
}

export function nextServiceSoonness(nextServiceMinutes: number | null): number {
  if (nextServiceMinutes == null || nextServiceMinutes < 0) return 0;
  // starting now → 1; linear-ish decay to 0 over a 7-day horizon.
  const HORIZON = 7 * 24 * 60;
  if (nextServiceMinutes >= HORIZON) return 0;
  return 1 - nextServiceMinutes / HORIZON;
}

export function denominationAndMinistryOverlap(
  church: Church,
  prefs: ChurchPreferences | null,
): number {
  if (!prefs) return 0;
  let score = 0;
  if (prefs.denominations.length > 0 && prefs.denominations.includes(church.denomination)) {
    score += 0.5;
  }
  if (prefs.ministries.length > 0) {
    const overlap = prefs.ministries.filter((m) => church.ministries.includes(m)).length;
    if (overlap > 0) score += 0.5 * Math.min(1, overlap / prefs.ministries.length);
  }
  return Math.min(1, score);
}

export function accessibilityNeedsMet(church: Church, prefs: ChurchPreferences | null): number {
  if (!prefs) return 0;
  const needs = prefs.accessibilityNeeds;
  const required: boolean[] = [];
  if (needs.wheelchair) required.push(church.accessibility.wheelchair);
  if (needs.hearingLoop) required.push(church.accessibility.hearingLoop);
  if (needs.aslInterpreted) required.push(church.accessibility.aslInterpreted);
  if (required.length === 0) return 0; // no needs declared → neutral
  return required.filter(Boolean).length / required.length;
}

export function languageMatch(church: Church, prefs: ChurchPreferences | null): number {
  if (!prefs || prefs.languages.length === 0) return 0;
  return prefs.languages.some((l) => church.languages.includes(l)) ? 1 : 0;
}

export function recentEventActivity(recentEventCount: number): number {
  if (recentEventCount <= 0) return 0;
  return Math.min(1, recentEventCount / 5); // saturates at 5 events
}

export function normalizedFollowers(church: Church): number {
  // capped, non-vanity: log-scaled and saturated so big churches can't dominate.
  const f = Math.max(0, church.followerCount);
  return Math.min(1, Math.log10(f + 1) / 4); // ~10k followers → 1.0
}

/** safetyScore: policy present (+), background-check for volunteers/child-facing
 *  (+). Missing both is NEUTRAL (0), never negative (don't penalize small
 *  churches). Absence still blocks the kids_safe_policy badge (handled in
 *  projection, not here). */
export function safetyScore(church: Church): number {
  let s = 0;
  if (church.safety.hasChildSafetyPolicy) s += 0.5;
  if (church.safety.backgroundCheckPolicy === "all_volunteers" ||
      church.safety.backgroundCheckPolicy === "child_facing") {
    s += 0.5;
  }
  return s;
}

// ---------------------------------------------------------------------------
// Distance display helpers (for whyMatched labels only).
// ---------------------------------------------------------------------------

function milesLabel(distanceMeters: number): string {
  const mi = distanceMeters / 1609.344;
  return `${mi.toFixed(1)} mi away`;
}

function serviceLabel(nextServiceMinutes: number): string {
  if (nextServiceMinutes < 60) return `Service starts in ${Math.round(nextServiceMinutes)} min`;
  if (nextServiceMinutes < 24 * 60) return `Service starts in ${Math.round(nextServiceMinutes / 60)} hr`;
  return `Next service in ${Math.round(nextServiceMinutes / (24 * 60))} days`;
}

// ---------------------------------------------------------------------------
// score() + scoreChurch() — the frozen weighted-sum composition.
// ---------------------------------------------------------------------------

export interface ScoreResult {
  score: number;
  whyMatched: string[];   // top-3 contributors, concrete labels
}

export function scoreChurch(church: Church, ctx: RankingContext, f: ChurchFeatures): ScoreResult {
  if (isExcludedByReportState(church.reportState)) {
    return { score: -P.restricted, whyMatched: [] };
  }

  const terms = {
    distance:         distanceDecay(f.distanceMeters, ctx.radiusMeters),
    serviceProximity: nextServiceSoonness(f.nextServiceMinutes),
    preferenceMatch:  denominationAndMinistryOverlap(church, ctx.preferences),
    accessibility:    accessibilityNeedsMet(church, ctx.preferences),
    language:         languageMatch(church, ctx.preferences),
    verified:         church.verification.status === "verified" ? 1 : 0,
    safetySignal:     safetyScore(church),
    eventActivity:    recentEventActivity(f.recentEventCount),
    completeness:     Math.min(1, Math.max(0, church.profileCompleteness)),
    engagement:       normalizedFollowers(church),
  };

  const contributors: Contributor[] = [];
  const add = (key: keyof typeof W, label: string) => {
    const weighted = W[key] * terms[key];
    if (weighted > 0) contributors.push({ key, label, weighted });
  };

  add("distance", milesLabel(f.distanceMeters));
  if (f.nextServiceMinutes != null) add("serviceProximity", serviceLabel(f.nextServiceMinutes));
  add("preferenceMatch", prefMatchLabel(church, ctx.preferences));
  add("accessibility", "Meets your accessibility needs");
  add("language", "Service in your language");
  add("verified", "Verified church");
  add("safetySignal", "Child-safety policy");
  add("eventActivity", "Active this week");
  add("completeness", "Complete profile");
  add("engagement", "Active community");

  const positive =
      W.distance         * terms.distance
    + W.serviceProximity * terms.serviceProximity
    + W.preferenceMatch  * terms.preferenceMatch
    + W.accessibility    * terms.accessibility
    + W.language         * terms.language
    + W.verified         * terms.verified
    + W.safetySignal     * terms.safetySignal
    + W.eventActivity    * terms.eventActivity
    + W.completeness     * terms.completeness
    + W.engagement       * terms.engagement;

  const penalty = P.reportPenalty * (church.reportState === "under_review" ? 1 : 0);

  const whyMatched = contributors
    .sort((a, b) => b.weighted - a.weighted)
    .slice(0, 3)
    .map((c) => c.label);

  return { score: positive - penalty, whyMatched };
}

function prefMatchLabel(church: Church, prefs: ChurchPreferences | null): string {
  if (prefs && prefs.denominations.includes(church.denomination)) {
    return `Matches your preference`;
  }
  const overlap = prefs?.ministries.find((m) => church.ministries.includes(m));
  if (overlap) return `${overlap.replace(/_/g, " ")} ministry`;
  return "Matches your preferences";
}
