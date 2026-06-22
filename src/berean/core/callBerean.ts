/**
 * callBerean.ts — Berean Phase 2A
 *
 * Client-side wrapper around the `bereanChat` Firebase callable.
 * Translates router error shapes (blocked, refusal) into BereanCallModelResult.
 *
 * NO secrets here. All AI routing happens server-side via the bereanChat CF.
 *
 * FROZEN: 2026-06-07
 * OWNER: Phase 2A Core Agent
 */

import { httpsCallable, type HttpsCallableResult } from 'firebase/functions';
import { functions } from '../firebase';

import type {
  Domain,
  BereanContext,
  BereanCallModelResult,
  RefusalReason,
  SafetyLevel,
} from '../contracts';

// ─────────────────────────────────────────────────────────────────────────────
// Internal CF payload shapes
// ─────────────────────────────────────────────────────────────────────────────

interface BereanChatRequest {
  task: string;
  input: string;
  memoryContext: BereanContext['memoryContext'];
  safetyLevel: SafetyLevel;
}

interface BereanChatResponse {
  text: string | null;
  provenance: BereanCallModelResult['provenance'] | null;
  refusal: RefusalReason | null;
  blocked: boolean;
}

// ─────────────────────────────────────────────────────────────────────────────
// Sentinel provenance for blocked / refusal results
// ─────────────────────────────────────────────────────────────────────────────

function blockedProvenance(reason: RefusalReason): BereanCallModelResult['provenance'] {
  return {
    sources: [],
    truthLevel: 'refused',
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// callBerean — public API
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Calls the `bereanChat` Firebase callable with the given task, input, and context.
 *
 * The CF handles all routing (callModel), NVIDIA guards, Pinecone retrieval,
 * citation validation, and rate limiting. This function only marshals the call
 * and normalises the response into a BereanCallModelResult.
 *
 * @param params.task     Domain enum value — maps to a callModel task string server-side
 * @param params.input    Raw user input (already validated by the caller)
 * @param params.context  Full BereanContext including memoryContext and safetyLevel
 */
export async function callBerean(params: {
  task: Domain;
  input: string;
  context: BereanContext;
}): Promise<BereanCallModelResult> {
  const { task, input, context } = params;

  const bereanChat = httpsCallable<BereanChatRequest, BereanChatResponse>(
    functions,
    'bereanChat',
  );

  let raw: HttpsCallableResult<BereanChatResponse>;

  try {
    raw = await bereanChat({
      task,
      input,
      memoryContext: context.memoryContext ?? [],
      safetyLevel: context.safetyLevel,
    });
  } catch (err: unknown) {
    // Firebase Functions SDK wraps CF errors in a FirebaseFunctionsError.
    // Treat any thrown error as a provider_unavailable refusal so the caller
    // always receives a typed BereanCallModelResult — never a raw exception.
    const message =
      err instanceof Error ? err.message : 'AI service temporarily unavailable.';

    return {
      text: message,
      provenance: blockedProvenance('provider_unavailable'),
      refusal: 'provider_unavailable',
      blocked: true,
    };
  }

  const data = raw.data;

  // ── Blocked result (input/output guard failed, citations missing, etc.) ──
  if (data.blocked) {
    const refusalReason: RefusalReason = data.refusal ?? 'moderation_blocked';
    return {
      text: '',
      provenance: blockedProvenance(refusalReason),
      refusal: refusalReason,
      blocked: true,
    };
  }

  // ── Explicit refusal (no_grounded_source, capability_disabled, etc.) ─────
  if (data.refusal) {
    return {
      text: data.text ?? '',
      provenance: data.provenance ?? blockedProvenance(data.refusal),
      refusal: data.refusal,
      blocked: false,
    };
  }

  // ── Successful response ──────────────────────────────────────────────────
  return {
    text: data.text ?? '',
    provenance: data.provenance ?? { sources: [], truthLevel: 'inferred' },
    blocked: false,
  };
}
