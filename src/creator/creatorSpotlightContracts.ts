/**
 * creatorSpotlightContracts.ts — Creator Showcase & Studio / Creator Spotlight
 * Wave 0 contracts. Frozen after commit; behavior in subsequent waves.
 *
 * AIL rule: TypeScript is source of truth; Swift mirrors in
 * AMENAPP/Creator/CreatorSpotlightContracts.swift.
 *
 * Extends existing Creator Profiles — does NOT fork a parallel profile model.
 *
 * CONSTITUTION LOCK (grep the diff to prove these hold):
 *   - No public trust score / tier / trust level progression
 *   - No leaderboards of people; no "Most X" people-ranking
 *   - No shareable big-number "Wrapped" cards
 *   - No demographic inference or AI expertise-confidence score on a person
 *   - No 5-star rating on a person; no automated theological-correctness score
 *   - No ads or promoted placements (labeled sponsorship only, disclosed transparently)
 *   - No passive-viewer identity list
 *   - No engagement-time optimizer; no infinite scroll; no variable-reward delight
 *   - All UGC fails closed without GUARDIAN pre-moderation
 */

import type { PrivacyCoreZone } from '../berean/spiritualIntelligenceContracts';

// ─────────────────────────────────────────────────────────────────────────────
// VERIFICATION BADGE (factual role badge — not a rank or trust tier)
// ─────────────────────────────────────────────────────────────────────────────

export type VerificationBadgeKind =
  | 'identity'         // Verified real person
  | 'organization'     // Verified organization / ministry
  | 'educator'         // Verified educator
  | 'minister'         // Verified minister / pastor / clergy
  | 'professional'     // Verified professional (counselor, theologian, etc.)
  | 'community_leader'; // Verified community leader

export interface VerificationBadge {
  kind: VerificationBadgeKind;
  verifiedAt: number;
  verifiedBy: 'amen_team'; // Only source; no self-verification
  displayLabel: string;
  /** Internal TrustOS use only — never shown publicly */
  _internalTrustOsEligible?: boolean;
}

// ─────────────────────────────────────────────────────────────────────────────
// ORIENTING METADATA (replaces vanity stat row)
// ─────────────────────────────────────────────────────────────────────────────

export type ContentFormat =
  | 'video' | 'audio' | 'text' | 'series'
  | 'study_guide' | 'devotional' | 'prayer' | 'live';

export type LiturgicalSeason =
  | 'advent' | 'christmas' | 'epiphany' | 'lent' | 'holy_week'
  | 'easter' | 'pentecost' | 'ordinary_time' | 'none';

export interface OrientingMetadata {
  format: ContentFormat[];
  approximateLengthMinutes?: number;
  scriptureReferences: string[];
  liturgicalSeason?: LiturgicalSeason;
  /** Plain-language description: "For new believers exploring faith" */
  audienceDescription?: string;
  /** Onboarding hook: "Start with Episode 1: The Call" */
  whereToStart?: string;
  seriesName?: string;
  totalEpisodes?: number;
}

// ─────────────────────────────────────────────────────────────────────────────
// CONTENT CAPABILITY ("What's inside")
// ─────────────────────────────────────────────────────────────────────────────

export type ContentCapabilityKind =
  | 'study_guide'
  | 'audio'
  | 'group_ready'
  | 'original_language_notes'
  | 'works_with_berean'
  | 'transcripts'
  | 'captions'
  | 'sign_language'
  | 'discussion_guide'
  | 'prayer_guide'
  | 'downloadable';

export interface ContentCapability {
  kind: ContentCapabilityKind;
  available: boolean;
}

// ─────────────────────────────────────────────────────────────────────────────
// MODERATION (fail-closed: invisible until approved)
// ─────────────────────────────────────────────────────────────────────────────

export type ModerationStatus =
  | 'pending'      // Not yet reviewed — NEVER show to viewers
  | 'approved'     // GUARDIAN cleared — readable
  | 'rejected'     // Failed moderation
  | 'unavailable'; // Moderation path down — fail-closed, treat as pending

// ─────────────────────────────────────────────────────────────────────────────
// APPROPRIATENESS SIGNAL (aligned to COPPA/KOSA minor-safety invariants)
// ─────────────────────────────────────────────────────────────────────────────

export type AppropriatenessSignal =
  | 'all_ages'
  | 'teen_and_up'          // 13+ aligned
  | 'mature_themes'        // Auto-hidden from minor-scoped sessions
  | 'guidance_suggested';

// ─────────────────────────────────────────────────────────────────────────────
// CREATOR CONTENT
// ─────────────────────────────────────────────────────────────────────────────

export interface CreatorContent {
  id: string;
  creatorId: string;
  title: string;
  description?: string;
  format: ContentFormat;
  thumbnailUrl?: string;
  /** First session / sample only — never full without commitment */
  previewUrl?: string;
  durationSeconds?: number;
  scriptureReferences: string[];
  seriesId?: string;
  seriesPosition?: number;
  publishedAt?: number;
  orientingMetadata: OrientingMetadata;
  capabilities: ContentCapability[];
  appropriatenessSignal: AppropriatenessSignal;
  moderationStatus: ModerationStatus;
  privacyDisclosure: PrivacyDisclosure;
}

// ─────────────────────────────────────────────────────────────────────────────
// REASONED CONNECTIONS (CalmCap-bound; finite list; no ads; no infinite feed)
// ─────────────────────────────────────────────────────────────────────────────

export type ReasonedConnectionKind =
  | 'theme_continuation'
  | 'passage_deepening'
  | 'perspective_contrast'  // Anti-echo-chamber; required "Different Perspectives" slot
  | 'collaborator'
  | 'church_affiliation';

export interface ReasonedConnection {
  targetId: string;
  targetKind: 'creator' | 'series' | 'content';
  /** Required; must be shown to the user */
  reason: string;
  reasonCategory: ReasonedConnectionKind;
  /** Compile-time guard: this connection is never an ad slot */
  readonly _neverAdSlot: true;
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMUNITY REFLECTION (replaces star-rating on a person)
// GUARDIAN-moderated, fail-closed; qualitative only.
// ─────────────────────────────────────────────────────────────────────────────

export type ReflectionTag =
  | 'scripture_helpful'
  | 'encouraged_deeper_study'
  | 'practical'
  | 'good_for_groups'
  | 'helpful_for_new_believers'
  | 'clear';

export interface CommunityReflection {
  id: string;
  authorId: string;
  contentId?: string;      // Null = reflection on the creator overall
  targetCreatorId: string;
  tags: ReflectionTag[];
  writtenReflection?: string;
  submittedAt: number;
  moderationStatus: ModerationStatus;
  /** Invisible to public until moderationStatus === 'approved' */
  visibleToPublic: boolean;
}

export interface BereanReflectionSummary {
  contentId?: string;
  creatorId: string;
  analyzedCount: number;
  /** Always this exact string — never just "AI Summary" */
  readonly label: 'Summarized by Berean';
  /** Link to explanation of how this was generated */
  howGeneratedUrl: string;
  /** e.g. "People found this helpful for grace and small-group discussion" */
  themeSummary: string;
  excludedCategories: string[];
  generatedAt: number;
}

// ─────────────────────────────────────────────────────────────────────────────
// PRIVACY DISCLOSURE ("What this touches" + "Never touched" list)
// Every field mapped to a PRIVACY-CORE zone. Out-transparency Apple.
// ─────────────────────────────────────────────────────────────────────────────

export interface PrivacyFieldDisclosure {
  fieldName: string;
  description: string;
  zone: PrivacyCoreZone;
  purposeDescription: string;
}

export interface PrivacyDisclosure {
  contentId?: string;
  creatorId?: string;
  touchedFields: PrivacyFieldDisclosure[];
  /** Explicit list of things this content NEVER accesses */
  neverTouchedList: string[];
  /** NSPrivacyTracking invariant — always false */
  readonly nsmPrivacyTracking: false;
  generatedAt: number;
}

/** What creators CAN and CANNOT see about viewers */
export interface CreatorViewerPrivacyRules {
  creatorCanSee: string[];
  creatorCannotSee: string[];
  /** Identity revealed only after explicit action */
  identityRevealedAfter: string[];
  viewerControls: string[];
}

// ─────────────────────────────────────────────────────────────────────────────
// NOW / NEW (event timeline — no dark patterns, no artificial urgency)
// ─────────────────────────────────────────────────────────────────────────────

export type NowAndNewKind =
  | 'new_series' | 'live_session' | 'upcoming_event'
  | 'new_episode' | 'announcement' | 'resource';

export interface NowAndNewItem {
  id: string;
  creatorId: string;
  kind: NowAndNewKind;
  headline: string;
  description?: string;
  scheduledAt?: number;
  liveNow: boolean;
  primaryAction?: { label: string; deepLink: string };
}

// ─────────────────────────────────────────────────────────────────────────────
// CURATION SLOT (editorial/pastoral; NEVER a popularity rank)
// ─────────────────────────────────────────────────────────────────────────────

export type CurationIntent =
  | 'editorial'
  | 'pastoral'
  | 'seasonal'
  | 'new_voice'          // Reserve inventory for emerging creators
  | 'local'
  | 'labeled_sponsorship'; // Paid placement — MUST be labeled transparently

export interface CurationSlot {
  id: string;
  intent: CurationIntent;
  targetId: string;
  targetKind: 'creator' | 'content' | 'series';
  /** Shown to user: "Featured for Lent" / "Editorial Pick" */
  intentLabel: string;
  liturgicalSeason?: LiturgicalSeason;
  activeFrom: number;
  activeUntil: number;
  /** Required when intent === 'labeled_sponsorship' */
  sponsorLabel?: string;
  /** Compile-time guard: no popularity rank exists on this slot */
  readonly _noPopularityRank: true;
}

// ─────────────────────────────────────────────────────────────────────────────
// CREATOR SPOTLIGHT (public page extension — not a parallel profile model)
// ─────────────────────────────────────────────────────────────────────────────

export type ContentTab =
  | 'overview' | 'teachings' | 'series' | 'posts'
  | 'live' | 'events' | 'resources' | 'communities' | 'about';

export interface CreatorSpotlight {
  /** Links to existing CreatorProfile — never duplicates profile fields */
  creatorId: string;
  missionStatement?: string;
  featuredContentId?: string;
  verificationBadges: VerificationBadge[];
  activeSeriesIds: string[];
  contentTabOrder: ContentTab[];
  /** Finite list — no infinite feed, no ads */
  reasonedConnections: ReasonedConnection[];
  nowAndNew: NowAndNewItem[];
  /** Always false until flag enabled — fail-closed */
  readonly enabled: false;
}

// ─────────────────────────────────────────────────────────────────────────────
// STUDIO INSIGHT (stewardship framing — not a scoreboard)
// Numbers contextualized; no growth chart; no streak; no "post more to grow"
// ─────────────────────────────────────────────────────────────────────────────

export type InsightKind =
  | 'formation_trend'
  | 'search_discovery'
  | 'passage_resonance'
  | 'stewardship_summary';

export interface StudioInsight {
  id: string;
  creatorId: string;
  kind: InsightKind;
  /** Stewardship-framed plain language — raw number is never the hero */
  narrativeText: string;
  supportingMetric?: {
    label: string;
    value: string;
    context: string;
  };
  periodLabel: string;
  generatedAt: number;
  /** Compile-time guards */
  readonly _noGrowthChart: true;
  readonly _noStreak: true;
}
