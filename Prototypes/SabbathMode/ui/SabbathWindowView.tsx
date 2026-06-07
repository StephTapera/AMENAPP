/**
 * SabbathWindowView.tsx
 * Phase 2B — Sabbath Surface UI
 * Date: 2026-06-07
 *
 * The main full-screen view shown when Sabbath is active.
 * Composes SabbathSurfaceList, SolidarityPresence, and BlessAndCloseSheet.
 *
 * Layout (centered column, full screen):
 * 1. Small header — day of week in light gray
 * 2. White card (max-width 390px, ambient shadow):
 *    - Heading: "Today is a day for rest."
 *    - Subline: "The app is quiet. You don't have to be."
 *    - Divider
 *    - SabbathSurfaceList (8 entries)
 * 3. SolidarityPresence (if solidarityText is provided)
 * 4. "Step out of Sabbath" button — tertiary gray, small, understated
 *
 * BlessAndCloseSheet is rendered as an overlay and shown before any step-out
 * (sabbathConfig.stepOutPolicy.requiresConfirm is true).
 */

import React, { useState } from 'react';
import type { SabbathSurface } from '../contracts/SabbathTypes';
import { sabbathConfig } from '../contracts/SabbathConfig';
import { SabbathSurfaceList } from './SabbathSurfaceList';
import { SolidarityPresence } from './SolidarityPresence';
import { BlessAndCloseSheet } from './BlessAndCloseSheet';
import { SabbathTokens } from './SabbathTokens';

interface SabbathWindowViewProps {
  onSurfaceSelect: (surface: SabbathSurface) => void;
  onStepOut: () => void;
  solidarityText?: string;
}

/** Returns the current day of the week name (device-local). */
function getTodayLabel(): string {
  return new Date().toLocaleDateString('en-US', { weekday: 'long' });
}

export const SabbathWindowView: React.FC<SabbathWindowViewProps> = ({
  onSurfaceSelect,
  onStepOut,
  solidarityText,
}) => {
  const [showBlessSheet, setShowBlessSheet] = useState(false);

  const handleStepOutIntent = () => {
    if (sabbathConfig.stepOutPolicy.requiresConfirm) {
      setShowBlessSheet(true);
    } else {
      onStepOut();
    }
  };

  const handleSheetConfirm = () => {
    setShowBlessSheet(false);
    onStepOut();
    // Caller is responsible for calling enterStepOut(true) on the engine
  };

  const handleSheetDismiss = () => {
    setShowBlessSheet(false);
  };

  const pageStyle: React.CSSProperties = {
    minHeight: '100vh',
    background: SabbathTokens.pageBg,
    fontFamily: SabbathTokens.fontStack,
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'flex-start',
    padding: '56px 24px 48px',
    boxSizing: 'border-box',
    gap: '24px',
  };

  const dayLabelStyle: React.CSSProperties = {
    fontSize: '13px',
    fontWeight: 400,
    color: SabbathTokens.textTertiary,
    letterSpacing: '0.04em',
    textTransform: 'uppercase' as const,
    margin: 0,
    userSelect: 'none',
  };

  const cardStyle: React.CSSProperties = {
    background: SabbathTokens.cardBg,
    borderRadius: SabbathTokens.radiusCard,
    boxShadow: SabbathTokens.cardShadow,
    border: SabbathTokens.cardBorder,
    padding: '28px 20px 20px',
    width: '100%',
    maxWidth: '390px',
    display: 'flex',
    flexDirection: 'column',
    gap: '0',
  };

  const headingStyle: React.CSSProperties = {
    fontSize: '24px',
    fontWeight: 700,
    color: SabbathTokens.textPrimary,
    margin: '0 0 6px',
    lineHeight: '1.2',
  };

  const sublineStyle: React.CSSProperties = {
    fontSize: '15px',
    fontWeight: 400,
    color: SabbathTokens.textSecondary,
    margin: '0 0 20px',
    lineHeight: '1.45',
  };

  const dividerStyle: React.CSSProperties = {
    height: '1px',
    background: 'rgba(0,0,0,0.04)',
    margin: '0 0 16px',
  };

  const stepOutButtonStyle: React.CSSProperties = {
    fontFamily: SabbathTokens.fontStack,
    fontSize: '13px',
    fontWeight: 400,
    color: SabbathTokens.textTertiary,
    background: 'transparent',
    border: 'none',
    padding: '8px 16px',
    borderRadius: SabbathTokens.radiusPill,
    cursor: 'pointer',
    transition: 'opacity 0.15s ease',
    // Understated: small, tertiary, no fill, no border
  };

  return (
    <>
      <main style={pageStyle} aria-label="Sabbath mode">
        {/* 1. Day of week header */}
        <p style={dayLabelStyle} aria-label={`Today is ${getTodayLabel()}`}>
          {getTodayLabel()}
        </p>

        {/* 2. Main white card */}
        <section style={cardStyle} aria-label="Sabbath rest">
          <h1 style={headingStyle}>Today is a day for rest.</h1>
          <p style={sublineStyle}>The app is quiet. You don't have to be.</p>
          <div style={dividerStyle} aria-hidden="true" />

          {/* 8 allowed surfaces */}
          <SabbathSurfaceList onSurfaceSelect={onSurfaceSelect} />
        </section>

        {/* 3. Solidarity presence — renders nothing if text is undefined/empty */}
        <SolidarityPresence text={solidarityText} />

        {/* 4. Step-out button — tertiary, understated */}
        <button
          style={stepOutButtonStyle}
          onClick={handleStepOutIntent}
          type="button"
          aria-label="Step out of Sabbath for the rest of today"
        >
          Step out of Sabbath
        </button>
      </main>

      {/* Bless & Close confirmation sheet */}
      <BlessAndCloseSheet
        isOpen={showBlessSheet}
        onConfirm={handleSheetConfirm}
        onDismiss={handleSheetDismiss}
      />
    </>
  );
};

export default SabbathWindowView;
