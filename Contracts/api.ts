/**
 * Discussion System — Cloud Function API Signatures
 * Version: 1.0.0 | Status: FROZEN (Phase 0)
 * Amendment requires: RUNLOG entry + orchestrator approval
 *
 * Every callable Cloud Function in the discussion system is defined here.
 * Backend workers implement these signatures exactly.
 * Frontend workers call these signatures exactly.
 * Do not add parameters or return fields without amending this file.
 */

// ─────────────────────────────────────────────────────────────
// askBerean
// ─────────────────────────────────────────────────────────────
//
// Summarizes a thread using an LLM. The LLM key is read from env only
// (process.env.BEREAN_LLM_KEY). A mock adapter is provided for local dev.
//
// Auth: required (any authenticated user)
// Rate limit: 1 call per threadId per 10 minutes per user (enforced server-side)
// Side effect: writes a BereanSummary doc and updates thread.bereanSummaryRef
//
// Path: /askBerean

export interface AskBereanRequest {
  threadId: string;
}

export interface AskBereanResponse {
  /** ID of the newly created BereanSummary doc */
  summaryId: string;
  summary: string;
  agreementPoints: string[];
  openQuestions: string[];
  biblicalRefs: string[];
  studyQuestions: string[];
  /** True when mock adapter was used (local dev / no API key) */
  isMock: boolean;
}

// ─────────────────────────────────────────────────────────────
// detectDuplicate
// ─────────────────────────────────────────────────────────────
//
// Embeds the draft text and compares it against existing in-thread comments.
// Returns the most similar existing comments and a UI suggestion.
//
// The embedding model key is read from env only (process.env.EMBEDDING_KEY).
// A mock adapter returns zero similarity when the key is absent.
//
// Auth: required
// Side effect: none (read-only)
//
// Path: /detectDuplicate

export interface DetectDuplicateRequest {
  threadId: string;
  /** Draft comment body; max 2,000 chars (validated server-side) */
  draftBody: string;
}

export interface DetectDuplicateResponse {
  isDuplicate: boolean;
  /** IDs of up to 3 most similar existing comments; empty when not duplicate */
  similarCommentIds: string[];
  /** Similarity score 0.0–1.0 of the closest match */
  similarityScore: number;
  /** Suggested action for the UI to present */
  suggestion: "supportExisting" | "addAngle" | "postAnyway" | null;
}

// ─────────────────────────────────────────────────────────────
// computeReputation
// ─────────────────────────────────────────────────────────────
//
// Aggregates reputationEvents for a user and returns their current score.
// This is a read-only computation — no writes.
// The client calls this on profile load and after any helpful-mark action.
//
// Auth: required (any authenticated user; can query their own UID or others')
//
// Path: /computeReputation

export interface ComputeReputationRequest {
  uid: string;
}

export interface ComputeReputationResponse {
  uid: string;
  totalPoints: number;
  badgeTier: "none" | "seeker" | "berean" | "elder";
  breakdown: {
    helpfulMark: number;
    acceptedAnswer: number;
    firstComment: number;
    bereanCite: number;
  };
}

// ─────────────────────────────────────────────────────────────
// postComment
// ─────────────────────────────────────────────────────────────
//
// Creates a new comment after the Pre-Post Threshold has been passed.
// Server-side: validates fields, detects verse keys, writes embedding job,
// increments thread.commentCount, awards firstComment reputation event.
//
// Auth: required
// Side effect: writes comment doc, queues embedding job, writes reputation event
//
// Path: /postComment

export interface PostCommentRequest {
  threadId: string;
  /** null = root comment */
  parentCommentId: string | null;
  body: string;
  destination: "public" | "reflection" | "churchNotes";
  /** ISO timestamp from the client when the threshold completed */
  thresholdPassedAt: string;
}

export interface PostCommentResponse {
  commentId: string;
  /** Verse keys detected in body by the server */
  verseKeys: string[];
  /** True if a bereanCite reputation event was awarded */
  awardedBereanCite: boolean;
}

// ─────────────────────────────────────────────────────────────
// markHelpful
// ─────────────────────────────────────────────────────────────
//
// Records a helpful-mark from the calling user on a comment.
// Idempotent: if the user already marked this comment, returns existing event.
// Awards reputation to the comment's author.
//
// Auth: required
// Cannot mark own comment (enforced server-side).
//
// Path: /markHelpful

export interface MarkHelpfulRequest {
  commentId: string;
  threadId: string;
}

export interface MarkHelpfulResponse {
  /** ID of the reputationEvent doc */
  eventId: string;
  /** true = new mark; false = already marked (idempotent) */
  isNew: boolean;
  /** Updated helpfulCount for the comment */
  helpfulCount: number;
}

// ─────────────────────────────────────────────────────────────
// updateWatchProgress
// ─────────────────────────────────────────────────────────────
//
// Client calls this as the user watches media (e.g. every 5 seconds,
// and on pause/seek). Server validates and upserts watchProgress doc.
//
// Auth: required (can only write own progress)
//
// Path: /updateWatchProgress

export interface UpdateWatchProgressRequest {
  postId: string;
  progressFraction: number;
  durationSecs: number;
  watchedSecs: number;
  transcriptRead?: boolean;
}

export interface UpdateWatchProgressResponse {
  /** true = nudge should fire; false = user has watched enough */
  shouldNudge: boolean;
}

// ─────────────────────────────────────────────────────────────
// getWatchProgress
// ─────────────────────────────────────────────────────────────
//
// Reads watch progress for the calling user + a specific post.
// Called by the Pre-Post Threshold before step 1.
//
// Auth: required
//
// Path: /getWatchProgress

export interface GetWatchProgressRequest {
  postId: string;
}

export interface GetWatchProgressResponse {
  /** null = no progress recorded yet */
  progressFraction: number | null;
  transcriptRead: boolean;
  /** true = nudge should fire; false = user has watched enough */
  shouldNudge: boolean;
}

// ─────────────────────────────────────────────────────────────
// OUT-OF-SCOPE stubs (do not implement in V1)
// ─────────────────────────────────────────────────────────────

// TODO: transcribeVoiceComment — STT pipeline; receives Storage path, returns transcript
// TODO: generateHeatMap — per-second engagement aggregation for a post
// TODO: indexCommunityMemory — cross-thread AI knowledge indexing
// TODO: escalateToMediator — elevated conflict resolution queue
// TODO: getCreatorThreadAnalytics — impressions, reach, helpful-mark rate
