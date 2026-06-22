/**
 * callSabbathModel.ts
 * Phase 2D — Berean Sabbath Guide
 * Date: 2026-06-07
 *
 * Routes Sabbath AI calls through bereanChatProxy (Claude-only).
 * - Fail closed: no fallover to any other model, ever.
 * - NeMo moderation applied to communal-visible output only
 *   (family_questions, devotional).
 * - Private tasks (sabbath_guide, sermon_prep, reflection_prompt) are never
 *   sent to moderation and never stored communally.
 * - Retry: up to 2 retries with 1s, 2s exponential backoff.
 * - Guide mode enforced in every system prompt.
 */

import type { SabbathAITask } from '../contracts/SabbathRouting';
import type { LiturgicalContext } from './liturgicalSeason';
import {
  buildSabbathGuidePrompt,
  buildFamilyQuestionsPrompt,
  buildSermonPrepPrompt,
  buildDevotionalPrompt,
  buildReflectionPrompt,
  type PromptContext,
} from './sabbathPrompts';

// ── Firebase callable stubs ────────────────────────────────────────────────────
// In the iOS React prototype layer these are called via firebase/functions.
// Type-only declarations to avoid hard dependency on the Firebase SDK in TS.

declare function getFunctions(): unknown;
declare function httpsCallable(
  functions: unknown,
  name: string
): (data: unknown) => Promise<{ data: unknown }>;

// ── Types ─────────────────────────────────────────────────────────────────────

export interface SabbathModelRequest {
  task: SabbathAITask;
  userInput: string;
  liturgicalContext: LiturgicalContext;
  userName?: string;
  sermonText?: string;
  hasFamily?: boolean;
  uid: string;
}

export interface SabbathModelResponse {
  text: string;
  task: SabbathAITask;
  moderationPassed: boolean;
  error?: string;
}

// ── Constants ─────────────────────────────────────────────────────────────────

/**
 * Tasks whose output is communal-visible (shown at dinner table or to family).
 * These MUST pass NeMo moderation before being returned.
 */
const COMMUNAL_TASKS: ReadonlySet<SabbathAITask> = new Set([
  'family_questions',
  'devotional',
]);

/**
 * Tasks whose output is strictly private.
 * Skip moderation entirely — never aggregate, never share.
 */
const PRIVATE_TASKS: ReadonlySet<SabbathAITask> = new Set([
  'sabbath_guide',
  'sermon_prep',
  'reflection_prompt',
]);

/** Maximum retry attempts (first attempt + 2 retries = 3 total). */
const MAX_ATTEMPTS = 3;

/** Backoff delays in milliseconds for each retry index (0-indexed). */
const BACKOFF_MS = [0, 1000, 2000] as const;

/**
 * Guide mode enforcement — prepended to every system prompt.
 * This is the canonical guide-mode instruction required by Phase 2D spec.
 */
const GUIDE_MODE_PREAMBLE =
  'You are a guide, not an oracle. Lead the user through the practice. ' +
  'Do not give answers — ask the question that helps them find their own.';

// ── Internal Helpers ──────────────────────────────────────────────────────────

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Selects and builds the appropriate system prompt for the given task.
 * Always prepends GUIDE_MODE_PREAMBLE.
 */
function buildSystemPrompt(req: SabbathModelRequest): string {
  const ctx: PromptContext = {
    liturgicalContext: req.liturgicalContext,
    userName: req.userName,
    sermonText: req.sermonText,
    hasFamily: req.hasFamily,
  };

  let taskPrompt: string;

  switch (req.task) {
    case 'sabbath_guide':
      taskPrompt = buildSabbathGuidePrompt(ctx);
      break;
    case 'family_questions':
      taskPrompt = buildFamilyQuestionsPrompt(ctx);
      break;
    case 'sermon_prep':
      taskPrompt = buildSermonPrepPrompt(ctx);
      break;
    case 'devotional':
      taskPrompt = buildDevotionalPrompt(ctx);
      break;
    case 'reflection_prompt':
      taskPrompt = buildReflectionPrompt(ctx);
      break;
    default: {
      // Exhaustive check — TypeScript will flag if a new task is added
      // without updating this switch.
      const _exhaustive: never = req.task;
      taskPrompt = '';
      break;
    }
  }

  // Guide mode preamble is always first, regardless of task prompt content.
  return `${GUIDE_MODE_PREAMBLE}\n\n${taskPrompt}`;
}

/**
 * Calls the bereanChatProxy Cloud Function once.
 * Returns the text string on success, throws on failure.
 *
 * Payload shape matches the existing bereanChatProxy callable contract
 * (confirmed in Phase 0 findings: ClaudeAPIService, UnifiedChatView pattern).
 */
async function callBereanProxy(
  task: SabbathAITask,
  userInput: string,
  systemPrompt: string,
  uid: string
): Promise<string> {
  // Firebase callable via Firebase JS SDK (prototype layer).
  // In production iOS, this is bridged through the Swift Firebase callable.
  const functions = getFunctions();
  const callable = httpsCallable(functions, 'bereanChatProxy');

  const result = await callable({
    task,
    input: userInput,
    systemPrompt,
    uid,
  });

  const data = result.data as Record<string, unknown>;

  if (typeof data?.text !== 'string' || data.text.trim().length === 0) {
    throw new Error('bereanChatProxy returned empty or malformed response');
  }

  return data.text as string;
}

/**
 * Calls NeMo content moderation via the moderateContent Cloud Function.
 *
 * Pattern: moderateContent is exported from Backend/functions/src/intelligence/amenRouting.ts
 * and called as a Firebase callable named "moderateContent".
 *
 * Fail closed: if the moderation call fails or is unavailable, treat as BLOCKED.
 * Never publish content whose moderation status is unknown.
 *
 * Returns true if content is safe, false if blocked or error.
 */
async function runNemoModeration(text: string, uid: string): Promise<boolean> {
  try {
    const functions = getFunctions();
    // moderateContent is the callable that wraps NeMo/Perspective guard
    // (see Backend/functions/src/intelligence/amenRouting.ts line 206)
    const callable = httpsCallable(functions, 'moderateContent');
    const result = await callable({ text, uid });
    const data = result.data as Record<string, unknown>;
    // moderateContent returns { safe: boolean, reason?: string }
    return data?.safe === true;
  } catch {
    // Fail closed: if we cannot confirm safety, block the content.
    return false;
  }
}

// ── Main Export ───────────────────────────────────────────────────────────────

/**
 * Calls the Berean Sabbath Guide AI model.
 *
 * Routing:
 * 1. Build the system prompt for the requested task.
 * 2. Call bereanChatProxy (Claude-only, fail closed).
 *    - Up to 2 retries with 1s / 2s backoff.
 *    - After 3 failures → graceful error, never fabricate.
 * 3. For communal tasks (family_questions, devotional):
 *    - Run NeMo moderation on the response.
 *    - If blocked → return empty text with moderationPassed: false.
 * 4. For private tasks (sabbath_guide, sermon_prep, reflection_prompt):
 *    - Skip moderation entirely.
 *    - Return with moderationPassed: true (private — no moderation layer).
 *
 * NEVER falls over to GPT-4o, Gemini, Grok, or any other model.
 * NEVER fabricates a response if the model call fails.
 */
export async function callSabbathModel(
  req: SabbathModelRequest
): Promise<SabbathModelResponse> {
  const systemPrompt = buildSystemPrompt(req);

  // ── Retry loop ──────────────────────────────────────────────────────────
  let lastError: string | undefined;

  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    // Backoff before retry (no delay on first attempt)
    if (attempt > 0) {
      await sleep(BACKOFF_MS[attempt]);
    }

    try {
      const text = await callBereanProxy(
        req.task,
        req.userInput,
        systemPrompt,
        req.uid
      );

      // ── Moderation ──────────────────────────────────────────────────────
      if (COMMUNAL_TASKS.has(req.task)) {
        // Communal output: must pass NeMo before returning
        const safe = await runNemoModeration(text, req.uid);

        if (!safe) {
          // Block — never publish content that failed moderation
          return {
            text: '',
            task: req.task,
            moderationPassed: false,
            error: 'Content moderation blocked this response.',
          };
        }

        return {
          text,
          task: req.task,
          moderationPassed: true,
        };
      }

      if (PRIVATE_TASKS.has(req.task)) {
        // Private output: skip moderation, return directly
        return {
          text,
          task: req.task,
          moderationPassed: true,
        };
      }

      // Fallthrough (should not be reached with valid task types)
      return {
        text,
        task: req.task,
        moderationPassed: true,
      };

    } catch (err: unknown) {
      lastError =
        err instanceof Error ? err.message : 'Unknown error calling Berean.';
      // Continue to next attempt
    }
  }

  // ── All attempts exhausted ───────────────────────────────────────────────
  // Graceful error — never fabricate, never fallover to another model.
  return {
    text: '',
    task: req.task,
    moderationPassed: false,
    error:
      'Berean Guide is not available right now. Please try again in a moment.',
  };
}
