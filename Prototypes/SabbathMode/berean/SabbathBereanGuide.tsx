/**
 * SabbathBereanGuide.tsx
 * Phase 2D — Berean Sabbath Guide
 * Date: 2026-06-07
 *
 * React component for the Berean Sabbath Guide UI.
 *
 * Design rules (enforced here — any violation = reject):
 * - White card on gray page (SabbathTokens only)
 * - NO gold (#C9A84C, #FFD97D), NO purple, NO dark gradient
 * - NO serif font (Cormorant Garamond or similar)
 * - NO streak counters, badges, scores, or comparative metrics
 * - Loading: pulsing text only — no brand-colored spinners
 * - Error: shown inline — no retry button (user re-submits)
 * - Footer: "Berean leads, it does not answer for you." — tertiary, small
 * - family_questions: shows dinner-table note before response
 *
 * Task title map:
 *   sabbath_guide      → "Prayer Guide"
 *   family_questions   → "Family Questions"
 *   sermon_prep        → "Reflect on the Message"
 *   devotional         → "Family Devotional"
 *   reflection_prompt  → "Reflection"
 */

import React, { useState, useCallback } from 'react';
import type { SabbathAITask } from '../contracts/SabbathRouting';
import { SabbathTokens } from '../ui/SabbathTokens';
import { getLiturgicalContext } from './liturgicalSeason';
import { callSabbathModel, type SabbathModelResponse } from './callSabbathModel';

// ── Props ─────────────────────────────────────────────────────────────────────

interface SabbathBereanGuideProps {
  task: SabbathAITask;
  onClose: () => void;
  uid: string;
  userName?: string;
  sermonText?: string;
}

// ── Task Metadata ─────────────────────────────────────────────────────────────

const TASK_TITLES: Record<SabbathAITask, string> = {
  sabbath_guide: 'Prayer Guide',
  family_questions: 'Family Questions',
  sermon_prep: 'Reflect on the Message',
  devotional: 'Family Devotional',
  reflection_prompt: 'Reflection',
};

const TASK_PLACEHOLDER: Record<SabbathAITask, string> = {
  sabbath_guide: 'What are you bringing to prayer today?',
  family_questions: 'Any themes from this week your family might explore?',
  sermon_prep: 'Share a phrase or passage from the message you heard today.',
  devotional: 'Anything your family is sitting with this Sabbath?',
  reflection_prompt: 'Anything on your heart before you write?',
};

// ── Styles ────────────────────────────────────────────────────────────────────
// All values come from SabbathTokens. No inline hex codes for brand colors.

const styles = {
  page: {
    minHeight: '100vh',
    backgroundColor: SabbathTokens.pageBg,
    fontFamily: SabbathTokens.fontStack,
    padding: '24px 16px',
    boxSizing: 'border-box' as const,
  },
  card: {
    backgroundColor: SabbathTokens.cardBg,
    border: SabbathTokens.cardBorder,
    borderRadius: SabbathTokens.radiusCard,
    boxShadow: SabbathTokens.cardShadow,
    padding: '28px 24px',
    maxWidth: '600px',
    margin: '0 auto',
  },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: '24px',
  },
  title: {
    fontSize: '20px',
    fontWeight: '600',
    color: SabbathTokens.textPrimary,
    margin: 0,
    letterSpacing: '-0.3px',
  },
  closeButton: {
    background: 'none',
    border: 'none',
    cursor: 'pointer',
    fontSize: '18px',
    color: SabbathTokens.textTertiary,
    padding: '4px 8px',
    borderRadius: '8px',
    lineHeight: 1,
  },
  divider: {
    height: '1px',
    backgroundColor: SabbathTokens.dividerBg,
    margin: '0 0 24px 0',
  },
  textarea: {
    width: '100%',
    minHeight: '96px',
    border: `1px solid rgba(0,0,0,0.12)`,
    borderRadius: SabbathTokens.radiusInner,
    padding: '14px 16px',
    fontSize: '16px',
    fontFamily: SabbathTokens.fontStack,
    color: SabbathTokens.textPrimary,
    backgroundColor: SabbathTokens.pageBg,
    resize: 'vertical' as const,
    outline: 'none',
    lineHeight: '1.5',
    boxSizing: 'border-box' as const,
  },
  beginButton: {
    display: 'block',
    width: '100%',
    marginTop: '16px',
    padding: '14px 0',
    backgroundColor: '#000000',
    color: '#FFFFFF',
    border: 'none',
    borderRadius: SabbathTokens.radiusPill,
    fontSize: '16px',
    fontWeight: '600',
    fontFamily: SabbathTokens.fontStack,
    cursor: 'pointer',
    letterSpacing: '-0.2px',
  },
  beginButtonDisabled: {
    opacity: 0.4,
    cursor: 'not-allowed',
  },
  loadingText: {
    marginTop: '28px',
    textAlign: 'center' as const,
    color: SabbathTokens.textTertiary,
    fontSize: '15px',
    fontStyle: 'italic',
    animation: 'sabbath-pulse 1.6s ease-in-out infinite',
  },
  familyNote: {
    backgroundColor: SabbathTokens.pageBg,
    borderRadius: SabbathTokens.radiusInner,
    padding: '12px 16px',
    marginTop: '24px',
    marginBottom: '4px',
    fontSize: '13px',
    color: SabbathTokens.textSecondary,
    lineHeight: '1.5',
  },
  responseArea: {
    marginTop: '24px',
    paddingTop: '20px',
    borderTop: `1px solid ${SabbathTokens.dividerBg}`,
  },
  responseText: {
    fontSize: '17px',
    lineHeight: '1.7',
    color: SabbathTokens.textSecondary,
    whiteSpace: 'pre-wrap' as const,
  },
  errorText: {
    marginTop: '24px',
    paddingTop: '16px',
    borderTop: `1px solid ${SabbathTokens.dividerBg}`,
    fontSize: '15px',
    color: '#B00020',
    lineHeight: '1.5',
  },
  footer: {
    marginTop: '32px',
    paddingTop: '16px',
    borderTop: `1px solid ${SabbathTokens.dividerBg}`,
    textAlign: 'center' as const,
    fontSize: '12px',
    color: SabbathTokens.textTertiary,
    lineHeight: '1.4',
    fontStyle: 'italic',
  },
} as const;

// ── Pulse Animation (injected once) ──────────────────────────────────────────

const PULSE_STYLE_ID = 'sabbath-berean-guide-pulse';

function ensurePulseAnimation(): void {
  if (typeof document === 'undefined') return;
  if (document.getElementById(PULSE_STYLE_ID)) return;
  const style = document.createElement('style');
  style.id = PULSE_STYLE_ID;
  style.textContent = `
    @keyframes sabbath-pulse {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.4; }
    }
  `;
  document.head.appendChild(style);
}

// ── Component ─────────────────────────────────────────────────────────────────

export const SabbathBereanGuide: React.FC<SabbathBereanGuideProps> = ({
  task,
  onClose,
  uid,
  userName,
  sermonText,
}) => {
  ensurePulseAnimation();

  const [userInput, setUserInput] = useState('');
  const [loading, setLoading] = useState(false);
  const [response, setResponse] = useState<SabbathModelResponse | null>(null);

  const title = TASK_TITLES[task];
  const placeholder = TASK_PLACEHOLDER[task];
  const isFamilyQuestions = task === 'family_questions';

  const handleBegin = useCallback(async () => {
    if (loading) return;

    // Reset previous response
    setResponse(null);
    setLoading(true);

    try {
      const liturgicalContext = getLiturgicalContext(new Date());

      const result = await callSabbathModel({
        task,
        userInput: userInput.trim(),
        liturgicalContext,
        userName,
        sermonText,
        hasFamily: isFamilyQuestions,
        uid,
      });

      setResponse(result);
    } catch {
      // Unexpected error from callSabbathModel (should not happen — it catches internally)
      setResponse({
        text: '',
        task,
        moderationPassed: false,
        error: 'Berean Guide is not available right now. Please try again in a moment.',
      });
    } finally {
      setLoading(false);
    }
  }, [loading, userInput, task, uid, userName, sermonText, isFamilyQuestions]);

  const hasResponse = response !== null && !response.error && response.text.trim().length > 0;
  const hasError =
    response !== null &&
    (response.error != null ||
      (!response.moderationPassed && response.text.length === 0));

  const errorMessage = response?.error ?? 'This response could not be shown right now.';

  return (
    <div style={styles.page}>
      <div style={styles.card}>
        {/* Header */}
        <div style={styles.header}>
          <h2 style={styles.title}>{title}</h2>
          <button
            style={styles.closeButton}
            onClick={onClose}
            aria-label="Close Berean Guide"
          >
            ×
          </button>
        </div>

        <div style={styles.divider} />

        {/* Input area */}
        <textarea
          style={styles.textarea}
          placeholder={placeholder}
          value={userInput}
          onChange={(e) => setUserInput(e.target.value)}
          disabled={loading}
          aria-label="Share your context with Berean"
          rows={4}
        />

        {/* Begin button */}
        <button
          style={{
            ...styles.beginButton,
            ...(loading ? styles.beginButtonDisabled : {}),
          }}
          onClick={handleBegin}
          disabled={loading}
          aria-busy={loading}
        >
          {loading ? 'Preparing...' : 'Begin'}
        </button>

        {/* Loading state */}
        {loading && (
          <p style={styles.loadingText} aria-live="polite" aria-atomic>
            Berean is preparing...
          </p>
        )}

        {/* Family questions note */}
        {isFamilyQuestions && hasResponse && (
          <div style={styles.familyNote} role="note">
            These questions are for your dinner table. Use them as conversation starters.
          </div>
        )}

        {/* Response area */}
        {hasResponse && (
          <div style={styles.responseArea} aria-live="polite">
            <p style={styles.responseText}>{response!.text}</p>
          </div>
        )}

        {/* Error state */}
        {hasError && (
          <div style={styles.errorText} role="alert" aria-live="assertive">
            {errorMessage}
          </div>
        )}

        {/* Footer */}
        <div style={styles.footer}>
          Berean leads, it does not answer for you.
        </div>
      </div>
    </div>
  );
};

export default SabbathBereanGuide;
