/**
 * CalendarDraftCard.tsx — DRAFT event card + ConfirmationGate for @calendar writes.
 *
 * Agent D (@Tool Mentions) — Connected Intelligence Phase 2.
 *
 * A @calendar WRITE intent ("schedule prayer night Friday") NEVER writes silently.
 * It produces this draft card. The user must press "Add to calendar" (the
 * ConfirmationGate) before event_create runs. The ceiling is drafts_for_approval.
 *
 * Liquid Glass white/light. No gold/purple/cosmic-dark/Cormorant Garamond.
 *
 * OWNER: Agent D. Create-only under src/features/berean/composer/**.
 */

import React, { useState } from 'react';

import { tokens } from '../../../berean/contracts';
import type { CalendarDraft, CommitResult } from './calendarDraftService';

const FONT = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';

interface CalendarDraftCardProps {
  draft: CalendarDraft;
  /** Runs event_create. Provided by the composer (wraps confirmDraft). */
  onConfirm: () => Promise<CommitResult>;
  onCancel: () => void;
}

function formatRange(draft: CalendarDraft): string {
  try {
    const start = new Date(draft.startISO);
    const dateFmt: Intl.DateTimeFormatOptions = {
      weekday: 'short', month: 'short', day: 'numeric',
    };
    const timeFmt: Intl.DateTimeFormatOptions = { hour: 'numeric', minute: '2-digit' };
    if (draft.allDay) {
      return `${start.toLocaleDateString(undefined, dateFmt)} · All day`;
    }
    const startStr = `${start.toLocaleDateString(undefined, dateFmt)}, ${start.toLocaleTimeString(undefined, timeFmt)}`;
    if (draft.endISO) {
      const end = new Date(draft.endISO);
      return `${startStr} – ${end.toLocaleTimeString(undefined, timeFmt)}`;
    }
    return startStr;
  } catch {
    return draft.humanReadable;
  }
}

export function CalendarDraftCard({
  draft,
  onConfirm,
  onCancel,
}: CalendarDraftCardProps): React.ReactElement {
  const [state, setState] = useState<'idle' | 'committing' | 'error'>('idle');
  const [errorReason, setErrorReason] = useState<string | null>(null);

  const handleConfirm = async () => {
    if (state === 'committing') return;
    setState('committing');
    setErrorReason(null);
    const result = await onConfirm();
    if (result.status === 'committed') {
      // Parent clears the draft on success; nothing else to do here.
      return;
    }
    setState('error');
    setErrorReason(result.reason ?? 'Could not create the event. Nothing was written.');
  };

  const cardStyle: React.CSSProperties = {
    margin: '0 16px 8px',
    backgroundColor: tokens.card,
    borderRadius: tokens.radius,
    boxShadow: tokens.shadow,
    border: `1px solid ${tokens.divider}`,
    overflow: 'hidden',
    fontFamily: FONT,
  };

  return (
    <div style={cardStyle} role="group" aria-label="Calendar draft awaiting confirmation">
      <div style={{ padding: '14px 16px 10px' }}>
        <div
          style={{
            fontSize: 11, fontWeight: 600, letterSpacing: 0.4,
            textTransform: 'uppercase', color: tokens.textSub, marginBottom: 8,
            display: 'flex', alignItems: 'center', gap: 6,
          }}
        >
          <span aria-hidden>▦</span> Draft · not yet on your calendar
        </div>
        <div style={{ fontSize: 16, fontWeight: 600, color: tokens.text, marginBottom: 4 }}>
          {draft.title}
        </div>
        <div style={{ fontSize: 13.5, color: tokens.textSub }}>{formatRange(draft)}</div>

        {draft.lowConfidence && (
          <div
            style={{
              marginTop: 8, fontSize: 12, color: tokens.textSub,
              backgroundColor: tokens.bg, borderRadius: 10, padding: '8px 10px',
            }}
          >
            Please double-check the details — I wasn’t fully sure of the time.
          </div>
        )}

        {state === 'error' && errorReason && (
          <div
            role="alert"
            style={{
              marginTop: 8, fontSize: 12.5, color: tokens.text,
              backgroundColor: tokens.bg, border: `1px solid ${tokens.divider}`,
              borderRadius: 10, padding: '8px 10px',
            }}
          >
            {errorReason}
          </div>
        )}
      </div>

      <div
        style={{
          display: 'flex', gap: 8, padding: '10px 16px 14px',
          borderTop: `1px solid ${tokens.divider}`,
        }}
      >
        <button
          onClick={onCancel}
          disabled={state === 'committing'}
          style={{
            flex: 1, padding: '10px', borderRadius: 12,
            border: `1px solid ${tokens.divider}`, background: tokens.card,
            color: tokens.text, fontSize: 14, fontWeight: 500,
            cursor: state === 'committing' ? 'default' : 'pointer', fontFamily: FONT,
          }}
        >
          Cancel
        </button>
        <button
          onClick={handleConfirm}
          disabled={state === 'committing'}
          style={{
            flex: 1.4, padding: '10px', borderRadius: 12, border: 'none',
            backgroundColor: tokens.accent, color: '#fff',
            fontSize: 14, fontWeight: 600,
            cursor: state === 'committing' ? 'default' : 'pointer',
            opacity: state === 'committing' ? 0.7 : 1, fontFamily: FONT,
          }}
        >
          {state === 'committing' ? 'Adding…' : 'Add to calendar'}
        </button>
      </div>
    </div>
  );
}
