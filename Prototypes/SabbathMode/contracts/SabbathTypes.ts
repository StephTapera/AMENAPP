/**
 * SabbathTypes.ts — FROZEN CONTRACT
 * Phase 1 — Contract Freeze Agent
 * Date: 2026-06-07
 *
 * Primitive type aliases for the Sabbath Mode feature.
 * These types are consumed by ALL Phase 2 agents.
 * DO NOT EDIT after Phase 1 is complete.
 */

/** The day the user observes as their Sabbath. */
export type SabbathDay = 'saturday' | 'sunday';

/**
 * The lifecycle state of a Sabbath session.
 * - 'inactive'    → Not in a Sabbath window; full app available.
 * - 'active'      → Inside a Sabbath window; gate is enforced.
 * - 'steppedOut'  → User deliberately exited for the day; banner persists,
 *                   no further restriction until next boundary.
 */
export type SabbathState = 'inactive' | 'active' | 'steppedOut';

/**
 * How the Sabbath window boundary is determined.
 * - 'localMidnight' → 00:00–23:59 device-local time on the chosen day (default).
 * - 'sundown'       → Sundown-to-sundown (requires lat/lng for solar calculation).
 */
export type SabbathBoundary = 'localMidnight' | 'sundown';

/**
 * Surfaces accessible to the user during active Sabbath.
 * These map 1-to-1 with sabbathConfig.allowedSurfaces.
 * Safety routes (emergency_support, trusted_circle, child_safety_report)
 * are NEVER listed here — they live in SABBATH_ALWAYS_ALLOWED.
 */
export type SabbathSurface =
  | 'scripture'
  | 'prayer'
  | 'bereanGuide'
  | 'churchNotes'
  | 'findChurch'
  | 'spaces'
  | 'familyQuestions'
  | 'reflection';
