/**
 * SolidarityPresence.tsx
 * Phase 2B — Sabbath Surface UI
 * Date: 2026-06-07
 *
 * Renders a plain text solidarity message when others are also observing Sabbath.
 *
 * CRITICAL RULES:
 * - showCount from sabbathConfig is ALWAYS false — never render a number
 * - No counts, no "X people", no percentages, no comparisons of any kind
 * - If text is undefined or empty, renders nothing (null)
 * - Text is always tertiary color, centered, small font
 */

import React from 'react';
import { sabbathConfig } from '../contracts/SabbathConfig';
import { SabbathTokens } from './SabbathTokens';

interface SolidarityPresenceProps {
  text?: string;
}

// Guard: the config must permanently enforce showCount: false.
// This is a type-level invariant — sabbathConfig.solidarity.showCount is typed as `false`.
const _showCountInvariant: false = sabbathConfig.solidarity.showCount;
void _showCountInvariant; // used only to satisfy the type checker

const DEFAULT_TEXT = 'Others in your family are resting too';

export const SolidarityPresence: React.FC<SolidarityPresenceProps> = ({ text }) => {
  // Render nothing if text is undefined or empty string
  if (!sabbathConfig.solidarity.enabled) return null;
  if (text === undefined || text === '') return null;

  const resolvedText = text || DEFAULT_TEXT;

  const wrapperStyle: React.CSSProperties = {
    textAlign: 'center',
    padding: '0 24px',
  };

  const textStyle: React.CSSProperties = {
    fontFamily: SabbathTokens.fontStack,
    fontSize: '13px',
    fontWeight: 400,
    color: SabbathTokens.textTertiary,
    lineHeight: '1.4',
    margin: 0,
    // Never include any number, count, comparison, or metric
  };

  return (
    <div style={wrapperStyle} aria-live="polite">
      <p style={textStyle}>{resolvedText}</p>
    </div>
  );
};

export default SolidarityPresence;
