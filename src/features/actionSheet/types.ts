/**
 * src/features/actionSheet/types.ts
 *
 * Internal types for the Response Action Sheet. Binds to the FROZEN contracts —
 * never redefines Provenance / SourceRef / MemoryItem / ResponseAction. Adds only
 * the view-model glue the sheet needs.
 *
 * OWNER: Agent F (Response Action Sheet). Connected Intelligence v1.
 */

import type { BereanCallModelResult, Domain } from '../../berean/contracts';
import type { Provenance, ResponseAction } from '../connectedIntelligence.contracts';

/**
 * The originating Berean response the sheet acts on. Carries everything an action
 * needs to PRESERVE PROVENANCE on any object it creates.
 */
export interface ActionSheetResponse {
  /** Stable id of the originating assistant message (provenance pointer target). */
  responseId: string;
  /** Domain of the originating response — inherited by AI transforms. */
  domain: Domain;
  /** The assistant text. */
  text: string;
  /** Canonical provenance (sources + truthLevel) from the Berean result. */
  provenance: Provenance;
  /** The thread/conversation this response belongs to (for continue_later). */
  threadId?: string;
  /** Full conversational state snapshot, for continue_later checkpointing. */
  conversationState?: ConversationState;
  /** The raw upstream result, if the caller wants to pass it through verbatim. */
  raw?: BereanCallModelResult;
}

/** Full conversational state persisted by continue_later, restored by resume. */
export interface ConversationState {
  threadId: string;
  domain: Domain;
  messages: Array<{ role: 'user' | 'berean'; text: string }>;
  /** Free-form scroll/UI hints the host wants restored. */
  ui?: Record<string, unknown>;
}

/** Provenance pointer stamped onto EVERY object an action creates. */
export interface ProvenanceStamp {
  /** Pointer back to the originating Berean response. */
  originResponseId: string;
  originDomain: Domain;
  /** Canonical provenance copied from the response (sources + truthLevel). */
  provenance: Provenance;
  /** Verbatim text excerpt that grounds the created object. */
  excerpt: string;
  createdAt: unknown; // serverTimestamp at write
}

/** Taxonomy groups, in display order, matching the ResponseAction taxonomy. */
export type ActionGroup =
  | 'Knowledge'
  | 'Community'
  | 'AI transforms'
  | 'Action'
  | 'Memory'
  | 'Continuity';

export interface ActionDescriptor {
  action: ResponseAction;
  group: ActionGroup;
  label: string;
  icon: string;
  /** True ⇒ a quick-access action shown on the floating pill. */
  pill?: boolean;
}

/** UI states the sheet (and each action) can be in. SIX total. */
export type ActionUiState =
  | 'idle'      // sheet open, no action running
  | 'running'   // an action is in flight
  | 'success'   // action completed, confirmation shown
  | 'error'     // action failed (recoverable)
  | 'blocked'   // moderation-blocked — DISTINCT from error
  | 'empty';    // e.g. show_related found nothing

/** Result returned by every action handler — drives the six UI states. */
export interface ActionResult {
  state: Exclude<ActionUiState, 'idle' | 'running'>;
  /** User-facing confirmation / error / blocked message. */
  message: string;
  /** Optional secondary detail (e.g. verbatim why_remembered, refusal reason). */
  detail?: string;
  /** For created objects: the provenance stamp that was written. */
  stamp?: ProvenanceStamp;
  /** For undoable actions (forget_this, remember_this), a one-tap undo. */
  undo?: () => Promise<void>;
  /** For show_related / why_remembered, labeled memory rows to render. */
  rows?: Array<{ text: string; label: string }>;
}
