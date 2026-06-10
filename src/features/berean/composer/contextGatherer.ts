/**
 * contextGatherer.ts — Build scoped ContextItem(s) for a parsed mention turn.
 *
 * Agent D (@Tool Mentions) — Connected Intelligence Phase 2.
 *
 * A parsed mention injects ONLY scoped ContextItem(s) — the single shape connector
 * data may enter a prompt in (per contract). There is NO ambient connector context:
 * if no mention is present, this gatherer returns no connector items.
 *
 * Provider-tier behavior (contract §4.4):
 *   - 'claude-exclusive' (@bible/@prayer): NO retrieval here, NO connector fetch.
 *     fail-closed is enforced server-side; this layer injects no extra context.
 *   - 'rag-grounded' (@notes/@sermon): refuse-if-no-index is enforced server-side via
 *     the routed taskKey; this layer marks the turn so the prompt is grounding-scoped.
 *   - 'tool-orchestration' (@calendar/@music/@church): fetch via httpsCallable. On
 *     connector error, return a DEGRADED marker (visible chip) — NEVER fabricate data.
 *
 * Every connector ContextItem is summaryOnly:true with a pointer back to source — raw
 * third-party content never persists.
 *
 * OWNER: Agent D. Create-only under src/features/berean/composer/**.
 */

import { httpsCallable } from 'firebase/functions';
import { functions } from '../../../berean/firebase';

import {
  ConnectorId,
  GrantSurface,
  ToolMention,
  type ContextItem,
} from '../../connectedIntelligence.contracts';

import type { MentionDescriptor } from './mentionConfig';

// ─────────────────────────────────────────────────────────────────────────────
// Result shape
// ─────────────────────────────────────────────────────────────────────────────

export type GatherStatus = 'ok' | 'degraded' | 'none';

export interface GatherResult {
  status: GatherStatus;
  /** Scoped ContextItems to inject. Empty when status !== 'ok'. */
  items: ContextItem[];
  /** Human-readable degraded reason, shown on the degraded chip. Null unless degraded. */
  degradedReason: string | null;
  /** The connector that degraded (for the chip), null otherwise. */
  degradedConnector: ConnectorId | null;
}

const NONE: GatherResult = {
  status: 'none',
  items: [],
  degradedReason: null,
  degradedConnector: null,
};

// ─────────────────────────────────────────────────────────────────────────────
// Connector ID for a tool-orchestration mention
// ─────────────────────────────────────────────────────────────────────────────

function connectorForMention(descriptor: MentionDescriptor): ConnectorId | null {
  if (descriptor.connectorId) return descriptor.connectorId;
  // @church is tool-orchestration but aliases church_mgmt (no grant doc).
  if (descriptor.mention === ToolMention.church) return ConnectorId.church_mgmt;
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// CF payload shapes (connectorFetch is Agent A/B's read endpoint; degrade if absent)
// ─────────────────────────────────────────────────────────────────────────────

interface ConnectorFetchRequest {
  connectorId: ConnectorId;
  surface: GrantSurface;
  query: string;
}

interface ConnectorFetchResponseItem {
  payload: string;
  pointer: string | null;
  truthLevel?: 'grounded' | 'inferred' | 'refused';
}

interface ConnectorFetchResponse {
  ok: boolean;
  items: ConnectorFetchResponseItem[];
  error?: string;
  /** Typed degrade signal from the connectorFetch CF (ok:false). Drives the chip copy. */
  degraded?: boolean;
  /** Machine reason code from the CF (e.g. 'no_grant', 'provider_unavailable'). */
  reason?: string;
}

/**
 * Map a connectorFetch CF reason code to friendly degraded-chip copy. The CF returns
 * non-sensitive reason codes only (never provider payloads); we translate them here so
 * the visible chip reads naturally and never implies fabricated data was used.
 */
function degradedCopyForReason(reason: string | undefined, label: string): string | null {
  switch (reason) {
    case 'no_grant':
    case 'grant_inactive':
    case 'surface_not_granted':
    case 'no_read_scope':
      return `Connect ${label} to use it here.`;
    case 'grant_expired':
      return `${label} access expired — reconnect to use it.`;
    case 'token_unavailable':
      return `${label} needs to be reconnected.`;
    case 'minor_blocked':
      return `${label} isn't available on this account.`;
    case 'no_results':
      return `${label} returned no results right now.`;
    case 'provider_unavailable':
    case 'consent_unavailable':
      return `${label} is unavailable right now.`;
    default:
      return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Gatherer
// ─────────────────────────────────────────────────────────────────────────────

export interface ContextGatherer {
  gather(descriptor: MentionDescriptor, query: string): Promise<GatherResult>;
}

/**
 * Build the gatherer. `fetchConnector` is injectable so tests (and Agent A's eventual
 * endpoint name) can be swapped without touching this file. Default calls the
 * `connectorFetch` httpsCallable.
 */
export function makeContextGatherer(
  fetchConnector: (req: ConnectorFetchRequest) => Promise<ConnectorFetchResponse> = defaultFetch,
): ContextGatherer {
  return {
    async gather(descriptor, query) {
      switch (descriptor.provider) {
        // ── claude-exclusive: no extra context injected (server fail-closed) ──
        case 'claude-exclusive':
          return NONE;

        // ── rag-grounded: server enforces refuse-if-no-index via taskKey ──────
        // No client connector fetch; the routed taskKey scopes retrieval server-side.
        case 'rag-grounded':
          return NONE;

        // ── tool-orchestration: fetch, degrade gracefully on error ────────────
        case 'tool-orchestration': {
          const connectorId = connectorForMention(descriptor);
          if (!connectorId) {
            return {
              status: 'degraded',
              items: [],
              degradedReason: 'Connector unavailable.',
              degradedConnector: null,
            };
          }
          try {
            const resp = await fetchConnector({
              connectorId,
              surface: GrantSurface.berean,
              query,
            });
            if (!resp.ok || resp.items.length === 0) {
              return {
                status: 'degraded',
                items: [],
                degradedReason:
                  resp.error?.trim() ||
                  degradedCopyForReason(resp.reason, descriptor.label) ||
                  `${descriptor.label} returned no results right now.`,
                degradedConnector: connectorId,
              };
            }
            const items: ContextItem[] = resp.items.map((it) => ({
              source: connectorId,
              provenance: {
                sources: [],
                truthLevel: it.truthLevel ?? 'grounded',
              },
              surface: GrantSurface.berean,
              fetchedAt: Date.now(),
              summaryOnly: true, // raw third-party content never persists
              payload: it.payload,
              pointer: it.pointer ?? null,
            }));
            return {
              status: 'ok',
              items,
              degradedReason: null,
              degradedConnector: null,
            };
          } catch (err) {
            // Connector error ⇒ visible degraded chip, never fabricate.
            const message =
              err instanceof Error ? err.message : `${descriptor.label} is unavailable.`;
            return {
              status: 'degraded',
              items: [],
              degradedReason: message,
              degradedConnector: connectorId,
            };
          }
        }

        default:
          return NONE;
      }
    },
  };
}

const defaultFetch = async (
  req: ConnectorFetchRequest,
): Promise<ConnectorFetchResponse> => {
  const callable = httpsCallable<ConnectorFetchRequest, ConnectorFetchResponse>(
    functions,
    'connectorFetch',
  );
  const raw = await callable(req);
  return raw.data;
};

export const contextGatherer = makeContextGatherer();

// ─────────────────────────────────────────────────────────────────────────────
// Enriched-input builder
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Fold scoped ContextItems into the prompt body. Connector context enters ONLY as a
 * fenced, summary-only block prefixed with provenance — the model is told these are
 * grounded summaries with pointers, not free-form claims.
 */
export function buildEnrichedInput(cleanText: string, items: ContextItem[]): string {
  if (items.length === 0) return cleanText;
  const lines = items.map((it) => {
    const ptr = it.pointer ? ` (source: ${it.pointer})` : '';
    return `- ${it.payload}${ptr}`;
  });
  return [
    cleanText,
    '',
    '[Connector context — summary only, grounded with sources]',
    ...lines,
  ].join('\n');
}
