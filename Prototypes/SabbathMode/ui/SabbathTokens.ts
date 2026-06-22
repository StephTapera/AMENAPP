/**
 * SabbathTokens.ts
 * Phase 2B — Sabbath Surface UI
 * Date: 2026-06-07
 *
 * Design token constants for all Sabbath Mode UI components.
 * All Phase 2B components import tokens from here — never hardcode values inline.
 *
 * BANNED (any of these in any UI file = reject):
 * - #C9A84C or #FFD97D (gold)
 * - #7B68EE or any purple
 * - Any dark gradient (dark bg + gradient overlay)
 * - Cormorant Garamond or any serif font
 * - Any "cosmic" or "night sky" visual
 * - Streak counters, unread counts, badges, scores
 * - Any comparative metric ("X others", "47 waiting", "3-day streak")
 */

export const SabbathTokens = {
  pageBg: '#F7F7F7',
  cardBg: '#FFFFFF',
  dividerBg: 'rgba(0,0,0,0.04)',
  cardShadow: '0 2px 20px rgba(0,0,0,0.08)',
  cardBorder: '1px solid rgba(0,0,0,0.06)',
  textPrimary: '#000000',
  textSecondary: '#3C3C3C',
  textTertiary: '#6B6B6B',
  radiusCard: '16px',
  radiusInner: '12px',
  radiusPill: '100px',
  fontStack: "-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif",
} as const;
