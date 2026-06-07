/**
 * ScriptureReadAloud.tsx — Berean Phase 2B Scripture Read-Aloud Component
 *
 * Displays a Scripture passage in a clean white card and reads it aloud
 * using the Web Speech API (SpeechSynthesis). Falls back gracefully when
 * the API is unavailable (button hidden, no error thrown to the user).
 *
 * CLEAN-END GUARDRAIL: when reading finishes, state returns to idle.
 * No engagement prompt, no "read another?", no continuation hook.
 *
 * Design: tokens from contracts.ts, SF system font, no gold, no dark bg.
 * Unicode speaker icon used — no icon library required.
 */

import React, { useCallback, useEffect, useRef, useState } from 'react';
import { tokens, VoicePersona, VoiceSpeed } from '../../contracts';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

const FONT_FAMILY =
  "-apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif";

const SPEED_RATE: Record<VoiceSpeed, number> = {
  slow: 0.75,
  normal: 1.0,
  fast: 1.35,
};

/** Map persona to a pitch offset (subtle; SpeechSynthesis pitch range 0–2) */
const PERSONA_PITCH: Record<VoicePersona, number> = {
  still: 0.90,
  warm: 1.05,
  clear: 1.00,
  plain: 0.95,
};

// ─────────────────────────────────────────────────────────────────────────────
// Sentence tokeniser (simple — avoids a full NLP dependency)
// ─────────────────────────────────────────────────────────────────────────────

function splitSentences(text: string): string[] {
  // Split on sentence-ending punctuation followed by whitespace or end-of-string
  return text
    .split(/(?<=[.!?])\s+/)
    .map((s) => s.trim())
    .filter(Boolean);
}

// ─────────────────────────────────────────────────────────────────────────────
// Styles
// ─────────────────────────────────────────────────────────────────────────────

const styles = {
  card: {
    backgroundColor: tokens.card,
    borderRadius: tokens.radius,
    boxShadow: tokens.shadow,
    padding: '20px 18px 16px',
    fontFamily: FONT_FAMILY,
    width: '100%',
  } as React.CSSProperties,

  meta: {
    display: 'flex',
    alignItems: 'baseline',
    justifyContent: 'space-between',
    marginBottom: 12,
  } as React.CSSProperties,

  reference: {
    fontSize: 13,
    fontWeight: 600,
    color: tokens.textSub,
    letterSpacing: 0.2,
  } as React.CSSProperties,

  translation: {
    fontSize: 11,
    fontWeight: 500,
    color: tokens.textSub,
    textTransform: 'uppercase' as const,
    letterSpacing: 0.8,
  } as React.CSSProperties,

  passageWrapper: {
    fontSize: 16,
    lineHeight: 1.65,
    color: tokens.text,
    marginBottom: 16,
  } as React.CSSProperties,

  sentence: (highlighted: boolean): React.CSSProperties => ({
    backgroundColor: highlighted ? 'rgba(0,122,255,0.09)' : 'transparent',
    borderRadius: 4,
    padding: highlighted ? '0 3px' : '0',
    transition: 'background-color 0.25s ease',
    display: 'inline',
  }),

  divider: {
    height: 1,
    backgroundColor: tokens.divider,
    margin: '0 0 14px',
  } as React.CSSProperties,

  footer: {
    display: 'flex',
    alignItems: 'center',
    gap: 10,
  } as React.CSSProperties,

  readButton: (reading: boolean): React.CSSProperties => ({
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    padding: '8px 16px',
    backgroundColor: reading ? tokens.divider : tokens.accent,
    color: reading ? tokens.textSub : '#FFFFFF',
    border: 'none',
    borderRadius: 100,
    fontSize: 14,
    fontWeight: 600,
    fontFamily: FONT_FAMILY,
    cursor: reading ? 'default' : 'pointer',
    transition: 'background-color 0.18s ease, color 0.18s ease',
    letterSpacing: -0.1,
  }),

  statusText: {
    fontSize: 13,
    color: tokens.textSub,
  } as React.CSSProperties,
} as const;

// ─────────────────────────────────────────────────────────────────────────────
// Props
// ─────────────────────────────────────────────────────────────────────────────

export interface ScriptureReadAloudProps {
  reference: string;    // e.g. "John 3:16"
  text: string;         // verse text from BibleProvider
  translation: string;  // e.g. "BSB"
  persona: VoicePersona;
  speed: VoiceSpeed;
}

// ─────────────────────────────────────────────────────────────────────────────
// Component
// ─────────────────────────────────────────────────────────────────────────────

export function ScriptureReadAloud({
  reference,
  text,
  translation,
  persona,
  speed,
}: ScriptureReadAloudProps): JSX.Element {
  const [reading, setReading] = useState(false);
  const [activeSentenceIndex, setActiveSentenceIndex] = useState<number | null>(null);
  const utteranceRef = useRef<SpeechSynthesisUtterance | null>(null);
  const speechAvailable =
    typeof window !== 'undefined' && 'speechSynthesis' in window;

  const sentences = splitSentences(text);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (typeof window !== 'undefined' && window.speechSynthesis) {
        window.speechSynthesis.cancel();
      }
    };
  }, []);

  const stopReading = useCallback(() => {
    if (typeof window !== 'undefined' && window.speechSynthesis) {
      window.speechSynthesis.cancel();
    }
    // CLEAN-END: return to idle state — no prompt, no hook
    setReading(false);
    setActiveSentenceIndex(null);
  }, []);

  const startReading = useCallback(() => {
    if (!speechAvailable || reading) return;

    window.speechSynthesis.cancel();
    setReading(true);
    setActiveSentenceIndex(0);

    /**
     * Read sentence-by-sentence so we can highlight each one.
     * Each sentence is its own utterance chained via onend.
     */
    let currentIndex = 0;

    function readSentence(index: number) {
      if (index >= sentences.length) {
        // All sentences done — CLEAN-END, return to idle
        setReading(false);
        setActiveSentenceIndex(null);
        utteranceRef.current = null;
        return;
      }

      const utterance = new SpeechSynthesisUtterance(sentences[index]);
      utterance.rate = SPEED_RATE[speed];
      utterance.pitch = PERSONA_PITCH[persona];
      utterance.lang = 'en-US';

      utterance.onstart = () => {
        setActiveSentenceIndex(index);
      };

      utterance.onend = () => {
        currentIndex = index + 1;
        if (currentIndex < sentences.length) {
          readSentence(currentIndex);
        } else {
          // CLEAN-END
          setReading(false);
          setActiveSentenceIndex(null);
          utteranceRef.current = null;
        }
      };

      utterance.onerror = () => {
        // Silent fail — return to idle
        setReading(false);
        setActiveSentenceIndex(null);
        utteranceRef.current = null;
      };

      utteranceRef.current = utterance;
      window.speechSynthesis.speak(utterance);
    }

    readSentence(0);
  }, [speechAvailable, reading, sentences, speed, persona]);

  const handleButtonClick = useCallback(() => {
    if (reading) {
      stopReading();
    } else {
      startReading();
    }
  }, [reading, stopReading, startReading]);

  return (
    <div style={styles.card} role="region" aria-label={`Scripture: ${reference}`}>
      {/* Meta row */}
      <div style={styles.meta}>
        <span style={styles.reference}>{reference}</span>
        <span style={styles.translation}>{translation}</span>
      </div>

      {/* Passage text with sentence highlight */}
      <div style={styles.passageWrapper} aria-live="off">
        {sentences.map((sentence, i) => (
          <React.Fragment key={i}>
            <span style={styles.sentence(activeSentenceIndex === i)}>
              {sentence}
            </span>
            {i < sentences.length - 1 ? ' ' : ''}
          </React.Fragment>
        ))}
      </div>

      <div style={styles.divider} />

      {/* Footer: Read Aloud button + status */}
      <div style={styles.footer}>
        {speechAvailable && (
          <button
            style={styles.readButton(reading)}
            onClick={handleButtonClick}
            aria-label={
              reading
                ? `Stop reading ${reference}`
                : `Read ${reference} aloud`
            }
            aria-pressed={reading}
          >
            {/* Unicode speaker icon — no icon library */}
            <span aria-hidden="true">{reading ? '■' : '♪'}</span>
            {reading ? 'Stop' : 'Read Aloud'}
          </button>
        )}

        {reading && (
          <span
            style={styles.statusText}
            aria-live="polite"
            aria-atomic="true"
          >
            Reading…
          </span>
        )}
      </div>
    </div>
  );
}

export default ScriptureReadAloud;
