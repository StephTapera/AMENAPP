/**
 * governance/policyEngine.ts — GUARDIAN policy-as-code (Wave 2).
 *
 * Pure, side-effect-free policy functions that bind invariants 1, 2, 4, 6, 7, 8
 * into enforceable checks. Every function is deterministic except for the
 * `recordedAtISO` timestamp on verdicts (which tests ignore). Keeping these pure
 * means they can run identically in the pipeline, in CI, and in the red-line
 * test suite.
 *
 * Fail-closed throughout: an unprovable safe state yields `blocked`/`degraded`,
 * never `pass`.
 */

import {
  FlagGovernanceSpec,
  ENGAGEMENT_PURPOSE_DENY_STEMS,
  RED_LINES,
  RedLineId,
  GovernanceVerdict,
  GovernanceVerdictStatus,
  CitationGrounding,
  CompanionBoundaryAssessment,
  CompanionBoundaryViolation,
  FounderRulingPolicy,
} from "./contracts";

function nowISO(): string {
  return new Date().toISOString();
}

function verdict(
  policyId: string,
  status: GovernanceVerdictStatus,
  constitutionVersion: string,
  reasons: string[]
): GovernanceVerdict {
  return { policyId, status, constitutionVersion, reasons, recordedAtISO: nowISO() };
}

// ─────────────────────────────────────────────────────────────────────────────
// Invariant 1 — Purpose firewall: reject engagement-maximizing flags.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Returns the deny-stems matched by a flag's stated purpose. Empty ⇒ clean.
 * Lower-cased substring match (deliberately broad / fail-closed).
 */
export function matchedEngagementStems(statedPurpose: string): string[] {
  const p = statedPurpose.toLowerCase();
  return ENGAGEMENT_PURPOSE_DENY_STEMS.filter((stem) => p.includes(stem));
}

/**
 * GUARDIAN rejects any flag whose stated purpose is to grow engagement metrics.
 * Formation over engagement is a hard invariant, not a value statement.
 */
export function evaluateFlagPurpose(
  spec: FlagGovernanceSpec,
  constitutionVersion: string
): GovernanceVerdict {
  const hits = matchedEngagementStems(spec.statedPurpose);
  if (hits.length > 0) {
    return verdict("INV1_PURPOSE_FIREWALL", "blocked", constitutionVersion, [
      `Flag "${spec.key}" stated purpose names attention-economy mechanics: ${hits.join(", ")}.`,
      "Formation over engagement is a hard invariant — this flag must not ship.",
    ]);
  }
  return verdict("INV1_PURPOSE_FIREWALL", "pass", constitutionVersion, [
    `Flag "${spec.key}" purpose is service-oriented.`,
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Invariant 6 — Gated capability: safety_critical ⇒ default-OFF + sign-off.
// ─────────────────────────────────────────────────────────────────────────────

/** True when the flag is tagged safety_critical. */
export function isSafetyCritical(spec: FlagGovernanceSpec): boolean {
  return spec.tag === "safety_critical";
}

/**
 * Schema invariant: a safety_critical flag MUST declare defaultEnabled=false.
 * CI fails the build if this returns `blocked`.
 */
export function evaluateFlagDefaultState(
  spec: FlagGovernanceSpec,
  constitutionVersion: string
): GovernanceVerdict {
  if (isSafetyCritical(spec) && spec.defaultEnabled !== false) {
    return verdict("INV6_DEFAULT_OFF", "blocked", constitutionVersion, [
      `safety_critical flag "${spec.key}" ships default-ON — forbidden.`,
    ]);
  }
  return verdict("INV6_DEFAULT_OFF", "pass", constitutionVersion, [
    `Flag "${spec.key}" default state is permitted.`,
  ]);
}

/**
 * Runtime gate: can this flag be ENABLED right now? A safety_critical flag
 * cannot be turned on without a complete, recorded sign-off (who/when/basis).
 * CSAM-class gates additionally require a non-engineer reviewer.
 */
export function canEnableFlag(
  spec: FlagGovernanceSpec,
  opts: { requireNonEngineerReviewer?: boolean } = {}
): { allowed: boolean; reason: string } {
  if (!isSafetyCritical(spec)) {
    return { allowed: true, reason: "Not safety_critical — standard flag." };
  }
  const s = spec.signOff;
  if (!s) {
    return { allowed: false, reason: `No sign-off record for safety_critical "${spec.key}".` };
  }
  if (!s.approver || !s.approvedAtISO || !s.basis) {
    return { allowed: false, reason: `Incomplete sign-off for "${spec.key}" (need approver, time, basis).` };
  }
  if (opts.requireNonEngineerReviewer && !s.nonEngineerReviewer) {
    return { allowed: false, reason: `"${spec.key}" requires a non-engineer reviewer (CSAM-class gate).` };
  }
  return { allowed: true, reason: `Sign-off present: ${s.approver} @ ${s.approvedAtISO}.` };
}

// ─────────────────────────────────────────────────────────────────────────────
// Invariant 4 — Red lines: no flag can override; deny-list is absolute.
// ─────────────────────────────────────────────────────────────────────────────

const RED_LINE_IDS = new Set<string>(RED_LINES.map((r) => r.id));

export function isRedLineId(id: string): id is RedLineId {
  return RED_LINE_IDS.has(id);
}

/**
 * A flag may not name a red line as something it overrides/disables. We detect
 * this by scanning the stated purpose for red-line ids/keywords. Fail-closed.
 */
export function assertNoRedLineOverride(
  spec: FlagGovernanceSpec,
  constitutionVersion: string
): GovernanceVerdict {
  const p = spec.statedPurpose.toLowerCase();
  const overrideVerb = /(override|bypass|disable|turn off|relax|skip)/.test(p);
  const namesRedLine = RED_LINES.some(
    (r) => p.includes(r.id) || p.includes(r.id.replace(/_/g, " "))
  );
  if (overrideVerb && namesRedLine) {
    return verdict("INV4_RED_LINE_DENY", "blocked", constitutionVersion, [
      `Flag "${spec.key}" attempts to override a red line — no flag may do this.`,
    ]);
  }
  return verdict("INV4_RED_LINE_DENY", "pass", constitutionVersion, [
    `Flag "${spec.key}" does not override a red line.`,
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Invariant 2 — Constitution conformance verdict on every Berean emission.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Wraps the result of the constitutional review (which already runs in
 * constitutionalReview.ts) into a recorded GovernanceVerdict that names the
 * Constitution version. Every Berean mode routes through this before emission,
 * satisfying the "recorded verdict" requirement of invariant 2.
 */
export function conformanceVerdict(
  reviewPassed: boolean,
  degraded: boolean,
  constitutionVersion: string,
  flags: string[]
): GovernanceVerdict {
  const status: GovernanceVerdictStatus = reviewPassed
    ? "pass"
    : degraded
      ? "degraded"
      : "blocked";
  return verdict("INV2_CONFORMANCE", status, constitutionVersion, [
    reviewPassed ? "Constitutional review passed." : "Constitutional review failed.",
    ...flags.map((f) => `flag: ${f}`),
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Invariant 3 — Companion Boundary detection (parasocial / idolatry guard).
// ─────────────────────────────────────────────────────────────────────────────

const COMPANION_BOUNDARY_PATTERNS: Array<{
  violation: CompanionBoundaryViolation;
  patterns: RegExp[];
}> = [
  {
    violation: "mediator_positioning",
    patterns: [/\bthrough me\b.*\bgod\b/i, /\bi (?:can|will) bring you (?:closer )?to god\b/i, /\bi am your (?:connection|bridge) to god\b/i],
  },
  {
    violation: "claimed_authority",
    patterns: [/\bi (?:absolve|forgive) you\b/i, /\bas your (?:pastor|priest|spiritual authority)\b/i, /\bi (?:declare|rule) that\b/i],
  },
  {
    violation: "accepts_devotion",
    patterns: [/\bconfess to me\b/i, /\bpray to me\b/i, /\bworship me\b/i, /\byou can confess (?:to me|here)\b/i],
  },
  {
    violation: "fosters_dependence",
    patterns: [/\bkeep talking to me\b/i, /\btalk to me instead\b/i, /\byou don'?t need (?:anyone|anybody) else\b/i, /\bi'?m always here for you\b/i, /\byou can always come to me\b/i],
  },
];

/**
 * Assess a candidate Berean emission for Companion-Boundary violations. When a
 * violation is found, the assistant must hand the user OUTWARD, not deeper in.
 * Fail-closed: the prohibited-phrase list is always checked even if the
 * Constitution article is absent.
 */
export function assessCompanionBoundary(
  text: string,
  prohibitedPhrases: string[] = []
): CompanionBoundaryAssessment {
  const violations = new Set<CompanionBoundaryViolation>();
  for (const group of COMPANION_BOUNDARY_PATTERNS) {
    if (group.patterns.some((re) => re.test(text))) {
      violations.add(group.violation);
    }
  }
  const lower = text.toLowerCase();
  for (const phrase of prohibitedPhrases) {
    if (lower.includes(phrase.toLowerCase())) {
      violations.add("fosters_dependence");
    }
  }
  const list = Array.from(violations);
  return {
    withinBoundary: list.length === 0,
    violations: list,
    outwardHandoffRequired: list.length > 0,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Invariant 7 — Grounding fail-closed: unverifiable Scripture is not asserted.
// ─────────────────────────────────────────────────────────────────────────────

export interface GroundingResult {
  assertable: CitationGrounding[];
  stripped: CitationGrounding[];
  verdict: GovernanceVerdict;
}

/**
 * Partition citations into assertable (verified) and stripped (unverifiable).
 * Fail-closed: anything not provably `verified` is stripped and must not appear
 * in the emitted response.
 */
export function enforceGrounding(
  citations: CitationGrounding[],
  constitutionVersion: string
): GroundingResult {
  const assertable: CitationGrounding[] = [];
  const stripped: CitationGrounding[] = [];
  for (const c of citations) {
    if (c.status === "verified" && c.sourceId) assertable.push(c);
    else stripped.push(c);
  }
  const v =
    stripped.length === 0
      ? verdict("INV7_GROUNDING", "pass", constitutionVersion, ["All citations verified."])
      : verdict("INV7_GROUNDING", "degraded", constitutionVersion, [
          `${stripped.length} unverifiable citation(s) stripped: ${stripped
            .map((c) => c.reference)
            .join(", ")}.`,
        ]);
  return { assertable, stripped, verdict: v };
}

// ─────────────────────────────────────────────────────────────────────────────
// Invariant 8 — Founder rulings are immutable; reversal needs a logged amendment.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Verify the founder-ruling policies arrived intact: each must be `immutable`,
 * and any amendment must carry a complete change-control record. A `blocked`
 * verdict signals tampering or an unlogged reversal.
 */
export function assertFounderRulingsImmutable(
  rulings: FounderRulingPolicy[],
  constitutionVersion: string
): GovernanceVerdict {
  const problems: string[] = [];
  for (const r of rulings) {
    if (r.immutable !== true) problems.push(`Ruling ${r.id} not marked immutable.`);
    for (const a of r.amendments) {
      if (!a.amendedBy || !a.reason || !a.fromVersion || !a.toVersion) {
        problems.push(`Ruling ${r.id} has an amendment missing change-control fields.`);
      }
    }
  }
  return problems.length > 0
    ? verdict("INV8_IMMUTABLE_RULINGS", "blocked", constitutionVersion, problems)
    : verdict("INV8_IMMUTABLE_RULINGS", "pass", constitutionVersion, [
        `${rulings.length} founder rulings intact.`,
      ]);
}
