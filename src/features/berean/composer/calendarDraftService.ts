/**
 * calendarDraftService.ts — @calendar WRITE intent → DRAFT event → ConfirmationGate.
 *
 * Agent D (@Tool Mentions) — Connected Intelligence Phase 2.
 *
 * Flow (NEVER a silent write):
 *   1. parseCalendarDraft() turns "schedule prayer night Friday" into a structured
 *      DRAFT event card by calling the `composerCalendarDraft` CF (drafts_for_approval).
 *      The CF parses the natural language; it does NOT write to any calendar.
 *   2. The composer renders a CalendarDraftCard for the draft.
 *   3. Only after the user confirms via ConfirmationGate do we call
 *      `composerCalendarCommit` (event_create). The draft ceiling is drafts_for_approval;
 *      committing requires the connector's write_commit scope + explicit confirmation.
 *
 * Both calls are httpsCallable — zero client keys, all auth server-side.
 *
 * OWNER: Agent D. Create-only under src/features/berean/composer/**.
 */

import { httpsCallable } from 'firebase/functions';
import { functions } from '../../../berean/firebase';

// ─────────────────────────────────────────────────────────────────────────────
// Draft model
// ─────────────────────────────────────────────────────────────────────────────

export interface CalendarDraft {
  /** Opaque server-issued draft id; required to commit. */
  draftId: string;
  title: string;
  /** ISO 8601 start, local TZ resolved server-side. */
  startISO: string;
  /** ISO 8601 end, or null if open-ended / all-day. */
  endISO: string | null;
  allDay: boolean;
  /** Human-readable echo of what will be created, for the card. */
  humanReadable: string;
  /** Low-confidence parse ⇒ surface a "please confirm details" hint on the card. */
  lowConfidence: boolean;
}

export type DraftStatus = 'ok' | 'degraded';

export interface DraftResult {
  status: DraftStatus;
  draft: CalendarDraft | null;
  /** Set when status === 'degraded'. */
  reason: string | null;
}

export interface CommitResult {
  status: 'committed' | 'degraded';
  /** Deep link / pointer to the created event when committed. */
  pointer: string | null;
  reason: string | null;
}

// ─────────────────────────────────────────────────────────────────────────────
// CF payloads
// ─────────────────────────────────────────────────────────────────────────────

interface DraftRequest {
  text: string;
}
interface DraftResponse {
  ok: boolean;
  draft: CalendarDraft | null;
  error?: string;
}

interface CommitRequest {
  draftId: string;
}
interface CommitResponse {
  ok: boolean;
  pointer: string | null;
  error?: string;
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

export interface CalendarDraftService {
  /** Parse NL write intent into a draft. Degrades (never fabricates) on error. */
  createDraft(text: string): Promise<DraftResult>;
  /** Commit a confirmed draft → event_create. Only call after ConfirmationGate. */
  commitDraft(draftId: string): Promise<CommitResult>;
}

export function makeCalendarDraftService(
  callDraft: (req: DraftRequest) => Promise<DraftResponse> = defaultDraftCall,
  callCommit: (req: CommitRequest) => Promise<CommitResponse> = defaultCommitCall,
): CalendarDraftService {
  return {
    async createDraft(text) {
      try {
        const resp = await callDraft({ text });
        if (!resp.ok || !resp.draft) {
          return {
            status: 'degraded',
            draft: null,
            reason: resp.error?.trim() || 'Could not read that into an event. Try rephrasing.',
          };
        }
        return { status: 'ok', draft: resp.draft, reason: null };
      } catch (err) {
        const message =
          err instanceof Error ? err.message : 'Calendar is unavailable right now.';
        return { status: 'degraded', draft: null, reason: message };
      }
    },

    async commitDraft(draftId) {
      try {
        const resp = await callCommit({ draftId });
        if (!resp.ok) {
          return {
            status: 'degraded',
            pointer: null,
            reason: resp.error?.trim() || 'Could not create the event. Nothing was written.',
          };
        }
        return { status: 'committed', pointer: resp.pointer, reason: null };
      } catch (err) {
        const message =
          err instanceof Error ? err.message : 'Calendar is unavailable right now.';
        return { status: 'degraded', pointer: null, reason: message };
      }
    },
  };
}

const defaultDraftCall = async (req: DraftRequest): Promise<DraftResponse> => {
  const callable = httpsCallable<DraftRequest, DraftResponse>(
    functions,
    'composerCalendarDraft',
  );
  return (await callable(req)).data;
};

const defaultCommitCall = async (req: CommitRequest): Promise<CommitResponse> => {
  const callable = httpsCallable<CommitRequest, CommitResponse>(
    functions,
    'composerCalendarCommit',
  );
  return (await callable(req)).data;
};

export const calendarDraftService = makeCalendarDraftService();
