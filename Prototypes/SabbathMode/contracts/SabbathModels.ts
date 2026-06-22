/**
 * SabbathModels.ts — FROZEN CONTRACT
 * Phase 1 — Contract Freeze Agent
 * Date: 2026-06-07
 *
 * Firestore-backed data models for the Sabbath Mode feature.
 * All collection paths are canonical — Phase 2 agents must not invent new ones.
 * DO NOT EDIT after Phase 1 is complete.
 */

import type { SabbathDay, SabbathBoundary, SabbathState, SabbathSurface } from './SabbathTypes';

/**
 * User's persisted Sabbath configuration.
 *
 * Firestore path: users/{uid}/sabbath/config
 *
 * Notes:
 * - `chosenDay` is mandatory; no Sabbath Mode without a chosen day.
 * - `timezone` MUST be an IANA timezone string (e.g. "America/New_York").
 *   Source of truth for iOS: TimeZone.current.identifier (device-local, runtime).
 *   Source of truth for server: restModePolicies/{uid}.timezone — follow the
 *   exact pattern in restModeEvaluator.ts function isPolicyActive().
 *   Fallback: users/{uid}/deviceTokens/{token}.timezone (per-device, written on
 *   token registration by PushNotificationHandler).
 */
export interface SabbathConfig {
  /** The day the user observes as their Sabbath. Required; default: 'sunday'. */
  chosenDay: SabbathDay;
  /** How the Sabbath window boundary is calculated. Default: 'localMidnight'. */
  boundary: SabbathBoundary;
  /**
   * IANA timezone string from device (iOS: TimeZone.current.identifier) or
   * restModePolicies/{uid}.timezone (server). Never null.
   */
  timezone: string;
  /** Unix epoch milliseconds — set on initial document creation. */
  createdAt: number;
  /** Unix epoch milliseconds — updated on any field change. */
  updatedAt: number;
}

/**
 * A single Sabbath observance session record.
 *
 * Firestore path: users/{uid}/sabbathSessions/{yyyy-mm-dd}
 *
 * Notes:
 * - Document ID is the ISO date string of the Sabbath (e.g. "2026-06-07").
 * - `surfacesUsed` is NOT a score or ranking — it is used only for the
 *   night-of digest capsule. Never expose as metrics to the user.
 * - `steppedOutAt` is set only once; no re-entry is allowed after stepping out.
 */
export interface SabbathSession {
  /** ISO date string matching the document ID (yyyy-mm-dd). */
  date: string;
  /** Current lifecycle state of this session. */
  state: SabbathState;
  /** Unix epoch milliseconds when the session was entered. */
  enteredAt: number;
  /** Unix epoch milliseconds when the user stepped out. Absent if not yet stepped out. */
  steppedOutAt?: number;
  /**
   * Which allowed surfaces the user visited during this session.
   * Used ONLY for the night-of digest capsule. NOT a score.
   * Capped at sabbathConfig.allowedSurfaces.length.
   */
  surfacesUsed: SabbathSurface[];
}

/**
 * A private reflection written by the user during or after a Sabbath session.
 *
 * Firestore path: users/{uid}/sabbathReflections/{id}
 *
 * Notes:
 * - `id` is a Firestore auto-generated document ID.
 * - `prompt` is the AI-generated or preset prompt the user responded to.
 * - `body` is the user's private text. Never surfaced to other users.
 * - `sessionDate` links back to the SabbathSession (yyyy-mm-dd).
 */
export interface SabbathReflection {
  /** ISO date string of the Sabbath session this reflection belongs to (yyyy-mm-dd). */
  sessionDate: string;
  /** The prompt that was shown to the user (from SABBATH_AI_TASKS: 'reflection_prompt'). */
  prompt: string;
  /** The user's private reflection body. */
  body: string;
  /** Unix epoch milliseconds — set at document creation. Immutable. */
  createdAt: number;
}

/**
 * A curated digest of what happened during the user's Sabbath, built server-side
 * at the moment of re-entry (state transitions from 'active' → 'steppedOut' or
 * window ends).
 *
 * Built by the server (evaluateSabbathMode callable or onSabbathWindowChanged trigger).
 * NEVER built client-side.
 *
 * Notes:
 * - `items` is capped at sabbathConfig.digest.maxItems (6). Server enforces this cap.
 * - `summaryLine` is a single human-readable sentence (max 80 chars).
 * - `deeplink` in each item uses the amenapp:// scheme.
 * - Shown once only (sabbathConfig.digest.showOnce = true); dismissed state tracked
 *   in the SabbathSession document.
 */
export interface SabbathDigest {
  /** ISO date string of the session this digest summarises (yyyy-mm-dd). */
  sessionDate: string;
  /** One-line human-readable summary. Max 80 characters. */
  summaryLine: string;
  /**
   * Curated items to resurface. Capped at sabbathConfig.digest.maxItems.
   * Each item has a label and a deep link into the app.
   */
  items: Array<{
    /** Short human-readable label for the item (max 40 chars). */
    label: string;
    /** amenapp:// deep link to navigate the user to this content on re-entry. */
    deeplink: string;
  }>;
}
