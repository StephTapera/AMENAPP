/**
 * DiscernmentCard.jsx — Berean Discernment Result Display Card
 *
 * Agent D — Discernment Surfacing
 * Consumes DiscernmentCheck from contracts (received via props, never imported directly).
 * All glass values from GLASS_TOKENS via selahGlass.css — no hardcoding.
 *
 * HARD CONSTRAINTS enforced here:
 * 1. Private-first: share is always opt-in (no auto-share)
 * 2. No pass/fail coloring: verdict chip uses neutral glass styling only
 * 3. No "FALSE/UNBIBLICAL" language in any copy
 * 4. Citations show translation label (BSB/WEB/KJV only)
 * 5. Refused state never shows an empty verdict chip
 */

import React, { useState } from 'react';
import './selahGlass.css';

// ─── Verdict label map ────────────────────────────────────────────────────────
// Labels are neutral descriptors — no pass/fail semantics, no red/green.
const VERDICT_LABELS = {
  aligns:      'Aligns',
  diverges:    'Diverges',
  contested:   'Contested',
  insufficient:'Insufficient',
};

// ─── Claim classification display map ────────────────────────────────────────
const CLAIM_CLASS_LABELS = {
  doctrinal:    'Doctrinal',
  ethical:      'Ethical',
  historical:   'Historical',
  devotional:   'Devotional',
  unverifiable: 'Unverifiable',
};

// ─── Sub-components ───────────────────────────────────────────────────────────

/** Animated placeholder row used during loading state. */
function PulsePlaceholder({ width = '100%', height = 16, marginBottom = 10 }) {
  return (
    <div
      style={{
        width,
        height,
        marginBottom,
        borderRadius: 8,
        background: 'linear-gradient(90deg, #E8E8EA 25%, #F2F2F4 50%, #E8E8EA 75%)',
        backgroundSize: '200% 100%',
        animation: 'selah-pulse 1.6s ease-in-out infinite',
      }}
      aria-hidden="true"
    />
  );
}

/** §7 citation inset block — shows reference, translation label, verse text. */
function CitationBlock({ citation }) {
  return (
    <div className="selah-citation-block" style={{ marginBottom: 10 }}>
      <p
        style={{
          margin: '0 0 4px 0',
          fontSize: 12,
          fontWeight: 600,
          color: '#8A8A8E',
          letterSpacing: 0.3,
          textTransform: 'uppercase',
        }}
      >
        {citation.reference}
        <span
          style={{
            marginLeft: 6,
            fontWeight: 400,
            fontSize: 11,
            color: '#AEAEB2',
          }}
        >
          {citation.translation}
        </span>
      </p>
      <p
        style={{
          margin: 0,
          fontSize: 15,
          lineHeight: 1.55,
          color: '#0A0A0A',
        }}
      >
        {citation.text}
      </p>
    </div>
  );
}

/** Frosted capsule verdict chip — neutral styling only, no red/green. */
function VerdictChip({ verdict }) {
  const label = VERDICT_LABELS[verdict] ?? verdict;
  return (
    <span
      className="selah-glass-light"
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        height: 32,
        padding: '0 14px',
        borderRadius: 999,
        fontSize: 13,
        fontWeight: 600,
        color: '#0A0A0A',
        letterSpacing: 0.1,
        userSelect: 'none',
      }}
      aria-label={`Verdict: ${label}`}
    >
      {label}
    </span>
  );
}

/** Individual claim row with classification badge. */
function ClaimRow({ claim }) {
  const classLabel = CLAIM_CLASS_LABELS[claim.classification] ?? claim.classification;
  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'flex-start',
        gap: 10,
        marginBottom: 10,
      }}
    >
      <span
        style={{
          flexShrink: 0,
          marginTop: 2,
          height: 20,
          padding: '0 8px',
          borderRadius: 999,
          background: '#F5F5F6',
          fontSize: 11,
          fontWeight: 600,
          color: '#8A8A8E',
          display: 'inline-flex',
          alignItems: 'center',
          textTransform: 'uppercase',
          letterSpacing: 0.4,
          whiteSpace: 'nowrap',
        }}
      >
        {classLabel}
      </span>
      <p style={{ margin: 0, fontSize: 14, lineHeight: 1.5, color: '#0A0A0A' }}>
        {claim.text}
      </p>
    </div>
  );
}

/** Perspective card for a single theological tradition (contested verdict). */
function PerspectiveCard({ perspective }) {
  return (
    <div
      className="selah-citation-block"
      style={{ marginBottom: 12 }}
    >
      <p
        style={{
          margin: '0 0 4px 0',
          fontSize: 12,
          fontWeight: 700,
          color: '#0A0A0A',
          textTransform: 'uppercase',
          letterSpacing: 0.5,
        }}
      >
        {perspective.tradition}
      </p>
      <p style={{ margin: '0 0 10px 0', fontSize: 14, lineHeight: 1.5, color: '#3A3A3C' }}>
        {perspective.summary}
      </p>
      {perspective.citations && perspective.citations.length > 0 && (
        <div>
          {perspective.citations.map((c, i) => (
            <CitationBlock key={`${c.reference}-${i}`} citation={c} />
          ))}
        </div>
      )}
    </div>
  );
}

/** Segmented switcher for contested perspectives (more than 2 traditions). */
function PerspectivesSwitcher({ perspectives }) {
  const [activeIndex, setActiveIndex] = useState(0);

  if (perspectives.length === 1) {
    return <PerspectiveCard perspective={perspectives[0]} />;
  }

  // Use stacked cards for 2 traditions, segmented switcher for 3+
  if (perspectives.length === 2) {
    return (
      <div>
        {perspectives.map((p, i) => (
          <PerspectiveCard key={`${p.tradition}-${i}`} perspective={p} />
        ))}
      </div>
    );
  }

  return (
    <div>
      <div
        className="selah-segmented-track"
        role="tablist"
        aria-label="Theological perspectives"
        style={{ marginBottom: 12, overflowX: 'auto', display: 'flex', maxWidth: '100%' }}
      >
        {perspectives.map((p, i) => (
          <button
            key={`tab-${i}`}
            role="tab"
            aria-selected={activeIndex === i}
            aria-controls={`perspective-panel-${i}`}
            className={`selah-segmented-option${activeIndex === i ? ' selah-segmented-selected' : ''}`}
            onClick={() => setActiveIndex(i)}
          >
            {p.tradition}
          </button>
        ))}
      </div>
      {perspectives.map((p, i) => (
        <div
          key={`panel-${i}`}
          id={`perspective-panel-${i}`}
          role="tabpanel"
          aria-label={p.tradition}
          hidden={activeIndex !== i}
        >
          <PerspectiveCard perspective={p} />
        </div>
      ))}
    </div>
  );
}

/** Section label with divider. */
function SectionLabel({ children }) {
  return (
    <p
      style={{
        margin: '16px 0 8px 0',
        fontSize: 11,
        fontWeight: 700,
        color: '#8A8A8E',
        textTransform: 'uppercase',
        letterSpacing: 0.8,
      }}
    >
      {children}
    </p>
  );
}

// ─── Loading state ─────────────────────────────────────────────────────────────

function LoadingState() {
  return (
    <>
      <style>{`
        @keyframes selah-pulse {
          0%   { background-position: 200% 0; }
          100% { background-position: -200% 0; }
        }
      `}</style>
      <div
        className="selah-card"
        role="status"
        aria-label="Loading Berean check"
        aria-live="polite"
        aria-busy="true"
      >
        {/* Header row */}
        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 18 }}>
          <PulsePlaceholder width="40%" height={18} marginBottom={0} />
          <PulsePlaceholder width="20%" height={18} marginBottom={0} />
        </div>
        {/* Verdict chip placeholder */}
        <PulsePlaceholder width="28%" height={32} marginBottom={16} />
        {/* Claims */}
        <PulsePlaceholder width="90%" />
        <PulsePlaceholder width="75%" />
        {/* Citations */}
        <div
          style={{
            marginTop: 16,
            background: '#F5F5F6',
            borderRadius: 16,
            padding: '14px 16px',
          }}
        >
          <PulsePlaceholder width="35%" height={12} />
          <PulsePlaceholder width="100%" />
          <PulsePlaceholder width="80%" marginBottom={0} />
        </div>
      </div>
    </>
  );
}

// ─── Refused state ─────────────────────────────────────────────────────────────

const DEFAULT_REFUSAL_COPY =
  'Unable to assess this claim against Scripture at this time.';

function RefusedState({ check, onDismiss }) {
  return (
    <div className="selah-card" role="region" aria-label="Berean check result">
      {/* Header */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          marginBottom: 16,
        }}
      >
        <div>
          <p
            style={{
              margin: 0,
              fontSize: 16,
              fontWeight: 700,
              color: '#0A0A0A',
              letterSpacing: -0.2,
            }}
          >
            Berean Check
          </p>
          <p style={{ margin: '2px 0 0 0', fontSize: 12, color: '#8A8A8E' }}>
            Acts 17:11 · 1 Thess 5:21
          </p>
        </div>
        <button
          onClick={onDismiss}
          className="selah-glass-circle"
          aria-label="Dismiss Berean check"
          style={{ flexShrink: 0 }}
        >
          ×
        </button>
      </div>

      {/* Refusal block — no verdict chip, calm copy only */}
      <div className="selah-citation-block">
        <p
          style={{
            margin: 0,
            fontSize: 15,
            lineHeight: 1.6,
            color: '#3A3A3C',
          }}
        >
          {check.refusalReason || DEFAULT_REFUSAL_COPY}
        </p>
      </div>

      {/* Privacy badge */}
      <p
        style={{
          margin: '14px 0 0 0',
          fontSize: 12,
          color: '#AEAEB2',
          textAlign: 'center',
        }}
      >
        Private — only visible to you
      </p>
    </div>
  );
}

// ─── Grounded state (aligns / diverges / insufficient / contested) ─────────────

function GroundedState({ check, onShare, onDismiss, isSharing }) {
  const isContested = check.verdict === 'contested';

  // Build a map from claim index to its citations for display grouping.
  // Since DiscernmentCheck.citations is a flat array, we display all together.
  // Claims and citations are rendered in parallel sections.

  return (
    <div className="selah-card" role="region" aria-label="Berean check result">
      {/* Header */}
      <div
        style={{
          display: 'flex',
          alignItems: 'flex-start',
          justifyContent: 'space-between',
          marginBottom: 14,
        }}
      >
        <div>
          <p
            style={{
              margin: 0,
              fontSize: 16,
              fontWeight: 700,
              color: '#0A0A0A',
              letterSpacing: -0.2,
            }}
          >
            Berean Check
          </p>
          <p style={{ margin: '2px 0 0 0', fontSize: 12, color: '#8A8A8E' }}>
            Acts 17:11 · 1 Thess 5:21
          </p>
        </div>
        <button
          onClick={onDismiss}
          className="selah-glass-circle"
          aria-label="Dismiss Berean check"
          style={{ flexShrink: 0 }}
        >
          ×
        </button>
      </div>

      {/* Verdict chip — frosted capsule, neutral styling only */}
      <div style={{ marginBottom: 18 }}>
        <VerdictChip verdict={check.verdict} />
      </div>

      {/* Claims section */}
      {check.claims && check.claims.length > 0 && (
        <div>
          <SectionLabel>Claims assessed</SectionLabel>
          {check.claims.map((claim, i) => (
            <ClaimRow key={i} claim={claim} />
          ))}
        </div>
      )}

      {/* Citations section */}
      {check.citations && check.citations.length > 0 && (
        <div>
          <SectionLabel>Scripture</SectionLabel>
          {check.citations.map((citation, i) => (
            <CitationBlock key={`${citation.reference}-${i}`} citation={citation} />
          ))}
        </div>
      )}

      {/* Perspectives section — only for contested verdict */}
      {isContested && check.perspectives && check.perspectives.length > 0 && (
        <div>
          <SectionLabel>Perspectives across traditions</SectionLabel>
          <PerspectivesSwitcher perspectives={check.perspectives} />
        </div>
      )}

      {/* Footer: privacy badge + optional share */}
      <div
        style={{
          marginTop: 20,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          flexWrap: 'wrap',
          gap: 8,
        }}
      >
        <p
          style={{
            margin: 0,
            fontSize: 12,
            color: '#AEAEB2',
          }}
        >
          Private — only visible to you
        </p>

        {/* Share button — secondary, not prominent; opt-in only */}
        <button
          onClick={onShare}
          disabled={isSharing}
          className="selah-glass-pill"
          aria-label="Share this Berean check to the thread"
          style={{
            fontSize: 13,
            height: 36,
            opacity: isSharing ? 0.55 : 1,
            cursor: isSharing ? 'default' : 'pointer',
          }}
        >
          {isSharing ? (
            <span aria-live="polite" aria-busy="true">
              Sharing…
            </span>
          ) : (
            'Share to thread'
          )}
        </button>
      </div>
    </div>
  );
}

// ─── Main export ───────────────────────────────────────────────────────────────

/**
 * DiscernmentCard
 *
 * Props:
 *   check: DiscernmentCheck | null  — null triggers loading state
 *   onShare() → void
 *   onDismiss() → void
 *   isSharing: boolean
 */
export default function DiscernmentCard({ check, onShare, onDismiss, isSharing }) {
  // State 1: Loading
  if (check === null) {
    return <LoadingState />;
  }

  // State 2: Refused — no verdict chip, calm copy, no citations
  if (check.status === 'refused') {
    return <RefusedState check={check} onDismiss={onDismiss} />;
  }

  // State 3 + 4: Grounded (aligns/diverges/insufficient) and Contested
  // Both use GroundedState; contested branch is handled inside via check.verdict === 'contested'
  return (
    <GroundedState
      check={check}
      onShare={onShare}
      onDismiss={onDismiss}
      isSharing={isSharing}
    />
  );
}
