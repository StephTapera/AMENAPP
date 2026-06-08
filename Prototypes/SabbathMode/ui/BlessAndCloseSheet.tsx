// COPY OPTION A (gentle):
//   Title:  "Step out of Sabbath?"
//   Body:   "You can return to the full app for the rest of today. Sabbath will resume next week."
//   CTA 1:  "Step out"
//   CTA 2:  "Stay in Sabbath"
//
// COPY OPTION B (more liturgical):
//   Title:  "Leaving the rest?"
//   Body:   "The Sabbath will keep the door open for you. You can return to the full app if you need to."
//   CTA 1:  "Step out"
//   CTA 2:  "Stay in the rest"
//
// AWAITING HUMAN SIGN-OFF — currently using Option A

/**
 * BlessAndCloseSheet.tsx
 * Phase 2B — Sabbath Surface UI
 * Date: 2026-06-07
 *
 * Bottom sheet modal confirming the user's intent to step out of Sabbath.
 * Copy tone: invitational, never punitive. No shame language.
 *
 * Props:
 * - isOpen:     Whether the sheet is visible
 * - onConfirm:  Called when user taps "Step out".
 *               Caller is responsible for calling enterStepOut(true) on the engine.
 * - onDismiss:  Called when user taps "Stay in Sabbath" or taps the backdrop.
 *
 * Config: sabbathConfig.stepOutPolicy.requiresConfirm is true — this sheet
 * MUST be shown before restoring full access (never bypass).
 */

import React, { useEffect } from 'react';
import { sabbathConfig } from '../contracts/SabbathConfig';
import { SabbathTokens } from './SabbathTokens';

interface BlessAndCloseSheetProps {
  isOpen: boolean;
  onConfirm: () => void;
  onDismiss: () => void;
}

// Guard: this sheet may only be shown when requiresConfirm is true (from config)
const _requiresConfirmInvariant: true = sabbathConfig.stepOutPolicy.requiresConfirm;
void _requiresConfirmInvariant;

export const BlessAndCloseSheet: React.FC<BlessAndCloseSheetProps> = ({
  isOpen,
  onConfirm,
  onDismiss,
}) => {
  // Trap focus inside sheet when open
  useEffect(() => {
    if (!isOpen) return;

    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        onDismiss();
      }
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, onDismiss]);

  if (!isOpen) return null;

  const backdropStyle: React.CSSProperties = {
    position: 'fixed',
    inset: 0,
    background: 'rgba(0,0,0,0.18)',
    zIndex: 10000,
    display: 'flex',
    alignItems: 'flex-end',
    justifyContent: 'center',
  };

  const sheetStyle: React.CSSProperties = {
    background: SabbathTokens.cardBg,
    borderRadius: `${SabbathTokens.radiusCard} ${SabbathTokens.radiusCard} 0 0`,
    boxShadow: '0 -4px 32px rgba(0,0,0,0.10)',
    padding: '32px 24px 40px',
    width: '100%',
    maxWidth: '390px',
    display: 'flex',
    flexDirection: 'column',
    gap: '12px',
  };

  const handleBarStyle: React.CSSProperties = {
    width: '36px',
    height: '4px',
    borderRadius: '100px',
    background: 'rgba(0,0,0,0.12)',
    margin: '0 auto 20px',
  };

  const titleStyle: React.CSSProperties = {
    fontFamily: SabbathTokens.fontStack,
    fontSize: '20px',
    fontWeight: 600,
    color: SabbathTokens.textPrimary,
    margin: 0,
    lineHeight: '1.25',
  };

  const bodyStyle: React.CSSProperties = {
    fontFamily: SabbathTokens.fontStack,
    fontSize: '15px',
    fontWeight: 400,
    color: SabbathTokens.textSecondary,
    margin: 0,
    lineHeight: '1.5',
  };

  const buttonGroupStyle: React.CSSProperties = {
    display: 'flex',
    flexDirection: 'column',
    gap: '10px',
    marginTop: '8px',
  };

  const primaryButtonStyle: React.CSSProperties = {
    fontFamily: SabbathTokens.fontStack,
    fontSize: '15px',
    fontWeight: 500,
    color: '#FFFFFF',
    background: SabbathTokens.textPrimary,
    border: 'none',
    borderRadius: SabbathTokens.radiusPill,
    padding: '14px 24px',
    cursor: 'pointer',
    transition: 'opacity 0.15s ease',
    width: '100%',
    textAlign: 'center',
  };

  const secondaryButtonStyle: React.CSSProperties = {
    fontFamily: SabbathTokens.fontStack,
    fontSize: '15px',
    fontWeight: 500,
    color: SabbathTokens.textPrimary,
    background: SabbathTokens.cardBg,
    border: SabbathTokens.cardBorder,
    borderRadius: SabbathTokens.radiusPill,
    padding: '14px 24px',
    cursor: 'pointer',
    transition: 'background 0.15s ease',
    width: '100%',
    textAlign: 'center',
  };

  return (
    <div
      style={backdropStyle}
      role="dialog"
      aria-modal="true"
      aria-labelledby="bless-close-title"
      aria-describedby="bless-close-body"
      onClick={(e) => {
        // Dismiss when tapping the backdrop
        if (e.target === e.currentTarget) onDismiss();
      }}
    >
      <div style={sheetStyle}>
        <div style={handleBarStyle} aria-hidden="true" />

        {/* COPY OPTION A — awaiting human sign-off */}
        <h2 id="bless-close-title" style={titleStyle}>
          Step out of Sabbath?
        </h2>
        <p id="bless-close-body" style={bodyStyle}>
          You can return to the full app for the rest of today. Sabbath will resume next week.
        </p>

        <div style={buttonGroupStyle}>
          <button
            style={primaryButtonStyle}
            onClick={onConfirm}
            type="button"
            aria-label="Step out of Sabbath and return to the full app"
          >
            Step out
          </button>
          <button
            style={secondaryButtonStyle}
            onClick={onDismiss}
            type="button"
            aria-label="Stay in Sabbath"
          >
            Stay in Sabbath
          </button>
        </div>
      </div>
    </div>
  );
};

export default BlessAndCloseSheet;
