/**
 * UsageLimitsScreen.tsx — Usage & limits for Connected Intelligence.
 * OWNER: Phase 2 Agent A.
 *
 * Reads caps straight from connectedIntelligence.config (daily prompts,
 * connector requests, scheduled-action runs, plan caps). Live "used today"
 * counts come from the connectorStatus CF.
 *
 * CAP-degradation messaging (amber CapChip) is VISUALLY DISTINCT from
 * error/degraded messaging (red DegradedChip). Hitting a limit is not a fault.
 */

import React from 'react';
import { s, STATUS_COLORS } from './styles';
import { CapChip } from './StatusChips';
import { tokens } from '../../berean/contracts';
import { connectedIntelligence } from '../connectedIntelligence.config';
import type { Plan } from '../connectedIntelligence.contracts';

export interface UsageLimitsScreenProps {
  plan: Plan;
  /** Live connector-request usage from the connectorStatus CF. */
  connectorRequestsUsedToday: number;
  /** Optional live daily-prompt usage (from Berean usage doc), if available. */
  dailyPromptsUsedToday?: number;
}

interface MeterRow {
  label: string;
  used: number | null;
  cap: number;
  help: string;
}

function planCap(plan: Plan, freeVal: number, plusVal: number): number {
  return plan === 'free' ? freeVal : plusVal;
}

function Meter({ row }: { row: MeterRow }): JSX.Element {
  const pct = row.used != null && row.cap > 0 ? Math.min(100, (row.used / row.cap) * 100) : 0;
  const atCap = row.used != null && row.used >= row.cap;
  return (
    <div style={s.card}>
      <div style={{ ...s.rowBetween, marginBottom: 8 }}>
        <span style={s.cardTitle}>{row.label}</span>
        {atCap && <CapChip />}
      </div>
      <div
        style={{
          height: 8,
          borderRadius: 4,
          backgroundColor: tokens.bg,
          overflow: 'hidden',
          marginBottom: 8,
        }}
        role="progressbar"
        aria-valuemin={0}
        aria-valuemax={row.cap}
        aria-valuenow={row.used ?? 0}
        aria-label={row.label}
      >
        <div
          style={{
            width: `${pct}%`,
            height: '100%',
            backgroundColor: atCap ? STATUS_COLORS.cap : tokens.accent,
            transition: 'width .2s',
          }}
        />
      </div>
      <div style={s.checkHelp}>
        {row.used != null ? `${row.used} of ${row.cap} used today` : `Up to ${row.cap} per day`}
        {atCap ? ' — you’ve reached today’s limit. It resets tomorrow.' : ''}
      </div>
      <div style={{ ...s.checkHelp, marginTop: 4 }}>{row.help}</div>
    </div>
  );
}

export default function UsageLimitsScreen({
  plan,
  connectorRequestsUsedToday,
  dailyPromptsUsedToday,
}: UsageLimitsScreenProps): JSX.Element {
  const cfg = connectedIntelligence;

  const rows: MeterRow[] = [
    {
      label: 'Daily Berean prompts',
      used: dailyPromptsUsedToday ?? null,
      cap: planCap(plan, cfg.limits.dailyPromptsFree, cfg.limits.dailyPromptsPlus),
      help: 'How many questions you can ask Berean each day. Safety and crisis help are never limited.',
    },
    {
      label: 'Connector requests',
      used: connectorRequestsUsedToday,
      cap: cfg.limits.connectorRequestsPerDay,
      help: 'How often connected apps (Calendar, Music, Church) can be checked each day.',
    },
    {
      label: 'Scheduled actions',
      used: null,
      cap: planCap(plan, cfg.scheduledActions.maxActiveFree, cfg.scheduledActions.maxActivePlus),
      help: cfg.scheduledActions.enabled
        ? 'How many reminders and scheduled tasks you can keep active.'
        : 'Scheduled actions are coming soon — they’re turned off for now.',
    },
    {
      label: 'Notebook sources',
      used: null,
      cap: planCap(plan, cfg.notebooks.maxSourcesFree, cfg.notebooks.maxSourcesPlus),
      help: 'How many sources you can add to a single notebook.',
    },
  ];

  return (
    <main style={s.screen} aria-label="Usage and limits">
      <h1 style={s.heading}>Usage &amp; limits</h1>
      <p style={s.subheading}>
        Your current plan: <strong>{plan === 'free' ? 'Free' : plan === 'plus' ? 'Amen+' : 'Amen Pro'}</strong>.
        These limits keep Amen calm and predictable. Reaching a limit is normal — it is not an error.
      </p>

      {rows.map((row) => (
        <Meter key={row.label} row={row} />
      ))}

      <p style={s.footerNote}>
        Safety and crisis support are always available and are never counted against any limit.
      </p>
    </main>
  );
}
