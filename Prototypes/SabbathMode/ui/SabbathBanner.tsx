/**
 * SabbathBanner.tsx
 * Phase 2B — Sabbath Surface UI
 * Date: 2026-06-07
 *
 * Thin, persistent top banner shown when the user is in the 'steppedOut' state.
 * Persists until the next Sabbath boundary — no close button.
 *
 * Props:
 * - steppedOutAt: Unix epoch ms when the user stepped out (not displayed to user;
 *   used by callers to track step-out time if needed)
 */

import React from 'react';
import { SabbathTokens } from './SabbathTokens';

interface SabbathBannerProps {
  steppedOutAt: number;
}

export const SabbathBanner: React.FC<SabbathBannerProps> = ({ steppedOutAt: _steppedOutAt }) => {
  // steppedOutAt is accepted for caller tracking; not displayed to the user.
  // No time-based text, no "X hours ago", no counts of any kind.

  const bannerStyle: React.CSSProperties = {
    position: 'fixed',
    top: 0,
    left: 0,
    right: 0,
    height: '32px',
    background: 'rgba(0,0,0,0.06)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 9999,
    // No close button — persists until next boundary
  };

  const textStyle: React.CSSProperties = {
    fontFamily: SabbathTokens.fontStack,
    fontSize: '12px',
    fontWeight: 400,
    color: SabbathTokens.textSecondary,
    letterSpacing: '0.01em',
    margin: 0,
    userSelect: 'none',
  };

  return (
    <div style={bannerStyle} role="status" aria-label="Sabbath step-out banner">
      <p style={textStyle}>You stepped out of Sabbath&nbsp;&middot;&nbsp;Returns next week</p>
    </div>
  );
};

export default SabbathBanner;
