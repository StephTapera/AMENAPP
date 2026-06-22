/**
 * DiscernmentShareFlow.jsx — Opt-in sharing confirmation sheet
 *
 * Agent D — Discernment Surfacing
 * Renders a bottom sheet that lets users explicitly opt in to sharing their
 * Berean check result to a thread. Share is ALWAYS opt-in — nothing auto-shares.
 *
 * HARD CONSTRAINTS:
 * 1. Private-first: callShareFn only fires on explicit "Share" tap
 * 2. No red/green coloring anywhere
 * 3. No "FALSE/UNBIBLICAL" language
 * 4. Preview of DiscernmentCard is read-only (no share button inside preview)
 * 5. NeMo re-moderation note shown before share confirms
 */

import React, { useState } from 'react';
import './selahGlass.css';
import DiscernmentCard from './DiscernmentCard';

/**
 * DiscernmentShareFlow
 *
 * Props:
 *   check: DiscernmentCheck         — the check to potentially share
 *   onConfirmShare() → void         — called after callShareFn resolves
 *   onCancelShare() → void          — called when user taps "Keep Private"
 *   callShareFn: (checkId) => Promise<DiscernmentCheck>  — injected CF caller
 */
export default function DiscernmentShareFlow({
  check,
  onConfirmShare,
  onCancelShare,
  callShareFn,
}) {
  const [isSharing, setIsSharing] = useState(false);
  const [shareError, setShareError] = useState(null);

  async function handleShare() {
    if (isSharing) return;
    setIsSharing(true);
    setShareError(null);

    try {
      await callShareFn(check.id);
      setIsSharing(false);
      onConfirmShare?.();
    } catch (err) {
      setIsSharing(false);
      setShareError(
        err?.message ?? 'Unable to share right now. Your check remains private.'
      );
    }
  }

  return (
    // Overlay backdrop — traps focus context for the sheet
    <div
      className="selah-bottom-sheet-overlay"
      role="dialog"
      aria-modal="true"
      aria-label="Share Berean check confirmation"
      onClick={(e) => {
        // Dismiss on backdrop tap (treat as cancel)
        if (e.target === e.currentTarget) onCancelShare?.();
      }}
    >
      <div
        className="selah-bottom-sheet"
        style={{ paddingTop: 16 }}
      >
        {/* Drag handle */}
        <div className="selah-bottom-sheet-handle" aria-hidden="true" />

        {/* Title */}
        <p
          style={{
            margin: '0 0 6px 0',
            fontSize: 18,
            fontWeight: 700,
            color: '#0A0A0A',
            letterSpacing: -0.3,
          }}
        >
          Share Berean Check
        </p>

        {/* Body copy — explains what is shared; no verdict-about-person framing */}
        <p
          style={{
            margin: '0 0 20px 0',
            fontSize: 14,
            lineHeight: 1.6,
            color: '#3A3A3C',
          }}
        >
          This will make your Scripture check visible to other participants in
          this thread. The check shows which claims were assessed and what Scripture
          says — not a verdict about the person.
        </p>

        {/* Read-only preview of the check — share button suppressed inside preview */}
        <div
          style={{
            marginBottom: 16,
            pointerEvents: 'none',  // preview only, no interactions
            opacity: 0.92,
          }}
          aria-label="Preview of Berean check to be shared"
          role="img"
          aria-hidden="false"
        >
          <DiscernmentCard
            check={check}
            onShare={() => {}}      // no-op: share button inside preview is non-functional
            onDismiss={() => {}}    // no-op: dismiss inside preview is non-functional
            isSharing={false}
          />
        </div>

        {/* NeMo re-moderation notice */}
        <p
          style={{
            margin: '0 0 16px 0',
            fontSize: 12,
            color: '#AEAEB2',
            textAlign: 'center',
          }}
        >
          Content is reviewed before sharing
        </p>

        {/* Error state (non-blocking, stays private on error) */}
        {shareError && (
          <div
            className="selah-citation-block"
            style={{ marginBottom: 14 }}
            role="alert"
            aria-live="assertive"
          >
            <p style={{ margin: 0, fontSize: 13, color: '#3A3A3C' }}>
              {shareError}
            </p>
          </div>
        )}

        {/* Action buttons */}
        <div
          style={{
            display: 'flex',
            flexDirection: 'column',
            gap: 10,
          }}
        >
          {/* Primary: Share */}
          <button
            onClick={handleShare}
            disabled={isSharing}
            style={{
              width: '100%',
              minHeight: 50,
              borderRadius: 999,
              border: 'none',
              background: isSharing
                ? 'rgba(10,10,10,0.08)'
                : '#0A0A0A',
              color: isSharing ? '#8A8A8E' : '#FFFFFF',
              fontSize: 16,
              fontWeight: 600,
              cursor: isSharing ? 'default' : 'pointer',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: 8,
              transition: 'opacity 0.15s ease',
              fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif',
            }}
            aria-label={isSharing ? 'Sharing in progress' : 'Confirm share to thread'}
            aria-busy={isSharing}
          >
            {isSharing ? (
              <>
                <SharingSpinner />
                <span aria-live="polite">Sharing…</span>
              </>
            ) : (
              'Share'
            )}
          </button>

          {/* Secondary: Keep Private */}
          <button
            onClick={onCancelShare}
            disabled={isSharing}
            className="selah-glass-pill"
            style={{
              width: '100%',
              minHeight: 50,
              borderRadius: 999,
              justifyContent: 'center',
              fontSize: 16,
              fontWeight: 500,
              opacity: isSharing ? 0.45 : 1,
              cursor: isSharing ? 'default' : 'pointer',
            }}
            aria-label="Keep this Berean check private"
          >
            Keep Private
          </button>
        </div>

        {/* Safe area spacer for devices with home indicator */}
        <div style={{ height: 8 }} aria-hidden="true" />
      </div>
    </div>
  );
}

// ─── Spinner sub-component ────────────────────────────────────────────────────

function SharingSpinner() {
  return (
    <>
      <style>{`
        @keyframes selah-share-spin {
          to { transform: rotate(360deg); }
        }
        .selah-share-spinner {
          animation: selah-share-spin 0.75s linear infinite;
          flex-shrink: 0;
        }
      `}</style>
      <svg
        className="selah-share-spinner"
        width="16"
        height="16"
        viewBox="0 0 16 16"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        aria-hidden="true"
        focusable="false"
      >
        <circle
          cx="8" cy="8" r="6.5"
          stroke="rgba(255,255,255,0.25)"
          strokeWidth="1.6"
          fill="none"
        />
        <path
          d="M8 1.5A6.5 6.5 0 0 1 14.5 8"
          stroke="#FFFFFF"
          strokeWidth="1.6"
          strokeLinecap="round"
          fill="none"
        />
      </svg>
    </>
  );
}
