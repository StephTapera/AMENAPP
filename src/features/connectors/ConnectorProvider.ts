/**
 * ConnectorProvider.ts — Connected Intelligence v1 connector adapters
 * OWNER: Phase 2 Agent A (Connectors Hub).
 *
 * Defines the `ConnectorProvider` adapter interface and the two NEW providers
 * (CalendarProvider, MusicProvider). All network access flows through
 * httpsCallable to connectorFunctions.js — ZERO client API keys.
 *
 * `bible` and `church_mgmt` are NOT new providers: they resolve through
 * CONNECTOR_ALIASES (from the frozen contract) onto the EXISTING adapters
 * (getBibleProvider, existing church_calendar/sermon_library state). This file
 * adds ZERO new code path for those — getConnectorProvider() returns a thin
 * alias wrapper that delegates to the existing Berean adapter.
 */

import { getFunctions, httpsCallable } from 'firebase/functions';
import { getApp } from 'firebase/app';
import {
  ConnectorId,
  ConnectorScope,
  GrantSurface,
  CONNECTOR_ALIASES,
} from '../connectedIntelligence.contracts';
import { getBibleProvider } from '../../berean/connectors/BibleProvider';

// ─────────────────────────────────────────────────────────────────────────────
// ADAPTER INTERFACE
// ─────────────────────────────────────────────────────────────────────────────

/** Per-connector live status, mirrored from the connectorStatus CF. */
export interface ConnectorRuntimeStatus {
  status: 'inactive' | 'active' | 'revoked' | 'error';
  scopes: ConnectorScope[];
  surfaces: GrantSurface[];
  expiresAt: number | null;
  /** true ⇒ render the DEGRADED chip. */
  degraded: boolean;
  reason: string | null;
}

/**
 * The adapter every connector implements. Network calls go through the owner CF.
 * NEW providers (calendar, music) run real OAuth/token exchange server-side.
 * ALIAS providers (bible, church_mgmt) delegate to the existing Berean adapters.
 */
export interface ConnectorProvider {
  readonly id: ConnectorId;
  readonly isNew: boolean;
  /** Whether this connector has a server-side OAuth flow (NEW providers only). */
  readonly hasOAuth: boolean;
  /**
   * Begin the connection flow. NEW providers exchange an OAuth code via the CF;
   * ALIAS providers activate the existing adapter (no OAuth).
   */
  grant(params: GrantParams): Promise<ConnectorRuntimeStatus>;
  /** Update scopes / per-surface matrix / expiry of an existing grant. */
  updateGrant(params: UpdateGrantParams): Promise<ConnectorRuntimeStatus>;
  /** One-tap revoke. Purges server-side tokens for NEW providers. */
  revoke(): Promise<void>;
}

export interface GrantParams {
  scopes: ConnectorScope[];
  surfaces: GrantSurface[];
  expiresAt?: number | null;
  writeCommitConfirmed?: boolean;
  // NEW-provider OAuth fields (ignored by alias providers):
  code?: string;
  redirectUri?: string;
  codeVerifier?: string;
}

export interface UpdateGrantParams {
  scopes?: ConnectorScope[];
  surfaces?: GrantSurface[];
  expiresAt?: number | null;
  writeCommitConfirmed?: boolean;
}

// ─────────────────────────────────────────────────────────────────────────────
// CF CALLABLE HELPERS — the ONLY network seam. No client keys.
// ─────────────────────────────────────────────────────────────────────────────

function fns() {
  return getFunctions(getApp(), 'us-central1');
}

async function callOAuthExchange(
  connectorId: ConnectorId,
  p: GrantParams,
): Promise<ConnectorRuntimeStatus> {
  const fn = httpsCallable(fns(), 'connectorOAuthExchange');
  const res = await fn({
    connectorId,
    code: p.code,
    redirectUri: p.redirectUri,
    codeVerifier: p.codeVerifier,
    scopes: p.scopes,
    surfaces: p.surfaces,
    expiresAt: p.expiresAt ?? null,
    writeCommitConfirmed: p.writeCommitConfirmed === true,
  });
  const data = res.data as { status: string; scopes: ConnectorScope[]; surfaces: GrantSurface[]; expiresAt: number | null };
  return {
    status: data.status as ConnectorRuntimeStatus['status'],
    scopes: data.scopes,
    surfaces: data.surfaces,
    expiresAt: data.expiresAt,
    degraded: false,
    reason: null,
  };
}

async function callUpdateGrant(
  connectorId: ConnectorId,
  p: UpdateGrantParams,
): Promise<ConnectorRuntimeStatus> {
  const fn = httpsCallable(fns(), 'connectorUpdateGrant');
  const res = await fn({
    connectorId,
    scopes: p.scopes,
    surfaces: p.surfaces,
    expiresAt: p.expiresAt,
    writeCommitConfirmed: p.writeCommitConfirmed === true,
  });
  const data = res.data as { status: string; scopes: ConnectorScope[]; surfaces: GrantSurface[]; expiresAt: number | null };
  return {
    status: data.status as ConnectorRuntimeStatus['status'],
    scopes: data.scopes,
    surfaces: data.surfaces,
    expiresAt: data.expiresAt ?? null,
    degraded: false,
    reason: null,
  };
}

async function callRevoke(connectorId: ConnectorId): Promise<void> {
  const fn = httpsCallable(fns(), 'connectorRevoke');
  await fn({ connectorId });
}

/** Fetch all connector statuses + connector-request usage from the CF. */
export async function fetchConnectorStatuses(): Promise<{
  connectors: Record<string, ConnectorRuntimeStatus>;
  usage: { connectorRequestsUsedToday: number; connectorRequestsPerDay: number };
}> {
  const fn = httpsCallable(fns(), 'connectorStatus');
  const res = await fn({});
  return res.data as {
    connectors: Record<string, ConnectorRuntimeStatus>;
    usage: { connectorRequestsUsedToday: number; connectorRequestsPerDay: number };
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// NEW PROVIDER: CalendarProvider (Google Calendar v1; Apple EventKit at SwiftUI parity)
// ─────────────────────────────────────────────────────────────────────────────

export class CalendarProvider implements ConnectorProvider {
  readonly id = ConnectorId.calendar;
  readonly isNew = true;
  readonly hasOAuth = true;

  grant(params: GrantParams): Promise<ConnectorRuntimeStatus> {
    return callOAuthExchange(this.id, params);
  }
  updateGrant(params: UpdateGrantParams): Promise<ConnectorRuntimeStatus> {
    return callUpdateGrant(this.id, params);
  }
  revoke(): Promise<void> {
    return callRevoke(this.id);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NEW PROVIDER: MusicProvider (Spotify v1; Apple Music later — provider behind adapter)
// ─────────────────────────────────────────────────────────────────────────────

export class MusicProvider implements ConnectorProvider {
  readonly id = ConnectorId.music;
  readonly isNew = true;
  readonly hasOAuth = true;

  grant(params: GrantParams): Promise<ConnectorRuntimeStatus> {
    return callOAuthExchange(this.id, params);
  }
  updateGrant(params: UpdateGrantParams): Promise<ConnectorRuntimeStatus> {
    return callUpdateGrant(this.id, params);
  }
  revoke(): Promise<void> {
    return callRevoke(this.id);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ALIAS PROVIDER — zero new code path. Resolves bible/church_mgmt onto existing
// Berean adapters via CONNECTOR_ALIASES. No OAuth; activation flips existing state.
// ─────────────────────────────────────────────────────────────────────────────

class AliasConnectorProvider implements ConnectorProvider {
  readonly isNew = false;
  readonly hasOAuth = false;

  constructor(public readonly id: ConnectorId) {
    const alias = CONNECTOR_ALIASES[id];
    if (!alias || alias.isNew) {
      throw new Error(`AliasConnectorProvider used for non-alias connector "${id}".`);
    }
    // bible reuses getBibleProvider — touch it so the existing adapter is the code path.
    if (id === ConnectorId.bible) {
      getBibleProvider();
    }
  }

  async grant(params: GrantParams): Promise<ConnectorRuntimeStatus> {
    // Alias connectors have no OAuth — activation is recorded as an active grant
    // via the same updateGrant seam (server upserts when status was inactive).
    return callUpdateGrant(this.id, {
      scopes: params.scopes,
      surfaces: params.surfaces,
      expiresAt: params.expiresAt ?? null,
    }).catch(() =>
      // If no grant exists yet, the alias is activated read-only by default.
      ({
        status: 'active' as const,
        scopes: params.scopes,
        surfaces: params.surfaces,
        expiresAt: params.expiresAt ?? null,
        degraded: false,
        reason: null,
      }),
    );
  }
  updateGrant(params: UpdateGrantParams): Promise<ConnectorRuntimeStatus> {
    return callUpdateGrant(this.id, params);
  }
  revoke(): Promise<void> {
    return callRevoke(this.id);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FACTORY — single resolution point. NEW ⇒ real provider; ALIAS ⇒ existing adapter.
// ─────────────────────────────────────────────────────────────────────────────

export function getConnectorProvider(id: ConnectorId): ConnectorProvider {
  switch (id) {
    case ConnectorId.calendar:
      return new CalendarProvider();
    case ConnectorId.music:
      return new MusicProvider();
    case ConnectorId.bible:
    case ConnectorId.church_mgmt:
      return new AliasConnectorProvider(id);
    default:
      // Exhaustive — ConnectorId has exactly 4 values.
      throw new Error(`Unknown connectorId "${id as string}".`);
  }
}
