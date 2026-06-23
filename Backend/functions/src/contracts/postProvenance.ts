/**
 * Post + Account Provenance Resolution — Shared TypeScript Types
 * Version: 1.0.0 | Status: Wave 0 contract (frozen after commit)
 * Feature D — Provenance & authenticity labels (post + account precedence).
 *
 * SOURCE OF TRUTH. The Swift mirror lives in
 * AMENAPP/AIIntelligence/PostProvenanceReceiptContracts.swift and must stay
 * shape-aligned (TS -> Swift, never the reverse).
 *
 * NON-NEGOTIABLE INVARIANTS (postProvenance.test.ts):
 *   D-I1  POST precedence: a post-level label/decision ALWAYS overrides the
 *         account tier. The account tier may only adjust PROMINENCE, never
 *         flip a label or contribute a number to a displayed score.
 *   D-I2  Internal-only Trust Passport: the account tier is never surfaced as a
 *         displayed number. `accountTierWeight` is internal-only and never
 *         leaves the resolver as a public score.
 *   D-I3  Fail-closed: when the post's TrustAnalysisProfile is absent OR the
 *         account passport is absent, the resolver returns a single FLAT
 *         `pendingReview` label — never an optimistic/confident label.
 *   D-I4  Provenance trail like an AIReceipt: every receipt carries basis +
 *         sources + a coarse confidence band, never a raw public score.
 *
 * This is a presentation/derivation type. It never fabricates labels or
 * sources; absence of an affirmative positive signal is itself "pendingReview".
 *
 * Reconciliation with existing runtime types (named so we extend, not dup):
 *   - AuthenticityKind  <- AuthenticityLabel.AuthenticityKind (SocialOSModels.swift)
 *   - post layer        <- TrustAnalysisProfile (PostTrustAnalysisService.swift)
 *   - account layer      <- PassportLevel / TrustPassportService (internal-only)
 *   - confidence band   <- ReceiptConfidence shape (trustTransparency.ts AIReceipt)
 */

// ─────────────────────────────────────────────────────────────
// AuthenticityKind — MIRRORS AuthenticityLabel.AuthenticityKind raw values
// (SocialOSModels.swift). Do NOT add kinds here without adding them there.
// ─────────────────────────────────────────────────────────────

export type AuthenticityKind =
  | "real_media"
  | "creator_verified"
  | "community_verified"
  | "church_media"
  | "edited_real_footage"
  | "ai_assisted_captions"
  | "ai_assisted_translation"
  | "transcript_approved"
  | "pending_review"
  | "synthetic_warning";

// ─────────────────────────────────────────────────────────────
// Account tier — MIRRORS PassportLevel raw values (TrustOSContracts.swift).
// INTERNAL ONLY (D-I2): affects label prominence, never a displayed number.
// ─────────────────────────────────────────────────────────────

export type AccountPassportTier =
  | "EMAIL"
  | "PHONE"
  | "IDENTITY"
  | "CHURCH"
  | "LEADER"
  | "ORG";

/** Ordering used internally for prominence only. Never surfaced as a number. */
export const ACCOUNT_TIER_ORDER: Readonly<Record<AccountPassportTier, number>> =
  Object.freeze({
    EMAIL: 0,
    PHONE: 1,
    IDENTITY: 2,
    CHURCH: 3,
    LEADER: 4,
    ORG: 5,
  });

// ─────────────────────────────────────────────────────────────
// Coarse confidence band — shape-aligned with AIReceipt ReceiptConfidence
// (trustTransparency.ts). `basis` is REQUIRED; `score` is omitted unless a
// real principled signal exists. Never a public score on its own.
// ─────────────────────────────────────────────────────────────

export type ProvenanceConfidenceBand = "low" | "medium" | "high";

export interface ProvenanceConfidence {
  band: ProvenanceConfidenceBand;
  /** Human-readable basis, e.g. "captured in app". REQUIRED, never invented. */
  basis: string;
  /** Optional principled internal signal in [0,1]. Omit when no real signal. */
  score?: number;
}

// ─────────────────────────────────────────────────────────────
// Provenance source trail — like an AIReceipt's sources[].
// ─────────────────────────────────────────────────────────────

export type ProvenanceSourceType =
  | "captureSignal"      // in-app capture / on-device bonus
  | "contentCredentials" // C2PA status
  | "syntheticAnalysis"  // deepfake / synthetic-media analysis
  | "accountTier"        // passport tier (prominence only, internal)
  | "moderation";        // moderation review status

export interface ProvenanceSource {
  type: ProvenanceSourceType;
  /** Real locator: signal id, status string, or tier raw value. */
  locator: string;
  /** Human-readable summary, never a raw score. */
  summary: string;
}

// ─────────────────────────────────────────────────────────────
// Label prominence — derived from the account tier (D-I1: prominence ONLY).
// ─────────────────────────────────────────────────────────────

export type LabelProminence = "subtle" | "standard" | "elevated";

export interface PostProvenanceLabel {
  kind: AuthenticityKind;
  title: string;
  detail: string;
  /** Coarse only. Never a displayed number. */
  confident: boolean;
  /** Account tier may raise prominence; it can NEVER change `kind` (D-I1). */
  prominence: LabelProminence;
}

// ─────────────────────────────────────────────────────────────
// Inputs — the two layers. Both intentionally minimal and internal.
// ─────────────────────────────────────────────────────────────

/** POST layer. Mirrors the surfaceable parts of TrustAnalysisProfile. */
export interface PostTrustProfile {
  postId: string;
  /** Resolved post-level label kind. POST precedence (D-I1). */
  resolvedKind: AuthenticityKind;
  /** Coarse confidence band for the post label. */
  confidence: ProvenanceConfidence;
  /** Whether the post-level analysis is confident (gates `confident`). */
  confidentSignal: boolean;
  /** Real provenance sources for the trail. */
  sources: ProvenanceSource[];
}

/** ACCOUNT layer. Internal-only — never a displayed number (D-I2). */
export interface AccountTrustPassport {
  uid: string;
  tier: AccountPassportTier;
}

// ─────────────────────────────────────────────────────────────
// PostProvenanceReceipt — the resolved output. Shape echoes AIReceipt:
// a derivation/presentation receipt carrying basis + sources + band.
// ─────────────────────────────────────────────────────────────

export interface PostProvenanceReceipt {
  postId: string;
  /** The single resolved label. POST precedence over account tier (D-I1). */
  label: PostProvenanceLabel;
  /** Confidence band + basis. No public score. */
  confidence: ProvenanceConfidence;
  /** The provenance trail. */
  sources: ProvenanceSource[];
  /** True when this receipt is the fail-closed flat pendingReview (D-I3). */
  failClosed: boolean;
  /** ISO-8601 string. */
  resolvedAt: string;
  /**
   * Internal-only tier weight used for prominence. NEVER displayed (D-I2).
   * Present for audit/debug parity with the Swift mirror; not a public score.
   */
  accountTierWeight: number;
}

// ─────────────────────────────────────────────────────────────
// Title / detail copy for each kind. Positive framing; no scores.
// ─────────────────────────────────────────────────────────────

const LABEL_COPY: Readonly<
  Record<AuthenticityKind, { title: string; detail: string }>
> = Object.freeze({
  real_media: { title: "Real Media", detail: "No synthetic modifications detected." },
  creator_verified: { title: "Captured On Device", detail: "Media was captured directly on the creator's device." },
  community_verified: { title: "Community Verified", detail: "Verified by the community." },
  church_media: { title: "Church Media", detail: "Published by a verified church." },
  edited_real_footage: { title: "AI Edited", detail: "Real footage with AI editing applied." },
  ai_assisted_captions: { title: "AI Assisted", detail: "AI was used for metadata or captions." },
  ai_assisted_translation: { title: "AI Translated", detail: "AI was used to translate this content." },
  transcript_approved: { title: "Transcript Ready", detail: "Transcript was reviewed and approved." },
  pending_review: { title: "Pending Review", detail: "Authenticity is being reviewed." },
  synthetic_warning: { title: "Synthetic Media", detail: "This media may be synthetically generated." },
});

// ─────────────────────────────────────────────────────────────
// Fail-closed flat receipt (D-I3): a single pendingReview label, never
// confident, no positive framing, internal tier weight 0.
// ─────────────────────────────────────────────────────────────

export function failClosedReceipt(postId: string, basis: string): PostProvenanceReceipt {
  const copy = LABEL_COPY.pending_review;
  return {
    postId,
    label: {
      kind: "pending_review",
      title: copy.title,
      detail: copy.detail,
      confident: false,
      prominence: "subtle",
    },
    confidence: { band: "low", basis },
    sources: [],
    failClosed: true,
    resolvedAt: new Date().toISOString(),
    accountTierWeight: 0,
  };
}

// ─────────────────────────────────────────────────────────────
// Prominence derivation — account tier affects PROMINENCE ONLY (D-I1).
// IDENTITY/CHURCH/LEADER/ORG elevate; PHONE is standard; EMAIL is subtle.
// ─────────────────────────────────────────────────────────────

export function prominenceForTier(tier: AccountPassportTier): LabelProminence {
  const weight = ACCOUNT_TIER_ORDER[tier];
  if (weight >= ACCOUNT_TIER_ORDER.IDENTITY) return "elevated";
  if (weight >= ACCOUNT_TIER_ORDER.PHONE) return "standard";
  return "subtle";
}

// ─────────────────────────────────────────────────────────────
// resolvePostLabels — PURE. POST precedence over account tier.
//
// Precedence (D-I1):
//   1. The post-level `resolvedKind` is the label kind. The account tier can
//      NEVER change it.
//   2. The account tier only raises label PROMINENCE.
//
// Fail-closed (D-I3): if `profile` is null/undefined OR `passport` is
// null/undefined, return the flat pendingReview receipt.
//
// Internal-only (D-I2): the tier weight is recorded in `accountTierWeight`
// for audit parity but is never a displayed number.
// ─────────────────────────────────────────────────────────────

export function resolvePostLabels(
  profile: PostTrustProfile | null | undefined,
  passport: AccountTrustPassport | null | undefined
): PostProvenanceReceipt {
  // D-I3: missing the account passport -> flat fail-closed receipt.
  if (!passport) {
    return failClosedReceipt(profile?.postId ?? "", "account passport unavailable");
  }
  // D-I3: missing the post analysis -> flat fail-closed receipt.
  if (!profile) {
    return failClosedReceipt("", "post analysis unavailable");
  }

  const copy = LABEL_COPY[profile.resolvedKind] ?? LABEL_COPY.pending_review;
  // D-I1: account tier influences prominence ONLY; never the kind.
  const prominence = prominenceForTier(passport.tier);

  const sources: ProvenanceSource[] = [
    ...profile.sources,
    {
      type: "accountTier",
      locator: passport.tier,
      summary: "Account verification affects label prominence only.",
    },
  ];

  return {
    postId: profile.postId,
    label: {
      kind: profile.resolvedKind, // POST precedence (D-I1)
      title: copy.title,
      detail: copy.detail,
      confident: profile.confidentSignal,
      prominence,
    },
    confidence: profile.confidence,
    sources,
    failClosed: false,
    resolvedAt: new Date().toISOString(),
    // D-I2: internal-only weight, never displayed.
    accountTierWeight: ACCOUNT_TIER_ORDER[passport.tier],
  };
}
