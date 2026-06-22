/**
 * SabbathConfig.ts — FROZEN CONTRACT  (also serves as sabbath.config.ts)
 * Phase 1 — Contract Freeze Agent
 * Date: 2026-06-07
 *
 * Canonical runtime defaults for Sabbath Mode.
 * All Phase 2 agents import `sabbathConfig` from this file — never hardcode these
 * values inline in feature code.
 * DO NOT EDIT after Phase 1 is complete.
 */

import type { SabbathDay, SabbathBoundary, SabbathSurface } from './SabbathTypes';

/**
 * Shape of the sabbathConfig constant.
 * Exported separately so Phase 2 agents can reference the type without
 * importing the runtime value.
 */
export interface SabbathConfigDefaults {
  /** Default Sabbath day for new users. */
  defaultDay: SabbathDay;
  /** Default window boundary calculation method. */
  defaultBoundary: SabbathBoundary;

  stepOutPolicy: {
    /**
     * Maximum number of times a user may step out of Sabbath per Sabbath day.
     * Enforced both client-side (gate) and server-side (evaluateSabbathMode).
     */
    maxPerSabbath: number;
    /**
     * Whether the user must confirm before stepping out.
     * True = show a confirmation sheet before restoring full access.
     */
    requiresConfirm: boolean;
    /**
     * When the user steps out, full access is restored for the remainder of the
     * local day. No partial restoration.
     */
    restoresFullDay: boolean;
  };

  /**
   * The surfaces explicitly unlocked during active Sabbath.
   * These are in addition to SABBATH_ALWAYS_ALLOWED (safety routes).
   * See SabbathAllowList.ts — do NOT duplicate these lists.
   */
  allowedSurfaces: SabbathSurface[];

  digest: {
    /**
     * Maximum number of items shown in the night-of digest capsule.
     * Server enforces this cap when building SabbathDigest.items.
     */
    maxItems: number;
    /**
     * Whether the digest capsule self-dismisses after one view.
     * True = shown exactly once per session; dismissed state tracked in
     * the SabbathSession Firestore document.
     */
    showOnce: boolean;
  };

  solidarity: {
    /**
     * Whether to show a presence indicator that others are also observing Sabbath.
     * When true, display presence TEXT ONLY (e.g. "Others are resting too").
     */
    enabled: boolean;
    /**
     * MUST remain false (literal type). NEVER a number.
     * Displaying a count would create social comparison pressure, violating the
     * human-first media design principle.
     */
    showCount: false;
  };
}

/**
 * Canonical Sabbath Mode runtime defaults.
 *
 * Import this constant whenever you need a default value — never hardcode.
 * All values are intentionally conservative (privacy-first, low-friction).
 */
export const sabbathConfig: SabbathConfigDefaults = {
  defaultDay: 'sunday',
  defaultBoundary: 'localMidnight',

  stepOutPolicy: {
    maxPerSabbath: 1,
    requiresConfirm: true,
    restoresFullDay: true,
  },

  allowedSurfaces: [
    'scripture',
    'prayer',
    'bereanGuide',
    'churchNotes',
    'findChurch',
    'spaces',
    'familyQuestions',
    'reflection',
  ],

  digest: {
    maxItems: 6,
    showOnce: true,
  },

  solidarity: {
    enabled: true,
    showCount: false,
  },
};
