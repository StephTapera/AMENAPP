/**
 * scheduledStyles.ts — AMEN Connected Intelligence v1, Phase 2 (Agent E)
 *
 * Liquid Glass white/light styles for the Scheduled Actions surface.
 * Tokens imported from the FROZEN Berean contracts — never redefined.
 * FORBIDDEN: cosmic-dark, gold #C9A84C/#FFD97D, purple #7B68EE, Cormorant Garamond.
 */

import React from 'react';
import { tokens } from '../../berean/contracts';

const FONT =
  '-apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", "Helvetica Neue", Arial, sans-serif';

export const s = {
  screen: {
    minHeight: '100vh',
    backgroundColor: tokens.bg,
    fontFamily: FONT,
    paddingBottom: 48,
    color: tokens.text,
  } as React.CSSProperties,

  header: {
    padding: '24px 20px 4px 20px',
  } as React.CSSProperties,

  pageTitle: {
    fontSize: 28,
    fontWeight: 700,
    color: tokens.text,
    margin: 0,
    letterSpacing: -0.5,
  } as React.CSSProperties,

  pageSub: {
    fontSize: 14,
    color: tokens.textSub,
    margin: '6px 0 0 0',
    lineHeight: 1.45,
  } as React.CSSProperties,

  section: { margin: '20px 16px 0 16px' } as React.CSSProperties,

  sectionTitle: {
    fontSize: 12,
    fontWeight: 600,
    color: tokens.textSub,
    textTransform: 'uppercase' as const,
    letterSpacing: 0.6,
    marginBottom: 8,
    paddingLeft: 4,
  } as React.CSSProperties,

  card: {
    backgroundColor: tokens.card,
    borderRadius: tokens.radius,
    boxShadow: tokens.shadow,
    overflow: 'hidden',
  } as React.CSSProperties,

  pad: { padding: '16px 18px' } as React.CSSProperties,

  rowDivider: { borderTop: `1px solid ${tokens.divider}` } as React.CSSProperties,

  itemTitle: {
    fontSize: 16,
    fontWeight: 600,
    color: tokens.text,
    margin: 0,
  } as React.CSSProperties,

  itemSub: {
    fontSize: 13,
    color: tokens.textSub,
    margin: '4px 0 0 0',
    lineHeight: 1.45,
  } as React.CSSProperties,

  // Liquid-glass pill — frosted light chip, never gold/purple.
  pill: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: 4,
    fontSize: 11,
    fontWeight: 600,
    padding: '3px 9px',
    borderRadius: 999,
    backgroundColor: 'rgba(0,0,0,0.05)',
    color: tokens.textSub,
    letterSpacing: 0.2,
  } as React.CSSProperties,

  pillAccent: {
    backgroundColor: 'rgba(0,122,255,0.10)',
    color: tokens.accent,
  } as React.CSSProperties,

  pillWarn: {
    backgroundColor: 'rgba(196,79,62,0.10)',
    color: '#B23A2C',
  } as React.CSSProperties,

  pillCare: {
    backgroundColor: 'rgba(0,122,255,0.08)',
    color: '#0A6CCF',
  } as React.CSSProperties,

  // Primary action button — iOS blue, used sparingly.
  primaryBtn: {
    appearance: 'none' as const,
    border: 'none',
    borderRadius: 14,
    backgroundColor: tokens.accent,
    color: '#FFFFFF',
    fontSize: 15,
    fontWeight: 600,
    padding: '12px 18px',
    cursor: 'pointer',
    fontFamily: FONT,
  } as React.CSSProperties,

  secondaryBtn: {
    appearance: 'none' as const,
    border: `1px solid ${tokens.divider}`,
    borderRadius: 14,
    backgroundColor: tokens.card,
    color: tokens.text,
    fontSize: 15,
    fontWeight: 600,
    padding: '12px 18px',
    cursor: 'pointer',
    fontFamily: FONT,
  } as React.CSSProperties,

  ghostBtn: {
    appearance: 'none' as const,
    border: 'none',
    background: 'none',
    color: tokens.accent,
    fontSize: 14,
    fontWeight: 600,
    cursor: 'pointer',
    padding: '6px 4px',
    fontFamily: FONT,
  } as React.CSSProperties,

  dangerGhostBtn: {
    appearance: 'none' as const,
    border: 'none',
    background: 'none',
    color: '#B23A2C',
    fontSize: 14,
    fontWeight: 600,
    cursor: 'pointer',
    padding: '6px 4px',
    fontFamily: FONT,
  } as React.CSSProperties,

  input: {
    width: '100%',
    boxSizing: 'border-box' as const,
    border: `1px solid ${tokens.divider}`,
    borderRadius: 14,
    padding: '12px 14px',
    fontSize: 15,
    fontFamily: FONT,
    color: tokens.text,
    backgroundColor: '#FBFBFA',
    outline: 'none',
    resize: 'none' as const,
  } as React.CSSProperties,

  // Disabled / pending-review banner — clearly informative, not a dead button.
  pendingBanner: {
    backgroundColor: '#FFFFFF',
    border: `1px solid ${tokens.divider}`,
    borderRadius: tokens.radius,
    boxShadow: tokens.shadow,
    padding: '20px 18px',
    margin: '20px 16px 0 16px',
  } as React.CSSProperties,

  pendingTitle: {
    fontSize: 17,
    fontWeight: 700,
    color: tokens.text,
    margin: '0 0 6px 0',
  } as React.CSSProperties,

  pendingBody: {
    fontSize: 14,
    color: tokens.textSub,
    margin: 0,
    lineHeight: 1.5,
  } as React.CSSProperties,

  // Dry-run "would have" card — visibly provisional.
  dryRunCard: {
    backgroundColor: '#F7FAFF',
    border: '1px dashed rgba(0,122,255,0.35)',
    borderRadius: 16,
    padding: '14px 16px',
    margin: '10px 0 0 0',
  } as React.CSSProperties,

  dryRunLabel: {
    fontSize: 11,
    fontWeight: 700,
    letterSpacing: 0.4,
    textTransform: 'uppercase' as const,
    color: tokens.accent,
    margin: '0 0 4px 0',
  } as React.CSSProperties,

  // Run-failed strip — never silent, never fabricated.
  failedStrip: {
    backgroundColor: '#FDF3F1',
    border: '1px solid rgba(178,58,44,0.30)',
    borderRadius: 16,
    padding: '12px 14px',
    margin: '10px 0 0 0',
  } as React.CSSProperties,

  failedLabel: {
    fontSize: 11,
    fontWeight: 700,
    letterSpacing: 0.4,
    textTransform: 'uppercase' as const,
    color: '#B23A2C',
    margin: '0 0 4px 0',
  } as React.CSSProperties,

  emptyWrap: {
    textAlign: 'center' as const,
    padding: '48px 28px',
    color: tokens.textSub,
  } as React.CSSProperties,

  emptyTitle: {
    fontSize: 17,
    fontWeight: 600,
    color: tokens.text,
    margin: '12px 0 6px 0',
  } as React.CSSProperties,

  templateRow: {
    display: 'flex',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: 12,
    padding: '14px 16px',
    cursor: 'pointer',
  } as React.CSSProperties,

  modalScrim: {
    position: 'fixed' as const,
    inset: 0,
    backgroundColor: 'rgba(0,0,0,0.28)',
    display: 'flex',
    alignItems: 'flex-end',
    justifyContent: 'center',
    zIndex: 1000,
  } as React.CSSProperties,

  sheet: {
    width: '100%',
    maxWidth: 520,
    backgroundColor: tokens.bg,
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    maxHeight: '92vh',
    overflowY: 'auto' as const,
    paddingBottom: 24,
  } as React.CSSProperties,

  errorText: {
    fontSize: 13,
    color: '#B23A2C',
    margin: '8px 0 0 0',
  } as React.CSSProperties,

  spinnerWrap: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    padding: '64px 0',
    color: tokens.textSub,
    fontSize: 15,
  } as React.CSSProperties,
};
