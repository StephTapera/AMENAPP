/**
 * UsageMeters.tsx — Berean Phase 2C
 *
 * Honest usage meter screen. Shows session + weekly progress, safety exemption
 * line (always visible), and a soft low-usage signal at 80%+.
 *
 * Meters are signals to stop — not pressure to upgrade.
 * No gamification. No streaks. No urgency language.
 *
 * Design tokens: from ../../contracts (frozen)
 * Font: SF system font only
 * FORBIDDEN: gold, dark gradients, Cormorant Garamond, purple
 */

import React, { useState } from 'react';
import { tokens } from '../contracts';
import { useUsage } from './useUsage';
import { UsagePeriod } from './usageService';

// ─────────────────────────────────────────────────────────────────────────────
// Props
// ─────────────────────────────────────────────────────────────────────────────

interface UsageMetersProps {
  userId: string;
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Formats a Date into a human-readable day + time string for the reset label.
 * Example: "Sunday at midnight" or "Sunday at 12:00 AM"
 */
function formatResetsAt(date: Date): string {
  const days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  const dayName = days[date.getUTCDay()];
  const h = date.getUTCHours();
  const m = date.getUTCMinutes();

  if (h === 0 && m === 0) {
    return `${dayName} at midnight`;
  }

  const period = h < 12 ? 'AM' : 'PM';
  const hour12 = h === 0 ? 12 : h > 12 ? h - 12 : h;
  const minuteStr = m === 0 ? '' : `:${String(m).padStart(2, '0')}`;
  return `${dayName} at ${hour12}${minuteStr} ${period} UTC`;
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-components
// ─────────────────────────────────────────────────────────────────────────────

interface ProgressBarProps {
  pct: number; // 0–100
}

function ProgressBar({ pct }: ProgressBarProps) {
  const clampedPct = Math.max(0, Math.min(100, pct));

  return (
    <div
      style={{
        width: '100%',
        height: 10,
        backgroundColor: tokens.divider,
        borderRadius: 9999,
        overflow: 'hidden',
      }}
      role="progressbar"
      aria-valuenow={clampedPct}
      aria-valuemin={0}
      aria-valuemax={100}
    >
      <div
        style={{
          width: `${clampedPct}%`,
          height: '100%',
          backgroundColor: tokens.accent,
          borderRadius: 9999,
          transition: 'width 0.3s ease',
        }}
      />
    </div>
  );
}

interface BarRowProps {
  left: string;
  right: string;
}

function BarRow({ left, right }: BarRowProps) {
  return (
    <div
      style={{
        display: 'flex',
        justifyContent: 'space-between',
        marginTop: 6,
      }}
    >
      <span
        style={{
          fontSize: 13,
          color: tokens.textSub,
          fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
        }}
      >
        {left}
      </span>
      <span
        style={{
          fontSize: 13,
          color: tokens.textSub,
          fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
        }}
      >
        {right}
      </span>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SafetyLine — always rendered, never hidden, never below a fold
// ─────────────────────────────────────────────────────────────────────────────

function SafetyLine() {
  const [expanded, setExpanded] = useState(false);

  return (
    <div
      style={{
        marginTop: 20,
        padding: '12px 14px',
        backgroundColor: tokens.card,
        borderRadius: tokens.radius,
        boxShadow: tokens.shadow,
        display: 'flex',
        flexDirection: 'column',
        gap: 6,
      }}
      aria-label="Safety features information"
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        <span
          style={{
            fontSize: 15,
            color: tokens.textSub,
            fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
          }}
        >
          Safety features are always free.
        </span>
        <button
          onClick={() => setExpanded((prev) => !prev)}
          aria-expanded={expanded}
          aria-label={
            expanded
              ? 'Collapse safety feature explanation'
              : 'Expand safety feature explanation'
          }
          style={{
            background: 'none',
            border: 'none',
            padding: 0,
            cursor: 'pointer',
            fontSize: 15,
            color: tokens.textSub,
            lineHeight: 1,
            flexShrink: 0,
          }}
        >
          ⓘ
        </button>
      </div>

      {expanded && (
        <p
          style={{
            margin: 0,
            fontSize: 13,
            color: tokens.textSub,
            fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
            lineHeight: 1.5,
          }}
        >
          Safety actions like crisis support and content filters are never counted
          against your usage.
        </p>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// WeeklyNudge — soft signal only, no pressure
// ─────────────────────────────────────────────────────────────────────────────

interface WeeklyNudgeProps {
  weeklyPct: number;
  resetsAt: Date;
}

function WeeklyNudge({ weeklyPct, resetsAt }: WeeklyNudgeProps) {
  if (weeklyPct >= 100) {
    return (
      <div
        style={{
          marginTop: 12,
          fontSize: 14,
          color: tokens.textSub,
          fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          flexWrap: 'wrap',
          gap: 6,
        }}
        role="status"
        aria-live="polite"
      >
        <span>
          {"You've reached your weekly limit. Resets "}
          {formatResetsAt(resetsAt)}.
        </span>
        <a
          href="#plans"
          style={{
            fontSize: 13,
            color: tokens.accent,
            textDecoration: 'none',
            fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
          }}
          aria-label="Learn about Berean usage plans"
        >
          Learn about plans
        </a>
      </div>
    );
  }

  if (weeklyPct >= 80) {
    return (
      <p
        style={{
          marginTop: 12,
          marginBottom: 0,
          fontSize: 14,
          color: tokens.textSub,
          fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
        }}
        role="status"
        aria-live="polite"
      >
        Running low on Berean usage this week.
      </p>
    );
  }

  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// CreditDetail — collapsed by default
// ─────────────────────────────────────────────────────────────────────────────

interface CreditDetailProps {
  creditsUsed: number;
  creditsCap: number;
}

function CreditDetail({ creditsUsed, creditsCap }: CreditDetailProps) {
  const [open, setOpen] = useState(false);

  return (
    <div style={{ marginTop: 20 }}>
      <button
        onClick={() => setOpen((prev) => !prev)}
        aria-expanded={open}
        aria-controls="credit-detail-panel"
        style={{
          background: 'none',
          border: 'none',
          padding: 0,
          cursor: 'pointer',
          fontSize: 14,
          color: tokens.accent,
          fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
          display: 'flex',
          alignItems: 'center',
          gap: 4,
        }}
      >
        <span>{open ? '▾' : '▸'}</span>
        <span>View usage details</span>
      </button>

      {open && (
        <div
          id="credit-detail-panel"
          role="region"
          aria-label="Credit usage details"
          style={{
            marginTop: 10,
            backgroundColor: tokens.card,
            borderRadius: tokens.radius,
            boxShadow: tokens.shadow,
            padding: '12px 14px',
          }}
        >
          <div
            style={{
              display: 'grid',
              gridTemplateColumns: '1fr 1fr',
              gap: '8px 16px',
            }}
          >
            <span
              style={{
                fontSize: 13,
                color: tokens.textSub,
                fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
              }}
            >
              Credits used
            </span>
            <span
              style={{
                fontSize: 13,
                color: tokens.text,
                fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
                fontWeight: 500,
                textAlign: 'right',
              }}
            >
              {creditsUsed}
            </span>

            <span
              style={{
                fontSize: 13,
                color: tokens.textSub,
                fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
              }}
            >
              Credits cap
            </span>
            <span
              style={{
                fontSize: 13,
                color: tokens.text,
                fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
                fontWeight: 500,
                textAlign: 'right',
              }}
            >
              {creditsCap}
            </span>

            <span
              style={{
                fontSize: 13,
                color: tokens.textSub,
                fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
              }}
            >
              Safety actions
            </span>
            <span
              style={{
                fontSize: 13,
                color: tokens.text,
                fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
                fontWeight: 500,
                textAlign: 'right',
              }}
            >
              Always free
            </span>
          </div>
        </div>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// MeterContent — rendered when usage is loaded
// ─────────────────────────────────────────────────────────────────────────────

interface MeterContentProps {
  usage: UsagePeriod;
}

function MeterContent({ usage }: MeterContentProps) {
  const resetsLabel = formatResetsAt(usage.resetsAt);

  return (
    <>
      {/* Safety line — ALWAYS first, always visible */}
      <SafetyLine />

      {/* Section 1 — Current Session */}
      <section
        aria-labelledby="section-session"
        style={{
          marginTop: 24,
          backgroundColor: tokens.card,
          borderRadius: tokens.radius,
          boxShadow: tokens.shadow,
          padding: '16px 16px',
        }}
      >
        <h2
          id="section-session"
          style={{
            margin: '0 0 12px 0',
            fontSize: 15,
            fontWeight: 500,
            color: tokens.text,
            fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
          }}
        >
          Current Session
        </h2>

        <ProgressBar pct={usage.sessionPct} />

        <BarRow
          left={`${Math.round(usage.sessionPct)}% used`}
          right="Resets at end of session"
        />
      </section>

      {/* Section 2 — Weekly Limits */}
      <section
        aria-labelledby="section-weekly"
        style={{
          marginTop: 16,
          backgroundColor: tokens.card,
          borderRadius: tokens.radius,
          boxShadow: tokens.shadow,
          padding: '16px 16px',
        }}
      >
        <h2
          id="section-weekly"
          style={{
            margin: '0 0 12px 0',
            fontSize: 15,
            fontWeight: 500,
            color: tokens.text,
            fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
          }}
        >
          Weekly Limits
        </h2>

        <ProgressBar pct={usage.weeklyPct} />

        <BarRow
          left={`${Math.round(usage.weeklyPct)}% used`}
          right={`Resets ${resetsLabel}`}
        />

        <WeeklyNudge weeklyPct={usage.weeklyPct} resetsAt={usage.resetsAt} />
      </section>

      {/* Credit detail — collapsed by default */}
      <CreditDetail
        creditsUsed={usage.creditsUsed}
        creditsCap={usage.creditsCap}
      />
    </>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// UsageMeters — main export
// ─────────────────────────────────────────────────────────────────────────────

export function UsageMeters({ userId }: UsageMetersProps) {
  const { usage, loading, error } = useUsage(userId);

  return (
    <main
      style={{
        backgroundColor: tokens.bg,
        minHeight: '100vh',
        padding: '24px 16px 48px',
        boxSizing: 'border-box',
        maxWidth: 560,
        margin: '0 auto',
      }}
      aria-label="Berean usage meters"
    >
      <h1
        style={{
          margin: '0 0 4px 0',
          fontSize: 22,
          fontWeight: 600,
          color: tokens.text,
          fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif',
        }}
      >
        Usage
      </h1>

      <p
        style={{
          margin: '0 0 8px 0',
          fontSize: 14,
          color: tokens.textSub,
          fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
        }}
      >
        Your Berean session and weekly usage at a glance.
      </p>

      {loading && (
        <p
          style={{
            fontSize: 14,
            color: tokens.textSub,
            fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
            marginTop: 32,
            textAlign: 'center',
          }}
          role="status"
          aria-live="polite"
        >
          Loading usage…
        </p>
      )}

      {!loading && error && (
        <p
          style={{
            fontSize: 14,
            color: tokens.textSub,
            fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
            marginTop: 32,
          }}
          role="alert"
        >
          Unable to load usage right now. Please try again later.
        </p>
      )}

      {!loading && !error && usage && <MeterContent usage={usage} />}
    </main>
  );
}

export default UsageMeters;
