/**
 * Discussion System — Shared TypeScript Types
 * Version: 1.0.0 | Status: FROZEN (Phase 0)
 * Amendment requires: RUNLOG entry + orchestrator approval
 *
 * These types are the single source of truth for both the React frontend
 * and the Cloud Functions backend. Import from this file only — do not
 * inline duplicate shapes.
 */

import type { Timestamp } from "firebase/firestore";

// ─────────────────────────────────────────────────────────────
// Primitives
// ─────────────────────────────────────────────────────────────

export type PostType = "text" | "video" | "audio" | "image";

export type CommentDestination = "public" | "reflection" | "churchNotes";

export type ReputationEventType =
  | "helpfulMark"
  | "acceptedAnswer"
  | "firstComment"
  | "bereanCite";

export type BadgeTier = "none" | "seeker" | "berean" | "elder";

// ─────────────────────────────────────────────────────────────
// threads/{threadId}
// ─────────────────────────────────────────────────────────────

export interface Thread {
  id: string;
  postId: string;
  postAuthorUID: string;
  postType: PostType;
  /** Storage path to plain-text transcript; null when not available */
  transcriptRef: string | null;
  createdAt: Timestamp;
  updatedAt: Timestamp;
  /** Denormalized; never written by the client */
  commentCount: number;
  isLocked: boolean;
  lockedReason: string | null;
  /** Doc path of latest AskBerean result; null until first Berean query */
  bereanSummaryRef: string | null;
}

// ─────────────────────────────────────────────────────────────
// threads/{threadId}/comments/{commentId}
// ─────────────────────────────────────────────────────────────

export interface Comment {
  id: string;
  threadId: string;
  authorUID: string;
  /** Display name snapshotted at write time */
  authorDisplayName: string;
  /** Avatar URL snapshotted at write time; null = use initials fallback */
  authorAvatarURL: string | null;
  /** null = root comment */
  parentCommentId: string | null;
  /** 0 = root, 1 = reply, 2 = reply-to-reply (max enforced server-side) */
  depth: number;
  /** Max 2,000 characters; validated server-side */
  body: string;
  /** OSIS verse keys detected in body, e.g. ["JHN.3.16"] */
  verseKeys: string[];
  destination: CommentDestination;
  /** Denormalized; never written by the client */
  helpfulCount: number;
  /** Set to true by thread's postAuthorUID only */
  isAcceptedAnswer: boolean;
  isDeleted: boolean;
  deletedAt: Timestamp | null;
  createdAt: Timestamp;
  updatedAt: Timestamp | null;
  /** Set server-side on first report */
  reportedAt: Timestamp | null;
  thresholdPassedAt: Timestamp;
  /**
   * 768-d semantic embedding; written by CF after creation.
   * null until embedding job completes.
   * Never returned to the client — CF-only field.
   */
  embedding?: number[] | null;
}

// ─────────────────────────────────────────────────────────────
// reputationEvents/{eventId}
// ─────────────────────────────────────────────────────────────

export interface ReputationEvent {
  id: string;
  type: ReputationEventType;
  fromUID: string;
  toUID: string;
  commentId: string;
  threadId: string;
  points: number;
  createdAt: Timestamp;
}

export const REPUTATION_POINTS: Record<ReputationEventType, number> = {
  helpfulMark: 3,
  acceptedAnswer: 10,
  firstComment: 1,
  bereanCite: 2,
};

export const BADGE_THRESHOLDS: Record<BadgeTier, number> = {
  none: 0,
  seeker: 10,
  berean: 50,
  elder: 200,
};

// ─────────────────────────────────────────────────────────────
// watchProgress/{uid}_{postId}
// ─────────────────────────────────────────────────────────────

export interface WatchProgress {
  uid: string;
  postId: string;
  /** 0.0–1.0 */
  progressFraction: number;
  durationSecs: number;
  watchedSecs: number;
  /** True if user opened the transcript parity path */
  transcriptRead: boolean;
  updatedAt: Timestamp;
}

/** Threshold fraction below which the consume-nudge fires */
export const CONSUME_NUDGE_THRESHOLD = 0.8;

// ─────────────────────────────────────────────────────────────
// contextRefs/{verseKey}
// ─────────────────────────────────────────────────────────────

export interface ContextRef {
  verseKey: string;
  bookName: string;
  chapterNumber: number;
  verseNumber: number;
  /** Human-readable, e.g. "John 3:16" */
  displayRef: string;
  textESV: string;
  textKJV: string;
  textNIV: string | null;
  /** Up to 5 related verse keys */
  crossRefs: string[];
  cachedAt: Timestamp;
}

// ─────────────────────────────────────────────────────────────
// Berean summary — stored as threads/{threadId}/bereanSummaries/{summaryId}
// ─────────────────────────────────────────────────────────────

export interface BereanSummary {
  id: string;
  threadId: string;
  requestedBy: string;
  /** High-level synthesis of the thread discussion */
  summary: string;
  /** Bullet points where commenters agree */
  agreementPoints: string[];
  /** Unresolved questions surfaced in the thread */
  openQuestions: string[];
  /** Verse keys cited or relevant to the thread */
  biblicalRefs: string[];
  /** Questions to deepen personal or group study */
  studyQuestions: string[];
  generatedAt: Timestamp;
  /** Token count of the LLM response, for cost tracking */
  tokenCount: number;
  /** Whether this result was served from the mock adapter (test mode) */
  isMock: boolean;
}

// ─────────────────────────────────────────────────────────────
// UI-only helper types (not stored in Firestore)
// ─────────────────────────────────────────────────────────────

/** A comment with its children pre-assembled for rendering */
export interface CommentNode {
  comment: Comment;
  /** Direct children only; client recurses to render deeper levels */
  children: CommentNode[];
  isCollapsed: boolean;
}

/** Result of the duplicate-detection check, surfaced in the threshold UI */
export interface DuplicateCheckResult {
  isDuplicate: boolean;
  /** IDs of the most similar existing comments */
  similarCommentIds: string[];
  /**
   * One of:
   * - "supportExisting" — the existing comment already says this
   * - "addAngle"        — user has a new perspective to contribute
   * - "postAnyway"      — override, always available
   */
  suggestion: "supportExisting" | "addAngle" | "postAnyway" | null;
  /** Similarity score 0.0–1.0; for display only */
  similarityScore: number;
}

/** User's computed reputation profile */
export interface ReputationProfile {
  uid: string;
  totalPoints: number;
  badgeTier: BadgeTier;
  /** Breakdown by event type */
  breakdown: Record<ReputationEventType, number>;
}

// ─────────────────────────────────────────────────────────────
// Pre-Post Threshold state machine
// ─────────────────────────────────────────────────────────────

export type ThresholdStep =
  | "idle"
  | "consumeNudge"    // Step 1: watch-progress gate
  | "duplicateCheck"  // Step 2: similarity check
  | "destination"     // Step 3: public / reflection / churchNotes
  | "composing"       // Threshold passed; user is writing
  | "submitting";

export interface ThresholdState {
  step: ThresholdStep;
  /** Draft body being composed */
  draftBody: string;
  /** Result of consume nudge; null until step 1 completes */
  watchProgress: WatchProgress | null;
  /** Whether user chose the transcript parity path */
  choseTranscript: boolean;
  /** Result of duplicate check; null until step 2 completes */
  duplicateResult: DuplicateCheckResult | null;
  /** Chosen destination; null until step 3 completes */
  destination: CommentDestination | null;
}
