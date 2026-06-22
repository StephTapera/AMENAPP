/**
 * SelahVOTD.jsx
 *
 * Verse of the Day (VOTD) photo-hero card.
 *
 * Layout:
 *   - Photo hero fills the card (heroImageUrl prop, fallback gray gradient)
 *   - Bottom scrim: linear gradient transparent → rgba(0,0,0,0.65) at 45% height
 *   - Over the scrim: verse text bold white bottom-left, reference below it
 *   - Dark glass pill bottom-right: "Read Chapter" CTA
 *   - Floats in a §2 white card container
 *
 * NO vanity counters (no likes, shares, view counts) anywhere in this component.
 *
 * @prop {string}   verseRef      — canonical verse reference, e.g. "John 3:16"
 * @prop {string}   verseText     — display text of the verse (may be licensed; display only)
 * @prop {string}   reference     — formatted reference string for display, e.g. "John 3:16 (ESV)"
 * @prop {string}  [heroImageUrl] — URL of the hero image; falls back to gray gradient placeholder
 * @prop {(reference: string) => void} onReadChapter — called when user taps "Read Chapter"
 *
 * Design tokens (all from GLASS_TOKENS in selah.contracts.ts):
 *   §2  Floating white card (cardFill, cardRadius, cardShadow)
 *   §3  heroScrimGradient, heroScrimHeight, darkGlassPill, darkGlassPillBlur
 */

import React, { useState } from 'react';
import './selahGlass.css';

// Fallback placeholder when no heroImageUrl is provided.
// A neutral gray gradient — no gold, no cosmic gradients, no purple per GLASS_TOKENS.
const PLACEHOLDER_GRADIENT = 'linear-gradient(160deg, #C8C8CC 0%, #A0A0A6 100%)';

export default function SelahVOTD({
  verseRef,
  verseText,
  reference,
  heroImageUrl,
  onReadChapter,
}) {
  const [imageError, setImageError] = useState(false);
  const usePhoto = heroImageUrl && !imageError;

  return (
    /* §2 Floating white card */
    <article
      className="selah-card"
      aria-label={`Verse of the Day: ${reference}`}
      style={{
        padding: 0,           // card handles its own overflow; inner elements manage spacing
        position: 'relative',
        overflow: 'hidden',
        borderRadius: 28,
        // cardShadowAmbient + cardShadowTight
        boxShadow: '0 12px 40px rgba(0,0,0,0.10), 0 2px 8px rgba(0,0,0,0.04)',
        minHeight: 320,
        display: 'flex',
        flexDirection: 'column',
      }}
    >
      {/* ── Hero layer ──────────────────────────────────────────────── */}
      <div
        aria-hidden="true"
        style={{
          position: 'absolute',
          inset: 0,
          background: usePhoto ? undefined : PLACEHOLDER_GRADIENT,
          zIndex: 0,
        }}
      >
        {usePhoto && (
          <img
            src={heroImageUrl}
            alt=""          /* decorative; verse text conveys meaning */
            onError={() => setImageError(true)}
            style={{
              width: '100%',
              height: '100%',
              objectFit: 'cover',
              display: 'block',
            }}
          />
        )}
      </div>

      {/* ── Bottom scrim (§3): transparent → rgba(0,0,0,0.65) at 45% height ── */}
      <div
        aria-hidden="true"
        style={{
          position: 'absolute',
          bottom: 0,
          left: 0,
          right: 0,
          height: '45%',    // heroScrimHeight from §3
          background: 'linear-gradient(transparent, rgba(0,0,0,0.65))', // heroScrimGradient §3
          zIndex: 1,
        }}
      />

      {/* ── Content area: sits above the scrim ──────────────────────── */}
      <div
        style={{
          position: 'relative',
          zIndex: 2,
          marginTop: 'auto',   // push to bottom
          padding: '0 20px 20px',
          display: 'flex',
          flexDirection: 'row',
          alignItems: 'flex-end',
          justifyContent: 'space-between',
          gap: 12,
          minHeight: 120,
        }}
      >
        {/* Left column: verse text + reference */}
        <div style={{ flex: 1, minWidth: 0 }}>
          <p
            style={{
              margin: 0,
              fontSize: 18,
              fontWeight: 700,
              color: '#FFFFFF',
              lineHeight: 1.35,
              textShadow: '0 1px 4px rgba(0,0,0,0.40)',
              // clamp to 4 lines to prevent overflow
              display: '-webkit-box',
              WebkitLineClamp: 4,
              WebkitBoxOrient: 'vertical',
              overflow: 'hidden',
            }}
          >
            {verseText}
          </p>
          <p
            style={{
              margin: '6px 0 0',
              fontSize: 14,
              fontWeight: 500,
              color: 'rgba(255,255,255,0.70)',
              textShadow: '0 1px 3px rgba(0,0,0,0.35)',
            }}
          >
            {reference}
          </p>
        </div>

        {/* Right: dark glass pill — "Read Chapter" (§3 darkGlassPill) */}
        <button
          type="button"
          className="selah-glass-dark-pill"
          aria-label={`Read the chapter for ${verseRef}`}
          onClick={() => onReadChapter(verseRef)}
          style={{
            flexShrink: 0,
            paddingTop: 12,
            paddingBottom: 12,
            paddingLeft: 18,
            paddingRight: 18,
            fontSize: 14,
            fontWeight: 600,
            color: '#FFFFFF',
            cursor: 'pointer',
            border: 'none',
            whiteSpace: 'nowrap',
          }}
        >
          Read Chapter
        </button>
      </div>
    </article>
  );
}
