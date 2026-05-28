export type SafetyAction = "allow" | "warn" | "review" | "block";
export type RiskCategory =
  | "youthMentalHealth"
  | "exploitation"
  | "sexualExploitation"
  | "childSafety"
  | "csam"
  | "grooming"
  | "sexTrafficking"
  | "sextortion"
  | "pornography"
  | "nonConsensualIntimateImagery"
  | "prostitutionFacilitation"
  | "cyberbullying"
  | "misinformation"
  | "addiction";
export type Severity = "low" | "medium" | "high" | "critical";

export interface SafetyDecision {
  decisionId?: string;
  action: SafetyAction;
  riskCategory: RiskCategory | null;
  severity: Severity;
  reason: string | null;
  userFacingMessage: string | null;
  requiresHumanReview: boolean;
  appealEligible: boolean;
  allowed?: boolean;
  requiredActions?: string[];
  canAppeal?: boolean;
}

export function requiredActionsFor(decision: SafetyDecision): string[] {
  const actions = new Set<string>();

  switch (decision.action) {
  case "allow":
    actions.add("allow");
    break;
  case "warn":
    actions.add("prompt_before_post");
    break;
  case "review":
    actions.add("hold_for_review");
    actions.add("escalate_to_human_review");
    break;
  case "block":
    actions.add("block_send");
    break;
  }

  if (decision.requiresHumanReview) actions.add("escalate_to_human_review");
  if (decision.riskCategory === "misinformation") actions.add("require_source");
  if (decision.riskCategory === "youthMentalHealth") actions.add("show_crisis_resources");
  if (decision.severity === "critical") actions.add("preserve_evidence");

  return Array.from(actions);
}

export function clientSafeDecision(decision: SafetyDecision, decisionId?: string): SafetyDecision {
  return {
    decisionId,
    action: decision.action,
    riskCategory: decision.riskCategory,
    severity: decision.severity,
    reason: null,
    userFacingMessage: decision.userFacingMessage,
    requiresHumanReview: decision.requiresHumanReview,
    appealEligible: decision.appealEligible,
    allowed: decision.action === "allow" || decision.action === "warn",
    requiredActions: requiredActionsFor(decision),
    canAppeal: decision.appealEligible,
  };
}

