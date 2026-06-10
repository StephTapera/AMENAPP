/**
 * ConnectorsHubScreen.tsx — the mountable Connectors Hub.
 * OWNER: Phase 2 Agent A.
 *
 * Surfaces one card per connector (Calendar, Music, Bible, Church) with:
 *   - enable toggle, "What Amen can see" sheet, example prompts, scope picker,
 *     per-surface grant matrix, expiry option, one-tap revoke.
 *   - a visible DEGRADED state (DegradedChip) when a connector is status:'error'.
 *   - a link into the Usage & limits screen.
 *
 * SIX UI STATES: loading / empty / partial / full / error / offline.
 * MINOR: the entire hub is replaced by MinorExplainer — NO grant path in the UI.
 *
 * Off-by-default, read-only-by-default, revocable in one tap.
 */

import React, { useCallback, useEffect, useState } from 'react';
import { s, STATUS_COLORS } from './styles';
import { tokens } from '../../berean/contracts';
import { ConnectorId } from '../connectedIntelligence.contracts';
import type { Plan } from '../connectedIntelligence.contracts';
import { CONNECTOR_META, ORDERED_CONNECTORS } from './connectorMeta';
import {
  getConnectorProvider,
  fetchConnectorStatuses,
  ConnectorRuntimeStatus,
} from './ConnectorProvider';
import ConnectorCard from './ConnectorCard';
import UsageLimitsScreen from './UsageLimitsScreen';
import MinorExplainer from './MinorExplainer';

export interface ConnectorsHubScreenProps {
  /** Minor-scoped accounts get the explainer; no grant path. */
  minorScoped: boolean;
  plan: Plan;
  /**
   * Platform OAuth bridge (provided by the host app — SwiftUI/iOS opens the system
   * web auth session). Returns the authorization code + redirectUri. NO client keys
   * pass through here; the code is exchanged for tokens server-side.
   */
  beginOAuth: (meta: { id: ConnectorId; title: string }) => Promise<{ code: string; redirectUri: string; codeVerifier?: string }>;
}

type LoadState = 'loading' | 'ready' | 'error' | 'offline';

const DEFAULT_STATUS: ConnectorRuntimeStatus = {
  status: 'inactive',
  scopes: [],
  surfaces: [],
  expiresAt: null,
  degraded: false,
  reason: null,
};

/**
 * Public entry point. MINOR accounts short-circuit to the explainer WITHOUT ever
 * mounting the adult hub — so no connector hooks, data fetches, or grant paths
 * exist for minors. The adult hub lives in a separate component so React hooks are
 * never conditionally skipped.
 */
export default function ConnectorsHubScreen(props: ConnectorsHubScreenProps): JSX.Element {
  if (props.minorScoped) {
    return <MinorExplainer />;
  }
  return <AdultConnectorsHub plan={props.plan} beginOAuth={props.beginOAuth} />;
}

function AdultConnectorsHub({
  plan,
  beginOAuth,
}: Omit<ConnectorsHubScreenProps, 'minorScoped'>): JSX.Element {
  const [loadState, setLoadState] = useState<LoadState>('loading');
  const [statuses, setStatuses] = useState<Record<string, ConnectorRuntimeStatus>>({});
  const [usage, setUsage] = useState<{ connectorRequestsUsedToday: number; connectorRequestsPerDay: number }>({
    connectorRequestsUsedToday: 0,
    connectorRequestsPerDay: 100,
  });
  const [showUsage, setShowUsage] = useState(false);

  const load = useCallback(async () => {
    setLoadState('loading');
    if (typeof navigator !== 'undefined' && navigator.onLine === false) {
      setLoadState('offline');
      return;
    }
    try {
      const res = await fetchConnectorStatuses();
      setStatuses(res.connectors ?? {});
      setUsage(res.usage ?? { connectorRequestsUsedToday: 0, connectorRequestsPerDay: 100 });
      setLoadState('ready');
    } catch (err) {
      const msg = err instanceof Error ? err.message : '';
      if (/offline|network|unavailable/i.test(msg)) {
        setLoadState('offline');
      } else {
        setLoadState('error');
      }
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  // ── STATE: loading ──────────────────────────────────────────────────────────
  if (loadState === 'loading') {
    return (
      <main style={s.screen} aria-label="Connectors" aria-busy="true">
        <h1 style={s.heading}>Connectors</h1>
        <p style={s.subheading}>Loading your connections…</p>
        {[0, 1, 2].map((i) => (
          <div key={i} style={{ ...s.card, height: 96, opacity: 0.55 }} aria-hidden="true" />
        ))}
      </main>
    );
  }

  // ── STATE: offline ──────────────────────────────────────────────────────────
  if (loadState === 'offline') {
    return (
      <main style={s.screen} aria-label="Connectors">
        <h1 style={s.heading}>Connectors</h1>
        <div style={{ ...s.card, textAlign: 'center', padding: '32px 22px' }} role="status">
          <div aria-hidden="true" style={{ fontSize: 26, marginBottom: 10 }}>⌁</div>
          <p style={{ fontSize: 16, fontWeight: 600, color: tokens.text, marginBottom: 6 }}>You’re offline</p>
          <p style={{ fontSize: 14, color: tokens.textSub, lineHeight: 1.5 }}>
            Connect to the internet to manage your connectors.
          </p>
          <button style={s.secondaryButton} onClick={load}>Try again</button>
        </div>
      </main>
    );
  }

  // ── STATE: error (whole-screen load failure) ────────────────────────────────
  if (loadState === 'error') {
    return (
      <main style={s.screen} aria-label="Connectors">
        <h1 style={s.heading}>Connectors</h1>
        <div
          style={{ ...s.card, textAlign: 'center', padding: '32px 22px', borderColor: STATUS_COLORS.errorBorder, backgroundColor: STATUS_COLORS.errorBg }}
          role="alert"
        >
          <div aria-hidden="true" style={{ fontSize: 26, marginBottom: 10 }}>⚠</div>
          <p style={{ fontSize: 16, fontWeight: 600, color: STATUS_COLORS.error, marginBottom: 6 }}>
            Couldn’t load connectors
          </p>
          <p style={{ fontSize: 14, color: tokens.textSub, lineHeight: 1.5 }}>
            Something went wrong on our side. Please try again.
          </p>
          <button style={s.secondaryButton} onClick={load}>Try again</button>
        </div>
      </main>
    );
  }

  // ── Usage sub-screen ────────────────────────────────────────────────────────
  if (showUsage) {
    return (
      <main style={{ ...s.screen, paddingTop: 16 }} aria-label="Usage and limits">
        <button style={{ ...s.linkButton, marginBottom: 12 }} onClick={() => setShowUsage(false)}>
          ‹ Back to connectors
        </button>
        <UsageLimitsScreen plan={plan} connectorRequestsUsedToday={usage.connectorRequestsUsedToday} />
      </main>
    );
  }

  // ── READY: compute empty / partial / full for the header copy ───────────────
  const activeCount = ORDERED_CONNECTORS.filter(
    (id) => (statuses[id]?.status ?? 'inactive') === 'active',
  ).length;
  const errorCount = ORDERED_CONNECTORS.filter(
    (id) => (statuses[id]?.status === 'error') || statuses[id]?.degraded,
  ).length;

  const headerCopy =
    activeCount === 0
      ? 'Nothing connected yet. Everything is off until you turn it on.'
      : activeCount === ORDERED_CONNECTORS.length
        ? 'All your connectors are on. Adjust or revoke any in one tap.'
        : `${activeCount} of ${ORDERED_CONNECTORS.length} connected. Turn on more whenever you’re ready.`;

  return (
    <main style={s.screen} aria-label="Connectors">
      <h1 style={s.heading}>Connectors</h1>
      <p style={s.subheading}>{headerCopy}</p>

      {errorCount > 0 && (
        <div
          style={{ ...s.card, backgroundColor: STATUS_COLORS.errorBg, borderColor: STATUS_COLORS.errorBorder, padding: '12px 14px', marginBottom: 16 }}
          role="alert"
        >
          <span style={{ fontSize: 13, color: STATUS_COLORS.error, fontWeight: 600 }}>
            {errorCount === 1 ? '1 connector needs attention.' : `${errorCount} connectors need attention.`}
          </span>{' '}
          <span style={{ fontSize: 13, color: tokens.textSub }}>Reconnect below to restore them.</span>
        </div>
      )}

      {ORDERED_CONNECTORS.map((id) => (
        <ConnectorCard
          key={id}
          meta={CONNECTOR_META[id]}
          status={statuses[id] ?? DEFAULT_STATUS}
          provider={getConnectorProvider(id)}
          beginOAuth={() => beginOAuth({ id, title: CONNECTOR_META[id].title })}
          onChanged={load}
        />
      ))}

      <button style={{ ...s.linkButton, marginTop: 6 }} onClick={() => setShowUsage(true)}>
        View usage &amp; limits ›
      </button>

      <p style={s.footerNote}>
        Amen connects only to faith-focused services. Connectors are off by default, read-only by
        default, and you can revoke any of them in one tap. Connected apps are never used for ads.
      </p>
    </main>
  );
}
