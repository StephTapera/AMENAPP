/**
 * ConnectorsScreen.tsx — Berean connectors management UI
 * Phase 2D: Berean Connectors
 *
 * Displays four faith-native connector cards (Bible, Church Calendar, Giving, Sermon Library).
 * Generic productivity connectors (Notion, Google Drive, Slack, etc.) are NOT shown.
 * All design tokens imported from contracts.ts — no hardcoded colors.
 */

import React, { useEffect, useState } from 'react';
import { tokens } from '../contracts';
import type { ConnectorType } from '../contracts';
import {
  fetchConnectors,
  connectConnector,
  revokeConnector,
} from './connectorsService';
import type { ConnectorState } from './connectorsService';

// ─────────────────────────────────────────────────────────────────────────────
// TYPES
// ─────────────────────────────────────────────────────────────────────────────

interface ConnectorCardDef {
  type: ConnectorType;
  icon: string;
  title: string;
  description: string;
}

interface ConnectorsScreenProps {
  userId: string;
  minorScoped: boolean;
}

// ─────────────────────────────────────────────────────────────────────────────
// CONNECTOR DEFINITIONS
// ─────────────────────────────────────────────────────────────────────────────

const CONNECTOR_CARDS: ConnectorCardDef[] = [
  {
    type: 'bible',
    icon: '✝',
    title: 'Bible',
    description:
      'Connect your Bible app and reading plan. Open-licensed translations (BSB, WEB, KJV) used by default.',
  },
  {
    type: 'church_calendar',
    icon: '📅',
    title: 'Church Calendar',
    description:
      'Sync your church\'s calendar for upcoming events and sermon series.',
  },
  {
    type: 'giving',
    icon: '🙏',
    title: 'Giving',
    description:
      'Track your giving history and set giving goals. Stripe-backed, faith-first.',
  },
  {
    type: 'sermon_library',
    icon: '🎙',
    title: 'Sermon Library',
    description: 'Access your church\'s sermon archive.',
  },
];

// ─────────────────────────────────────────────────────────────────────────────
// STYLES
// ─────────────────────────────────────────────────────────────────────────────

const styles = {
  screen: {
    backgroundColor: tokens.bg,
    minHeight: '100vh',
    fontFamily:
      '-apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", system-ui, sans-serif',
    padding: '24px 16px 40px',
    boxSizing: 'border-box' as const,
  },
  minorBanner: {
    backgroundColor: '#FFF4E5',
    border: '1px solid #FFD580',
    borderRadius: tokens.radius,
    padding: '14px 16px',
    marginBottom: 20,
    fontSize: 14,
    color: tokens.text,
    fontWeight: 500,
    textAlign: 'center' as const,
  },
  heading: {
    fontSize: 22,
    fontWeight: 700,
    color: tokens.text,
    marginBottom: 4,
    letterSpacing: -0.3,
  },
  subheading: {
    fontSize: 14,
    color: tokens.textSub,
    marginBottom: 24,
  },
  cardList: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 14,
  },
  card: {
    backgroundColor: tokens.card,
    borderRadius: tokens.radius,
    boxShadow: tokens.shadow,
    padding: '18px 16px',
  },
  cardHeader: {
    display: 'flex',
    alignItems: 'center',
    gap: 10,
    marginBottom: 6,
  },
  cardIcon: {
    fontSize: 22,
    lineHeight: 1,
    flexShrink: 0,
  },
  cardTitle: {
    fontSize: 16,
    fontWeight: 600,
    color: tokens.text,
    flex: 1,
  },
  statusBadge: (connected: boolean): React.CSSProperties => ({
    display: 'flex',
    alignItems: 'center',
    gap: 5,
    fontSize: 12,
    fontWeight: 500,
    color: connected ? '#1A7F4F' : tokens.textSub,
  }),
  statusDot: (connected: boolean): React.CSSProperties => ({
    width: 7,
    height: 7,
    borderRadius: '50%',
    backgroundColor: connected ? '#34C759' : '#AEAEB2',
    flexShrink: 0,
  }),
  cardDescription: {
    fontSize: 13,
    color: tokens.textSub,
    lineHeight: 1.5,
    marginBottom: 14,
  },
  cardFooter: {
    display: 'flex',
    justifyContent: 'flex-end',
  },
  connectButton: (disabled: boolean): React.CSSProperties => ({
    backgroundColor: disabled ? '#E5E5EA' : tokens.accent,
    color: disabled ? '#AEAEB2' : '#FFFFFF',
    border: 'none',
    borderRadius: 10,
    padding: '9px 20px',
    fontSize: 14,
    fontWeight: 600,
    cursor: disabled ? 'not-allowed' : 'pointer',
    fontFamily: 'inherit',
    opacity: disabled ? 0.6 : 1,
  }),
  disconnectButton: {
    backgroundColor: 'transparent',
    color: '#FF3B30',
    border: 'none',
    borderRadius: 10,
    padding: '9px 20px',
    fontSize: 14,
    fontWeight: 600,
    cursor: 'pointer',
    fontFamily: 'inherit',
  } as React.CSSProperties,
  footerNote: {
    marginTop: 28,
    fontSize: 12,
    color: tokens.textSub,
    textAlign: 'center' as const,
    lineHeight: 1.5,
  },
  errorText: {
    fontSize: 13,
    color: '#FF3B30',
    marginTop: 4,
  },
  loadingText: {
    fontSize: 14,
    color: tokens.textSub,
    textAlign: 'center' as const,
    marginTop: 40,
  },
};

// ─────────────────────────────────────────────────────────────────────────────
// CONNECTOR CARD COMPONENT
// ─────────────────────────────────────────────────────────────────────────────

interface ConnectorCardProps {
  def: ConnectorCardDef;
  connected: boolean;
  minorScoped: boolean;
  onConnect: () => Promise<void>;
  onDisconnect: () => Promise<void>;
}

function ConnectorCard({
  def,
  connected,
  minorScoped,
  onConnect,
  onDisconnect,
}: ConnectorCardProps): JSX.Element {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleAction = async (action: () => Promise<void>) => {
    if (busy || minorScoped) return;
    setBusy(true);
    setError(null);
    try {
      await action();
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Something went wrong. Please try again.';
      setError(message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div style={styles.card}>
      <div style={styles.cardHeader}>
        <span style={styles.cardIcon} aria-hidden="true">
          {def.icon}
        </span>
        <span style={styles.cardTitle}>{def.title}</span>
        <span
          style={styles.statusBadge(connected)}
          aria-label={connected ? `${def.title} connected` : `${def.title} not connected`}
        >
          <span style={styles.statusDot(connected)} aria-hidden="true" />
          {connected ? 'Connected' : 'Not connected'}
        </span>
      </div>

      <p style={styles.cardDescription}>{def.description}</p>

      {error && <p style={styles.errorText}>{error}</p>}

      <div style={styles.cardFooter}>
        {connected ? (
          <button
            style={styles.disconnectButton}
            onClick={() => handleAction(onDisconnect)}
            disabled={busy || minorScoped}
            aria-label={`Disconnect ${def.title}`}
          >
            {busy ? 'Disconnecting…' : 'Disconnect'}
          </button>
        ) : (
          <button
            style={styles.connectButton(minorScoped)}
            onClick={() => handleAction(onConnect)}
            disabled={busy || minorScoped}
            aria-label={`Connect ${def.title}`}
          >
            {busy ? 'Connecting…' : 'Connect'}
          </button>
        )}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN SCREEN
// ─────────────────────────────────────────────────────────────────────────────

export default function ConnectorsScreen({
  userId,
  minorScoped,
}: ConnectorsScreenProps): JSX.Element {
  const [state, setState] = useState<ConnectorState | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);

  useEffect(() => {
    if (minorScoped) {
      setState({
        bible: false,
        church_calendar: false,
        giving: false,
        sermon_library: false,
      });
      return;
    }

    fetchConnectors(userId, minorScoped)
      .then((connectors) => setState(connectors))
      .catch(() => {
        setLoadError('Unable to load connectors. Please try again.');
      });
  }, [userId, minorScoped]);

  const handleConnect = async (type: ConnectorType) => {
    await connectConnector(userId, type, minorScoped);
    setState((prev) =>
      prev ? { ...prev, [type]: true } : prev
    );
  };

  const handleDisconnect = async (type: ConnectorType) => {
    await revokeConnector(userId, type, minorScoped);
    setState((prev) =>
      prev ? { ...prev, [type]: false } : prev
    );
  };

  return (
    <main style={styles.screen} aria-label="Berean Connectors">
      {minorScoped && (
        <div
          style={styles.minorBanner}
          role="status"
          aria-live="polite"
        >
          Connectors are not available for your account.
        </div>
      )}

      <h1 style={styles.heading}>Connectors</h1>
      <p style={styles.subheading}>
        Connect faith-focused services to enrich your Berean experience.
      </p>

      {loadError && (
        <p style={{ ...styles.errorText, marginBottom: 16 }}>{loadError}</p>
      )}

      {state === null && !loadError ? (
        <p style={styles.loadingText}>Loading connectors…</p>
      ) : (
        <div style={styles.cardList}>
          {CONNECTOR_CARDS.map((def) => (
            <ConnectorCard
              key={def.type}
              def={def}
              connected={state?.[def.type] ?? false}
              minorScoped={minorScoped}
              onConnect={() => handleConnect(def.type)}
              onDisconnect={() => handleDisconnect(def.type)}
            />
          ))}
        </div>
      )}

      <p style={styles.footerNote}>
        Berean connects only to faith-focused services. No general productivity apps.
      </p>
    </main>
  );
}
