/**
 * AmenSafetyPolicy.ts
 *
 * Canonical policy catalog for the Amen Safety OS.
 * All 50+ harm categories are mapped to enforcement actions, escalation
 * paths, evidence requirements, and external-reporting partners.
 *
 * This file is the single source of truth for policy decisions.
 * Cloud Functions import enforcement actions from here; the iOS client
 * reads user-facing messages returned by those functions.
 *
 * Policy version is bumped whenever a category or enforcement action changes.
 */

export const AMEN_SAFETY_POLICY_VERSION = "2026-05-25";

// ─── Enforcement Actions ─────────────────────────────────────────────────────

export type EnforcementAction =
  | "allow"
  | "warn_user"           // Show contextual warning, allow post after acknowledgment
  | "content_warning"    // Allow but attach a content warning label visible to recipient
  | "require_edit"        // Block submit; require user to edit content
  | "block"               // Hard block; content never becomes visible
  | "block_and_suspend"   // Block content + suspend account
  | "escalate"            // Block + preserve evidence + route to safety queue
  | "escalate_to_legal";  // Block + preserve + NCMEC/law enforcement referral

export type EscalationTarget =
  | "none"
  | "human_review_queue"
  | "child_safety_queue"
  | "sexual_exploitation_queue"
  | "self_harm_queue"
  | "violence_queue"
  | "harassment_queue"
  | "misinformation_queue"
  | "law_enforcement"
  | "ncmec_cybertipline"
  | "988_lifeline";

export type ModerationStatus =
  | "pending"
  | "approved"
  // Content that passes moderation but viewers may choose to filter.
  | "borderline"
  | "blocked"
  | "needs_human_review"
  | "escalated"
  | "removed_after_publish";

// ─── Harm Category Definition ─────────────────────────────────────────────────

export interface HarmCategory {
  /** Stable identifier used in audit logs and Firestore documents. */
  id: string;
  /** Human-readable label for moderator dashboards. */
  label: string;
  /** Enforcement action applied when this category is detected. */
  enforcement: EnforcementAction;
  /**
   * moderationStatus written to the content document.
   * Feeds only read content where moderationStatus == "approved".
   */
  moderationStatus: ModerationStatus;
  /** Whether evidence must be preserved before any cleanup. */
  preserveEvidence: boolean;
  /** Whether Firebase Auth disablement should be triggered. */
  suspendAccount: boolean;
  /** Where this case is routed after blocking. */
  escalationTarget: EscalationTarget;
  /**
   * Minimum strike count on an account before this category auto-escalates
   * to the next severity tier. null = always escalate immediately.
   */
  autoEscalateAfterStrikes: number | null;
  /** User-facing message shown when content is blocked. */
  userFacingMessage: string;
  /** Whether minors have extra restrictions for this category. */
  youthStricterEnforcement: boolean;
}

// ─── Policy Catalog ───────────────────────────────────────────────────────────

export const AMEN_POLICY_CATALOG: HarmCategory[] = [
  // ── CSAM & Child Safety ────────────────────────────────────────────────────
  {
    id: "csam",
    label: "CSAM",
    enforcement: "escalate_to_legal",
    moderationStatus: "escalated",
    preserveEvidence: true,
    suspendAccount: true,
    escalationTarget: "ncmec_cybertipline",
    autoEscalateAfterStrikes: null,
    userFacingMessage: "This content cannot be posted on Amen.",
    youthStricterEnforcement: true,
  },
  {
    id: "grooming",
    label: "Grooming",
    enforcement: "escalate_to_legal",
    moderationStatus: "escalated",
    preserveEvidence: true,
    suspendAccount: true,
    escalationTarget: "child_safety_queue",
    autoEscalateAfterStrikes: null,
    userFacingMessage: "This content cannot be posted on Amen.",
    youthStricterEnforcement: true,
  },
  {
    id: "sex_trafficking",
    label: "Sex Trafficking",
    enforcement: "escalate_to_legal",
    moderationStatus: "escalated",
    preserveEvidence: true,
    suspendAccount: true,
    escalationTarget: "ncmec_cybertipline",
    autoEscalateAfterStrikes: null,
    userFacingMessage: "This content cannot be posted on Amen.",
    youthStricterEnforcement: true,
  },
  {
    id: "human_trafficking",
    label: "Human Trafficking",
    enforcement: "escalate_to_legal",
    moderationStatus: "escalated",
    preserveEvidence: true,
    suspendAccount: true,
    escalationTarget: "law_enforcement",
    autoEscalateAfterStrikes: null,
    userFacingMessage: "This content cannot be posted on Amen.",
    youthStricterEnforcement: true,
  },
  {
    id: "online_enticement",
    label: "Online Enticement of Minors",
    enforcement: "escalate_to_legal",
    moderationStatus: "escalated",
    preserveEvidence: true,
    suspendAccount: true,
    escalationTarget: "ncmec_cybertipline",
    autoEscalateAfterStrikes: null,
    userFacingMessage: "This content cannot be posted on Amen.",
    youthStricterEnforcement: true,
  },
  {
    id: "sexualized_minor",
    label: "Sexualized Minor Content",
    enforcement: "escalate_to_legal",
    moderationStatus: "escalated",
    preserveEvidence: true,
    suspendAccount: true,
    escalationTarget: "ncmec_cybertipline",
    autoEscalateAfterStrikes: null,
    userFacingMessage: "This content cannot be posted on Amen.",
    youthStricterEnforcement: true,
  },

  // ── Sexual Content ─────────────────────────────────────────────────────────
  {
    id: "pornography",
    label: "Pornography",
    enforcement: "block",
    moderationStatus: "blocked",
    preserveEvidence: false,
    suspendAccount: false,
    escalationTarget: "human_review_queue",
    autoEscalateAfterStrikes: 2,
    userFacingMessage: "This content cannot be posted on Amen. Please remove sexual content.",
    youthStricterEnforcement: true,
  },
  {
    id: "nudity",
    label: "Nudity",
    enforcement: "block",
    moderationStatus: "blocked",
    preserveEvidence: false,
    suspendAccount: false,
    escalationTarget: "human_review_queue",
    autoEscalateAfterStrikes: 3,
    userFacingMessage: "This content cannot be posted on Amen. Please remove nudity.",
    youthStricterEnforcement: true,
  },
  {
    id: "sexual_content",
    label: "Sexual Content",
    enforcement: "block",
    moderationStatus: "blocked",
    preserveEvidence: false,
    suspendAccount: false,
    escalationTarget: "human_review_queue",
    autoEscalateAfterStrikes: 3,
    userFacingMessage: "This content cannot be posted on Amen. Please remove sexual language.",
    youthStricterEnforcement: true,
  },
  {
    id: "sexual_solicitation",
    label: "Sexual Solicitation",
    enforcement: "block_and_suspend",
    moderationStatus: "escalated",
    preserveEvidence: true,
    suspendAccount: true,
    escalationTarget: "sexual_exploitation_queue",
    autoEscalateAfterStrikes: null,
    userFacingMessage: "This content cannot be posted on Amen.",
    youthStricterEnforcement: true,
  },
  {
    id: "non_consensual_intimate_imagery",
    label: "Non-Consensual Intimate Imagery (Revenge Porn)",
    enforcement: "escalate_to_legal",
    moderationStatus: "escalated",
    preserveEvidence: true,
    suspendAccount: true,
    escalationTarget: "sexual_exploitation_queue",
    autoEscalateAfterStrikes: null,
    userFacingMessage: "This content cannot be posted on Amen.",
    youthStricterEnforcement: true,
  },
  {
    id: "sextortion",
    label: "Sextortion",
    enforcement: "escalate_to_legal",
    moderationStatus: "escalated",
    preserveEvidence: true,
    suspendAccount: true,
    escalationTarget: "sexual_exploitation_queue",
    autoEscalateAfterStrikes: null,
    userFacingMessage: "This content cannot be posted on Amen.",
    youthStricterEnforcement: true,
  },
  {
    id: "deepfake_sexual",
    label: "Sexual Deepfake / AI-Generated NCII",
    enforcement: "escalate_to_legal",
    moderationStatus: "escalated",
    preserveEvidence: true,
    suspendAccount: true,
    escalationTarget: "sexual_exploitation_queue",
    autoEscalateAfterStrikes: null,
    userFacingMessage: "This content cannot be posted on Amen.",
    youthStricterEnforcement: true,
  },
  {
    id: "sexual_harassment",
    label: "Sexual Harassment",
    enforcement: "block",
    moderationStatus: "blocked",
    preserveEvidence: true,
    suspendAccount: false,
    escalationTarget: "harassment_queue",
    autoEscalateAfterStrikes: 1,
    userFacingMessage: "This message cannot be sent on Amen. Please remove harassing language.",
    youthStricterEnforcement: true,
  },
  {
    id: "sexual_violence",
    label: "Sexual Violence / Rape Threats",
    enforcement: "block_and_suspend",
    moderationStatus: "escalated",
    preserveEvidence: true,
    suspendAccount: true,
    escalationTarget: "sexual_exploitation_queue",
    autoEscalateAfterStrikes: null,
    userFacingMessage: "This content cannot be posted on Amen.",
    youthStricterEnforcement: true,
  },

  // ── Violence ───────────────────────────────────────────────────────────────
  {
    id: "graphic_violence",
    label: "Graphic Violence",
    enforcement: "block",
    moderationStatus: "blocked",
    preserveEvidence: false,
    suspendAccount: false,
    escalationTarget: "human_review_queue",
    autoEscalateAfterStrikes: 2,
    userFacingMessage: "This content cannot be posted on Amen. Please remove violent content.",
    youthStricterEnforcement: true,
  },
  {
    id: "gore",
    label: "Gore",
    enforcement: "block",
    moderationStatus: "blocked",
    preserveEvidence: false,
    suspendAccount: false,
    escalationTarget: "human_review_queue",
    autoEscalateAfterStrikes: 2,
    userFacingMessage: "This content cannot be posted on Amen.",
    youthStricterEnforcement: true,
  },
  {
    id: "violence_threat",
    label: "Credible Violence Threat",
    enforcement: "block_and_suspend",
    moderationStatus: "escalated",
    preserveEvidence: true,
    suspendAccount: true,
    escalationTarget: "violence_queue",
    autoEscalateAfterStrikes: null,
    userFacingMessage: "This content cannot be posted on Amen.",
    youthStricterEnforcement: true,
  },
  {
    id: "murder_assault_footage",
    label: "Murder / Assault Footage",
    enforcement: "escalate_to_legal",
    moderationStatus: "escalated",
    preserveEvidence: true,
    suspendAccount: true,
    escalationTarget: "law_enforcement",
    autoEscalateAfterStrikes: null,
    userFacingMessage: "This content cannot be posted on Amen.",
    youthStricterEnforcement: true,
  },
  {
    id: "animal_abuse",
    label: "Animal Abuse",
    enforcement: "block",
    moderationStatus: "blocked",
    preserveEvidence: true,
    suspendAccount: false,
    escalationTarget: "human_review_queue",
    autoEscalateAfterStrikes: 1,
    userFacingMessage: "This content cannot be posted on Amen.",
    youthStricterEnforcement: true,
  },

  // ── Hate / Extremism ───────────────────────────────────────────────────────
  {
    id: "hate_speech",
    label: "Hate Speech",
    enforcement: "block",
    moderationStatus: "blocked",
    preserveEvidence: false,
    suspendAccount: false,
    escalationTarget: "harassment_queue",
    autoEscalateAfterStrikes: 2,
    userFacingMessage: "This content cannot be posted on Amen. Please remove hateful language.",
    youthStricterEnforcement: true,
  },
  {
    id: "racism",
    label: "Racism",
    enforcement: "block",
    moderationStatus: "blocked",
    preserveEvidence: false,
    suspendAccount: false,
    escalationTarget: "harassment_queue",
    autoEscalateAfterStrikes: 2,
    userFacingMessage: "This content cannot be posted on Amen. Please remove hateful language.",
    youthStricterEnforcement: true,
  },
  {
    id: "extremism",
    label: "Extremism",
    enforcement: "block_and_suspend",
    moderationStatus: "escalated",
    preserveEvidence: true,
    suspendAccount: true,
    escalationTarget: "violence_queue",
    autoEscalateAfterStrikes: null,
    userFacingMessage: "This content cannot be posted on Amen.",
    youthStricterEnforcement: true,
  },
  {
    id: "terrorism",
    label: "Terrorism",
    enforcement: "escalate_to_legal",
    moderationStatus: "escalated",
    preserveEvidence: true,
    suspendAccount: true,
    escalationTarget: "law_enforcement",
    autoEscalateAfterStrikes: null,
    userFacingMessage: "This content cannot be posted on Amen.",
    youthStricterEnforcement: true,
  },

  // ── Harassment / Bullying ──────────────────────────────────────────────────
  {
    id: "cyberbullying",
    label: "Cyberbullying",
    enforcement: "warn_user",
    moderationStatus: "needs_human_review",
    preserveEvidence: false,
    suspendAccount: false,
    escalationTarget: "harassment_queue",
    autoEscalateAfterStrikes: 3,
    userFacingMessage: "This content may be considered harmful. Please review our community guidelines.",
    youthStricterEnforcement: true,
  },
  {
    id: "harassment",
    label: "Harassment",
    enforcement: "block",
    moderationStatus: "blocked",
    preserveEvidence: false,
    suspendAccount: false,
    escalationTarget: "harassment_queue",
    autoEscalateAfterStrikes: 3,
    userFacingMessage: "This content cannot be posted on Amen. Please remove harassing language.",
    youthStricterEnforcement: true,
  },
  {
    id: "doxxing",
    label: "Doxxing / PII Exposure",
    enforcement: "block",
    moderationStatus: "blocked",
    preserveEvidence: true,
    suspendAccount: false,
    escalationTarget: "harassment_queue",
    autoEscalateAfterStrikes: 1,
    userFacingMessage: "This content cannot be posted on Amen. Do not share personal information.",
    youthStricterEnforcement: true,
  },
  {
    id: "stalking",
    label: "Stalking / Location Tracking",
    enforcement: "block_and_suspend",
    moderationStatus: "escalated",
    preserveEvidence: true,
    suspendAccount: true,
    escalationTarget: "harassment_queue",
    autoEscalateAfterStrikes: null,
    userFacingMessage: "This content cannot be posted on Amen.",
    youthStricterEnforcement: true,
  },
  {
    id: "blackmail",
    label: "Blackmail / Coercion",
    enforcement: "escalate_to_legal",
    moderationStatus: "escalated",
    preserveEvidence: true,
    suspendAccount: true,
    escalationTarget: "law_enforcement",
    autoEscalateAfterStrikes: null,
    userFacingMessage: "This content cannot be posted on Amen.",
    youthStricterEnforcement: true,
  },

  // ── Mental Health / Self-Harm ──────────────────────────────────────────────
  {
    id: "self_harm_encouragement",
    label: "Self-Harm Encouragement",
    enforcement: "block",
    moderationStatus: "blocked",
    preserveEvidence: true,
    suspendAccount: false,
    escalationTarget: "self_harm_queue",
    autoEscalateAfterStrikes: null,
    userFacingMessage: "This content cannot be posted on Amen. If you need support, help is available.",
    youthStricterEnforcement: true,
  },
  {
    id: "eating_disorder_promotion",
    label: "Eating Disorder Promotion",
    enforcement: "block",
    moderationStatus: "blocked",
    preserveEvidence: false,
    suspendAccount: false,
    escalationTarget: "self_harm_queue",
    autoEscalateAfterStrikes: 2,
    userFacingMessage: "This content cannot be posted on Amen.",
    youthStricterEnforcement: true,
  },
  {
    id: "suicide_method",
    label: "Suicide Method Content",
    enforcement: "block",
    moderationStatus: "blocked",
    preserveEvidence: true,
    suspendAccount: false,
    escalationTarget: "self_harm_queue",
    autoEscalateAfterStrikes: null,
    userFacingMessage: "This content cannot be posted on Amen. If you need support, help is available.",
    youthStricterEnforcement: true,
  },

  // ── Fraud / Scams ──────────────────────────────────────────────────────────
  {
    id: "scam_phishing",
    label: "Scam / Phishing",
    enforcement: "block",
    moderationStatus: "blocked",
    preserveEvidence: true,
    suspendAccount: false,
    escalationTarget: "human_review_queue",
    autoEscalateAfterStrikes: 1,
    userFacingMessage: "This content cannot be posted on Amen. Scam links are not allowed.",
    youthStricterEnforcement: false,
  },
  {
    id: "financial_fraud",
    label: "Financial Fraud",
    enforcement: "block_and_suspend",
    moderationStatus: "escalated",
    preserveEvidence: true,
    suspendAccount: true,
    escalationTarget: "law_enforcement",
    autoEscalateAfterStrikes: null,
    userFacingMessage: "This content cannot be posted on Amen.",
    youthStricterEnforcement: true,
  },
  {
    id: "identity_theft",
    label: "Identity Theft / Impersonation",
    enforcement: "block_and_suspend",
    moderationStatus: "escalated",
    preserveEvidence: true,
    suspendAccount: true,
    escalationTarget: "law_enforcement",
    autoEscalateAfterStrikes: null,
    userFacingMessage: "This content cannot be posted on Amen.",
    youthStricterEnforcement: true,
  },
  {
    id: "fake_giveaway",
    label: "Fake Giveaway / Lottery Scam",
    enforcement: "block",
    moderationStatus: "blocked",
    preserveEvidence: false,
    suspendAccount: false,
    escalationTarget: "human_review_queue",
    autoEscalateAfterStrikes: 2,
    userFacingMessage: "This content cannot be posted on Amen. Please remove scam content.",
    youthStricterEnforcement: false,
  },

  // ── Drugs / Weapons ────────────────────────────────────────────────────────
  {
    id: "drug_sales",
    label: "Drug Sales",
    enforcement: "block_and_suspend",
    moderationStatus: "escalated",
    preserveEvidence: true,
    suspendAccount: true,
    escalationTarget: "law_enforcement",
    autoEscalateAfterStrikes: null,
    userFacingMessage: "This content cannot be posted on Amen.",
    youthStricterEnforcement: true,
  },
  {
    id: "illegal_weapon_sales",
    label: "Illegal Weapon Sales",
    enforcement: "block_and_suspend",
    moderationStatus: "escalated",
    preserveEvidence: true,
    suspendAccount: true,
    escalationTarget: "law_enforcement",
    autoEscalateAfterStrikes: null,
    userFacingMessage: "This content cannot be posted on Amen.",
    youthStricterEnforcement: true,
  },

  // ── Profanity ──────────────────────────────────────────────────────────────
  {
    id: "profanity",
    label: "Profanity / Cussing",
    enforcement: "require_edit",
    moderationStatus: "blocked",
    preserveEvidence: false,
    suspendAccount: false,
    escalationTarget: "none",
    autoEscalateAfterStrikes: 10,
    userFacingMessage: "This content cannot be posted on Amen. Please remove profanity.",
    youthStricterEnforcement: true,
  },

  // ── Misinformation ─────────────────────────────────────────────────────────
  {
    id: "misinformation",
    label: "Misinformation",
    enforcement: "warn_user",
    moderationStatus: "needs_human_review",
    preserveEvidence: false,
    suspendAccount: false,
    escalationTarget: "misinformation_queue",
    autoEscalateAfterStrikes: 5,
    userFacingMessage: "This content has been flagged for review. Consider adding a source.",
    youthStricterEnforcement: false,
  },
  {
    id: "deepfake_impersonation",
    label: "Deepfake / AI Impersonation",
    enforcement: "block",
    moderationStatus: "blocked",
    preserveEvidence: true,
    suspendAccount: false,
    escalationTarget: "misinformation_queue",
    autoEscalateAfterStrikes: 1,
    userFacingMessage: "This content cannot be posted on Amen.",
    youthStricterEnforcement: true,
  },

  // ── Spam / Bots ────────────────────────────────────────────────────────────
  {
    id: "spam_bot",
    label: "Spam / Bot Activity",
    enforcement: "block",
    moderationStatus: "blocked",
    preserveEvidence: false,
    suspendAccount: false,
    escalationTarget: "human_review_queue",
    autoEscalateAfterStrikes: 3,
    userFacingMessage: "This content cannot be posted on Amen.",
    youthStricterEnforcement: false,
  },

  // ── Unsafe Viral Content ───────────────────────────────────────────────────
  {
    id: "unsafe_viral_challenge",
    label: "Unsafe Viral Challenge",
    enforcement: "block",
    moderationStatus: "blocked",
    preserveEvidence: false,
    suspendAccount: false,
    escalationTarget: "human_review_queue",
    autoEscalateAfterStrikes: null,
    userFacingMessage: "This content cannot be posted on Amen.",
    youthStricterEnforcement: true,
  },

  // ── Privacy ────────────────────────────────────────────────────────────────
  {
    id: "privacy_violation",
    label: "Privacy Violation",
    enforcement: "block",
    moderationStatus: "blocked",
    preserveEvidence: true,
    suspendAccount: false,
    escalationTarget: "harassment_queue",
    autoEscalateAfterStrikes: 2,
    userFacingMessage: "This content cannot be posted on Amen. Please remove private information.",
    youthStricterEnforcement: true,
  },

  // ── Addictive Design ───────────────────────────────────────────────────────
  {
    id: "addictive_outrage_content",
    label: "Addictive / Outrage-Loop Content",
    enforcement: "warn_user",
    moderationStatus: "needs_human_review",
    preserveEvidence: false,
    suspendAccount: false,
    escalationTarget: "none",
    autoEscalateAfterStrikes: 10,
    userFacingMessage: "Please review how this content may affect your community.",
    youthStricterEnforcement: true,
  },
];

// ─── Index for fast lookup ────────────────────────────────────────────────────

const _policyMap = new Map<string, HarmCategory>(
  AMEN_POLICY_CATALOG.map((h) => [h.id, h])
);

export function policyFor(harmCategoryId: string): HarmCategory | undefined {
  return _policyMap.get(harmCategoryId);
}

export function enforcementFor(harmCategoryId: string): EnforcementAction {
  return _policyMap.get(harmCategoryId)?.enforcement ?? "allow";
}

export function moderationStatusFor(harmCategoryId: string): ModerationStatus {
  return _policyMap.get(harmCategoryId)?.moderationStatus ?? "pending";
}

export function escalationTargetFor(harmCategoryId: string): EscalationTarget {
  return _policyMap.get(harmCategoryId)?.escalationTarget ?? "none";
}

export function userFacingMessageFor(harmCategoryId: string): string {
  return (
    _policyMap.get(harmCategoryId)?.userFacingMessage ??
    "This content cannot be posted on Amen. Please remove sexual, violent, hateful, or harmful language."
  );
}

/** True if this content must have evidence preserved before any deletion. */
export function requiresEvidencePreservation(harmCategoryId: string): boolean {
  return _policyMap.get(harmCategoryId)?.preserveEvidence ?? false;
}

/** True if the policy mandates account suspension for this category. */
export function requiresAccountSuspension(harmCategoryId: string): boolean {
  return _policyMap.get(harmCategoryId)?.suspendAccount ?? false;
}
