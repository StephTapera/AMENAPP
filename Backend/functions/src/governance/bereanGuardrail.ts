/**
 * governance/bereanGuardrail.ts — emission-boundary composition (Wave 2).
 *
 * One call that every Berean mode routes its candidate answer through before
 * emission. Composes:
 *   - invariant 2: a recorded constitutional-conformance verdict (names the version)
 *   - invariant 3: the Companion Boundary (parasocial / idolatry guard)
 *   - invariant 7: grounding fail-closed (unverifiable citations stripped)
 *
 * Pure and synchronous — no I/O — so it can run in the pipeline AND in the
 * red-line test suite identically.
 */

import {
  CitationGrounding,
  CompanionBoundaryAssessment,
  GovernanceVerdict,
} from "./contracts";
import {
  assessCompanionBoundary,
  conformanceVerdict,
  enforceGrounding,
  GroundingResult,
} from "./policyEngine";

export interface BereanEmissionInput {
  /** The candidate answer text the model produced. */
  text: string;
  /** Citations extracted from the candidate, each already grounded-or-not. */
  citations: CitationGrounding[];
  /** Whether the upstream constitutional review passed. */
  reviewPassed: boolean;
  /** Whether the upstream review degraded the answer. */
  degraded: boolean;
  /** The Constitution version this emission was governed under. */
  constitutionVersion: string;
  /** Prohibited phrases from the Companion Boundary article (fail-closed default applied). */
  prohibitedPhrases?: string[];
  /** Review flags to carry into the recorded verdict. */
  reviewFlags?: string[];
}

export interface BereanGuardrailResult {
  /** True when the emission must be blocked (replace with degraded response). */
  blocked: boolean;
  /** True when Berean must append an outward handoff (to God/church/pastor). */
  mustHandoffOutward: boolean;
  companion: CompanionBoundaryAssessment;
  grounding: GroundingResult;
  /** Recorded verdicts (persist alongside the pipeline trace). */
  verdicts: GovernanceVerdict[];
}

/**
 * Guard a candidate Berean emission. Fail-closed:
 *   - a Companion-Boundary violation forces an outward handoff;
 *   - unverifiable citations are stripped (never asserted);
 *   - a failed-and-not-degraded review blocks the emission.
 */
export function guardBereanEmission(input: BereanEmissionInput): BereanGuardrailResult {
  const companion = assessCompanionBoundary(input.text, input.prohibitedPhrases ?? []);
  const grounding = enforceGrounding(input.citations, input.constitutionVersion);
  const conformance = conformanceVerdict(
    input.reviewPassed,
    input.degraded,
    input.constitutionVersion,
    input.reviewFlags ?? []
  );

  const blocked = conformance.status === "blocked";

  return {
    blocked,
    mustHandoffOutward: companion.outwardHandoffRequired,
    companion,
    grounding,
    verdicts: [conformance, grounding.verdict],
  };
}

/**
 * The canonical outward-handoff text appended when the Companion Boundary fires.
 * Points the user OUTWARD — never deeper into Berean.
 */
export const OUTWARD_HANDOFF_TEXT =
  "I'm a study tool, not a substitute for God or for people who love you. " +
  "Please bring this to God in prayer, and to your local church, a pastor, or " +
  "trusted believers who can walk with you in person.";
