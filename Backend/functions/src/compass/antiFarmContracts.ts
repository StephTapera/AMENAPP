// antiFarmContracts.ts
// AMEN COMPASS — Anti-Farming + Steering + Activity-Discovery contracts.
// Wave 0 FROZEN. TypeScript is the source of truth; the Swift mirror
// (AMENAPP/AMENAPP/COMPASS/AntiFarmContracts.swift) must match field-for-field.
//
// Design rules baked into these types (see audit/BORROW_AND_SMARTEN_SPEC.md §8.1):
//  - Deterministic coordinated-behavior signals set an `integrityPenalty` BEFORE ranking;
//    bot detection is device/burst heuristics, never a public person score.
//  - `OriginalityScore` and `integrityPenalty` are INTERNAL-only — never serialized to a
//    user-facing number, never displayed.
//  - Steering is additive InterestTag editing on a clamped [-1, 1] weight; faith is one
//    vertical, never privileged; never a person score.
//  - Activity discovery is driven by shared activity OBJECTS + coarse private signals
//    (join/rsvp/complete), never follower counts and never GPS.
//  - Every new behavior is flag-gated and fail-closed: flag OFF =>
//    integrityPenalty stays 0 (no demotion), steering is unweighted, surface is empty.

// ── Anti-farming signals ────────────────────────────────────────────

/// Deterministic coordinated-behavior signal kinds. These are evidence categories,
/// NOT scores. They are produced by burst/graph heuristics, never by a model judgement
/// about a person.
export type AntiFarmSignal =
  | "sybilCluster"            // many low-cost accounts acting as one
  | "followFarm"             // reciprocal/ring follow inflation
  | "coordinatedAmplification"; // synchronized reshare/engagement bursts

/// Per-user amplification budget. Reach is bounded, never bought. A depleted budget
/// caps further amplification; it can never raise reach above the base allotment.
export interface AmplificationBudget {
  uid: string;
  /// Total amplification units available this window (base allotment, never purchasable).
  totalUnits: number;
  /// Units already consumed this window.
  consumedUnits: number;
  /// UTC epoch ms when the budget window resets.
  windowResetAtUTC: number;
  /// True once consumed >= total; further amplification is held, never extended for pay.
  depleted: boolean;
}

/// INTERNAL-ONLY. Composite originality assessment used to inform the integrity penalty.
/// MUST NEVER be serialized into a user-facing payload or rendered as a number.
/// Mirrors the spirit of DiscoverMetadata.originalityScore but stays server-side.
export interface OriginalityScore {
  /// 0..1, higher = more likely original to this author. INTERNAL.
  value: number;
  /// Coarse provenance basis (mirrors ProvenanceStatus raw values), INTERNAL.
  provenanceBasis: string;
  /// Repost-chain depth observed; longer chains lower originality. INTERNAL.
  repostLineageDepth: number;
  /// Always true — a structural reminder this type is never client-facing.
  readonly internalOnly: true;
}

/// Deterministic integrity evaluation applied BEFORE ranking. When the anti-farming
/// flag is OFF, `integrityPenalty` is fixed at 0 (fail-closed = no demotion), and the
/// originality assessment is omitted.
export interface IntegrityEvaluation {
  /// Subject of the evaluation (post id or account id depending on `subjectKind`).
  subjectId: string;
  subjectKind: "post" | "account";
  /// Detected coordinated-behavior signals (may be empty).
  signals: AntiFarmSignal[];
  /// 0..1 demotion magnitude applied to ranking. INTERNAL — never displayed.
  /// MUST be exactly 0 when `flagEnabled` is false.
  integrityPenalty: number;
  /// INTERNAL originality assessment; omitted when flag is OFF.
  originality?: OriginalityScore;
  /// Reflects compass_anti_farming_enabled at evaluation time.
  flagEnabled: boolean;
  evaluatedAtUTC: number;
}

// ── Steering ────────────────────────────────────────────────────────

/// A single user-owned, additive steering edit on an interest tag. The weight is clamped
/// server-side to [-1, 1]. Steering never represents a person score and never keys on
/// time-on-app; faith is one optional vertical, never privileged.
export interface SteeringPreference {
  interestTagId: string;
  /// -1..1, clamped via clampSteeringWeight. Negative = less of, positive = more of.
  weight: number;
  /// Optional vertical context (e.g. "faith"); additive only, never privileged.
  vertical?: string;
}

/// User-owned, inspectable, deletable steering set (PRIVACY-CORE preference zone).
export interface SteeringPreferenceSet {
  uid: string;
  preferences: SteeringPreference[];
  /// Reflects compass_steering_enabled; when false, ranking is unweighted.
  flagEnabled: boolean;
  updatedAtUTC: number;
}

// ── Activity discovery ──────────────────────────────────────────────

/// Coarse, private activity signals that drive discovery. Never GPS, never follower counts.
export type SharedActivitySignal =
  | "joined"
  | "rsvped"
  | "completed";

/// Kinds of shared activity OBJECTS that anchor discovery.
export type ActivityObjectKind =
  | "event"
  | "prayerCircle"
  | "localGroup"
  | "volunteer";

/// Truthful "why shown" rationale. No reason => no surface (mirrors discovery WhyShown intent).
export interface ActivityDiscoveryRationale {
  /// Which shared activity drove this candidate.
  sharedActivity: SharedActivitySignal;
  /// Human-readable, truthful explanation.
  detail: string;
}

/// Eligibility gate for an activity-discovery candidate; fail-closed.
export interface ActivityDiscoveryEligibility {
  /// False => candidate is dropped (never surfaced).
  eligible: boolean;
  /// Reflects compass_activity_discovery_enabled.
  flagEnabled: boolean;
}

/// A discovery candidate anchored to a shared activity object.
export interface ActivityDiscoveryCandidate {
  candidateId: string;
  objectId: string;
  objectKind: ActivityObjectKind;
  /// The coarse private signal that surfaced this candidate.
  sharedActivity: SharedActivitySignal;
  rationale: ActivityDiscoveryRationale;
  eligibility: ActivityDiscoveryEligibility;
}

// ── Clamps + fail-closed constructors ───────────────────────────────

export const STEERING_WEIGHT_MIN = -1;
export const STEERING_WEIGHT_MAX = 1;

/// Clamp a steering weight to [-1, 1].
export function clampSteeringWeight(weight: number): number {
  return Math.max(STEERING_WEIGHT_MIN, Math.min(STEERING_WEIGHT_MAX, weight));
}

/// Fail-closed integrity evaluation used when the anti-farming flag is OFF or the subject
/// is unevaluable: no signals, zero penalty (no demotion), no originality leakage.
export function unweightedIntegrityEvaluation(
  subjectId: string,
  subjectKind: "post" | "account",
  evaluatedAtUTC: number
): IntegrityEvaluation {
  return {
    subjectId,
    subjectKind,
    signals: [],
    integrityPenalty: 0,
    flagEnabled: false,
    evaluatedAtUTC,
  };
}

/// Fail-closed (empty) activity-discovery surface.
export function emptyActivityDiscoverySurface(): ActivityDiscoveryCandidate[] {
  return [];
}
