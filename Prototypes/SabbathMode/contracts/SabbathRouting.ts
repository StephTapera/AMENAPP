/**
 * SabbathRouting.ts — FROZEN CONTRACT
 * Phase 1 — Contract Freeze Agent
 * Date: 2026-06-07
 *
 * Navigation contract and AI task registry for Sabbath Mode.
 *
 * Agent A (State Engine) MUST implement SabbathRouteGuardContract exactly.
 * No Phase 2 agent may alter the routing invariants below.
 * DO NOT EDIT after Phase 1 is complete.
 */

import type { SabbathState } from './SabbathTypes';
import { SABBATH_ALWAYS_ALLOWED } from './SabbathAllowList';
import { sabbathConfig } from './SabbathConfig';

// ─────────────────────────────────────────────────────────────────────────────
// NAVIGATION CONTRACT
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Frozen navigation contract that Agent A (State Engine) must implement.
 *
 * INVARIANTS (enforced by the gate, never by individual views):
 *
 * When SabbathState === 'active':
 *   - ALL routes resolve to the Sabbath Surface (SabbathWindowView).
 *   - EXCEPT: routes whose policyKey is in SABBATH_ALWAYS_ALLOWED (safety).
 *   - EXCEPT: routes corresponding to sabbathConfig.allowedSurfaces.
 *   - The gate NEVER inlines route ids — it imports from SABBATH_ALWAYS_ALLOWED.
 *
 * When SabbathState === 'steppedOut':
 *   - Full app is restored for the remainder of the local day.
 *   - SabbathBanner MUST persist at the top of every screen until midnight.
 *   - No further Sabbath restriction until the next boundary crossing.
 *   - stepOutPolicy.maxPerSabbath is enforced: a second step-out attempt
 *     within the same Sabbath day must be silently rejected (no gate shown).
 *
 * When SabbathState === 'inactive':
 *   - Normal routing; no restriction; no banner.
 *
 * IMPLEMENTATION NOTES for Agent A:
 *   - The existing SundayChurchFocusGateView + RestModeGate pattern is the
 *     structural model. Sabbath Mode is a superset of that gate.
 *   - Allowed tabs during Shabbat (from Phase 0): 3 (Resources), 5 (Profile),
 *     7 (Intelligence). The Sabbath gate adds allowedSurfaces on top of this.
 *   - Do NOT duplicate RestModeGate logic — extend or wrap it.
 *   - Timezone evaluation MUST follow restModeEvaluator.ts isPolicyActive()
 *     pattern: read restModePolicies/{uid}.timezone from Firestore.
 */
export interface SabbathRouteGuardContract {
  /** Current lifecycle state driving the gate decision. */
  state: SabbathState;
  /** The frozen safety allow-list. Gate imports this; never inlines it. */
  safetyAllowList: typeof SABBATH_ALWAYS_ALLOWED;
  /** Surfaces explicitly unlocked during active Sabbath (from sabbathConfig). */
  surfaceAllowList: typeof sabbathConfig.allowedSurfaces;
  /**
   * Compile-time guard: the gate MUST NOT hardcode route id strings.
   * Always import from SABBATH_ALWAYS_ALLOWED.
   */
  readonly neverInlineRouteIds: true;
}

// ─────────────────────────────────────────────────────────────────────────────
// AI TASK REGISTRY
// ─────────────────────────────────────────────────────────────────────────────

/**
 * AI tasks available inside Sabbath Mode surfaces.
 *
 * ALL tasks:
 *   - Are routed exclusively through the existing bereanChatProxy callable.
 *   - Fail closed — if the callable is unavailable, show a graceful offline state.
 *     NEVER fall back to a non-Berean provider.
 *   - Are Claude-only (no GPT-4o, no Grok, no fallover to another model).
 *   - Must pass the Berean Constitutional Constraint check before any response
 *     is shown to the user.
 *
 * Naming follows the existing camelCase verb+Noun convention from Phase 0
 * (evaluateSabbathMode, getSabbathPolicy, setSabbathPreference).
 *
 * Task keys are lowercase_snake to match existing routing config patterns
 * in functions/router/amenRouting.config.js.
 */
export const SABBATH_AI_TASKS = [
  /**
   * sabbath_guide
   * Triggered by: "Lead me through prayer", "Prepare me for church",
   *               "Help me prepare my heart", "What should I pray about?"
   * Surface: prayer | bereanGuide
   */
  'sabbath_guide',

  /**
   * family_questions
   * Liturgical-season-aware dinner-table discussion questions.
   * Triggered by: familyQuestions surface.
   * Seasonality: reads current liturgical season from the server
   *              (same pattern as Berean OS seasonal context).
   */
  'family_questions',

  /**
   * sermon_prep
   * Explain today's sermon text in plain language for post-service reflection.
   * Triggered by: churchNotes surface after a note is captured.
   * Input: sermon scripture reference or raw transcript excerpt.
   */
  'sermon_prep',

  /**
   * devotional
   * Generate a short family devotional for the Sabbath day.
   * Triggered by: scripture | bereanGuide surface.
   * Must include: a scripture passage, a reflection question, a closing prayer prompt.
   */
  'devotional',

  /**
   * reflection_prompt
   * Generate a single private journal prompt for the user's SabbathReflection.
   * Triggered by: reflection surface.
   * Output stored in: users/{uid}/sabbathReflections/{id} (see SabbathModels.ts).
   * PRIVACY: response is never shared; never used for recommendations.
   */
  'reflection_prompt',
] as const;

/** Union type of all valid Sabbath AI task keys. */
export type SabbathAITask = (typeof SABBATH_AI_TASKS)[number];
