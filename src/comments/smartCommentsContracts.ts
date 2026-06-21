/**
 * smartCommentsContracts.ts — Smart Comments (enhanced end-to-end)
 * Wave 0 contracts. Frozen after commit; behavior in subsequent waves.
 *
 * AIL rule: TypeScript is source of truth; Swift mirrors in
 * AMENAPP/AIIntelligence/SmartCommentsContracts.swift.
 *
 * SCOPE SPLIT:
 *   SHIP NOW: text comments + entity detection + link/scripture/music previews
 *             + layered moderation (fail-closed) + Berean smart features + CalmCap
 *   DEFER (contracts only): VoiceComment, PaymentTransaction
 *   PERMANENTLY REMOVED: pay-for-reach / paid boosts of spiritual content
 *
 * INVARIANTS:
 *   - NO read-before-moderation: a comment is never publicly visible until
 *     moderation passes. Fail-closed. This is the spine of the build.
 *   - NO UserTrustScore model — route through existing TrustOS signals (internal).
 *   - NO pay-for-boost path exists anywhere in this codebase.
 *   - NSPrivacyTracking=false; do not expose private user data to creators.
 */

import type { PrivacyCoreZone } from '../berean/spiritualIntelligenceContracts';

// ─────────────────────────────────────────────────────────────────────────────
// MODERATION (fail-closed spine)
// ─────────────────────────────────────────────────────────────────────────────

export type ModerationStatus =
  | 'allowed'
  | 'limited'
  | 'pending_review'   // Awaiting human review
  | 'blocked'          // Blocked by automated moderation
  | 'removed'          // Removed after human review
  | 'appealed'         // User has appealed removal
  | 'restored';        // Restored after appeal

export type VisibilityStatus =
  | 'public'
  | 'private'
  | 'creator_only'
  | 'hidden'
  | 'shadow_limited'
  | 'deleted';

export type ModerationCategory =
  | 'harassment'
  | 'hate'
  | 'threats'
  | 'sexual_content'
  | 'child_safety'
  | 'self_harm'        // → supportive resources; no method content
  | 'violence'
  | 'scam'
  | 'spam'
  | 'malware_phishing_link'
  | 'impersonation'
  | 'donation_fraud'
  | 'misinformation'   // medical/legal/financial
  | 'spiritual_abuse'  // Claimed prophetic authority used to control/harm
  | 'doxxing'
  | 'graphic_content'
  | 'ai_generated_spam';

export interface ModerationResult {
  id: string;
  targetId: string;      // commentId or replyId
  targetType: 'comment' | 'reply';
  status: ModerationStatus;
  category?: ModerationCategory;
  confidence: number;    // 0.0–1.0
  source: 'on_device' | 'server_ai' | 'link_scanner' | 'human_review';
  reviewedAt: number;
  reviewedBy?: string;   // Anonymized reviewer ID; never public
}

export interface ModerationAuditLog {
  id: string;
  targetId: string;
  action: 'flagged' | 'approved' | 'removed' | 'appealed' | 'restored' | 'published';
  reason?: string;
  actorType: 'system' | 'human_reviewer' | 'creator' | 'admin' | 'user_reporter';
  actorId?: string;      // Internal only; never exposed publicly
  timestamp: number;
  /** Sensitive records (crisis, child safety) are encrypted at rest */
  encryptedAtRest: boolean;
}

// ─────────────────────────────────────────────────────────────────────────────
// ENTITY DETECTION (server-side authoritative + on-device pre-check)
// ─────────────────────────────────────────────────────────────────────────────

export type DetectedEntityKind =
  | 'bible_verse'
  | 'bible_reference'   // Reference without inline text; needs lookup
  | 'link'
  | 'music_mention'
  | 'video_link'
  | 'prayer_request'
  | 'testimony'
  | 'question'
  | 'crisis_signal';    // → safety workflow; never surface method content

export interface DetectedEntity {
  kind: DetectedEntityKind;
  rawText: string;
  startIndex: number;
  endIndex: number;
  metadata?: Record<string, string>;
}

// ─────────────────────────────────────────────────────────────────────────────
// PREVIEW CARDS (cached; never block UI on generation)
// ─────────────────────────────────────────────────────────────────────────────

export interface ScripturePreview {
  reference: string;
  translation: string;
  text: string;
  /** Passes Citation Integrity before display */
  citationVerified: boolean;
  crossReferenceCount?: number;
  cachedAt: number;
}

export type LinkSafetyVerdict =
  | 'safe'
  | 'unknown'           // Show warning interstitial
  | 'suspicious'        // Show warning interstitial
  | 'phishing'          // Block with explanation
  | 'malware'           // Block with explanation
  | 'adult'             // Block per content policy
  | 'extremist';        // Block with explanation

export interface LinkPreview {
  originalUrl: string;
  /** Server-expanded (shortened links resolved server-side) */
  resolvedUrl: string;
  safetyVerdict: LinkSafetyVerdict;
  title?: string;
  description?: string;
  imageUrl?: string;
  domain?: string;
  /** Unknown or risky → show warning interstitial before navigation */
  requiresWarningInterstitial: boolean;
  cachedAt: number;
}

export interface MusicPreview {
  platform: 'apple_music' | 'spotify' | 'other';
  title?: string;
  artist?: string;
  albumArt?: string;
  previewUrl: string;   // Link to platform — never autoplay
  safetyVerdict: LinkSafetyVerdict;
  /** Invariant: never autoplay */
  readonly _neverAutoplay: true;
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMENT ATTACHMENT (text/preview only — no user media upload in this build)
// ─────────────────────────────────────────────────────────────────────────────

export type AttachmentKind =
  | 'scripture_preview'
  | 'link_preview'
  | 'music_preview'
  | 'video_preview';

export interface CommentAttachment {
  id: string;
  kind: AttachmentKind;
  scripturePreview?: ScripturePreview;
  linkPreview?: LinkPreview;
  musicPreview?: MusicPreview;
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMENT REACTION
// ─────────────────────────────────────────────────────────────────────────────

export type ReactionKind = 'amen' | 'pray' | 'testimony' | 'save';

export interface CommentReaction {
  id: string;
  commentId: string;
  authorId: string;
  kind: ReactionKind;
  createdAt: number;
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMENT + REPLY
// ─────────────────────────────────────────────────────────────────────────────

export interface Comment {
  id: string;
  postId: string;
  parentCommentId?: string;
  userId: string;
  body: string;
  detectedEntities: DetectedEntity[];
  attachments: CommentAttachment[];
  moderationStatus: ModerationStatus;
  /** Comment is NEVER publicly visible until moderationStatus === 'allowed' */
  visibilityStatus: VisibilityStatus;
  safetyLabels: ModerationCategory[];
  /** Internal TrustOS snapshot — never displayed, never exposed to creators */
  _trustScoreSnapshot?: number;
  reactions: CommentReaction[];
  replyCount: number;
  createdAt: number;
  updatedAt: number;
}

export interface CommentReply {
  id: string;
  commentId: string;
  userId: string;
  body: string;
  detectedEntities: DetectedEntity[];
  attachments: CommentAttachment[];
  moderationStatus: ModerationStatus;
  visibilityStatus: VisibilityStatus;
  safetyLabels: ModerationCategory[];
  reactions: CommentReaction[];
  createdAt: number;
  updatedAt: number;
}

// ─────────────────────────────────────────────────────────────────────────────
// REPORT & APPEAL
// ─────────────────────────────────────────────────────────────────────────────

export interface Report {
  id: string;
  reporterId: string;
  targetId: string;
  targetType: 'comment' | 'reply';
  category: ModerationCategory;
  detail?: string;
  submittedAt: number;
}

export interface Appeal {
  id: string;
  reporterId: string;
  targetId: string;
  moderationResultId: string;
  appealText?: string;
  status: 'pending' | 'granted' | 'denied';
  submittedAt: number;
  resolvedAt?: number;
}

// ─────────────────────────────────────────────────────────────────────────────
// CALMCAP MODES (opt-in or creator-set; non-coercive)
// ─────────────────────────────────────────────────────────────────────────────

export interface CalmCapSettings {
  slowModeEnabled: boolean;
  slowModeDelaySeconds?: number;  // Throttle in heated threads
  sabbathModeEnabled: boolean;    // Reduce addictive infinite replies
  kindnessNudgeEnabled: boolean;  // Pre-post; optional; non-preachy
}

// ─────────────────────────────────────────────────────────────────────────────
// DEFERRED CONTRACTS (contracts only — no implementation in this build)
// ─────────────────────────────────────────────────────────────────────────────

/** DEFERRED: behind media-safety gate + founder ruling + App Store policy review */
export interface VoiceComment {
  id: string;
  commentId: string;
  audioUrl: string;          // Signed URL; never permanent public link
  durationSeconds: number;
  transcript?: string;
  transcriptionStatus: 'pending' | 'complete' | 'failed';
  /** DEFERRED: behind founder ruling + App Store review */
  paymentStatus?: 'none' | 'pending' | 'paid';
  moderationStatus: ModerationStatus;
  reviewStatus: 'pending' | 'approved' | 'rejected';
  publishStatus: 'draft' | 'published' | 'removed';
}

/** DEFERRED: no pay-for-reach; creator-offered labor monetization only, behind gate */
export interface VoicePaymentTransaction {
  id: string;
  voiceCommentId: string;
  creatorId: string;
  listenerId: string;
  amountCents: number;
  status: 'pending' | 'completed' | 'refunded';
  createdAt: number;
  /** Invariant: never touches reach or ranking of spiritual content */
  readonly _neverAffectsReach: true;
}
