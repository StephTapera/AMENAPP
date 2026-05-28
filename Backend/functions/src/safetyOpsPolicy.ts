export type SafetyOpsQueue =
  | "child_safety"
  | "sexual_exploitation"
  | "self_harm"
  | "violence_threat"
  | "harassment"
  | "misinformation"
  | "general_abuse";

export type ExternalPartner =
  | "ncmec_cybertipline"
  | "988_lifeline"
  | "law_enforcement"
  | "none";

export interface SafetyOpsPlan {
  queue: SafetyOpsQueue;
  priority: 1 | 2 | 3 | 4;
  initialResponseMinutes: number;
  resolutionTargetMinutes: number;
  dualApprovalRequired: boolean;
  preserveEvidence: boolean;
  externalPartner: ExternalPartner;
  externalReportingRequiresHumanReview: boolean;
}

export const SAFETY_OPS_POLICY_VERSION = "safety-ops-2026-05-20";

export function safetyOpsPlanFor(category: string, severity: string): SafetyOpsPlan {
  const normalizedCategory = category.toLowerCase();
  const normalizedSeverity = severity.toLowerCase();
  const isCritical = normalizedSeverity === "critical";
  const isHigh = normalizedSeverity === "high";

  if (["minor_safety", "child_safety", "csam", "grooming", "trafficking"].includes(normalizedCategory)) {
    return {
      queue: "child_safety",
      priority: 1,
      initialResponseMinutes: 15,
      resolutionTargetMinutes: 240,
      dualApprovalRequired: true,
      preserveEvidence: true,
      externalPartner: "ncmec_cybertipline",
      externalReportingRequiresHumanReview: true,
    };
  }

  if (["sextortion", "exploitation", "sexual_content", "non_consensual_intimate_imagery"].includes(normalizedCategory)) {
    return {
      queue: "sexual_exploitation",
      priority: 1,
      initialResponseMinutes: 15,
      resolutionTargetMinutes: 240,
      dualApprovalRequired: true,
      preserveEvidence: true,
      externalPartner: "ncmec_cybertipline",
      externalReportingRequiresHumanReview: true,
    };
  }

  if (["self_harm", "mental_health"].includes(normalizedCategory)) {
    return {
      queue: "self_harm",
      priority: isCritical ? 1 : 2,
      initialResponseMinutes: isCritical ? 15 : 60,
      resolutionTargetMinutes: 240,
      dualApprovalRequired: isCritical,
      preserveEvidence: isCritical,
      externalPartner: "988_lifeline",
      externalReportingRequiresHumanReview: true,
    };
  }

  if (["harassment", "hate", "dogpile"].includes(normalizedCategory)) {
    return {
      queue: "harassment",
      priority: isCritical || isHigh ? 2 : 3,
      initialResponseMinutes: isCritical || isHigh ? 60 : 1440,
      resolutionTargetMinutes: isCritical || isHigh ? 720 : 2880,
      dualApprovalRequired: isCritical,
      preserveEvidence: isCritical || isHigh,
      externalPartner: "none",
      externalReportingRequiresHumanReview: false,
    };
  }

  if (["misinformation", "deepfake", "medical_claim", "financial_claim", "political_claim"].includes(normalizedCategory)) {
    return {
      queue: "misinformation",
      priority: isCritical || isHigh ? 2 : 3,
      initialResponseMinutes: isCritical || isHigh ? 120 : 1440,
      resolutionTargetMinutes: isCritical || isHigh ? 1440 : 4320,
      dualApprovalRequired: false,
      preserveEvidence: isCritical || isHigh,
      externalPartner: "none",
      externalReportingRequiresHumanReview: false,
    };
  }

  return {
    queue: "general_abuse",
    priority: isCritical ? 2 : isHigh ? 3 : 4,
    initialResponseMinutes: isCritical ? 60 : isHigh ? 1440 : 2880,
    resolutionTargetMinutes: isCritical ? 720 : isHigh ? 2880 : 10080,
    dualApprovalRequired: isCritical,
    preserveEvidence: isCritical || isHigh,
    externalPartner: "none",
    externalReportingRequiresHumanReview: false,
  };
}

export function safetyOpsDueAt(nowMs: number, minutes: number): Date {
  return new Date(nowMs + minutes * 60 * 1000);
}
