/**
 * src/features/actionSheet/ResponseActionSheet.tsx
 *
 * Floating Liquid Glass pill under every Berean response + the full grouped sheet.
 *
 *   Pill:  Save · Share(Discuss) · Study(Remember) · Create(Post) · Continue · •••
 *   Long-press OR ••• → expands the full sheet grouped by the ResponseAction taxonomy
 *   (Knowledge / Community / AI transforms / Action / Memory / Continuity).
 *
 * SIX UI states: idle · running · success · error · BLOCKED (distinct) · empty.
 * Deferred actions are ABSENT (filtered in taxonomy), never disabled.
 *
 * DESIGN: white/light Liquid Glass (tokens from src/berean/contracts.ts).
 * FORBIDDEN: cosmic-dark, gold, purple, Cormorant Garamond.
 *
 * OWNER: Agent F (Response Action Sheet). Connected Intelligence v1.
 */

import React, { useCallback, useMemo, useRef, useState } from 'react';

import { tokens } from '../../berean/contracts';
import { useBerean } from '../../berean/core/BereanCore';
import { ResponseAction } from '../connectedIntelligence.contracts';
import { groupedActions, PILL_ACTIONS } from './taxonomy';
import { runAction } from './actionService';
import type {
  ActionSheetResponse,
  ActionResult,
  ActionUiState,
  ActionDescriptor,
} from './types';

const FONT = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';
const LONG_PRESS_MS = 450;

interface Props {
  response: ActionSheetResponse;
}

interface RunningState {
  action: ResponseAction | null;
  state: ActionUiState;
  result: ActionResult | null;
}

export function ResponseActionSheet({ response }: Props): React.ReactElement {
  const { context } = useBerean();
  const uid = context.userId;

  const [sheetOpen, setSheetOpen] = useState(false);
  const [run, setRun] = useState<RunningState>({ action: null, state: 'idle', result: null });
  const pressTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const groups = useMemo(() => groupedActions(), []);

  const execute = useCallback(
    async (action: ResponseAction) => {
      setRun({ action, state: 'running', result: null });
      try {
        const result = await runAction(action, uid, response);
        setRun({ action, state: result.state, result });
      } catch {
        setRun({
          action,
          state: 'error',
          result: { state: 'error', message: 'Something went wrong.', detail: 'Please try again.' },
        });
      }
    },
    [uid, response],
  );

  const openSheet = useCallback(() => {
    setRun({ action: null, state: 'idle', result: null });
    setSheetOpen(true);
  }, []);

  // Long-press handlers (pointer-based — works for touch + mouse).
  const startPress = useCallback(() => {
    pressTimer.current = setTimeout(openSheet, LONG_PRESS_MS);
  }, [openSheet]);
  const cancelPress = useCallback(() => {
    if (pressTimer.current) { clearTimeout(pressTimer.current); pressTimer.current = null; }
  }, []);

  return (
    <>
      <FloatingPill
        actions={PILL_ACTIONS}
        onAction={execute}
        onMore={openSheet}
        onPressStart={startPress}
        onPressEnd={cancelPress}
        runningAction={run.state === 'running' ? run.action : null}
      />

      {/* Inline result chip for pill-triggered actions (when sheet is closed). */}
      {!sheetOpen && run.state !== 'idle' && run.action !== null && (
        <ResultChip run={run} onUndo={() => run.result?.undo?.()} onDismiss={() => setRun({ action: null, state: 'idle', result: null })} />
      )}

      {sheetOpen && (
        <ActionSheetModal
          groups={groups}
          run={run}
          onAction={execute}
          onClose={() => { setSheetOpen(false); setRun({ action: null, state: 'idle', result: null }); }}
          onResetRun={() => setRun({ action: null, state: 'idle', result: null })}
        />
      )}
    </>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Floating Liquid Glass pill
// ─────────────────────────────────────────────────────────────────────────────

function FloatingPill({
  actions, onAction, onMore, onPressStart, onPressEnd, runningAction,
}: {
  actions: ActionDescriptor[];
  onAction: (a: ResponseAction) => void;
  onMore: () => void;
  onPressStart: () => void;
  onPressEnd: () => void;
  runningAction: ResponseAction | null;
}): React.ReactElement {
  return (
    <div
      role="toolbar"
      aria-label="Response actions"
      onPointerDown={onPressStart}
      onPointerUp={onPressEnd}
      onPointerLeave={onPressEnd}
      style={{
        display: 'inline-flex', alignItems: 'center', gap: 2,
        marginTop: 8, padding: '4px 6px',
        background: 'rgba(255,255,255,0.72)',
        backdropFilter: 'blur(20px) saturate(180%)',
        WebkitBackdropFilter: 'blur(20px) saturate(180%)',
        border: `1px solid ${tokens.divider}`,
        borderRadius: 999,
        boxShadow: tokens.shadow,
        fontFamily: FONT,
      }}
    >
      {actions.map((d) => (
        <button
          key={d.action}
          onClick={() => onAction(d.action)}
          aria-label={d.label}
          title={d.label}
          disabled={runningAction === d.action}
          style={pillBtn(runningAction === d.action)}
        >
          <span aria-hidden style={{ fontSize: 15 }}>{d.icon}</span>
        </button>
      ))}
      <button onClick={onMore} aria-label="More actions" title="More actions" style={pillBtn(false)}>
        <span aria-hidden style={{ fontSize: 15, letterSpacing: 1 }}>•••</span>
      </button>
    </div>
  );
}

function pillBtn(active: boolean): React.CSSProperties {
  return {
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    width: 30, height: 30, borderRadius: 999, border: 'none',
    background: active ? tokens.divider : 'transparent',
    color: tokens.text, cursor: active ? 'default' : 'pointer',
    fontFamily: FONT,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Inline result chip (success / error / blocked / empty) for pill actions
// ─────────────────────────────────────────────────────────────────────────────

function ResultChip({
  run, onUndo, onDismiss,
}: { run: RunningState; onUndo: () => void; onDismiss: () => void }): React.ReactElement {
  if (run.state === 'running') {
    return <div style={chipStyle('neutral')}>Working…</div>;
  }
  const r = run.result;
  if (!r) return <></>;
  const tone = r.state === 'blocked' ? 'blocked' : r.state === 'error' ? 'error' : r.state === 'empty' ? 'neutral' : 'success';
  return (
    <div style={chipStyle(tone)}>
      <span style={{ fontWeight: 600 }}>{r.message}</span>
      {r.detail && <span style={{ color: tokens.textSub, marginLeft: 6 }}>{r.detail}</span>}
      {r.undo && (
        <button onClick={() => { onUndo(); onDismiss(); }} style={chipBtn}>Undo</button>
      )}
      <button onClick={onDismiss} aria-label="Dismiss" style={chipBtn}>✕</button>
    </div>
  );
}

type Tone = 'success' | 'error' | 'blocked' | 'neutral';

function chipStyle(tone: Tone): React.CSSProperties {
  const border =
    tone === 'blocked' ? '#B25A00' :
    tone === 'error'   ? '#C0341D' :
    tone === 'success' ? tokens.accent : tokens.divider;
  return {
    display: 'inline-flex', alignItems: 'center', gap: 4, flexWrap: 'wrap',
    marginTop: 6, padding: '6px 10px',
    background: tone === 'blocked' ? '#FFF4E8' : tokens.card,
    border: `1px solid ${border}`,
    borderRadius: 12, fontSize: 13, color: tokens.text, fontFamily: FONT,
    boxShadow: tokens.shadow,
  };
}

const chipBtn: React.CSSProperties = {
  border: 'none', background: 'none', color: tokens.accent,
  cursor: 'pointer', fontSize: 13, fontWeight: 600, padding: '0 4px', fontFamily: FONT,
};

// ─────────────────────────────────────────────────────────────────────────────
// Full grouped sheet modal
// ─────────────────────────────────────────────────────────────────────────────

function ActionSheetModal({
  groups, run, onAction, onClose, onResetRun,
}: {
  groups: Array<{ group: string; items: ActionDescriptor[] }>;
  run: RunningState;
  onAction: (a: ResponseAction) => void;
  onClose: () => void;
  onResetRun: () => void;
}): React.ReactElement {
  const showingResult = run.state !== 'idle' && run.action !== null;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label="Response actions"
      onClick={onClose}
      style={{
        position: 'fixed', inset: 0, zIndex: 1000,
        display: 'flex', alignItems: 'flex-end', justifyContent: 'center',
        background: 'rgba(20,20,20,0.28)',
        backdropFilter: 'blur(2px)', WebkitBackdropFilter: 'blur(2px)',
      }}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        style={{
          width: '100%', maxWidth: 520, maxHeight: '82vh', overflowY: 'auto',
          background: 'rgba(255,255,255,0.86)',
          backdropFilter: 'blur(28px) saturate(180%)',
          WebkitBackdropFilter: 'blur(28px) saturate(180%)',
          borderTopLeftRadius: 24, borderTopRightRadius: 24,
          border: `1px solid ${tokens.divider}`,
          boxShadow: tokens.shadow, fontFamily: FONT,
          padding: '8px 0 24px',
        }}
      >
        {/* Grabber */}
        <div style={{ display: 'flex', justifyContent: 'center', padding: '6px 0 10px' }}>
          <div style={{ width: 36, height: 5, borderRadius: 3, background: tokens.divider }} />
        </div>

        {showingResult ? (
          <ResultPanel run={run} onBack={onResetRun} onClose={onClose} />
        ) : (
          <div style={{ padding: '0 16px' }}>
            {groups.map(({ group, items }) => (
              <section key={group} style={{ marginBottom: 18 }}>
                <h3 style={{
                  margin: '4px 0 8px', fontSize: 12, fontWeight: 700,
                  letterSpacing: 0.4, textTransform: 'uppercase', color: tokens.textSub,
                }}>
                  {group}
                </h3>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
                  {items.map((d) => (
                    <button
                      key={d.action}
                      onClick={() => onAction(d.action)}
                      aria-label={d.label}
                      style={{
                        display: 'flex', alignItems: 'center', gap: 10,
                        padding: '12px 14px', textAlign: 'left',
                        background: tokens.card, border: `1px solid ${tokens.divider}`,
                        borderRadius: 14, cursor: 'pointer',
                        fontSize: 14, color: tokens.text, fontFamily: FONT,
                      }}
                    >
                      <span aria-hidden style={{ fontSize: 17 }}>{d.icon}</span>
                      <span>{d.label}</span>
                    </button>
                  ))}
                </div>
              </section>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Result panel — the SIX states rendered inside the sheet
// ─────────────────────────────────────────────────────────────────────────────

function ResultPanel({
  run, onBack, onClose,
}: { run: RunningState; onBack: () => void; onClose: () => void }): React.ReactElement {
  const r = run.result;

  // running
  if (run.state === 'running') {
    return (
      <PanelShell onBack={onBack} onClose={onClose} title="Working…">
        <div style={{ color: tokens.textSub, fontSize: 14, padding: '8px 0' }}>One moment.</div>
      </PanelShell>
    );
  }
  if (!r) return <PanelShell onBack={onBack} onClose={onClose} title="" />;

  // blocked — DISTINCT amber state
  if (r.state === 'blocked') {
    return (
      <PanelShell onBack={onBack} onClose={onClose} title={r.message} tone="blocked">
        <div style={{ fontSize: 14, color: tokens.text, lineHeight: 1.5 }}>
          {r.detail ?? 'This couldn’t be completed for safety reasons. Nothing was changed.'}
        </div>
      </PanelShell>
    );
  }

  // error — recoverable
  if (r.state === 'error') {
    return (
      <PanelShell onBack={onBack} onClose={onClose} title={r.message} tone="error">
        <div style={{ fontSize: 14, color: tokens.text, lineHeight: 1.5 }}>{r.detail ?? 'Please try again.'}</div>
        <button onClick={onBack} style={primaryBtn}>Try another action</button>
      </PanelShell>
    );
  }

  // empty
  if (r.state === 'empty') {
    return (
      <PanelShell onBack={onBack} onClose={onClose} title={r.message}>
        <div style={{ fontSize: 14, color: tokens.textSub, lineHeight: 1.5 }}>{r.detail}</div>
      </PanelShell>
    );
  }

  // success
  return (
    <PanelShell onBack={onBack} onClose={onClose} title={r.message} tone="success">
      {r.detail && (
        <div style={{
          fontSize: 14, color: tokens.text, lineHeight: 1.55, whiteSpace: 'pre-wrap',
          background: tokens.bg, border: `1px solid ${tokens.divider}`, borderRadius: 12, padding: 12,
        }}>
          {r.detail}
        </div>
      )}
      {r.rows && r.rows.length > 0 && (
        <div style={{ marginTop: 8, display: 'flex', flexDirection: 'column', gap: 6 }}>
          {r.rows.map((row, i) => (
            <div key={i} style={{
              display: 'flex', gap: 8, alignItems: 'baseline',
              padding: '8px 10px', background: tokens.card,
              border: `1px solid ${tokens.divider}`, borderRadius: 10, fontSize: 13,
            }}>
              <span style={{
                fontSize: 10, fontWeight: 700, textTransform: 'uppercase',
                color: tokens.accent, letterSpacing: 0.4, whiteSpace: 'nowrap',
              }}>
                {row.label}
              </span>
              <span style={{ color: tokens.text }}>{row.text}</span>
            </div>
          ))}
        </div>
      )}
      {r.undo && <button onClick={() => { r.undo?.(); onBack(); }} style={secondaryBtn}>Undo</button>}
    </PanelShell>
  );
}

function PanelShell({
  title, tone, children, onBack, onClose,
}: {
  title: string;
  tone?: 'success' | 'error' | 'blocked';
  children?: React.ReactNode;
  onBack: () => void;
  onClose: () => void;
}): React.ReactElement {
  const dot =
    tone === 'blocked' ? '#B25A00' :
    tone === 'error'   ? '#C0341D' :
    tone === 'success' ? tokens.accent : tokens.textSub;
  return (
    <div style={{ padding: '0 18px' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10 }}>
        <button onClick={onBack} aria-label="Back" style={chipBtn}>‹ Back</button>
        <div style={{ flex: 1 }} />
        <button onClick={onClose} aria-label="Close" style={chipBtn}>Done</button>
      </div>
      {title && (
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10 }}>
          <span aria-hidden style={{ width: 8, height: 8, borderRadius: 999, background: dot }} />
          <h3 style={{ margin: 0, fontSize: 16, fontWeight: 700, color: tokens.text }}>{title}</h3>
        </div>
      )}
      {children}
    </div>
  );
}

const primaryBtn: React.CSSProperties = {
  marginTop: 12, width: '100%', padding: '12px', borderRadius: 14, border: 'none',
  background: tokens.accent, color: '#fff', fontSize: 15, fontWeight: 600,
  cursor: 'pointer', fontFamily: FONT,
};
const secondaryBtn: React.CSSProperties = {
  marginTop: 12, width: '100%', padding: '12px', borderRadius: 14,
  border: `1px solid ${tokens.divider}`, background: tokens.card,
  color: tokens.accent, fontSize: 15, fontWeight: 600, cursor: 'pointer', fontFamily: FONT,
};

export default ResponseActionSheet;
