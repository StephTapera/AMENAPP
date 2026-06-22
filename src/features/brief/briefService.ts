/**
 * briefService.ts — Daily Brief client data layer
 * AMEN Connected Intelligence v1, Agent B (Daily Brief).
 *
 * Pull-based ONLY. Calls the `generateDailyBrief` callable, which assembles +
 * caches one BriefCard per user per day at users/{uid}/briefCache/{date}.
 * There is NO push path — config.brief.pushEnabled === false.
 *
 * All connector permissioning, minor-mode, Sabbath, crisis, and the 9-item cap
 * are enforced server-side. The client never assembles connector data itself.
 */

import { httpsCallable } from 'firebase/functions';
import { functions } from '../../berean/firebase';
import type {
  BriefCard,
  BriefSection,
  ContextItem,
} from '../connectedIntelligence.contracts';
import { connectedIntelligence } from '../connectedIntelligence.config';

// ─────────────────────────────────────────────────────────────────────────────
// RESULT SHAPE — mirrors the callable's return envelope.
// ─────────────────────────────────────────────────────────────────────────────

export interface BriefResult {
  card: BriefCard;
  /** True if the card came from today's (or yesterday's pre-hour) cache. */
  cached: boolean;
  /** One-line warm intro, or null. */
  intro: string | null;
  /** True if candidate items exceeded the 9-item cap and were trimmed. */
  capped: boolean;
  /** True if Sabbath is active — render the rest card. */
  sabbath: boolean;
}

interface CallableResponse {
  card: BriefCard;
  cached: boolean;
  intro: string | null;
  capped: boolean;
  sabbath: boolean;
}

// Hard cap mirror for client-side assertions (server is the source of truth).
const MAX_ITEMS_TOTAL = connectedIntelligence.brief.maxItems; // 9

// ─────────────────────────────────────────────────────────────────────────────
// PUBLIC API
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Fetch (or generate) today's Daily Brief.
 *
 * @param forceRegenerate When true, bypasses the cache and rebuilds the card.
 *   Used by the manual "Refresh" affordance.
 * @throws Error with a human-readable message on failure (caller shows error state).
 */
export async function fetchDailyBrief(forceRegenerate = false): Promise<BriefResult> {
  const callable = httpsCallable<{ forceRegenerate: boolean }, CallableResponse>(
    functions,
    'generateDailyBrief',
  );

  let response: CallableResponse;
  try {
    const res = await callable({ forceRegenerate });
    response = res.data;
  } catch (err: unknown) {
    throw normalizeError(err);
  }

  if (!response?.card) {
    throw new Error('The brief is unavailable right now. Please try again.');
  }

  // Client-side defense-in-depth: clamp to the contract cap even if the server
  // ever returned more (it should not).
  const card = clampCard(response.card);

  return {
    card,
    cached: !!response.cached,
    intro: response.intro ?? null,
    capped: !!response.capped,
    sabbath: !!response.sabbath,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

/** Total ContextItems across all sections. */
export function totalItemCount(card: BriefCard): number {
  return card.sections.reduce((sum, s) => sum + s.items.length, 0);
}

/** Flatten all items in render order (sections are already ordered server-side). */
export function flattenItems(card: BriefCard): Array<{ section: BriefSection; item: ContextItem }> {
  return card.sections.flatMap((s) =>
    s.items.map((item) => ({ section: s.section, item })),
  );
}

/** Clamp a card to the 9-item contract cap, trimming overflow deterministically. */
function clampCard(card: BriefCard): BriefCard {
  let remaining = MAX_ITEMS_TOTAL;
  const sections = [];
  for (const s of card.sections) {
    if (remaining <= 0) break;
    const items = s.items.slice(0, remaining);
    if (items.length > 0) {
      sections.push({ section: s.section, items });
      remaining -= items.length;
    }
  }
  return { ...card, sections };
}

/** Map a Firebase callable error into a calm, human-readable message. */
function normalizeError(err: unknown): Error {
  const code = (err as { code?: string })?.code ?? '';
  if (code.includes('unauthenticated')) {
    return new Error('Please sign in to see your brief.');
  }
  if (code.includes('resource-exhausted')) {
    return new Error('Your brief was refreshed a moment ago. Try again shortly.');
  }
  if (code.includes('unavailable')) {
    return new Error('The brief service is briefly unavailable. Please try again.');
  }
  const message = err instanceof Error ? err.message : '';
  return new Error(message || 'Something went wrong loading your brief. Please try again.');
}
