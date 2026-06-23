/**
 * governance/humanInLoop.ts — HITL boundary (Wave 2, invariant 5).
 *
 * "Intelligence proposes, people decide." Any irreversible or consequential
 * action must pass through this boundary, which refuses to return an executor
 * unless a complete human `approve` decision is attached. There is no code path
 * by which an AI- or automation-proposed action reaches a mutation without a
 * recorded human approval — the executor simply does not exist until authorized.
 */

import {
  ProposedConsequentialAction,
  HumanApproval,
  ConsequentialActionKind,
} from "./contracts";

/** The set of action kinds that ALWAYS require a human decision. */
export const HUMAN_REQUIRED_KINDS: ReadonlySet<ConsequentialActionKind> = new Set<ConsequentialActionKind>([
  "account_suspension",
  "account_ban",
  "content_takedown_non_auto_safety",
  "escalation_naming_user",
  "minor_data_mutation",
  "spiritually_binding_ruling",
  "community_shutdown",
  "creator_monetization_suspension",
  "law_enforcement_disclosure",
  "appeal_decision",
]);

export type AuthorizationResult<TPayload> =
  | {
      authorized: true;
      payload: TPayload;
      kind: ConsequentialActionKind;
      approval: HumanApproval;
      /** Run the mutation. Only reachable on the authorized branch. */
      execute: <R>(mutation: (payload: TPayload) => R) => R;
    }
  | { authorized: false; reason: string };

function approvalIsComplete(a: HumanApproval | undefined): a is HumanApproval {
  return !!a && !!a.approver && !!a.approvedAtISO && !!a.rationale;
}

/**
 * Authorize a consequential action. Returns an executor ONLY when:
 *   - a complete human approval is attached, AND
 *   - that approval's decision is "approve".
 *
 * Any AI/automation proposal without such an approval is refused. This is the
 * single chokepoint invariant 5 depends on; the red-line suite asserts that no
 * unauthorized branch can execute.
 */
export function authorizeConsequentialAction<TPayload>(
  action: ProposedConsequentialAction<TPayload>
): AuthorizationResult<TPayload> {
  if (!HUMAN_REQUIRED_KINDS.has(action.kind)) {
    // Defensive: anything routed here is consequential by construction. If a
    // caller passes an unknown kind, fail closed rather than auto-authorize.
    return { authorized: false, reason: `Unknown consequential kind "${action.kind}" — refusing.` };
  }
  if (!approvalIsComplete(action.approval)) {
    return {
      authorized: false,
      reason: `Action "${action.kind}" proposed by ${action.proposedBy} has no complete human approval.`,
    };
  }
  if (action.approval.decision !== "approve") {
    return {
      authorized: false,
      reason: `Human ${action.approval.decision}ed action "${action.kind}": ${action.approval.rationale}`,
    };
  }
  return {
    authorized: true,
    payload: action.payload,
    kind: action.kind,
    approval: action.approval,
    execute: (mutation) => mutation(action.payload),
  };
}

/**
 * Convenience guard for call sites that only need a boolean gate. Prefer
 * `authorizeConsequentialAction` where you will actually perform the mutation,
 * so the executor stays bound to the approval.
 */
export function requiresHumanDecision(kind: ConsequentialActionKind): boolean {
  return HUMAN_REQUIRED_KINDS.has(kind);
}
