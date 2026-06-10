/**
 * ConnectorCard.tsx — single per-connector card.
 * OWNER: Phase 2 Agent A.
 *
 * One card per connector: enable toggle, "What Amen can see" link, example prompts
 * link, grant (scope + per-surface matrix + expiry) entry, one-tap revoke, and a
 * visible DEGRADED state when status:'error'.
 */

import React, { useState } from 'react';
import { s } from './styles';
import { ConnectorMeta } from './connectorMeta';
import { ConnectorRuntimeStatus, ConnectorProvider } from './ConnectorProvider';
import { ConnectedChip, IdleChip, DegradedChip } from './StatusChips';
import { WhatAmenCanSeeSheet, GrantSheet, GrantSelection } from './ConnectorSheets';
import { tokens } from '../../berean/contracts';

export interface ConnectorCardProps {
  meta: ConnectorMeta;
  status: ConnectorRuntimeStatus;
  provider: ConnectorProvider;
  /** Begin the platform OAuth flow (NEW providers). Returns the code + redirectUri. */
  beginOAuth: (meta: ConnectorMeta) => Promise<{ code: string; redirectUri: string; codeVerifier?: string }>;
  onChanged: () => void;
}

export default function ConnectorCard({
  meta,
  status,
  provider,
  beginOAuth,
  onChanged,
}: ConnectorCardProps): JSX.Element {
  const [showSee, setShowSee] = useState(false);
  const [showGrant, setShowGrant] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const isActive = status.status === 'active';
  const isError = status.status === 'error' || status.degraded;

  function friendlyError(err: unknown): string {
    const msg = err instanceof Error ? err.message : '';
    if (/minor/i.test(msg)) return 'Connectors are not available for this account.';
    if (/unavailable|provider/i.test(msg)) return 'Couldn’t reach the service. Please try again.';
    if (/resource-exhausted|rate/i.test(msg)) return 'You’ve made a lot of changes — try again in a bit.';
    return 'Something went wrong. Please try again.';
  }

  // Toggle on → open grant sheet (NEW) or activate alias. Toggle off → revoke.
  async function handleToggle() {
    setError(null);
    if (isActive || isError) {
      // turning OFF — one-tap revoke
      setBusy(true);
      try {
        await provider.revoke();
        onChanged();
      } catch (err) {
        setError(friendlyError(err));
      } finally {
        setBusy(false);
      }
      return;
    }
    // turning ON
    if (provider.hasOAuth) {
      setShowGrant(true); // collect scopes/surfaces first, then OAuth on confirm
    } else {
      // alias connector — read-only by default, single least-privilege surface
      setBusy(true);
      try {
        await provider.grant({
          scopes: meta.supportedScopes.slice(0, 1),
          surfaces: [],
        });
        onChanged();
      } catch (err) {
        setError(friendlyError(err));
      } finally {
        setBusy(false);
      }
    }
  }

  async function handleGrantConfirm(sel: GrantSelection) {
    setBusy(true);
    setError(null);
    try {
      let code: string | undefined;
      let redirectUri: string | undefined;
      let codeVerifier: string | undefined;
      if (provider.hasOAuth) {
        const oauth = await beginOAuth(meta);
        code = oauth.code;
        redirectUri = oauth.redirectUri;
        codeVerifier = oauth.codeVerifier;
      }
      await provider.grant({
        scopes: sel.scopes,
        surfaces: sel.surfaces,
        expiresAt: sel.expiresAt,
        writeCommitConfirmed: sel.writeCommitConfirmed,
        code,
        redirectUri,
        codeVerifier,
      });
      setShowGrant(false);
      onChanged();
    } catch (err) {
      setError(friendlyError(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div style={s.card}>
      <div style={s.cardHeaderRow}>
        <span style={s.icon} aria-hidden="true">{meta.icon}</span>
        <span style={s.cardTitle}>{meta.title}</span>
        {isError ? (
          <DegradedChip reason={status.reason} />
        ) : isActive ? (
          <ConnectedChip />
        ) : (
          <IdleChip />
        )}
        <button
          style={s.toggleTrack(isActive)}
          onClick={handleToggle}
          disabled={busy}
          role="switch"
          aria-checked={isActive}
          aria-label={`${isActive ? 'Turn off' : 'Turn on'} ${meta.title}`}
        >
          <span style={s.toggleKnob(isActive)} aria-hidden="true" />
        </button>
      </div>

      <p style={s.tagline}>{meta.tagline}</p>

      {isError && (
        <p style={{ fontSize: 13, color: '#FF3B30', lineHeight: 1.5, marginTop: 0 }}>
          {meta.title} needs to be reconnected. Turn it off and on again to restore it.
        </p>
      )}

      {error && (
        <p style={{ fontSize: 13, color: '#FF3B30', marginTop: 4 }} role="alert">{error}</p>
      )}

      <div style={s.linkRow}>
        <button style={s.linkButton} onClick={() => setShowSee(true)}>
          What Amen can see
        </button>
        {isActive && (
          <button style={s.linkButton} onClick={() => setShowGrant(true)}>
            Adjust access
          </button>
        )}
        {(isActive || isError) && (
          <button style={s.revokeButton} onClick={handleToggle} disabled={busy}>
            {busy ? 'Removing…' : 'Revoke'}
          </button>
        )}
      </div>

      {status.surfaces.length > 0 && isActive && (
        <p style={{ fontSize: 12, color: tokens.textSub, marginTop: 10 }}>
          Used in: {status.surfaces.join(', ').replace(/_/g, ' ')}
        </p>
      )}

      {showSee && <WhatAmenCanSeeSheet meta={meta} onClose={() => setShowSee(false)} />}
      {showGrant && (
        <GrantSheet
          meta={meta}
          initial={isActive ? { scopes: status.scopes, surfaces: status.surfaces } : undefined}
          busy={busy}
          onClose={() => setShowGrant(false)}
          onConfirm={isActive ? (sel) => {
            // adjust existing grant (no re-OAuth)
            setBusy(true);
            setError(null);
            provider
              .updateGrant({ scopes: sel.scopes, surfaces: sel.surfaces, expiresAt: sel.expiresAt, writeCommitConfirmed: sel.writeCommitConfirmed })
              .then(() => { setShowGrant(false); onChanged(); })
              .catch((err) => setError(friendlyError(err)))
              .finally(() => setBusy(false));
          } : handleGrantConfirm}
        />
      )}
    </div>
  );
}
