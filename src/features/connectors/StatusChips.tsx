/**
 * StatusChips.tsx — Reusable status chips for Connected Intelligence surfaces.
 * OWNER: Phase 2 Agent A.
 *
 * Other surfaces (daily brief, notebooks, action sheet) import `DegradedChip`
 * from this folder to render a connector's status:'error' state consistently.
 *
 * IMPORTANT: error/degraded messaging (red) is VISUALLY DISTINCT from
 * cap/limit messaging (amber) — see CapChip. Never collapse the two.
 */

import React from 'react';
import { STATUS_COLORS, FONT } from './styles';

const chipBase: React.CSSProperties = {
  display: 'inline-flex',
  alignItems: 'center',
  gap: 6,
  fontSize: 12,
  fontWeight: 600,
  padding: '5px 10px',
  borderRadius: 999,
  fontFamily: FONT,
  lineHeight: 1.2,
  border: '1px solid transparent',
};

/**
 * DegradedChip — visible DEGRADED state for a connector whose token health failed
 * (status:'error'). Red family. Import this from other surfaces to show the same
 * state when a connector they depend on is degraded.
 */
export function DegradedChip({
  label = 'Needs attention',
  reason,
}: {
  label?: string;
  reason?: string | null;
}): JSX.Element {
  const reasonText =
    reason === 'token_expired'
      ? 'The connection expired — reconnect to keep using it.'
      : reason === 'token_missing'
        ? 'The connection was lost — reconnect to restore it.'
        : 'This connector needs to be reconnected.';
  return (
    <span
      style={{
        ...chipBase,
        color: STATUS_COLORS.error,
        backgroundColor: STATUS_COLORS.errorBg,
        borderColor: STATUS_COLORS.errorBorder,
      }}
      role="status"
      aria-label={`Degraded. ${reasonText}`}
      title={reasonText}
    >
      <span aria-hidden="true" style={{ fontSize: 13 }}>⚠</span>
      {label}
    </span>
  );
}

/**
 * CapChip — usage-cap / limit reached. Amber family — INTENTIONALLY different from
 * the red DegradedChip so users never confuse "you hit a limit" with "something broke".
 */
export function CapChip({ label = 'Daily limit reached' }: { label?: string }): JSX.Element {
  return (
    <span
      style={{
        ...chipBase,
        color: STATUS_COLORS.cap,
        backgroundColor: STATUS_COLORS.capBg,
        borderColor: STATUS_COLORS.capBorder,
      }}
      role="status"
      aria-label={`Usage limit. ${label}`}
    >
      <span aria-hidden="true" style={{ fontSize: 13 }}>◷</span>
      {label}
    </span>
  );
}

/** ConnectedChip — calm "active" state. */
export function ConnectedChip(): JSX.Element {
  return (
    <span style={{ ...chipBase, color: STATUS_COLORS.ok, backgroundColor: 'transparent' }} aria-label="Connected">
      <span aria-hidden="true" style={{ width: 7, height: 7, borderRadius: '50%', backgroundColor: STATUS_COLORS.okDot, display: 'inline-block' }} />
      Connected
    </span>
  );
}

/** IdleChip — not connected. */
export function IdleChip(): JSX.Element {
  return (
    <span style={{ ...chipBase, color: STATUS_COLORS.idleDot, backgroundColor: 'transparent' }} aria-label="Not connected">
      <span aria-hidden="true" style={{ width: 7, height: 7, borderRadius: '50%', backgroundColor: STATUS_COLORS.idleDot, display: 'inline-block' }} />
      Off
    </span>
  );
}
