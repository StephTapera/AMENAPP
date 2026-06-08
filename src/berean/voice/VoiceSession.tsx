/**
 * VoiceSession.tsx — Berean Phase 2B In-Session Voice UI
 *
 * CLEAN-END GUARDRAIL (non-negotiable):
 *   When the session ends — user taps End, or silence timeout fires —
 *   the component calls onEnd() immediately and renders nothing further.
 *   No "Great session!", no "Want to continue?", no auto-restart.
 *   Navigation back to the previous screen is the caller's responsibility.
 *
 * Design: white/light only, tokens from contracts.ts, SF system font.
 * Waveform: pure CSS keyframe animation — no animation library.
 */

import React, { useEffect, useRef, useState, useCallback } from 'react';
import { tokens, VoiceMode, VoicePersona } from '../contracts';
import { voiceService, VoiceSessionState } from './voiceService';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

const FONT_FAMILY =
  "-apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif";

/** Silence threshold for hands-free auto-end (ms). Caller may override via prop. */
const DEFAULT_SILENCE_TIMEOUT_MS = 15_000;

// CSS for waveform animation — injected once into document head
const WAVEFORM_CSS = `
@keyframes berean-bar-bounce {
  0%, 100% { transform: scaleY(0.25); }
  50%       { transform: scaleY(1); }
}
.berean-waveform-bar {
  width: 4px;
  border-radius: 2px;
  background-color: ${tokens.accent};
  transform-origin: bottom;
  animation: berean-bar-bounce 0.9s ease-in-out infinite;
}
.berean-waveform-bar:nth-child(1)  { animation-delay: 0.00s; }
.berean-waveform-bar:nth-child(2)  { animation-delay: 0.10s; }
.berean-waveform-bar:nth-child(3)  { animation-delay: 0.20s; }
.berean-waveform-bar:nth-child(4)  { animation-delay: 0.30s; }
.berean-waveform-bar:nth-child(5)  { animation-delay: 0.20s; }
.berean-waveform-bar:nth-child(6)  { animation-delay: 0.10s; }
.berean-waveform-bar:nth-child(7)  { animation-delay: 0.00s; }
.berean-waveform-bar--paused {
  animation-play-state: paused;
  transform: scaleY(0.25);
}
`;

function injectWaveformCSS() {
  if (typeof document === 'undefined') return;
  if (document.getElementById('berean-waveform-css')) return;
  const style = document.createElement('style');
  style.id = 'berean-waveform-css';
  style.textContent = WAVEFORM_CSS;
  document.head.appendChild(style);
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-components
// ─────────────────────────────────────────────────────────────────────────────

function Waveform({ active }: { active: boolean }): JSX.Element {
  injectWaveformCSS();
  const bars = Array.from({ length: 7 });
  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        gap: 5,
        height: 48,
      }}
      aria-hidden="true"
    >
      {bars.map((_, i) => (
        <div
          key={i}
          className={`berean-waveform-bar${active ? '' : ' berean-waveform-bar--paused'}`}
          style={{ height: 36 }}
        />
      ))}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Styles
// ─────────────────────────────────────────────────────────────────────────────

const styles = {
  page: {
    backgroundColor: tokens.bg,
    minHeight: '100vh',
    fontFamily: FONT_FAMILY,
    display: 'flex',
    flexDirection: 'column' as const,
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '48px 24px 40px',
  } as React.CSSProperties,

  topSection: {
    width: '100%',
    display: 'flex',
    flexDirection: 'column' as const,
    alignItems: 'center',
    gap: 12,
  } as React.CSSProperties,

  modeLabel: {
    fontSize: 12,
    fontWeight: 600,
    color: tokens.textSub,
    textTransform: 'uppercase' as const,
    letterSpacing: 0.8,
  } as React.CSSProperties,

  statusLine: {
    fontSize: 15,
    color: tokens.textSub,
    minHeight: 22,
    textAlign: 'center' as const,
    letterSpacing: -0.1,
  } as React.CSSProperties,

  waveformContainer: {
    width: '100%',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 16,
  } as React.CSSProperties,

  scriptureCard: {
    backgroundColor: tokens.card,
    borderRadius: tokens.radius,
    boxShadow: tokens.shadow,
    padding: '16px 18px',
    width: '100%',
    marginTop: 20,
  } as React.CSSProperties,

  scriptureRef: {
    fontSize: 12,
    fontWeight: 600,
    color: tokens.accent,
    marginBottom: 6,
  } as React.CSSProperties,

  scriptureText: {
    fontSize: 15,
    color: tokens.text,
    lineHeight: 1.55,
  } as React.CSSProperties,

  bottomSection: {
    width: '100%',
    display: 'flex',
    flexDirection: 'column' as const,
    alignItems: 'center',
    gap: 20,
  } as React.CSSProperties,

  holdButton: (isListening: boolean): React.CSSProperties => ({
    width: 120,
    height: 120,
    borderRadius: '50%',
    backgroundColor: isListening ? tokens.accent : tokens.card,
    border: `3px solid ${isListening ? tokens.accent : tokens.divider}`,
    boxShadow: isListening
      ? `0 0 0 12px rgba(0,122,255,0.12), ${tokens.shadow}`
      : tokens.shadow,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    cursor: 'pointer',
    transition: 'background-color 0.15s ease, border-color 0.15s ease, box-shadow 0.15s ease',
    userSelect: 'none' as const,
    WebkitUserSelect: 'none' as const,
  }),

  holdButtonLabel: (isListening: boolean): React.CSSProperties => ({
    fontSize: 14,
    fontWeight: 600,
    color: isListening ? '#FFFFFF' : tokens.text,
    textAlign: 'center' as const,
    pointerEvents: 'none',
    lineHeight: 1.3,
  }),

  endButton: {
    padding: '12px 36px',
    backgroundColor: 'transparent',
    border: `1.5px solid ${tokens.divider}`,
    borderRadius: 100,
    fontSize: 15,
    fontWeight: 500,
    color: tokens.textSub,
    fontFamily: FONT_FAMILY,
    cursor: 'pointer',
    transition: 'opacity 0.15s ease',
  } as React.CSSProperties,
} as const;

// ─────────────────────────────────────────────────────────────────────────────
// Props
// ─────────────────────────────────────────────────────────────────────────────

export interface ScriptureRef {
  reference: string;
  text: string;
}

interface VoiceSessionProps {
  mode: VoiceMode;
  persona: VoicePersona;
  /**
   * Called when session ends — no parameters, no return value.
   * Caller must navigate back. No prompt is shown here.
   */
  onEnd: () => void;
  /** Last scripture reference from Berean's response, if any */
  lastScripture?: ScriptureRef;
  /** Silence timeout override in ms (default: 15 000) */
  silenceTimeoutMs?: number;
}

// ─────────────────────────────────────────────────────────────────────────────
// Component
// ─────────────────────────────────────────────────────────────────────────────

export function VoiceSession({
  mode,
  persona: _persona,
  onEnd,
  lastScripture,
  silenceTimeoutMs = DEFAULT_SILENCE_TIMEOUT_MS,
}: VoiceSessionProps): JSX.Element {
  const [sessionState, setSessionState] = useState<VoiceSessionState>(
    voiceService.getState() as VoiceSessionState
  );

  // Silence timer ref for hands-free auto-end
  const silenceTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const didEndRef = useRef(false);

  // CLEAN-END: single exit point, no prompt, no hook
  const handleEnd = useCallback(() => {
    if (didEndRef.current) return;
    didEndRef.current = true;

    if (silenceTimerRef.current) {
      clearTimeout(silenceTimerRef.current);
      silenceTimerRef.current = null;
    }

    voiceService.endSession();
    // Navigate back — no toast, no dialog
    onEnd();
  }, [onEnd]);

  // Subscribe to service state
  useEffect(() => {
    voiceService.startSession(mode);

    const unsub = voiceService.subscribe((state) => {
      setSessionState(state);
    });

    return () => {
      unsub();
      // Cleanup if component unmounts before user taps End
      if (!didEndRef.current) {
        voiceService.endSession();
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Silence-timeout: reset whenever we start listening again (hands-free only)
  useEffect(() => {
    if (mode !== 'hands_free') return;
    if (sessionState.isListening) {
      // Started listening — reset silence clock
      if (silenceTimerRef.current) clearTimeout(silenceTimerRef.current);
      silenceTimerRef.current = setTimeout(() => {
        // Silence threshold reached — CLEAN-END, no prompt
        handleEnd();
      }, silenceTimeoutMs);
    }
    return () => {
      if (silenceTimerRef.current) clearTimeout(silenceTimerRef.current);
    };
  }, [sessionState.isListening, mode, silenceTimeoutMs, handleEnd]);

  // ── Status text ────────────────────────────────────────────────────────────

  let statusText = '';
  if (sessionState.isListening) statusText = 'Listening…';
  else if (sessionState.isSpeaking) statusText = 'Speaking…';
  else if (sessionState.active && mode === 'push_to_talk') statusText = '';
  // "Thinking…" is set externally by the AI response layer via voiceService

  const modeLabel =
    mode === 'hands_free' ? 'Hands-Free' : 'Push to Talk';

  // ── Push-to-talk handlers ──────────────────────────────────────────────────

  const onHoldStart = useCallback(() => {
    if (!sessionState.active) return;
    voiceService.holdToSpeak();
  }, [sessionState.active]);

  const onHoldEnd = useCallback(() => {
    if (!sessionState.active) return;
    voiceService.releaseToSpeak();
  }, [sessionState.active]);

  // ── Render ─────────────────────────────────────────────────────────────────

  return (
    <div style={styles.page} role="main" aria-label={`Voice session — ${modeLabel} mode`}>
      {/* Top section: mode label + status + waveform / last scripture */}
      <div style={styles.topSection}>
        <div style={styles.modeLabel} aria-live="off">{modeLabel}</div>

        <div
          style={styles.statusLine}
          aria-live="polite"
          aria-atomic="true"
        >
          {statusText}
        </div>

        {mode === 'hands_free' && (
          <div style={styles.waveformContainer}>
            <Waveform active={sessionState.isListening} />
          </div>
        )}

        {lastScripture && (
          <div style={styles.scriptureCard} role="region" aria-label="Scripture reference">
            <div style={styles.scriptureRef}>{lastScripture.reference}</div>
            <div style={styles.scriptureText}>{lastScripture.text}</div>
          </div>
        )}
      </div>

      {/* Bottom section: push-to-talk button (or spacer) + End button */}
      <div style={styles.bottomSection}>
        {mode === 'push_to_talk' && (
          <button
            style={styles.holdButton(sessionState.isListening)}
            onPointerDown={onHoldStart}
            onPointerUp={onHoldEnd}
            onPointerLeave={onHoldEnd}
            aria-label={
              sessionState.isListening ? 'Release to send' : 'Hold to speak'
            }
            aria-pressed={sessionState.isListening}
          >
            <span style={styles.holdButtonLabel(sessionState.isListening)}>
              {sessionState.isListening ? 'Release' : 'Hold to\nSpeak'}
            </span>
          </button>
        )}

        {/* CLEAN-END: End button — no confirmation dialog */}
        <button
          style={styles.endButton}
          onClick={handleEnd}
          aria-label="End voice session"
        >
          End
        </button>
      </div>
    </div>
  );
}

export default VoiceSession;
