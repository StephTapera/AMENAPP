/**
 * governance/contracts.ts — Frozen governance contracts (Wave 0).
 *
 * These types are the shared spine that binds the nine governance invariants
 * into AMEN's EXISTING systems (Constitution, GUARDIAN/Aegis, Berean pipeline,
 * PRIVACY-CORE, feature flags). They do not invent a parallel safety stack;
 * they give the existing stack typed, enforceable seams.
 *
 * Doctrine (honored here):
 *  - Fail-closed: if the safe state cannot be PROVEN, default to the
 *    restrictive state, never the permissive one.
 *  - Default-OFF: every new capability ships disabled.
 *  - TypeScript is the source of truth; the Swift mirror (AIL) follows.
 *
 * Nothing in this file performs I/O or has side effects — it is contracts only,
 * so it is safe to import from any layer (pipeline, flags, tests).
 */

// ─────────────────────────────────────────────────────────────────────────────
// Invariant 6 — Gated capability (default-OFF, recorded human sign-off)
// Generalizes the existing four-part CSAM gate to ALL safety-critical flags.
// ─────────────────────────────────────────────────────────────────────────────

export type FlagRiskTag = "safety_critical" | "standard";

/**
 * A recorded human sign-off. A `safety_critical` flag cannot be enabled unless
 * a complete sign-off (who / when / on what basis) exists. This is the durable
 * record demanded by invariant 8 — not an in-the-moment judgment.
 */
export interface FlagSignOff {
  /** Who authorized it. For the strictest gates this must be a non-engineer. */
  approver: string;
  /** When — ISO-8601 timestamp. */
  approvedAtISO: string;
  /** On what basis the elevated capability was deemed safe to enable. */
  basis: string;
  /** Whether the approver is a non-engineer reviewer (required for CSAM-class gates). */
  nonEngineerReviewer: boolean;
  /** Optional tracking reference. */
  ticket?: string;
}

/**
 * The governance metadata that wraps a feature flag. `safety_critical` flags
 * MUST declare `defaultEnabled: false` and carry a `statedPurpose` (which the
 * purpose firewall in invariant 1 inspects).
 */
export interface FlagGovernanceSpec {
  key: string;
  tag: FlagRiskTag;
  /** Safety-critical flags must default false; the schema check enforces it. */
  defaultEnabled: boolean;
  /** Plain-language reason the flag exists. Inspected by the purpose firewall. */
  statedPurpose: string;
  /** Required for safety_critical flags before they may be turned on. */
  signOff?: FlagSignOff;
}

// ─────────────────────────────────────────────────────────────────────────────
// Invariant 1 — Formation over engagement (purpose firewall)
// GUARDIAN rejects any flag whose stated purpose is to grow engagement metrics.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Stems that, if present in a flag's stated purpose, mark it as an
 * attention-economy mechanic and cause GUARDIAN to REJECT the flag.
 * Lower-cased substring match. Deliberately conservative (fail-closed):
 * a flag whose only justification is metric growth must not ship.
 */
export const ENGAGEMENT_PURPOSE_DENY_STEMS: readonly string[] = [
  "increase session length",
  "session length",
  "increase dau",
  "daily active",
  "boost retention",
  "increase retention",
  "maximize engagement",
  "engagement loop",
  "re-engagement",
  "reengagement",
  "time spent",
  "time-on-app",
  "watch time",
  "maximize time",
  "addictive",
  "habit loop",
  "streak pressure",
  "fomo",
] as const;

// ─────────────────────────────────────────────────────────────────────────────
// Invariant 4 — Red lines (non-negotiable, no flag can override)
// ─────────────────────────────────────────────────────────────────────────────

export type RedLineId =
  | "spiritual_surveillance"
  | "spiritual_scoring"
  | "ecclesial_impersonation"
  | "csam"
  | "minor_sexualization"
  | "crisis_data_export"
  | "crisis_data_unencrypted";

export interface RedLine {
  id: RedLineId;
  description: string;
  /** Red lines are absolute. No flag, A/B test, or growth pressure overrides them. */
  readonly overridable: false;
}

export const RED_LINES: readonly RedLine[] = [
  {
    id: "spiritual_surveillance",
    description:
      "AMEN does not monitor, log-for-scoring, or profile a user's spiritual " +
      "performance (prayer frequency, giving, attendance, doctrinal soundness) " +
      "for ranking, nudging, or disclosure.",
    overridable: false,
  },
  {
    id: "spiritual_scoring",
    description:
      "No metric ranking users by piety, growth, or faithfulness is ever " +
      "computed or rendered.",
    overridable: false,
  },
  {
    id: "ecclesial_impersonation",
    description:
      "Berean and AMEN never speak AS a church, pastor, or spiritual authority, " +
      "and never issue binding moral/spiritual rulings for a user.",
    overridable: false,
  },
  {
    id: "csam",
    description:
      "csam_hash_scan_enabled stays OFF until the four-part federal gate is " +
      "satisfied (ESP/NCMEC registration, hash-provider contract, written legal " +
      "sign-off, non-engineer review). Never a DIY build.",
    overridable: false,
  },
  {
    id: "minor_sexualization",
    description:
      "No content that sexualizes minors or facilitates grooming, ever.",
    overridable: false,
  },
  {
    id: "crisis_data_export",
    description:
      "Crisis-path data is never exported to analytics or any model-training / " +
      "behavioral pipeline.",
    overridable: false,
  },
  {
    id: "crisis_data_unencrypted",
    description:
      "Crisis-path data is encrypted at rest and fails closed if encryption " +
      "cannot be verified.",
    overridable: false,
  },
] as const;

// ─────────────────────────────────────────────────────────────────────────────
// Invariant 5 — Intelligence proposes, people decide (HITL boundary)
// No AI-only code path may reach an irreversible mutation. Consequential
// actions are wrapped so they cannot execute without a recorded human decision.
// ─────────────────────────────────────────────────────────────────────────────

export type ConsequentialActionKind =
  | "account_suspension"
  | "account_ban"
  | "content_takedown_non_auto_safety"
  | "escalation_naming_user"
  | "minor_data_mutation"
  | "spiritually_binding_ruling"
  | "community_shutdown"
  | "creator_monetization_suspension"
  | "law_enforcement_disclosure"
  | "appeal_decision";

export interface HumanApproval {
  approver: string;
  approvedAtISO: string;
  decision: "approve" | "reject";
  rationale: string;
}

/**
 * A consequential action proposed by AI/automation. It carries no `execute`
 * capability of its own — callers must route it through
 * `governance/humanInLoop.ts#authorize` which refuses to return an executor
 * unless a human `approve` decision is attached.
 */
export interface ProposedConsequentialAction<TPayload = unknown> {
  kind: ConsequentialActionKind;
  proposedBy: "ai" | "automation";
  payload: TPayload;
  /** Human-readable summary surfaced to the human reviewer. */
  summary: string;
  approval?: HumanApproval;
}

// ─────────────────────────────────────────────────────────────────────────────
// Invariant 2 & 7 — Constitutional conformance + grounding verdicts
// Every Berean emission routes through a conformance check whose verdict is
// recorded; every Scripture citation must resolve to a verified reference.
// ─────────────────────────────────────────────────────────────────────────────

export type GovernanceVerdictStatus = "pass" | "degraded" | "blocked";

export interface GovernanceVerdict {
  /** Which policy produced this verdict (stable id). */
  policyId: string;
  status: GovernanceVerdictStatus;
  /** The Constitution version the decision was made under (audit requirement). */
  constitutionVersion: string;
  reasons: string[];
  recordedAtISO: string;
}

/**
 * Invariant 7 — a citation grounding result. Fail-closed: an unverifiable
 * reference is NOT asserted (status `unverifiable` ⇒ caller must strip it).
 */
export interface CitationGrounding {
  /** As emitted by the model, e.g. "John 3:16". */
  reference: string;
  status: "verified" | "unverifiable";
  /** The grounded source id when verified (e.g. RAG chunk / canon index). */
  sourceId?: string;
}

// ─────────────────────────────────────────────────────────────────────────────
// Invariant 8 — Checks-and-balances over founder discretion
// Resolved safety decisions become immutable policy with change-control.
// ─────────────────────────────────────────────────────────────────────────────

export interface AmendmentRecord {
  amendedAtISO: string;
  amendedBy: string;
  reason: string;
  fromVersion: string;
  toVersion: string;
}

export interface FounderRulingPolicy {
  id: string;
  /** The ruling, stated as a durable invariant — not a flag. */
  ruling: string;
  codifiedAtISO: string;
  /** Once codified, a ruling cannot be silently reversed. */
  readonly immutable: true;
  /** Reversal requires an explicit, logged amendment. */
  amendments: AmendmentRecord[];
}

// ─────────────────────────────────────────────────────────────────────────────
// Invariant 3 — The Companion Boundary (parasocial / idolatry guard)
// Detection result for devotion/dependence directed AT the assistant.
// ─────────────────────────────────────────────────────────────────────────────

export type CompanionBoundaryViolation =
  | "mediator_positioning" // (i) assistant as mediator between user and God
  | "claimed_authority" //     (ii) spiritual / ecclesial authority
  | "accepts_devotion" //      (iii) worship / confession-as-absolution to itself
  | "fosters_dependence"; //   (iv) dependence on Berean in place of Scripture/prayer/community

export interface CompanionBoundaryAssessment {
  withinBoundary: boolean;
  violations: CompanionBoundaryViolation[];
  /** When out of boundary, Berean must hand the user OUTWARD, not deeper in. */
  outwardHandoffRequired: boolean;
}
