// heyFeed/heyFeedSteering.ts
// AMEN HeyFeed v2 — Steerable Feed · TypeScript mirror (SOURCE OF TRUTH).
// Wave 0 FROZEN: 2026-06-23. Spec authority: audit/BORROW_AND_SMARTEN_SPEC.md §8.2 Feature A.
// Swift side (HeyFeedSteeringContracts.swift) must mirror these field-for-field.
//
// EXTENDS HeyFeedModels / HeyFeedAlgorithm / HeyFeedNLModels + COMPASS. ONE ranking pipeline.
// HeyFeedAlgorithm stays the scorer; v2 adds (a) a user-owned, transparent, additive + CLAMPED
// steering delta and (b) an immovable SafetyFloor that runs BEFORE ranking and cannot be relaxed
// by any preference.
//
// INVARIANTS (heyFeedSteering.test.ts):
//   • SafetyFloor is non-overridable: a preference can only make the feed STRICTER, never laxer.
//   • Steering is clamped to ±STEER_CLAMP; baseScore stays HeyFeedAlgorithm.weightedTotal.
//   • Every steered item carries a truthful reason (RankingSignal.rationaleText).
//   • PreferenceVocabulary is user-owned / inspectable / deletable (PRIVACY-CORE preference zone);
//     liturgical context is additive only. NSPrivacyTracking=false.
//   • SafetyFloor is NOT gated by the heyFeedSteering flag — always-on like child safety.
//   • Fail-closed: an unevaluable post never surfaces (failClosedFloorVerdict.allowed === false).

// ────────────────────────────────────────────────────────────────────
// Steering vocabulary (maps HeyFeedNLAction from HeyFeedNLModels)
// ────────────────────────────────────────────────────────────────────

export type SteeringVerb =
  | "moreOf"
  | "lessOf"
  | "prioritize"
  | "mute"
  | "explore"
  | "reset"; // maps HeyFeedNLAction

export type SteeringTargetType =
  | "topic"
  | "tone"
  | "creatorType"
  | "relationship"
  | "locality"
  | "format"
  | "novelty"
  | "intensity";

export interface SteeringTarget {
  id: string;
  type: SteeringTargetType;
  label: string;
}

export type SteeringDuration =
  | "session"
  | "today"
  | "three_days"
  | "seven_days"
  | "persistent";

export type SteeringSource =
  | "nl_input"
  | "quick_chip"
  | "session_mode"
  | "explicit_control";

export interface PreferenceVocabularyEntry {
  id: string;
  verb: SteeringVerb;
  target: SteeringTarget;
  strength: number; // 0..1, clamped server-side
  duration: SteeringDuration;
  source: SteeringSource;
  active: boolean;
  paused: boolean;
  createdAt: number;
  expiresAt?: number;
  zone: "preference"; // user-inspectable + deletable; NSPrivacyTracking=false
}

export interface PreferenceVocabulary {
  userId: string;
  entries: PreferenceVocabularyEntry[];
  liturgicalSeasonKey?: string; // additive seasonal context only
  updatedAt: number;
}

// ────────────────────────────────────────────────────────────────────
// Ranking signals — additive contributions layered onto the base score
// ────────────────────────────────────────────────────────────────────

export type RankingSignalKind =
  | "following"
  | "topicRelevance"
  | "recency"
  | "intentBoost"
  | "resonance"
  | "authorBoost"
  | "userSteering" // NEW: additive delta from PreferenceVocabulary (clamped)
  | "liturgicalSeason"; // NEW: additive seasonal context (clamped)

export interface RankingSignal {
  kind: RankingSignalKind;
  contribution: number;
  origin?: string;
  rationaleText?: string;
}

export interface SteeredRankingResult {
  postId: string;
  baseScore: number; // HeyFeedAlgorithm.weightedTotal — unchanged scorer
  steeringDelta: number;
  liturgicalDelta: number;
  signals: RankingSignal[];
  finalScore: number;
}

// ────────────────────────────────────────────────────────────────────
// SafetyFloor — immovable, runs BEFORE ranking, NON-OVERRIDABLE
// ────────────────────────────────────────────────────────────────────

export type SafetyFloorCategory =
  | "childSafety"
  | "csam"
  | "harassment"
  | "hate"
  | "threats"
  | "selfHarm"
  | "sexualContent"
  | "violence"
  | "scam"
  | "spam";

export type SafetyFloorAction = "hardBlock" | "ceiling" | "alwaysShield";

export interface SafetyFloor {
  category: SafetyFloorCategory;
  action: SafetyFloorAction;
  ceilingRisk: number; // max risk that may EVER clear, even at SensitivityFilter.off
  alwaysOn: boolean; // ignores heyFeedSteering flag entirely
}

export interface SafetyFloorVerdict {
  postId: string;
  allowed: boolean; // false => never surfaces; fail-closed when unevaluable
  appliedFloor?: SafetyFloorCategory;
  appliedAction?: SafetyFloorAction;
  isMinorShielded: boolean;
  reasons: string[]; // INTERNAL ONLY — never displayed to users
}

// ────────────────────────────────────────────────────────────────────
// Constants + pure helpers (mirrored exactly in SteeringBounds / SafetyFloorEngine)
// ────────────────────────────────────────────────────────────────────

export const STEER_CLAMP = 0.35;

export function clampSteering(v: number): number {
  return Math.max(-STEER_CLAMP, Math.min(STEER_CLAMP, v));
}

/// User preference may only make the feed STRICTER, never laxer.
export function effectiveRiskThreshold(
  userThreshold: number,
  ceilingRisk: number
): number {
  return Math.min(userThreshold, ceilingRisk);
}

/// Fail-closed: an unevaluable post never surfaces.
export function failClosedFloorVerdict(postId: string): SafetyFloorVerdict {
  return {
    postId,
    allowed: false,
    isMinorShielded: false,
    reasons: ["unevaluable"],
  };
}

/// The full, frozen set of floor categories. A target whose id/type matches any of these
/// can NEVER be boosted by a steering preference.
export const SAFETY_FLOOR_CATEGORIES: readonly SafetyFloorCategory[] = Object.freeze([
  "childSafety",
  "csam",
  "harassment",
  "hate",
  "threats",
  "selfHarm",
  "sexualContent",
  "violence",
  "scam",
  "spam",
]);

/// A steering target is forbidden when its label/id corresponds to any SafetyFloor category.
/// Preferences can never request "more of" a floor category — fail-closed against laundering
/// unsafe content through the steering surface.
export function isFloorTargetForbidden(target: SteeringTarget): boolean {
  const needle = (target.id + " " + target.label).toLowerCase();
  return SAFETY_FLOOR_CATEGORIES.some((category) => {
    const token = category.toLowerCase();
    return needle.includes(token) || target.id.toLowerCase() === token;
  });
}
