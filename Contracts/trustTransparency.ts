/**
 * Trust, Transparency & Human-Flourishing — Shared TypeScript Types
 * Version: 1.0.0 | Status: Wave 0 foundation (frozen after Wave 0 commit)
 * Amendment requires: RUNLOG entry + orchestrator approval
 *
 * Single source of truth for the Trust/Transparency feature set. Swift mirrors
 * live in AMENAPP/AIIntelligence/TrustTransparencyContracts.swift and must stay
 * shape-aligned (TS → Swift, never the reverse).
 *
 * NON-NEGOTIABLE (see build brief §2): every field below is fed by a REAL signal
 * or omitted. No hardcoded metrics, no decorative confidence, no back-filled
 * provenance. Where a shape extends an existing system, the canonical runtime
 * type is named in the comment so we extend rather than duplicate.
 */

// ─────────────────────────────────────────────────────────────
// Constitutional principles (deduped from the brief)
// NEW — no pre-existing enum carries these named principles.
// BereanConstitutionalMode (ask/discern/build/guard/reflect) is a DIFFERENT
// concept (epistemic mode) and is NOT reused here.
// ─────────────────────────────────────────────────────────────

export type ConstitutionalPrinciple =
  | "truthBeforeVirality"
  | "contextBeforeOutrage"
  | "dignityBeforeEngagement"
  | "restorationBeforePunishment"
  | "humansBeforeAlgorithms"
  | "safetyScalesWithCapability";

// ─────────────────────────────────────────────────────────────
// Shared confidence primitive (brief §2.2)
// A band MUST carry the basis that produced it. `score` is present only when a
// principled numeric signal exists (retrieval-score agreement / self-consistency
// / model-reported uncertainty); otherwise it is omitted, never invented.
// ─────────────────────────────────────────────────────────────

export type ConfidenceBand = "low" | "medium" | "high";

export interface ReceiptConfidence {
  band: ConfidenceBand;
  /** Human-readable basis, e.g. "3 sources agree" / "limited sources". REQUIRED. */
  basis: string;
  /** Optional principled numeric signal in [0,1]. Omit when no real signal exists. */
  score?: number;
}

// ─────────────────────────────────────────────────────────────
// AIReceipt (Wave 1)
// DERIVED from the real BereanPipelineResponse (BereanConstitutionalPipeline.swift):
// sources ← evidence[], confidence ← trustScore + evidence agreement,
// unknowns ← unknowns[], safetyChecksPassed ← pipeline review stages.
// This is a presentation/derivation type; it never fabricates sources.
// ─────────────────────────────────────────────────────────────

export type ReceiptSourceType = "scripture" | "commentary" | "userNote" | "web";

export interface ReceiptSource {
  title: string;
  type: ReceiptSourceType;
  /** Real locator: verse ref, chunk id, URL, or note id. */
  locator: string;
  /** Real retrieval score in [0,1] when available; omit if the pipeline did not return one. */
  retrievalScore?: number;
}

export interface AIReceipt {
  /** Maps to BereanPipelineResponse.traceId. */
  responseId: string;
  mode: string;
  sources: ReceiptSource[];
  confidence: ReceiptConfidence;
  unknowns: string[];
  /** ISO-8601 string. */
  lastUpdated: string;
  /** Names of pipeline review stages that passed (real, not decorative). */
  safetyChecksPassed: string[];
}

// ─────────────────────────────────────────────────────────────
// ModerationReceipt (Wave 2)
// COMPLEMENTS the existing append-only ModerationAuditEntry (ModerationAuditLog.swift)
// and ModerationAppeal (ModerationConstitutionModels.swift). This is the
// user-facing projection that names the principle invoked.
// ─────────────────────────────────────────────────────────────

// Trust-prefixed to mirror the Swift names, which avoid collision with the
// app's existing top-level ModerationAction / AppealStatus types.
export type TrustModerationAction =
  | "hidden"
  | "downranked"
  | "warned"
  | "removed"
  | "allowed";

export type TrustAppealStatus =
  | "none"
  | "available"
  | "submitted"
  | "underReview"
  | "upheld"
  | "overturned";

export interface ModerationReceipt {
  eventId: string;
  action: TrustModerationAction;
  principleInvoked: ConstitutionalPrinciple;
  confidence: ReceiptConfidence;
  /** Real model identifier used for the decision, e.g. "nemo-guard" / "vision-llm". */
  modelUsed: string;
  /** The concrete rule that triggered, from the existing policy framework. */
  ruleTriggered: string;
  appealStatus: TrustAppealStatus;
  humanReviewAvailable: boolean;
}

// ─────────────────────────────────────────────────────────────
// MemoryLedgerEntry (Wave 3)
// NEW — Living Memory UI is dormant in the app. Entries reflect the user's real
// per-user namespace; delete/edit operations hit the real store.
// ─────────────────────────────────────────────────────────────

export interface MemoryLedgerEntry {
  id: string;
  summary: string;
  /** Per-user isolation namespace, e.g. "users/{uid}/berean_memory". */
  namespace: string;
  whyStored: string;
  /** ISO-8601. */
  storedAt: string;
  /** ISO-8601; null if never used since storage. */
  lastUsedAt: string | null;
  usageCount: number;
  editable: boolean;
  deletable: boolean;
}

// ─────────────────────────────────────────────────────────────
// TrustProvenanceLabel (Wave 4)
// RECONCILES with the canonical runtime type MediaProvenance (SocialOSModels.swift)
// and ONEProvenanceLabel. Named distinctly to avoid the duplicate-type collision
// that has broken builds before. Wave 4 maps this onto MediaProvenance rather
// than introducing a second provenance store.
// ─────────────────────────────────────────────────────────────

export type ProvenanceOrigin = "human" | "ai_assisted" | "ai_generated";

export type ProvenanceActor = "human" | "ai";

export interface ProvenanceEdit {
  actor: ProvenanceActor;
  /** ISO-8601. */
  at: string;
  summary: string;
}

export interface TrustProvenanceLabel {
  contentId: string;
  /** Written at creation time from the real pipeline; never back-filled. */
  origin: ProvenanceOrigin;
  editHistory: ProvenanceEdit[];
}

// ─────────────────────────────────────────────────────────────
// FlourishingMetrics (Wave 5)
// NEW — anti-engagement. `eventSource` is MANDATORY: a signal with no real source
// is OMITTED, never zero-filled. No leaderboards, no streaks.
// ─────────────────────────────────────────────────────────────

export interface FlourishingSignal {
  key: string;
  value: number;
  /** REQUIRED real event source, e.g. "conversations.meaningful" Firestore counter. */
  eventSource: string;
}

export interface FlourishingMetrics {
  /** ISO-8601 date of the week start. */
  weekOf: string;
  signals: FlourishingSignal[];
}

// ─────────────────────────────────────────────────────────────
// RedTeamReport (Wave 6)
// NEW — registry starts EMPTY and fills with real submissions only.
// ─────────────────────────────────────────────────────────────

export type RedTeamCategory =
  | "moderation"
  | "scam"
  | "jailbreak"
  | "ai_failure";

export type RedTeamStatus =
  | "submitted"
  | "triaging"
  | "confirmed"
  | "rejected"
  | "fixed";

export interface RedTeamReport {
  id: string;
  category: RedTeamCategory;
  description: string;
  reproSteps: string;
  status: RedTeamStatus;
  reporterId: string;
  /** True only after a human confirms the report is valid. */
  recognitionAwarded: boolean;
}

// ─────────────────────────────────────────────────────────────
// RecommendationExplanation (Wave 6)
// BRIDGES the existing FeedExplanation / FeedReasonCode (CommunityContractsModels.swift).
// Factors and weights are real ranking inputs, never invented reasons.
// ─────────────────────────────────────────────────────────────

export type RecommendationFactorKind =
  | "followedCreator"
  | "communityMembership"
  | "sharedInterest"
  | "recentActivity";

export interface RecommendationFactor {
  factor: RecommendationFactorKind;
  /** Real contribution weight in [0,1]. */
  weight: number;
}

export interface RecommendationExplanation {
  itemId: string;
  factors: RecommendationFactor[];
}
