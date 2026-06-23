// contracts/guardianPrePublish.ts
// AMEN — Feature C · GUARDIAN PrePublish hook chain · TypeScript mirror (SOURCE OF TRUTH).
// Spec authority: audit/BORROW_AND_SMARTEN_SPEC.md §8.2 (Feature C) + §8.3 (hook chain).
// Swift side (AMENAPP/AIIntelligence/GuardianPrePublishContracts.swift) MUST mirror these
// types field-for-field. Any change requires a contract-change note + re-freeze.
//
// WHAT THIS IS: a deterministic, fail-closed orderer that EVERY write path
// (comment/post/note/dm/mediaCaption) routes through BEFORE the Firestore commit.
// It owns NO detection logic — every hook delegates to an existing real seam.
//
// INVARIANTS (enforced + asserted in guardianPrePublish.test.ts):
//   PP-I1  every write routes through the chain.
//   PP-I2  fixed order; short-circuit on the first `blockCommit`.
//   PP-I3  childSafetyHash is index 0, unconditional (never flag-gated), fail-closed
//          (no screener => block).
//   PP-I4  throw/timeout => `holdForReview` on guard surfaces / when the flag is ON.
//   PP-I5  deterministic mapping (server AI may inform toxicity, but signal => verdict
//          is a fixed switch — never model vibes).
//   PP-I6  no person score is ever produced.
//   PP-I7  any non-proceed verdict emits a PrePublishEscalationRecord to /moderationQueue.
//   PP-I8  flag OFF => hooks 1–3 run in shadow/observe (log, don't block); only hook 0 blocks.

// ════════════════════════════════════════════════════════════════════
// §C.1 — Surfaces, hook kinds, decisions, reason codes
// ════════════════════════════════════════════════════════════════════

export type PrePublishSurface =
  | "comment"
  | "post"
  | "note"
  | "dm"
  | "mediaCaption";

export type PrePublishHookKind =
  | "childSafetyHash"
  | "toxicity"
  | "claimScriptureContext"
  | "provenanceStamp";

// Most-severe wins (see CHAIN reducer): blockCommit > holdForReview > stampOnly > proceed > shadowObserve.
export type HookDecision =
  | "proceed"
  | "stampOnly"
  | "holdForReview"
  | "blockCommit"
  | "shadowObserve";

// Coarse, audit-only reason codes. Never displayed to the author; never a person score.
export type HookReasonCode =
  | "clean"
  | "noScreener"           // PP-I3: child-safety provider nil => fail-closed block.
  | "hashMatch"            // known CSAM hash matched => block + escalate.
  | "providerError"        // delegate threw/timed out => fail-closed.
  | "providerUncertain"    // delegate returned uncertain on a guard surface => block.
  | "toxic"                // toxicity delegate said block.
  | "fabricatedCitation"   // citation gate said fabricated/unverifiable.
  | "pendingCitation"      // citation status never reached verified => fail-closed hold.
  | "provenancePending"    // media authenticity pending => hold.
  | "provenanceQuarantined"// media authenticity quarantined/failed-closed => block.
  | "stamped"              // advisory provenance label attached; not a block.
  | "shadow";              // flag OFF: hook observed only, no enforcement.

// ════════════════════════════════════════════════════════════════════
// §C.2 — Per-hook verdict + whole-chain verdict
// ════════════════════════════════════════════════════════════════════

export interface HookVerdict {
  readonly hook: PrePublishHookKind;
  readonly decision: HookDecision;
  readonly reason: HookReasonCode;
  readonly categories: string[];      // ModerationCategory raw values (e.g. "child_safety").
  readonly confidence: number;        // coarse, never displayed.
  readonly source: string;            // the real seam that produced this verdict.
  readonly requiresHumanReview: boolean;
  readonly evaluatedAt: number;       // epoch millis.
}

export interface ChainVerdict {
  readonly surface: PrePublishSurface;
  readonly contentRef: string | null;
  readonly verdicts: HookVerdict[];
  readonly finalDecision: HookDecision;
  readonly mayCommit: boolean;        // true ONLY when finalDecision is proceed | stampOnly.
  readonly provenanceLabels: string[];// AuthenticityKind raw values attached by provenanceStamp.
  readonly flagEnabled: boolean;      // guardianPrePublishEnabled at evaluation time.
  readonly evaluatedAt: number;
}

// PP-I7: any non-proceed verdict is written to /moderationQueue as one of these.
export interface PrePublishEscalationRecord {
  readonly surface: PrePublishSurface;
  readonly contentRef: string | null;
  readonly hook: PrePublishHookKind;
  readonly decision: HookDecision;
  readonly reason: HookReasonCode;
  readonly categories: string[];
  readonly escalateImmediately: boolean; // true for childSafetyHash hashMatch (=> type 'csam').
  readonly queueType: "csam" | "review"; // 'csam' routes to escalateImmediately path.
  readonly createdAt: number;
}

// ════════════════════════════════════════════════════════════════════
// §C.3 — Hook + chain interfaces (the orderer)
// ════════════════════════════════════════════════════════════════════

export interface PrePublishHook {
  readonly kind: PrePublishHookKind;
  readonly order: number;
  readonly flagGated: boolean;
  // Delegates to a real seam; returns a fail-closed verdict on any uncertainty.
  evaluate(input: PrePublishHookInput): Promise<HookVerdict>;
}

export interface PrePublishHookInput {
  readonly surface: PrePublishSurface;
  readonly contentRef: string | null;
  readonly text?: string;
  readonly hasMedia: boolean;
  readonly isGuardSurface: boolean;
  readonly flagEnabled: boolean;
}

export interface HookChain {
  readonly hooks: PrePublishHook[];
  run(input: PrePublishHookInput): Promise<ChainVerdict>;
}

// ════════════════════════════════════════════════════════════════════
// §C.4 — Frozen ordering (PP-I2/PP-I3)
// ════════════════════════════════════════════════════════════════════

// childSafetyHash is index 0 and is NEVER flag-gated. Order is fixed; the chain
// short-circuits on the first `blockCommit`.
export const PREPUBLISH_HOOK_ORDER = [
  { kind: "childSafetyHash",       order: 0, flagGated: false },
  { kind: "toxicity",              order: 1, flagGated: true  },
  { kind: "claimScriptureContext", order: 2, flagGated: true  },
  { kind: "provenanceStamp",       order: 3, flagGated: true  },
] as const;

// Remote Config key for the master enforcement flag (gates hooks 1–3 only).
export const GUARDIAN_PREPUBLISH_FLAG_KEY = "guardian_pre_publish_enabled";

// ════════════════════════════════════════════════════════════════════
// §C.5 — Fail-closed helpers (PP-I3/PP-I4)
// ════════════════════════════════════════════════════════════════════

// The single source of "deny when unevaluable". There is NO code path here where the
// absence of an affirmative allow maps to `proceed` — the absence IS a denial.
export function failClosedVerdict(
  hook: PrePublishHookKind,
  reason: HookReasonCode,
  source: string,
): HookVerdict {
  // childSafetyHash fails to a hard block; the other hooks fail to a human-review hold.
  // Neither is ever `proceed`.
  const decision: HookDecision = hook === "childSafetyHash" ? "blockCommit" : "holdForReview";
  return {
    hook,
    decision,
    reason,
    categories: hook === "childSafetyHash" ? ["child_safety"] : [],
    confidence: 0,
    source,
    requiresHumanReview: true,
    evaluatedAt: Date.now(),
  };
}

// Severity rank for the most-severe reducer. Higher wins.
export function decisionSeverity(decision: HookDecision): number {
  switch (decision) {
    case "blockCommit":   return 4;
    case "holdForReview": return 3;
    case "stampOnly":     return 2;
    case "proceed":       return 1;
    case "shadowObserve": return 0;
  }
}

// Reduces a set of hook decisions to the chain-level decision (most severe wins).
export function reduceDecisions(decisions: HookDecision[]): HookDecision {
  let worst: HookDecision = "proceed";
  for (const d of decisions) {
    if (decisionSeverity(d) > decisionSeverity(worst)) {
      worst = d;
    }
  }
  return worst;
}

// A chain may commit only when nothing more severe than a provenance stamp survived.
export function mayCommit(finalDecision: HookDecision): boolean {
  return finalDecision === "proceed" || finalDecision === "stampOnly";
}
