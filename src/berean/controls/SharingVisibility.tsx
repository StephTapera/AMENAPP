/**
 * SharingVisibility.tsx — Berean v1 Phase 2E
 * 5-tier visibility picker (radio-button style, reusable component).
 *
 * OWNER: Phase 2E Controls Agent
 * Design tokens imported from contracts.ts — never redefine.
 * Default visibility = 'private' — enforced in both props and render.
 * FORBIDDEN: gold, dark bg, Cormorant Garamond, purple, lock icons, premium badges.
 */

import React from 'react';
import { Visibility, tokens } from '../contracts';

// ─────────────────────────────────────────────────────────────────────────────
// TIER DEFINITIONS
// ─────────────────────────────────────────────────────────────────────────────

interface VisibilityTier {
  value: Visibility;
  label: string;
  description: string;
  isDefault: boolean;
}

const TIERS: VisibilityTier[] = [
  {
    value: 'public',
    label: 'Public',
    description: 'Books, music, sermons, podcasts',
    isDefault: false,
  },
  {
    value: 'followers',
    label: 'Followers',
    description: 'Personal teachings, extra notes',
    isDefault: false,
  },
  {
    value: 'paid',
    label: 'Paid Members',
    description: 'Courses, study guides, premium',
    isDefault: false,
  },
  {
    value: 'organization',
    label: 'Organization',
    description: 'Church / business / team resources',
    isDefault: false,
  },
  {
    value: 'private',
    label: 'Private (Draft)',
    description: 'Only you',
    isDefault: true,
  },
];

/** Visibility values blocked for minor-scoped accounts. */
const MINOR_BLOCKED: Visibility[] = ['public', 'organization'];

// ─────────────────────────────────────────────────────────────────────────────
// PROPS
// ─────────────────────────────────────────────────────────────────────────────

export interface SharingVisibilityProps {
  /** Currently selected visibility tier. Defaults to 'private' if undefined. */
  value?: Visibility;
  onChange: (v: Visibility) => void;
  /** When true, 'public' and 'organization' are grayed out and non-selectable. */
  minorScoped?: boolean;
  /** Optional label rendered above the option list. */
  label?: string;
  /** When true, all options are non-interactive. */
  disabled?: boolean;
}

// ─────────────────────────────────────────────────────────────────────────────
// STYLES
// ─────────────────────────────────────────────────────────────────────────────

const styles = {
  container: {
    fontFamily:
      '-apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", "Helvetica Neue", Arial, sans-serif',
  } as React.CSSProperties,

  label: {
    fontSize: 13,
    fontWeight: 600,
    color: tokens.textSub,
    textTransform: 'uppercase' as const,
    letterSpacing: 0.6,
    marginBottom: 8,
    paddingLeft: 4,
  } as React.CSSProperties,

  list: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 8,
  } as React.CSSProperties,

  // Base option row — not selected, not blocked.
  rowBase: {
    display: 'flex',
    alignItems: 'flex-start',
    gap: 12,
    backgroundColor: tokens.card,
    borderRadius: tokens.radius,
    boxShadow: tokens.shadow,
    padding: '14px 16px',
    cursor: 'pointer',
    borderLeft: `4px solid transparent`,
    transition: 'border-color 0.15s, opacity 0.15s',
    userSelect: 'none' as const,
    outline: 'none',
  } as React.CSSProperties,

  rowSelected: {
    borderLeft: `4px solid ${tokens.accent}`,
  } as React.CSSProperties,

  rowDisabled: {
    opacity: 0.42,
    cursor: 'not-allowed',
  } as React.CSSProperties,

  radioDot: {
    flexShrink: 0,
    width: 20,
    height: 20,
    borderRadius: '50%',
    border: `2px solid ${tokens.divider}`,
    marginTop: 1,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    transition: 'border-color 0.15s',
  } as React.CSSProperties,

  radioDotSelected: {
    borderColor: tokens.accent,
  } as React.CSSProperties,

  radioDotInner: {
    width: 10,
    height: 10,
    borderRadius: '50%',
    backgroundColor: tokens.accent,
  } as React.CSSProperties,

  rowContent: {
    flex: 1,
    minWidth: 0,
  } as React.CSSProperties,

  rowLabel: {
    fontSize: 15,
    fontWeight: 500,
    color: tokens.text,
    margin: '0 0 2px 0',
  } as React.CSSProperties,

  rowLabelDisabled: {
    fontSize: 15,
    fontWeight: 500,
    color: tokens.textSub,
    margin: '0 0 2px 0',
  } as React.CSSProperties,

  rowDescription: {
    fontSize: 13,
    color: tokens.textSub,
    margin: 0,
    lineHeight: 1.4,
  } as React.CSSProperties,

  defaultSuffix: {
    fontSize: 12,
    color: tokens.textSub,
    marginLeft: 4,
    fontWeight: 400,
  } as React.CSSProperties,

  blockedHint: {
    fontSize: 12,
    color: tokens.textSub,
    marginTop: 3,
    fontStyle: 'italic',
  } as React.CSSProperties,
};

// ─────────────────────────────────────────────────────────────────────────────
// COMPONENT
// ─────────────────────────────────────────────────────────────────────────────

export default function SharingVisibility({
  value,
  onChange,
  minorScoped = false,
  label,
  disabled = false,
}: SharingVisibilityProps) {
  // Enforce default: any new Berean output MUST start as 'private'.
  const effective: Visibility = value ?? 'private';

  function isBlocked(tier: VisibilityTier): boolean {
    if (disabled) return true;
    if (minorScoped && MINOR_BLOCKED.includes(tier.value)) return true;
    return false;
  }

  function handleSelect(tier: VisibilityTier) {
    if (isBlocked(tier)) return;
    if (tier.value === effective) return;
    onChange(tier.value);
  }

  return (
    <div style={styles.container}>
      {label && <p style={styles.label}>{label}</p>}

      <div style={styles.list} role="radiogroup" aria-label={label ?? 'Sharing visibility'}>
        {TIERS.map((tier) => {
          const selected = tier.value === effective;
          const blocked = isBlocked(tier);
          const minorBlocked =
            minorScoped && MINOR_BLOCKED.includes(tier.value);

          const rowStyle: React.CSSProperties = {
            ...styles.rowBase,
            ...(selected ? styles.rowSelected : {}),
            ...(blocked ? styles.rowDisabled : {}),
          };

          const dotStyle: React.CSSProperties = {
            ...styles.radioDot,
            ...(selected ? styles.radioDotSelected : {}),
          };

          return (
            <div
              key={tier.value}
              role="radio"
              aria-checked={selected}
              aria-disabled={blocked}
              tabIndex={blocked ? -1 : 0}
              style={rowStyle}
              onClick={() => handleSelect(tier)}
              onKeyDown={(e) => {
                if (e.key === 'Enter' || e.key === ' ') {
                  e.preventDefault();
                  handleSelect(tier);
                }
              }}
              title={
                minorBlocked
                  ? 'Not available for your account type'
                  : undefined
              }
            >
              {/* Radio dot */}
              <div style={dotStyle}>
                {selected && <div style={styles.radioDotInner} />}
              </div>

              {/* Text content */}
              <div style={styles.rowContent}>
                <p
                  style={
                    blocked ? styles.rowLabelDisabled : styles.rowLabel
                  }
                >
                  {tier.label}
                  {tier.isDefault && (
                    <span style={styles.defaultSuffix}>(Default)</span>
                  )}
                </p>
                <p style={styles.rowDescription}>{tier.description}</p>
                {minorBlocked && (
                  <p style={styles.blockedHint}>
                    Not available for your account type
                  </p>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
