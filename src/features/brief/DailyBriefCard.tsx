/**
 * DailyBriefCard.tsx — AMEN Connected Intelligence v1, Daily Brief home card.
 * Agent B (Daily Brief).
 *
 * Pull-based home card: generated on open (one-per-day cache, server-side). NEVER
 * a push notification. Renders sections per BriefSection, each item a ContextItem
 * with a pointer back to source. Hard 9-item cap (enforced server + client).
 *
 * Tone: matter-of-fact warmth. ZERO guilt framing — no "you missed", "streak",
 * "X days since". Connector-sourced sections render ONLY when the grant included
 * the daily_brief surface (server returns them or omits them; the client never
 * shows a locked teaser).
 *
 * SIX UI STATES (all distinct, all wired to real handlers):
 *   1. loading   — first fetch in flight
 *   2. ready     — card with sections + items
 *   3. empty     — generated, but nothing to surface today (calm, no guilt)
 *   4. sabbath   — rest-framing card; safety surfaces still reachable
 *   5. error     — fetch failed; retry handler wired
 *   6. minor     — Amen-native items only (handled by content; banner shown)
 *  + cap-degraded — non-blocking note when candidates exceeded the 9-cap
 *
 * Design: Liquid Glass white/light, tokens from src/berean/contracts.ts only.
 * FORBIDDEN: cosmic-dark, gold #C9A84C/#FFD97D, purple #7B68EE, Cormorant Garamond.
 */

import React, { useCallback, useEffect, useState } from 'react';
import { tokens } from '../../berean/contracts';
import type { BriefCard, BriefSection, ContextItem } from '../connectedIntelligence.contracts';
import { fetchDailyBrief, totalItemCount, type BriefResult } from './briefService';

// ─────────────────────────────────────────────────────────────────────────────
// PROPS
// ─────────────────────────────────────────────────────────────────────────────

export interface DailyBriefCardProps {
  /** Authenticated user id (used for accessibility labelling + analytics only). */
  userId: string;
  /**
   * Whether this account is minor-scoped. Passed for the banner; the SERVER is the
   * authority that strips connector data. Defaults to false.
   */
  minorScoped?: boolean;
  /**
   * Invoked when the user taps an item — receives the ContextItem pointer (deep
   * link back to source). Host app routes it. Required (no stubs).
   */
  onOpenPointer: (pointer: string, item: ContextItem) => void;
  /** Invoked when the user taps a safety/support surface in the Sabbath/rest card. */
  onOpenSafety: () => void;
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION PRESENTATION
// ─────────────────────────────────────────────────────────────────────────────

const SECTION_META: Record<BriefSection, { icon: string; label: string }> = {
  prayer_updates:             { icon: '🙏', label: 'Prayer' },
  messages_needing_attention: { icon: '💬', label: 'Waiting on you' },
  events:                     { icon: '📅', label: 'Coming up' },
  community:                  { icon: '👥', label: 'Your groups' },
  follow_ups:                 { icon: '↩︎', label: 'To return to' },
  saved_verse:                { icon: '✝', label: 'Saved verse' },
};

// ─────────────────────────────────────────────────────────────────────────────
// STYLES — white/light Liquid Glass. Tokens only; no forbidden colors.
// ─────────────────────────────────────────────────────────────────────────────

const styles = {
  card: {
    backgroundColor: tokens.card,
    borderRadius: tokens.radius,
    boxShadow: tokens.shadow,
    padding: '20px 18px',
    fontFamily:
      '-apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", system-ui, sans-serif',
    color: tokens.text,
    boxSizing: 'border-box' as const,
  },
  header: {
    display: 'flex',
    alignItems: 'baseline',
    justifyContent: 'space-between',
    marginBottom: 4,
  },
  title: {
    fontSize: 20,
    fontWeight: 700,
    letterSpacing: -0.3,
    color: tokens.text,
    margin: 0,
  },
  refreshButton: {
    background: 'transparent',
    border: 'none',
    color: tokens.accent,
    fontSize: 14,
    fontWeight: 600,
    cursor: 'pointer',
    fontFamily: 'inherit',
    padding: '4px 6px',
  } as React.CSSProperties,
  intro: {
    fontSize: 14,
    color: tokens.textSub,
    lineHeight: 1.5,
    margin: '2px 0 16px',
  },
  minorBanner: {
    backgroundColor: '#EAF4FF',
    border: `1px solid ${tokens.accent}33`,
    borderRadius: 12,
    padding: '10px 12px',
    marginBottom: 14,
    fontSize: 13,
    color: tokens.text,
    fontWeight: 500,
  },
  capNote: {
    fontSize: 12,
    color: tokens.textSub,
    marginTop: 12,
    lineHeight: 1.5,
  },
  sectionWrap: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 18,
  },
  section: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 8,
  },
  sectionHeader: {
    display: 'flex',
    alignItems: 'center',
    gap: 7,
  },
  sectionIcon: { fontSize: 14, lineHeight: 1 },
  sectionLabel: {
    fontSize: 12,
    fontWeight: 600,
    color: tokens.textSub,
    textTransform: 'uppercase' as const,
    letterSpacing: 0.4,
  },
  item: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 10,
    width: '100%',
    textAlign: 'left' as const,
    background: tokens.bg,
    border: 'none',
    borderRadius: 12,
    padding: '12px 12px',
    cursor: 'pointer',
    fontFamily: 'inherit',
    color: tokens.text,
  } as React.CSSProperties,
  itemText: {
    fontSize: 14,
    lineHeight: 1.45,
    color: tokens.text,
    flex: 1,
  },
  itemSource: {
    fontSize: 11,
    color: tokens.textSub,
    flexShrink: 0,
  },
  chevron: {
    color: tokens.textSub,
    fontSize: 15,
    flexShrink: 0,
  },
  divider: {
    height: 1,
    backgroundColor: tokens.divider,
    border: 'none',
    margin: '4px 0',
  },
  // Sabbath / rest
  restWrap: { textAlign: 'center' as const, padding: '8px 4px' },
  restTitle: { fontSize: 18, fontWeight: 700, color: tokens.text, margin: '0 0 6px' },
  restBody: { fontSize: 14, color: tokens.textSub, lineHeight: 1.55, margin: '0 0 16px' },
  safetyButton: {
    backgroundColor: tokens.accent,
    color: '#FFFFFF',
    border: 'none',
    borderRadius: 12,
    padding: '11px 18px',
    fontSize: 14,
    fontWeight: 600,
    cursor: 'pointer',
    fontFamily: 'inherit',
  } as React.CSSProperties,
  // Empty
  emptyWrap: { textAlign: 'center' as const, padding: '12px 8px' },
  emptyTitle: { fontSize: 16, fontWeight: 600, color: tokens.text, margin: '0 0 6px' },
  emptyBody: { fontSize: 14, color: tokens.textSub, lineHeight: 1.5, margin: 0 },
  // Error
  errorWrap: { textAlign: 'center' as const, padding: '12px 8px' },
  errorBody: { fontSize: 14, color: tokens.text, lineHeight: 1.5, margin: '0 0 14px' },
  retryButton: {
    backgroundColor: tokens.accent,
    color: '#FFFFFF',
    border: 'none',
    borderRadius: 12,
    padding: '10px 20px',
    fontSize: 14,
    fontWeight: 600,
    cursor: 'pointer',
    fontFamily: 'inherit',
  } as React.CSSProperties,
  // Loading skeleton
  skelLine: {
    height: 14,
    borderRadius: 7,
    backgroundColor: tokens.divider,
    marginBottom: 12,
  },
  skelItem: {
    height: 48,
    borderRadius: 12,
    backgroundColor: tokens.bg,
    marginBottom: 10,
  },
} satisfies Record<string, React.CSSProperties>;

// ─────────────────────────────────────────────────────────────────────────────
// SUB-VIEWS
// ─────────────────────────────────────────────────────────────────────────────

function CardShell({
  title,
  onRefresh,
  refreshing,
  children,
}: {
  title: string;
  onRefresh?: () => void;
  refreshing?: boolean;
  children: React.ReactNode;
}): JSX.Element {
  return (
    <section style={styles.card} aria-label="Daily brief">
      <div style={styles.header}>
        <h2 style={styles.title}>{title}</h2>
        {onRefresh && (
          <button
            type="button"
            style={styles.refreshButton}
            onClick={onRefresh}
            disabled={refreshing}
            aria-label="Refresh brief"
          >
            {refreshing ? 'Refreshing…' : 'Refresh'}
          </button>
        )}
      </div>
      {children}
    </section>
  );
}

function LoadingState(): JSX.Element {
  return (
    <CardShell title="Today">
      <div role="status" aria-live="polite" aria-busy="true">
        <div style={{ ...styles.skelLine, width: '60%' }} />
        <div style={styles.skelItem} />
        <div style={styles.skelItem} />
        <div style={{ ...styles.skelItem, width: '85%' }} />
        <span style={{ position: 'absolute', left: -9999 }}>Loading your brief…</span>
      </div>
    </CardShell>
  );
}

function EmptyState({ onRefresh, refreshing }: { onRefresh: () => void; refreshing: boolean }): JSX.Element {
  return (
    <CardShell title="Today" onRefresh={onRefresh} refreshing={refreshing}>
      <div style={styles.emptyWrap}>
        <p style={styles.emptyTitle}>You're all caught up.</p>
        <p style={styles.emptyBody}>
          Nothing needs your attention right now. Enjoy the quiet.
        </p>
      </div>
    </CardShell>
  );
}

function ErrorState({ message, onRetry, retrying }: { message: string; onRetry: () => void; retrying: boolean }): JSX.Element {
  return (
    <CardShell title="Today">
      <div style={styles.errorWrap} role="alert">
        <p style={styles.errorBody}>{message}</p>
        <button type="button" style={styles.retryButton} onClick={onRetry} disabled={retrying} aria-label="Try again">
          {retrying ? 'Trying…' : 'Try again'}
        </button>
      </div>
    </CardShell>
  );
}

function SabbathState({ card, onOpenSafety }: { card: BriefCard; onOpenSafety: () => void }): JSX.Element {
  // Crisis/safety items survive Sabbath — surface them if present.
  const safetyItems = card.sections.flatMap((s) => s.items);
  return (
    <CardShell title="Rest">
      <div style={styles.restWrap}>
        <p style={styles.restTitle}>It's a day of rest.</p>
        <p style={styles.restBody}>
          The brief is paused today so you can step back. It'll be here again tomorrow.
        </p>
        {safetyItems.length > 0 && (
          <button type="button" style={styles.safetyButton} onClick={onOpenSafety} aria-label="Open support">
            Support is here if you need it
          </button>
        )}
      </div>
    </CardShell>
  );
}

function ItemRow({
  item,
  onOpenPointer,
}: {
  item: ContextItem;
  onOpenPointer: (pointer: string, item: ContextItem) => void;
}): JSX.Element {
  const hasPointer = typeof item.pointer === 'string' && item.pointer.length > 0;
  const sourceLabel = item.source === 'amen_native' ? null : item.source;

  const handle = () => {
    if (hasPointer) onOpenPointer(item.pointer as string, item);
  };

  return (
    <button
      type="button"
      style={{ ...styles.item, cursor: hasPointer ? 'pointer' : 'default' }}
      onClick={handle}
      disabled={!hasPointer}
      aria-label={item.payload}
    >
      <span style={styles.itemText}>{item.payload}</span>
      {sourceLabel && <span style={styles.itemSource} aria-hidden="true">{sourceLabel}</span>}
      {hasPointer && <span style={styles.chevron} aria-hidden="true">›</span>}
    </button>
  );
}

function ReadyState({
  result,
  minorScoped,
  onOpenPointer,
  onRefresh,
  refreshing,
}: {
  result: BriefResult;
  minorScoped: boolean;
  onOpenPointer: (pointer: string, item: ContextItem) => void;
  onRefresh: () => void;
  refreshing: boolean;
}): JSX.Element {
  const { card, intro, capped } = result;
  return (
    <CardShell title="Today" onRefresh={onRefresh} refreshing={refreshing}>
      {minorScoped && (
        <div style={styles.minorBanner} role="note">
          Your brief shows your Amen activity — events, saved verses, and your groups.
        </div>
      )}
      {intro && <p style={styles.intro}>{intro}</p>}

      <div style={styles.sectionWrap}>
        {card.sections.map((s, idx) => (
          <div key={`${s.section}-${idx}`} style={styles.section}>
            <div style={styles.sectionHeader}>
              <span style={styles.sectionIcon} aria-hidden="true">
                {SECTION_META[s.section].icon}
              </span>
              <span style={styles.sectionLabel}>{SECTION_META[s.section].label}</span>
            </div>
            {s.items.map((item, i) => (
              <ItemRow key={i} item={item} onOpenPointer={onOpenPointer} />
            ))}
          </div>
        ))}
      </div>

      {/* cap-degraded state — non-blocking, calm, no guilt */}
      {capped && (
        <p style={styles.capNote}>
          Showing the most relevant {card.maxItemsTotal}. There's a little more inside your spaces.
        </p>
      )}
    </CardShell>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN COMPONENT
// ─────────────────────────────────────────────────────────────────────────────

type Phase = 'loading' | 'ready' | 'empty' | 'sabbath' | 'error';

export default function DailyBriefCard({
  userId,
  minorScoped = false,
  onOpenPointer,
  onOpenSafety,
}: DailyBriefCardProps): JSX.Element {
  const [phase, setPhase] = useState<Phase>('loading');
  const [result, setResult] = useState<BriefResult | null>(null);
  const [errorMsg, setErrorMsg] = useState<string>('');
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(
    async (forceRegenerate: boolean) => {
      if (forceRegenerate) setRefreshing(true);
      else setPhase('loading');
      setErrorMsg('');
      try {
        const res = await fetchDailyBrief(forceRegenerate);
        setResult(res);
        if (res.sabbath) {
          setPhase('sabbath');
        } else if (totalItemCount(res.card) === 0) {
          setPhase('empty');
        } else {
          setPhase('ready');
        }
      } catch (err: unknown) {
        setErrorMsg(err instanceof Error ? err.message : 'Something went wrong. Please try again.');
        setPhase('error');
      } finally {
        setRefreshing(false);
      }
    },
    [],
  );

  // Pull-based: generate on open (first mount). NEVER push.
  useEffect(() => {
    void load(false);
  }, [load, userId]);

  const handleRefresh = useCallback(() => void load(true), [load]);
  const handleRetry = useCallback(() => void load(false), [load]);

  switch (phase) {
    case 'loading':
      return <LoadingState />;
    case 'error':
      return <ErrorState message={errorMsg} onRetry={handleRetry} retrying={refreshing} />;
    case 'sabbath':
      return result ? <SabbathState card={result.card} onOpenSafety={onOpenSafety} /> : <LoadingState />;
    case 'empty':
      return <EmptyState onRefresh={handleRefresh} refreshing={refreshing} />;
    case 'ready':
      return result ? (
        <ReadyState
          result={result}
          minorScoped={minorScoped || result.card.minorMode}
          onOpenPointer={onOpenPointer}
          onRefresh={handleRefresh}
          refreshing={refreshing}
        />
      ) : (
        <LoadingState />
      );
    default:
      return <LoadingState />;
  }
}
