/**
 * VoiceSettings.tsx — Berean Phase 2B Voice Settings Screen
 *
 * Design contract (from contracts.ts tokens):
 *   bg: '#F4F4F2', card: '#FFFFFF', text: '#0A0A0A',
 *   textSub: '#6B6B6B', accent: '#007AFF', radius: 20
 * SF system font only. No gold, no dark, no Cormorant.
 * No engagement hooks, no streaks, no "suggested for you" copy.
 */

import React, { useState, useCallback } from 'react';
import { tokens, VoicePersona, VoiceMode, VoiceSpeed } from '../contracts';
import { VoiceSettings as VoiceSettingsData, voiceService } from './voiceService';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

const FONT_FAMILY =
  "-apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif";

const PERSONAS: { id: VoicePersona; label: string; description: string }[] = [
  {
    id: 'still',
    label: 'Still',
    description: 'Quiet, measured — suited for meditation and reflection.',
  },
  {
    id: 'warm',
    label: 'Warm',
    description: 'Gentle and pastoral — a caring, unhurried presence.',
  },
  {
    id: 'clear',
    label: 'Clear',
    description: 'Precise and grounded — ideal for study and doctrine.',
  },
  {
    id: 'plain',
    label: 'Plain',
    description: 'Unadorned and direct — the text, nothing more.',
  },
];

const LANGUAGES: { code: string; label: string; beta: boolean }[] = [
  { code: 'en', label: 'English', beta: false },
  { code: 'es', label: 'Spanish', beta: true },
  { code: 'pt', label: 'Portuguese', beta: true },
  { code: 'fr', label: 'French', beta: true },
  { code: 'de', label: 'German', beta: true },
  { code: 'zh', label: 'Chinese (Simplified)', beta: true },
  { code: 'ko', label: 'Korean', beta: true },
  { code: 'sw', label: 'Swahili', beta: true },
];

// ─────────────────────────────────────────────────────────────────────────────
// Styles
// ─────────────────────────────────────────────────────────────────────────────

const styles = {
  page: {
    backgroundColor: tokens.bg,
    minHeight: '100vh',
    fontFamily: FONT_FAMILY,
    padding: '0 0 48px 0',
  } as React.CSSProperties,

  header: {
    padding: '24px 20px 8px',
  } as React.CSSProperties,

  title: {
    fontSize: 22,
    fontWeight: 700,
    color: tokens.text,
    margin: 0,
    letterSpacing: -0.4,
  } as React.CSSProperties,

  subtitle: {
    fontSize: 14,
    color: tokens.textSub,
    margin: '4px 0 0',
  } as React.CSSProperties,

  section: {
    padding: '20px 20px 0',
  } as React.CSSProperties,

  sectionLabel: {
    fontSize: 12,
    fontWeight: 600,
    color: tokens.textSub,
    textTransform: 'uppercase' as const,
    letterSpacing: 0.8,
    marginBottom: 10,
  } as React.CSSProperties,

  personaRow: {
    display: 'flex',
    overflowX: 'auto' as const,
    gap: 10,
    paddingBottom: 4,
    WebkitOverflowScrolling: 'touch' as const,
    scrollbarWidth: 'none' as const,
  } as React.CSSProperties,

  personaCard: (selected: boolean): React.CSSProperties => ({
    minWidth: 130,
    backgroundColor: tokens.card,
    borderRadius: tokens.radius,
    border: selected ? `2px solid ${tokens.accent}` : `2px solid ${tokens.divider}`,
    boxShadow: tokens.shadow,
    padding: '14px 14px 12px',
    cursor: 'pointer',
    transition: 'border-color 0.18s ease',
    flexShrink: 0,
  }),

  personaName: (selected: boolean): React.CSSProperties => ({
    fontSize: 15,
    fontWeight: 600,
    color: selected ? tokens.accent : tokens.text,
    marginBottom: 4,
    transition: 'color 0.18s ease',
  }),

  personaDesc: {
    fontSize: 12,
    color: tokens.textSub,
    lineHeight: 1.4,
  } as React.CSSProperties,

  card: {
    backgroundColor: tokens.card,
    borderRadius: tokens.radius,
    boxShadow: tokens.shadow,
    padding: '4px 0',
    overflow: 'hidden',
  } as React.CSSProperties,

  selectWrapper: {
    padding: '10px 16px',
  } as React.CSSProperties,

  select: {
    width: '100%',
    border: 'none',
    outline: 'none',
    backgroundColor: 'transparent',
    fontSize: 15,
    color: tokens.text,
    fontFamily: FONT_FAMILY,
    cursor: 'pointer',
    appearance: 'none' as const,
    WebkitAppearance: 'none' as const,
    backgroundImage: `url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='8' viewBox='0 0 12 8'%3E%3Cpath d='M1 1l5 5 5-5' stroke='%236B6B6B' stroke-width='1.5' fill='none' stroke-linecap='round'/%3E%3C/svg%3E")`,
    backgroundRepeat: 'no-repeat',
    backgroundPosition: 'right 0 center',
    paddingRight: 20,
  } as React.CSSProperties,

  segmentedControl: {
    display: 'flex',
    backgroundColor: tokens.divider,
    borderRadius: 10,
    padding: 2,
    gap: 2,
  } as React.CSSProperties,

  segment: (selected: boolean): React.CSSProperties => ({
    flex: 1,
    padding: '8px 0',
    textAlign: 'center',
    borderRadius: 8,
    cursor: 'pointer',
    fontSize: 14,
    fontWeight: selected ? 600 : 400,
    color: selected ? '#FFFFFF' : tokens.textSub,
    backgroundColor: selected ? tokens.accent : 'transparent',
    transition: 'background-color 0.18s ease, color 0.18s ease',
    userSelect: 'none' as const,
  }),

  modeDescription: {
    fontSize: 13,
    color: tokens.textSub,
    marginTop: 8,
    lineHeight: 1.45,
  } as React.CSSProperties,

  saveButton: {
    margin: '32px 20px 0',
    display: 'block',
    width: 'calc(100% - 40px)',
    padding: '15px 0',
    backgroundColor: tokens.accent,
    color: '#FFFFFF',
    border: 'none',
    borderRadius: tokens.radius,
    fontSize: 16,
    fontWeight: 600,
    fontFamily: FONT_FAMILY,
    cursor: 'pointer',
    letterSpacing: -0.2,
    transition: 'opacity 0.15s ease',
  } as React.CSSProperties,

  saveButtonSaving: {
    opacity: 0.6,
    cursor: 'not-allowed',
  } as React.CSSProperties,

  divider: {
    height: 1,
    backgroundColor: tokens.divider,
    margin: '0 16px',
  } as React.CSSProperties,
} as const;

// ─────────────────────────────────────────────────────────────────────────────
// Props
// ─────────────────────────────────────────────────────────────────────────────

interface VoiceSettingsProps {
  userId: string;
  initialSettings?: Partial<VoiceSettingsData>;
  /**
   * Injected Firestore writer — (path, data) => Promise<void>.
   * Keeps this component free of direct Firebase imports.
   */
  firestoreWriter: (path: string, data: Record<string, unknown>) => Promise<void>;
  onSaved?: () => void;
}

// ─────────────────────────────────────────────────────────────────────────────
// Component
// ─────────────────────────────────────────────────────────────────────────────

export function VoiceSettings({
  userId,
  initialSettings,
  firestoreWriter,
  onSaved,
}: VoiceSettingsProps): JSX.Element {
  const [persona, setPersona] = useState<VoicePersona>(
    initialSettings?.persona ?? 'still'
  );
  const [language, setLanguage] = useState<string>(
    initialSettings?.language ?? 'en'
  );
  const [speed, setSpeed] = useState<VoiceSpeed>(
    initialSettings?.speed ?? 'normal'
  );
  const [mode, setMode] = useState<VoiceMode>(
    initialSettings?.mode ?? 'push_to_talk'
  );
  const [saving, setSaving] = useState(false);
  const [savedFeedback, setSavedFeedback] = useState(false);

  const handleSave = useCallback(async () => {
    if (saving) return;
    setSaving(true);
    try {
      await voiceService.saveSettings(
        userId,
        { persona, speed, language, mode },
        firestoreWriter
      );
      setSavedFeedback(true);
      setTimeout(() => setSavedFeedback(false), 1800);
      onSaved?.();
    } finally {
      setSaving(false);
    }
  }, [saving, userId, persona, speed, language, mode, firestoreWriter, onSaved]);

  const modeDescription =
    mode === 'hands_free'
      ? 'Continuous listening for quiet environments.'
      : 'Hold button to speak, release to send.';

  return (
    <div style={styles.page}>
      {/* Header */}
      <div style={styles.header}>
        <h1 style={styles.title}>Voice</h1>
        <p style={styles.subtitle}>Configure how Berean speaks and listens.</p>
      </div>

      {/* Persona */}
      <div style={styles.section}>
        <div style={styles.sectionLabel}>Persona</div>
        <div style={styles.personaRow}>
          {PERSONAS.map((p) => (
            <button
              key={p.id}
              style={styles.personaCard(persona === p.id)}
              onClick={() => setPersona(p.id)}
              aria-pressed={persona === p.id}
              aria-label={`${p.label} voice persona: ${p.description}`}
            >
              <div style={styles.personaName(persona === p.id)}>{p.label}</div>
              <div style={styles.personaDesc}>{p.description}</div>
            </button>
          ))}
        </div>
      </div>

      {/* Language */}
      <div style={styles.section}>
        <div style={styles.sectionLabel}>Language (Beta)</div>
        <div style={styles.card}>
          <div style={styles.selectWrapper}>
            <select
              style={styles.select}
              value={language}
              onChange={(e) => setLanguage(e.target.value)}
              aria-label="Select voice language"
            >
              {LANGUAGES.map((lang) => (
                <option key={lang.code} value={lang.code}>
                  {lang.label}
                  {lang.beta ? ' (Beta)' : ''}
                </option>
              ))}
            </select>
          </div>
        </div>
      </div>

      {/* Speed */}
      <div style={styles.section}>
        <div style={styles.sectionLabel}>Speed</div>
        <div style={styles.card}>
          <div style={{ padding: '10px 12px' }}>
            <div style={styles.segmentedControl} role="group" aria-label="Playback speed">
              {(['slow', 'normal', 'fast'] as VoiceSpeed[]).map((s) => (
                <div
                  key={s}
                  style={styles.segment(speed === s)}
                  onClick={() => setSpeed(s)}
                  role="radio"
                  aria-checked={speed === s}
                  tabIndex={0}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' || e.key === ' ') setSpeed(s);
                  }}
                >
                  {s.charAt(0).toUpperCase() + s.slice(1)}
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>

      {/* Mode */}
      <div style={styles.section}>
        <div style={styles.sectionLabel}>Mode</div>
        <div style={styles.card}>
          <div style={{ padding: '10px 12px' }}>
            <div style={styles.segmentedControl} role="group" aria-label="Voice mode">
              {(
                [
                  { id: 'hands_free' as VoiceMode, label: 'Hands-Free' },
                  { id: 'push_to_talk' as VoiceMode, label: 'Push to Talk' },
                ] as const
              ).map((m) => (
                <div
                  key={m.id}
                  style={styles.segment(mode === m.id)}
                  onClick={() => setMode(m.id)}
                  role="radio"
                  aria-checked={mode === m.id}
                  tabIndex={0}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' || e.key === ' ') setMode(m.id);
                  }}
                >
                  {m.label}
                </div>
              ))}
            </div>
            <p style={styles.modeDescription}>{modeDescription}</p>
          </div>
        </div>
      </div>

      {/* Save */}
      <button
        style={{
          ...styles.saveButton,
          ...(saving ? styles.saveButtonSaving : {}),
        }}
        onClick={handleSave}
        disabled={saving}
        aria-label="Save voice settings"
      >
        {savedFeedback ? 'Saved' : saving ? 'Saving…' : 'Save Voice Settings'}
      </button>
    </div>
  );
}

export default VoiceSettings;
