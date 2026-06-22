/**
 * DegradedChip.tsx — Distinct "connector degraded" chip for the composer.
 *
 * Agent D (@Tool Mentions) — Connected Intelligence Phase 2.
 *
 * A degraded connector is NOT an error. When @calendar/@music/@church can't return
 * data, the turn still runs (Berean answers from its own knowledge) but the user must
 * SEE that connector context was skipped — we never fabricate it. This chip is visually
 * distinct from a hard error: a muted amber-free, palette-safe info chip using the
 * Berean neutral tokens (no gold/purple).
 *
 * OWNER: Agent D. Create-only under src/features/berean/composer/**.
 */

import React from 'react';

import { tokens } from '../../../berean/contracts';
import type { DegradedSignal } from './useMentionComposer';

const FONT = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';

interface DegradedChipProps {
  signal: DegradedSignal;
  onDismiss: () => void;
}

export function DegradedChip({ signal, onDismiss }: DegradedChipProps): React.ReactElement {
  return (
    <div
      role="status"
      aria-live="polite"
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 8,
        margin: '0 16px 8px',
        padding: '8px 12px',
        borderRadius: 12,
        // Distinct from error: neutral light surface + dashed border = "degraded".
        backgroundColor: tokens.bg,
        border: `1px dashed ${tokens.divider}`,
        fontFamily: FONT,
      }}
    >
      <span aria-hidden style={{ fontSize: 14, color: tokens.textSub }}>◴</span>
      <span style={{ flex: 1, fontSize: 12.5, lineHeight: 1.4, color: tokens.text }}>
        <strong style={{ fontWeight: 600 }}>Connector skipped.</strong>{' '}
        <span style={{ color: tokens.textSub }}>
          {signal.reason} Berean answered without it — nothing was made up.
        </span>
      </span>
      <button
        onClick={onDismiss}
        aria-label="Dismiss"
        style={{
          border: 'none', background: 'none', cursor: 'pointer',
          color: tokens.textSub, fontSize: 14, fontFamily: FONT, flexShrink: 0,
        }}
      >
        ✕
      </button>
    </div>
  );
}
