/**
 * ReEntryDigestView.tsx
 * Phase 2B — Sabbath Surface UI
 * Date: 2026-06-07
 *
 * Shown exactly once at re-entry after Sabbath (sabbathConfig.digest.showOnce = true).
 * Presents a capped digest of content from the Sabbath window, plus a reflection prompt.
 *
 * CRITICAL RULES:
 * - Maximum 6 items (sabbathConfig.digest.maxItems — server-enforced, UI respects it)
 * - NO infinite catch-up scroll
 * - NO unread counts
 * - NO "you missed X things" language
 * - Items are shown as simple tappable links using item.deeplink
 *
 * Props:
 * - digest:               SabbathDigest from the server
 * - onReflectionSubmit:   Called with the user's reflection text, then onDismiss fires
 * - onDismiss:            Called after submission or if user skips
 */

import React, { useState } from 'react';
import type { SabbathDigest } from '../contracts/SabbathModels';
import { sabbathConfig } from '../contracts/SabbathConfig';
import { SabbathTokens } from './SabbathTokens';

interface ReEntryDigestViewProps {
  digest: SabbathDigest;
  onReflectionSubmit: (body: string) => void;
  onDismiss: () => void;
}

// Guard: UI respects the server-enforced cap — never show more than maxItems
const MAX_ITEMS = sabbathConfig.digest.maxItems; // 6

export const ReEntryDigestView: React.FC<ReEntryDigestViewProps> = ({
  digest,
  onReflectionSubmit,
  onDismiss,
}) => {
  const [reflectionText, setReflectionText] = useState('');

  const handleContinue = () => {
    onReflectionSubmit(reflectionText.trim());
    onDismiss();
  };

  const cappedItems = digest.items.slice(0, MAX_ITEMS);

  const pageStyle: React.CSSProperties = {
    minHeight: '100vh',
    background: SabbathTokens.pageBg,
    fontFamily: SabbathTokens.fontStack,
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'flex-start',
    padding: '48px 24px 40px',
    boxSizing: 'border-box',
  };

  const cardStyle: React.CSSProperties = {
    background: SabbathTokens.cardBg,
    borderRadius: SabbathTokens.radiusCard,
    boxShadow: SabbathTokens.cardShadow,
    border: SabbathTokens.cardBorder,
    padding: '28px 24px',
    width: '100%',
    maxWidth: '390px',
    display: 'flex',
    flexDirection: 'column',
    gap: '20px',
  };

  const summaryLineStyle: React.CSSProperties = {
    fontSize: '17px',
    fontWeight: 500,
    color: SabbathTokens.textPrimary,
    margin: 0,
    lineHeight: '1.4',
  };

  const sectionLabelStyle: React.CSSProperties = {
    fontSize: '12px',
    fontWeight: 500,
    color: SabbathTokens.textTertiary,
    letterSpacing: '0.06em',
    textTransform: 'uppercase' as const,
    margin: 0,
  };

  const itemsListStyle: React.CSSProperties = {
    display: 'flex',
    flexDirection: 'column',
    gap: '2px',
    margin: 0,
    padding: 0,
    listStyle: 'none',
  };

  const dividerStyle: React.CSSProperties = {
    height: '1px',
    background: 'rgba(0,0,0,0.04)',
    margin: '0 -24px',
  };

  const reflectionPromptStyle: React.CSSProperties = {
    fontSize: '15px',
    fontWeight: 500,
    color: SabbathTokens.textPrimary,
    margin: 0,
    lineHeight: '1.4',
  };

  const textareaStyle: React.CSSProperties = {
    fontFamily: SabbathTokens.fontStack,
    fontSize: '15px',
    fontWeight: 400,
    color: SabbathTokens.textPrimary,
    background: 'rgba(0,0,0,0.04)',
    border: 'none',
    borderRadius: SabbathTokens.radiusInner,
    padding: '12px 14px',
    resize: 'none',
    width: '100%',
    boxSizing: 'border-box',
    lineHeight: '1.5',
    outline: 'none',
    minHeight: '72px',
  };

  const continueButtonStyle: React.CSSProperties = {
    fontFamily: SabbathTokens.fontStack,
    fontSize: '15px',
    fontWeight: 500,
    color: '#FFFFFF',
    background: SabbathTokens.textPrimary,
    border: 'none',
    borderRadius: SabbathTokens.radiusPill,
    padding: '14px 24px',
    cursor: 'pointer',
    width: '100%',
    textAlign: 'center',
    marginTop: '4px',
  };

  return (
    <div style={pageStyle}>
      <div style={cardStyle}>
        {/* Header */}
        <p style={summaryLineStyle}>{digest.summaryLine}</p>

        {/* Digest items — capped at maxItems, no counts, no "you missed X" */}
        {cappedItems.length > 0 && (
          <div>
            <p style={{ ...sectionLabelStyle, marginBottom: '12px' }}>While you rested</p>
            <ul style={itemsListStyle} aria-label="Content from your Sabbath">
              {cappedItems.map((item, idx) => (
                <li key={idx}>
                  <DigestItemRow label={item.label} deeplink={item.deeplink} />
                </li>
              ))}
            </ul>
          </div>
        )}

        <div style={dividerStyle} aria-hidden="true" />

        {/* Reflection */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
          <p style={reflectionPromptStyle}>One thought before you dive back in</p>
          <textarea
            style={textareaStyle}
            placeholder="Your reflection stays private..."
            value={reflectionText}
            onChange={(e) => setReflectionText(e.target.value)}
            aria-label="Private reflection"
            rows={3}
          />
        </div>

        <button
          style={continueButtonStyle}
          onClick={handleContinue}
          type="button"
          aria-label="Continue to the full app"
        >
          Continue
        </button>
      </div>
    </div>
  );
};

interface DigestItemRowProps {
  label: string;
  deeplink: string;
}

const DigestItemRow: React.FC<DigestItemRowProps> = ({ label, deeplink }) => {
  const [hovered, setHovered] = useState(false);

  const rowStyle: React.CSSProperties = {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    padding: '9px 10px',
    borderRadius: SabbathTokens.radiusInner,
    background: hovered ? 'rgba(0,0,0,0.03)' : 'transparent',
    transition: 'background 0.15s ease',
    cursor: 'pointer',
    textDecoration: 'none',
  };

  const labelStyle: React.CSSProperties = {
    fontFamily: SabbathTokens.fontStack,
    fontSize: '14px',
    fontWeight: 400,
    color: SabbathTokens.textPrimary,
    margin: 0,
    flex: 1,
    minWidth: 0,
    // Never bold or highlighted — equal weight, no ranking implied
  };

  const chevronStyle: React.CSSProperties = {
    color: SabbathTokens.textTertiary,
    opacity: 0.5,
    flexShrink: 0,
  };

  return (
    <a
      href={deeplink}
      style={rowStyle}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      aria-label={label}
    >
      <p style={labelStyle}>{label}</p>
      <span style={chevronStyle} aria-hidden="true">
        <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
          <path d="M4 2.5l3.5 3.5L4 9.5" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </span>
    </a>
  );
};

export default ReEntryDigestView;
