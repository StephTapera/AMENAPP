/**
 * DiscernmentAction.jsx — "Check against Scripture" trigger pill
 *
 * Agent D — Discernment Surfacing
 * Universal entry point for the Berean discernment check.
 * Can be placed on: comment, post, space_message, pasted_text, selah_note, verse.
 *
 * This component does NOT render DiscernmentCard — it calls back with the result.
 * The parent is responsible for rendering DiscernmentCard with the returned check.
 *
 * HARD CONSTRAINTS:
 * 1. Nothing auto-shares — this component only fetches, never shares
 * 2. No red/green pass/fail coloring
 * 3. Payload always sends visibility: 'private'
 */

import React, { useState } from 'react';
import './selahGlass.css';

// ─── Internal state machine ───────────────────────────────────────────────────
const STATE = {
  IDLE:    'idle',
  LOADING: 'loading',
  ERROR:   'error',
};

const ERROR_DISPLAY_MS = 3500;

/**
 * DiscernmentAction
 *
 * Props:
 *   sourceType: DiscernmentSourceType
 *   sourceRef: string | null
 *   inputText: string               — the text to check (already visible to user)
 *   onCheckStarted(checkId: string) → void
 *   onCheckComplete(check: DiscernmentCheck) → void
 *   onCheckError(error: string) → void
 *   callDiscernmentFn: (payload) => Promise<DiscernmentCheck>  — injected CF caller
 */
export default function DiscernmentAction({
  sourceType,
  sourceRef,
  inputText,
  onCheckStarted,
  onCheckComplete,
  onCheckError,
  callDiscernmentFn,
}) {
  const [state, setState] = useState(STATE.IDLE);
  const [errorMessage, setErrorMessage] = useState(null);

  async function handleTap() {
    if (state === STATE.LOADING) return;

    setState(STATE.LOADING);
    setErrorMessage(null);

    // Generate a provisional check ID for the caller to track optimistic UI
    const provisionalId = `dc-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
    onCheckStarted?.(provisionalId);

    try {
      const result = await callDiscernmentFn({
        inputText,
        sourceType,
        sourceRef,
        visibility: 'private', // HARD CONSTRAINT: always private-first
      });

      setState(STATE.IDLE);
      onCheckComplete?.(result);
    } catch (err) {
      const msg =
        err?.message ?? 'Unable to check against Scripture right now. Please try again.';
      setState(STATE.ERROR);
      setErrorMessage(msg);
      onCheckError?.(msg);

      // Auto-reset error display after a short delay
      setTimeout(() => {
        setState(STATE.IDLE);
        setErrorMessage(null);
      }, ERROR_DISPLAY_MS);
    }
  }

  const isLoading = state === STATE.LOADING;
  const isError   = state === STATE.ERROR;

  return (
    <button
      className="selah-glass-pill"
      onClick={handleTap}
      disabled={isLoading}
      aria-label="Check this text against Scripture using the Berean method"
      aria-busy={isLoading}
      aria-live="polite"
      style={{
        cursor: isLoading ? 'default' : 'pointer',
        opacity: isLoading ? 0.7 : 1,
        // Error state: brief visual differentiation using opacity shift only — no red coloring
        filter: isError ? 'none' : undefined,
        minWidth: 44,
        minHeight: 44,
      }}
    >
      {isLoading ? (
        <>
          <Spinner />
          <span>Checking…</span>
        </>
      ) : isError ? (
        <>
          <ExclamationIcon />
          <span style={{ fontSize: 13 }}>{errorMessage ?? 'Unable to check — try again'}</span>
        </>
      ) : (
        <>
          <BookmarkCrossIcon />
          <span>Check against Scripture</span>
        </>
      )}
    </button>
  );
}

// ─── Icon sub-components (SF Symbols-style, inline SVG) ───────────────────────

/** Bookmark + cross icon representing Scripture check action. */
function BookmarkCrossIcon() {
  return (
    <svg
      width="15"
      height="17"
      viewBox="0 0 15 17"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      aria-hidden="true"
      focusable="false"
      style={{ flexShrink: 0 }}
    >
      {/* Bookmark outline */}
      <path
        d="M2 1.5h11a1 1 0 0 1 1 1V15l-6.5-3.5L1 15V2.5a1 1 0 0 1 1-1Z"
        stroke="#0A0A0A"
        strokeWidth="1.3"
        strokeLinejoin="round"
        fill="none"
      />
      {/* Cross inside bookmark */}
      <line x1="7.5" y1="4" x2="7.5" y2="9" stroke="#0A0A0A" strokeWidth="1.3" strokeLinecap="round" />
      <line x1="5"   y1="6.5" x2="10" y2="6.5" stroke="#0A0A0A" strokeWidth="1.3" strokeLinecap="round" />
    </svg>
  );
}

/** Animated spinner — purely CSS, no red/green. */
function Spinner() {
  return (
    <>
      <style>{`
        @keyframes selah-spin {
          to { transform: rotate(360deg); }
        }
        .selah-action-spinner {
          animation: selah-spin 0.75s linear infinite;
          flex-shrink: 0;
        }
      `}</style>
      <svg
        className="selah-action-spinner"
        width="14"
        height="14"
        viewBox="0 0 14 14"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        aria-hidden="true"
        focusable="false"
      >
        <circle
          cx="7" cy="7" r="5.5"
          stroke="rgba(10,10,10,0.2)"
          strokeWidth="1.5"
          fill="none"
        />
        <path
          d="M7 1.5A5.5 5.5 0 0 1 12.5 7"
          stroke="#0A0A0A"
          strokeWidth="1.5"
          strokeLinecap="round"
          fill="none"
        />
      </svg>
    </>
  );
}

/** Brief error indicator — neutral styling, no red. */
function ExclamationIcon() {
  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 14 14"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      aria-hidden="true"
      focusable="false"
      style={{ flexShrink: 0, opacity: 0.7 }}
    >
      <circle cx="7" cy="7" r="6" stroke="#0A0A0A" strokeWidth="1.3" fill="none" />
      <line x1="7" y1="4" x2="7" y2="7.5" stroke="#0A0A0A" strokeWidth="1.3" strokeLinecap="round" />
      <circle cx="7" cy="9.5" r="0.7" fill="#0A0A0A" />
    </svg>
  );
}
