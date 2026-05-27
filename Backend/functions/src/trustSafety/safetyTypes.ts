/**
 * safetyTypes.ts — Amen Trust + Safety OS
 *
 * Unified type system for the full Trust + Safety OS.
 * All moderation, provenance, bot defense, identity trust, ranking safety,
 * wellness, reporting, enforcement, and AI transparency modules share these types.
 *
 * Policy version is bumped whenever category definitions or decision thresholds change.
 */

export const TRUST_SAFETY_OS_VERSION = "2026-05-25-v1";

// ─── Core Decision ────────────────────────────────────────────────────────────

export type SafetyDecisionOutcome =
  | "allow"
  | "allow_with_label"
  | "limit_distribution"
  | "quarantine"
  | "block"
  | "escalate";

export type RiskCategory =
  | "sexual"
  | "nudity"
  | "csam_indicator"
  | "grooming"
  | "sextortion"
  | "trafficking"
  | "violence"
  | "gore"
  | "extremism"
  | "hate"
  | "harassment"
  | "scam"
  | "impersonation"
  | "misinformation"
  | "synthetic_media"
  | "bot_behavior"
  | "spam"
  | "manipulation"
  | "self_harm"
  | "privacy_violation"
  | "unknown";

export type ProvenanceStatus =
  | "original"
  | "edited"
  | "ai_assisted"
  | "ai_generated"
  | "reposted"
  | "source_uncertain"
  | "verified_source"
  | "context_missing"
  | "unknown";

export type AIGeneratedStatus =
  | "not_ai"
  | "ai_assisted"
  | "ai_generated"
  | "unknown";

export type EnforcementAction =
  | "none"
  | "label"
  | "warn"
  | "limit_distribution"
  | "quarantine"
  | "block"
  | "block_and_suspend"
  | "escalate_to_reviewer"
  | "escalate_to_legal"
  | "escalate_to_ncmec";

export interface SafetyDecision {
  decision: SafetyDecisionOutcome;
  riskScore: number;                      // 0.0 – 1.0
  categories: Partial<Record<RiskCategory, number>>;  // category → confidence 0–1
  explanation: string;                    // internal
  userFacingReason: string | null;
  reviewerReason: string | null;
  provenanceStatus: ProvenanceStatus;
  aiGeneratedStatus: AIGeneratedStatus;
  enforcementAction: EnforcementAction;
  createdAt: FirebaseFirestore.Timestamp | string;
  modelVersions: string[];
  appealAllowed: boolean;
  policyVersion: string;
  contentId?: string;
  contentType?: ContentSurface;
  authorUid?: string;
}

// ─── Content Surfaces ─────────────────────────────────────────────────────────

export type ContentSurface =
  | "post"
  | "comment"
  | "reply"
  | "dm"
  | "group_message"
  | "profile_bio"
  | "username"
  | "banner"
  | "church_page"
  | "creator_page"
  | "event"
  | "review"
  | "testimonial"
  | "livestream_metadata"
  | "thumbnail"
  | "caption"
  | "alt_text"
  | "ai_summary";

// ─── Provenance ───────────────────────────────────────────────────────────────

export interface MediaProvenance {
  mediaId: string;
  uploaderUid: string;
  originalHash: string;
  perceptualHash: string;
  metadataDigest: string;
  aiDetectionScore: number;     // 0–1, confidence this is AI-generated
  editingDetected: boolean;
  sourceChain: string[];
  uploadDeviceTrust: DeviceTrustLevel;
  creatorDeclaration: CreatorDeclaration;
  provenanceStatus: ProvenanceStatus;
  trendEligible: boolean;
  boostEligible: boolean;
  labelRequired: boolean;
  createdAt: FirebaseFirestore.Timestamp | string;
  policyVersion: string;
}

export type CreatorDeclaration =
  | "original"
  | "edited"
  | "ai_assisted"
  | "ai_generated"
  | "reposted"
  | "unknown";

export type DeviceTrustLevel =
  | "trusted"
  | "normal"
  | "low_trust"
  | "unknown";

// ─── Bot Defense ──────────────────────────────────────────────────────────────

export type BotScore =
  | "human_likely"
  | "suspicious"
  | "coordinated"
  | "automated"
  | "malicious";

export interface BotDefenseResult {
  uid: string;
  botScore: BotScore;
  confidence: number;           // 0–1
  signals: BotSignal[];
  requiresChallenge: boolean;
  throttleActions: boolean;
  suppressFromRanking: boolean;
  quarantineEngagement: boolean;
  createdAt: FirebaseFirestore.Timestamp | string;
  policyVersion: string;
}

export interface BotSignal {
  name: string;
  value: number | boolean | string;
  weight: number;
}

// ─── Identity Trust ───────────────────────────────────────────────────────────

export type IdentityTrustLevel =
  | "basic"
  | "email_verified"
  | "phone_verified"
  | "trusted_device"
  | "human_challenge_passed"
  | "community_verified"
  | "church_verified"
  | "creator_verified"
  | "professional_verified";

export interface IdentityTrustProfile {
  uid: string;
  trustLevel: IdentityTrustLevel;
  verifiedAt: FirebaseFirestore.Timestamp | string | null;
  verificationSource: string | null;
  claimedRoles: string[];
  unverifiedClaims: string[];
  isSuspectedImpersonation: boolean;
  trustScore: number;           // 0–100
  policyVersion: string;
}

export interface ChurchVerification {
  churchId: string;
  domainVerified: boolean;
  locationVerified: boolean;
  googlePlacesValidated: boolean;
  adminVerified: boolean;
  isDuplicate: boolean;
  isSuspectedImpersonation: boolean;
  verifiedAt: FirebaseFirestore.Timestamp | string | null;
  policyVersion: string;
}

// ─── Ranking Safety ───────────────────────────────────────────────────────────

export interface RankingSignals {
  safetyScore: number;
  provenanceScore: number;
  usefulnessScore: number;
  originalityScore: number;
  relationshipRelevance: number;
  communityHealthScore: number;
  spiritualHelpfulnessScore: number;
  localRelevance: number;
  userIntentMatch: number;
  freshness: number;
  diversity: number;
  wellnessImpact: number;
  // Penalty signals (negative when present)
  outrageSignal: number;
  fearBaitSignal: number;
  engagementFarmingSignal: number;
  botEngagementFraction: number;
  syntheticViralitySignal: number;
}

export interface RankingDecision {
  contentId: string;
  finalScore: number;
  signals: RankingSignals;
  trendEligible: boolean;
  boostEligible: boolean;
  suppressedReason: string | null;
  createdAt: FirebaseFirestore.Timestamp | string;
  policyVersion: string;
}

// ─── Wellness ─────────────────────────────────────────────────────────────────

export type WellnessTrigger =
  | "doomscrolling"
  | "repeated_anger_content"
  | "late_night_usage"
  | "repeated_conflict_replies"
  | "about_to_post_harmful"
  | "receiving_harassment"
  | "repeated_traumatic_content";

export type WellnessIntervention =
  | "selah_pause"
  | "reflection_prompt"
  | "post_confirmation"
  | "conflict_warning"
  | "reply_reflection"
  | "mute_suggestion"
  | "disable_notifications"
  | "switch_to_reflection_mode";

export interface WellnessEvent {
  uid: string;
  trigger: WellnessTrigger;
  intervention: WellnessIntervention;
  dismissed: boolean;
  actedOn: boolean;
  createdAt: FirebaseFirestore.Timestamp | string;
}

// ─── Reporting ────────────────────────────────────────────────────────────────

export type ReportCategory =
  | "sexual_content"
  | "minor_safety"
  | "grooming"
  | "impersonation"
  | "scam"
  | "trafficking"
  | "violence"
  | "harassment"
  | "fake_ai_media"
  | "misinformation"
  | "hate_extremism"
  | "self_harm_concern"
  | "privacy_violation"
  | "fake_church_profile"
  | "fake_review_testimonial"
  | "bot_activity";

export type ReportSeverity = "low" | "medium" | "high" | "critical";

export type ReportStatus =
  | "submitted"
  | "queued"
  | "under_review"
  | "escalated"
  | "resolved_actioned"
  | "resolved_no_action"
  | "appealed";

export interface AbuseReport {
  reportId: string;
  reporterUid: string;
  targetUid: string | null;
  contentId: string | null;
  contentType: ContentSurface | null;
  category: ReportCategory;
  severity: ReportSeverity;
  status: ReportStatus;
  details: string | null;
  evidencePreserved: boolean;
  contentQuarantined: boolean;
  escalated: boolean;
  resolvedAt: FirebaseFirestore.Timestamp | string | null;
  createdAt: FirebaseFirestore.Timestamp | string;
  policyVersion: string;
}

// ─── Enforcement ─────────────────────────────────────────────────────────────

export type StrikeSeverity = "minor" | "moderate" | "severe" | "critical";

export type AccountStatus =
  | "active"
  | "warned"
  | "restricted"
  | "suspended"
  | "banned";

export interface EnforcementRecord {
  uid: string;
  strikePoints: number;
  trustScore: number;         // 0–100, derived from strikes
  accountStatus: AccountStatus;
  strikeHistory: StrikeEntry[];
  lastUpdated: FirebaseFirestore.Timestamp | string;
  policyVersion: string;
}

export interface StrikeEntry {
  strikeId: string;
  harmCategoryId: string;
  severity: StrikeSeverity;
  points: number;
  contentId: string | null;
  issuedBy: string;
  expiresAt: FirebaseFirestore.Timestamp | string | null;
  createdAt: FirebaseFirestore.Timestamp | string;
}

// ─── AI Transparency ─────────────────────────────────────────────────────────

export interface AITransparencyRecord {
  contentId: string;
  contentType: ContentSurface;
  wasAIGenerated: boolean;
  wasAIAssisted: boolean;
  aiModelsUsed: string[];
  declarationByAuthor: AIGeneratedStatus;
  detectedBySystem: AIGeneratedStatus;
  labelShown: boolean;
  labelType: AILabelType;
  createdAt: FirebaseFirestore.Timestamp | string;
}

export type AILabelType =
  | "none"
  | "ai_generated"
  | "ai_assisted"
  | "may_be_ai"
  | "source_uncertain";

// ─── Audit ───────────────────────────────────────────────────────────────────

export interface SafetyAuditEvent {
  eventId: string;
  eventType: SafetyAuditEventType;
  actorUid: string | "system";
  targetUid: string | null;
  contentId: string | null;
  contentType: ContentSurface | null;
  decision: SafetyDecisionOutcome | null;
  category: RiskCategory | null;
  metadata: Record<string, unknown>;
  createdAt: FirebaseFirestore.Timestamp | string;
  policyVersion: string;
}

export type SafetyAuditEventType =
  | "preflight_check"
  | "content_blocked"
  | "content_quarantined"
  | "content_labeled"
  | "report_submitted"
  | "report_escalated"
  | "report_resolved"
  | "strike_issued"
  | "account_restricted"
  | "account_suspended"
  | "account_banned"
  | "evidence_preserved"
  | "provenance_registered"
  | "bot_flagged"
  | "identity_verified"
  | "appeal_submitted"
  | "appeal_resolved"
  | "wellness_intervention_shown";
