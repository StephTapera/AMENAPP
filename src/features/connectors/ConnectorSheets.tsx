/**
 * ConnectorSheets.tsx — bottom sheets for the Connectors Hub.
 * OWNER: Phase 2 Agent A.
 *
 *  - WhatAmenCanSeeSheet — plain-language transparency + example prompts.
 *  - GrantSheet — scope picker (ConnectorScope) + per-surface grant matrix
 *    (the 5 GrantSurface values) + expiry option + confirm. This is where
 *    "Calendar for reminders, not recommendations" is configured: grant calendar
 *    to scheduled_actions but NOT berean.
 */

import React, { useState } from 'react';
import { s } from './styles';
import {
  ConnectorScope,
  GrantSurface,
} from '../connectedIntelligence.contracts';
import {
  ConnectorMeta,
  SCOPE_LABELS,
  SURFACE_LABELS,
} from './connectorMeta';

// ── Shared sheet shell ──────────────────────────────────────────────────────
function SheetShell({
  title,
  onClose,
  children,
}: {
  title: string;
  onClose: () => void;
  children: React.ReactNode;
}): JSX.Element {
  return (
    <div style={s.sheetBackdrop} onClick={onClose} role="presentation">
      <div
        style={s.sheet}
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-label={title}
      >
        <h2 style={s.sheetTitle}>{title}</h2>
        {children}
      </div>
    </div>
  );
}

// ── WhatAmenCanSeeSheet ─────────────────────────────────────────────────────
export function WhatAmenCanSeeSheet({
  meta,
  onClose,
}: {
  meta: ConnectorMeta;
  onClose: () => void;
}): JSX.Element {
  return (
    <SheetShell title={`What Amen can see — ${meta.title}`} onClose={onClose}>
      <p style={s.sheetSectionTitle}>What Amen can see</p>
      {meta.whatAmenCanSee.map((b, i) => (
        <p key={i} style={s.bullet}>
          <span aria-hidden="true" style={{ position: 'absolute', left: 0 }}>•</span>
          {b}
        </p>
      ))}

      <p style={s.sheetSectionTitle}>What Amen will never do</p>
      {meta.whatAmenWontDo.map((b, i) => (
        <p key={i} style={s.bullet}>
          <span aria-hidden="true" style={{ position: 'absolute', left: 0 }}>•</span>
          {b}
        </p>
      ))}

      <p style={s.sheetSectionTitle}>Try asking</p>
      {meta.examplePrompts.map((p, i) => (
        <p key={i} style={s.examplePrompt}>“{p}”</p>
      ))}

      <button style={s.secondaryButton} onClick={onClose}>Close</button>
    </SheetShell>
  );
}

// ── GrantSheet ──────────────────────────────────────────────────────────────

const EXPIRY_OPTIONS: Array<{ label: string; ms: number | null }> = [
  { label: 'Until I turn it off', ms: null },
  { label: '24 hours', ms: 24 * 3600 * 1000 },
  { label: '7 days', ms: 7 * 24 * 3600 * 1000 },
  { label: '30 days', ms: 30 * 24 * 3600 * 1000 },
];

export interface GrantSelection {
  scopes: ConnectorScope[];
  surfaces: GrantSurface[];
  expiresAt: number | null;
  writeCommitConfirmed: boolean;
}

export function GrantSheet({
  meta,
  initial,
  busy,
  onClose,
  onConfirm,
}: {
  meta: ConnectorMeta;
  initial?: Partial<GrantSelection>;
  busy: boolean;
  onClose: () => void;
  onConfirm: (sel: GrantSelection) => void;
}): JSX.Element {
  // Read-only by default: default scope = least-privilege read_metadata only.
  const [scopes, setScopes] = useState<ConnectorScope[]>(
    initial?.scopes ?? [ConnectorScope.read_metadata],
  );
  // Default surfaces: none pre-selected for new providers → user opts in per surface.
  const [surfaces, setSurfaces] = useState<GrantSurface[]>(initial?.surfaces ?? []);
  const [expiryIdx, setExpiryIdx] = useState<number>(0);
  const [writeCommitConfirmed, setWriteCommitConfirmed] = useState(false);

  const allSurfaces = Object.values(GrantSurface);

  function toggleScope(scope: ConnectorScope) {
    setScopes((prev) =>
      prev.includes(scope) ? prev.filter((x) => x !== scope) : [...prev, scope],
    );
  }
  function toggleSurface(surface: GrantSurface) {
    setSurfaces((prev) =>
      prev.includes(surface) ? prev.filter((x) => x !== surface) : [...prev, surface],
    );
  }

  const needsWriteCommitConfirm = scopes.includes(ConnectorScope.write_commit);
  const expiresAt =
    EXPIRY_OPTIONS[expiryIdx].ms === null
      ? null
      : Date.now() + (EXPIRY_OPTIONS[expiryIdx].ms as number);

  const canConfirm =
    scopes.length > 0 &&
    surfaces.length > 0 &&
    (!needsWriteCommitConfirm || writeCommitConfirmed) &&
    !busy;

  return (
    <SheetShell title={`Set up ${meta.title}`} onClose={onClose}>
      {/* SCOPE PICKER */}
      <p style={s.sheetSectionTitle}>What Amen may access</p>
      {meta.supportedScopes.map((scope) => {
        const on = scopes.includes(scope);
        const l = SCOPE_LABELS[scope];
        return (
          <div
            key={scope}
            style={s.checkRow}
            role="checkbox"
            aria-checked={on}
            tabIndex={0}
            onClick={() => toggleScope(scope)}
            onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') toggleScope(scope); }}
          >
            <span style={s.checkbox(on)} aria-hidden="true">{on ? '✓' : ''}</span>
            <span>
              <div style={s.checkLabel}>{l.label}</div>
              <div style={s.checkHelp}>{l.help}</div>
            </span>
          </div>
        );
      })}

      {/* PER-SURFACE GRANT MATRIX */}
      <p style={s.sheetSectionTitle}>Where Amen may use it</p>
      <p style={{ ...s.checkHelp, marginBottom: 4 }}>
        Turn on only the places you want. For example: allow Calendar for reminders, but not for chat recommendations.
      </p>
      {allSurfaces.map((surface) => {
        const on = surfaces.includes(surface);
        const l = SURFACE_LABELS[surface];
        return (
          <div
            key={surface}
            style={s.checkRow}
            role="checkbox"
            aria-checked={on}
            tabIndex={0}
            onClick={() => toggleSurface(surface)}
            onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') toggleSurface(surface); }}
          >
            <span style={s.checkbox(on)} aria-hidden="true">{on ? '✓' : ''}</span>
            <span>
              <div style={s.checkLabel}>{l.label}</div>
              <div style={s.checkHelp}>{l.help}</div>
            </span>
          </div>
        );
      })}

      {/* EXPIRY */}
      <p style={s.sheetSectionTitle}>How long</p>
      <select
        style={s.expirySelect}
        value={expiryIdx}
        onChange={(e) => setExpiryIdx(Number(e.target.value))}
        aria-label="Access duration"
      >
        {EXPIRY_OPTIONS.map((o, i) => (
          <option key={i} value={i}>{o.label}</option>
        ))}
      </select>

      {/* write_commit confirmation gate (required at grant time) */}
      {needsWriteCommitConfirm && (
        <div
          style={{ ...s.checkRow, marginTop: 8 }}
          role="checkbox"
          aria-checked={writeCommitConfirmed}
          tabIndex={0}
          onClick={() => setWriteCommitConfirmed((v) => !v)}
          onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') setWriteCommitConfirmed((v) => !v); }}
        >
          <span style={s.checkbox(writeCommitConfirmed)} aria-hidden="true">{writeCommitConfirmed ? '✓' : ''}</span>
          <span>
            <div style={s.checkLabel}>I understand Amen may make changes</div>
            <div style={s.checkHelp}>Amen will still ask you before every single change.</div>
          </span>
        </div>
      )}

      <button
        style={s.primaryButton(!canConfirm)}
        disabled={!canConfirm}
        onClick={() =>
          onConfirm({ scopes, surfaces, expiresAt, writeCommitConfirmed })
        }
      >
        {busy ? 'Connecting…' : 'Allow access'}
      </button>
      <button style={s.secondaryButton} onClick={onClose} disabled={busy}>Cancel</button>
    </SheetShell>
  );
}
