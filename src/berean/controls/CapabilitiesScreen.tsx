/**
 * CapabilitiesScreen.tsx — Berean v1 Phase 2E
 * Capabilities toggles UI for Berean Settings.
 *
 * OWNER: Phase 2E Controls Agent
 * Design tokens imported from contracts.ts — never redefine.
 * FORBIDDEN: gold, dark bg, Cormorant Garamond, purple.
 */

import React, { useCallback, useEffect, useRef, useState } from 'react';
import { BereanCapabilities, tokens } from '../contracts';
import { fetchCapabilities, updateCapabilities } from './controlsService';

// ─────────────────────────────────────────────────────────────────────────────
// PROPS
// ─────────────────────────────────────────────────────────────────────────────

interface CapabilitiesScreenProps {
  userId: string;
}

// ─────────────────────────────────────────────────────────────────────────────
// STYLES
// ─────────────────────────────────────────────────────────────────────────────

const styles = {
  screen: {
    minHeight: '100vh',
    backgroundColor: tokens.bg,
    fontFamily:
      '-apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", "Helvetica Neue", Arial, sans-serif',
    paddingBottom: 40,
  } as React.CSSProperties,

  header: {
    padding: '24px 20px 8px 20px',
  } as React.CSSProperties,

  pageTitle: {
    fontSize: 28,
    fontWeight: 700,
    color: tokens.text,
    margin: 0,
    letterSpacing: -0.5,
  } as React.CSSProperties,

  savedBadge: {
    display: 'inline-flex',
    alignItems: 'center',
    marginTop: 8,
    fontSize: 13,
    color: tokens.accent,
    fontWeight: 500,
    height: 20,
    transition: 'opacity 0.25s',
  } as React.CSSProperties,

  section: {
    margin: '20px 16px 0 16px',
  } as React.CSSProperties,

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

  rowBase: {
    display: 'flex',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    padding: '14px 16px',
    gap: 12,
  } as React.CSSProperties,

  rowDivider: {
    borderTop: `1px solid ${tokens.divider}`,
  } as React.CSSProperties,

  rowContent: {
    flex: 1,
    minWidth: 0,
  } as React.CSSProperties,

  rowLabel: {
    fontSize: 15,
    fontWeight: 500,
    color: tokens.text,
    margin: 0,
  } as React.CSSProperties,

  rowLabelDisabled: {
    fontSize: 15,
    fontWeight: 500,
    color: tokens.textSub,
    margin: 0,
  } as React.CSSProperties,

  rowDescription: {
    fontSize: 13,
    color: tokens.textSub,
    marginTop: 2,
    lineHeight: 1.45,
  } as React.CSSProperties,

  minorNote: {
    fontSize: 13,
    color: tokens.textSub,
    marginTop: 8,
    paddingLeft: 4,
    lineHeight: 1.4,
  } as React.CSSProperties,

  minorBanner: {
    backgroundColor: tokens.card,
    borderRadius: tokens.radius,
    boxShadow: tokens.shadow,
    padding: '14px 16px',
  } as React.CSSProperties,

  minorBannerTitle: {
    fontSize: 15,
    fontWeight: 600,
    color: tokens.text,
    margin: '0 0 4px 0',
  } as React.CSSProperties,

  minorBannerSub: {
    fontSize: 13,
    color: tokens.textSub,
    margin: 0,
    lineHeight: 1.45,
  } as React.CSSProperties,
};

// ─────────────────────────────────────────────────────────────────────────────
// TOGGLE — native iOS-style switch rendered in HTML/CSS
// ─────────────────────────────────────────────────────────────────────────────

interface ToggleProps {
  checked: boolean;
  onChange: (next: boolean) => void;
  disabled?: boolean;
  ariaLabel: string;
}

function Toggle({ checked, onChange, disabled = false, ariaLabel }: ToggleProps) {
  const trackStyle: React.CSSProperties = {
    position: 'relative',
    display: 'inline-block',
    width: 51,
    height: 31,
    borderRadius: 16,
    backgroundColor: checked && !disabled ? tokens.accent : '#D1D1D6',
    transition: 'background-color 0.2s',
    cursor: disabled ? 'not-allowed' : 'pointer',
    flexShrink: 0,
    opacity: disabled ? 0.45 : 1,
  };

  const thumbStyle: React.CSSProperties = {
    position: 'absolute',
    top: 2,
    left: checked ? 22 : 2,
    width: 27,
    height: 27,
    borderRadius: '50%',
    backgroundColor: '#FFFFFF',
    boxShadow: '0 1px 3px rgba(0,0,0,0.25)',
    transition: 'left 0.18s cubic-bezier(0.34,1.56,0.64,1)',
  };

  return (
    <div
      role="switch"
      aria-checked={checked}
      aria-label={ariaLabel}
      aria-disabled={disabled}
      tabIndex={disabled ? -1 : 0}
      style={trackStyle}
      onClick={() => {
        if (!disabled) onChange(!checked);
      }}
      onKeyDown={(e) => {
        if (!disabled && (e.key === 'Enter' || e.key === ' ')) {
          e.preventDefault();
          onChange(!checked);
        }
      }}
    >
      <div style={thumbStyle} />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// TOGGLE ROW
// ─────────────────────────────────────────────────────────────────────────────

interface ToggleRowProps {
  label: string;
  description: string;
  checked: boolean;
  onChange: (next: boolean) => void;
  disabled?: boolean;
  divider?: boolean;
}

function ToggleRow({
  label,
  description,
  checked,
  onChange,
  disabled = false,
  divider = false,
}: ToggleRowProps) {
  return (
    <div style={{ ...styles.rowBase, ...(divider ? styles.rowDivider : {}) }}>
      <div style={styles.rowContent}>
        <p style={disabled ? styles.rowLabelDisabled : styles.rowLabel}>
          {label}
        </p>
        <p style={styles.rowDescription}>{description}</p>
      </div>
      <Toggle
        checked={checked}
        onChange={onChange}
        disabled={disabled}
        ariaLabel={label}
      />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// CAPABILITIES SCREEN
// ─────────────────────────────────────────────────────────────────────────────

export default function CapabilitiesScreen({ userId }: CapabilitiesScreenProps) {
  const [caps, setCaps] = useState<BereanCapabilities | null>(null);
  const [loading, setLoading] = useState(true);
  const [savedVisible, setSavedVisible] = useState(false);
  const savedTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Load capabilities on mount.
  useEffect(() => {
    let cancelled = false;
    fetchCapabilities(userId).then((c) => {
      if (!cancelled) {
        setCaps(c);
        setLoading(false);
      }
    });
    return () => {
      cancelled = true;
    };
  }, [userId]);

  // Show "Saved" indicator for 1.5 s after any change.
  const flashSaved = useCallback(() => {
    setSavedVisible(true);
    if (savedTimer.current) clearTimeout(savedTimer.current);
    savedTimer.current = setTimeout(() => setSavedVisible(false), 1500);
  }, []);

  // Generic capability toggle handler.
  const handleToggle = useCallback(
    async (patch: Partial<BereanCapabilities>) => {
      if (!caps) return;
      const optimistic: BereanCapabilities = {
        ...caps,
        ...patch,
        connectors: {
          ...caps.connectors,
          ...(patch.connectors ?? {}),
        },
      };
      setCaps(optimistic);
      try {
        await updateCapabilities(userId, patch);
        flashSaved();
      } catch {
        // Revert optimistic update on failure.
        setCaps(caps);
      }
    },
    [caps, userId, flashSaved],
  );

  if (loading || !caps) {
    return (
      <div
        style={{
          ...styles.screen,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        <p style={{ color: tokens.textSub, fontSize: 15 }}>Loading…</p>
      </div>
    );
  }

  const { minorScoped } = caps;

  return (
    <div style={styles.screen}>
      {/* ── Header ── */}
      <div style={styles.header}>
        <h1 style={styles.pageTitle}>Berean Settings</h1>
        <div style={{ ...styles.savedBadge, opacity: savedVisible ? 1 : 0 }}>
          Saved
        </div>
      </div>

      {/* ── Section: What Berean Can Remember ── */}
      <div style={styles.section}>
        <p style={styles.sectionTitle}>What Berean Can Remember</p>
        <div style={styles.card}>
          <ToggleRow
            label="Formation Memory"
            description="Berean remembers your prayer requests, reading plan, and reflections to give better guidance over time."
            checked={caps.memory}
            onChange={(next) => handleToggle({ memory: next })}
          />
        </div>
      </div>

      {/* ── Section: Proactive Guidance ── */}
      <div style={styles.section}>
        <p style={styles.sectionTitle}>Proactive Guidance</p>
        <div style={styles.card}>
          <ToggleRow
            label="Proactive Formation"
            description="Berean may surface a relevant verse or reflection when context suggests it would help."
            checked={caps.proactive}
            onChange={(next) => handleToggle({ proactive: next })}
          />
        </div>
      </div>

      {/* ── Section: Voice ── */}
      <div style={styles.section}>
        <p style={styles.sectionTitle}>Voice</p>
        <div style={styles.card}>
          <ToggleRow
            label="Voice"
            description="Enables voice input and Scripture read-aloud."
            checked={caps.voice}
            onChange={(next) => handleToggle({ voice: next })}
          />
        </div>
      </div>

      {/* ── Section: Connectors ── */}
      <div style={styles.section}>
        <p style={styles.sectionTitle}>Connectors</p>
        <div style={styles.card}>
          <ToggleRow
            label="Bible"
            description="Connect Berean to your Bible reading history and notes."
            checked={caps.connectors.bible}
            onChange={(next) =>
              handleToggle({ connectors: { ...caps.connectors, bible: next } })
            }
            disabled={minorScoped}
          />
          <ToggleRow
            label="Church Calendar"
            description="Surface liturgical seasons, feast days, and church events."
            checked={caps.connectors.church_calendar}
            onChange={(next) =>
              handleToggle({
                connectors: { ...caps.connectors, church_calendar: next },
              })
            }
            disabled={minorScoped}
            divider
          />
          <ToggleRow
            label="Giving"
            description="Allow Berean to reference your giving history for stewardship guidance."
            checked={caps.connectors.giving}
            onChange={(next) =>
              handleToggle({ connectors: { ...caps.connectors, giving: next } })
            }
            disabled={minorScoped}
            divider
          />
          <ToggleRow
            label="Sermon Library"
            description="Let Berean cite and recall sermons from your church's library."
            checked={caps.connectors.sermon_library}
            onChange={(next) =>
              handleToggle({
                connectors: { ...caps.connectors, sermon_library: next },
              })
            }
            disabled={minorScoped}
            divider
          />
        </div>
        {minorScoped && (
          <p style={styles.minorNote}>
            Connectors are not available for your account type.
          </p>
        )}
      </div>

      {/* ── Section: Account Scope (read-only, shown only for minor accounts) ── */}
      {minorScoped && (
        <div style={styles.section}>
          <p style={styles.sectionTitle}>Account Scope</p>
          <div style={styles.minorBanner}>
            <p style={styles.minorBannerTitle}>Minor Account Mode: Active</p>
            <p style={styles.minorBannerSub}>
              Some features are limited for minor accounts to protect your
              privacy.
            </p>
          </div>
        </div>
      )}
    </div>
  );
}
