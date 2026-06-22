/**
 * SelahAnnotationPanel.jsx
 *
 * Bottom-sheet panel for creating and editing SelahNotes (highlights, notes,
 * questions, prayers). Appears when the user picks an action from the verse
 * context menu.
 *
 * @prop {string}  verseRef        — canonical verse reference, e.g. "James 1:5"
 * @prop {'highlight'|'note'|'question'|'prayer'} mode — determines which sub-UI renders
 * @prop {import('../selah.contracts').SelahNote|undefined} existingNote — pre-populate for edit
 * @prop {(noteData: Partial<import('../selah.contracts').SelahNote>) => void} onCreateNote
 *   Called with the note payload; caller writes to Firestore users/{uid}/selahNotes/{noteId}.
 *   Hard contract: this path never passes translationRead to the AI citation layer.
 * @prop {(noteId: string) => void} onDeleteNote
 *   Soft-delete only: sets deletedAt timestamp; never hard-deletes.
 * @prop {() => void} onDismiss — close the sheet without saving
 *
 * GLASS_TOKENS used (all values from selah.contracts.ts):
 *   §4 light frosted glass for the sheet itself
 *   §8 highlight color palette: cyan / amber / pink / lavender
 *
 * FORBIDDEN: vanity counters, hard delete paths, licensed translation text in
 *   any payload that flows into the AI citation engine.
 */

import React, { useState, useCallback, useEffect } from 'react';
import './selahGlass.css';

// §8 Verse highlight palette — exact values from GLASS_TOKENS
const HIGHLIGHT_COLORS = [
  { id: 'cyan',     label: 'Cyan',     value: 'rgba(100,200,220,0.25)', solid: '#29B8D4' },
  { id: 'amber',    label: 'Amber',    value: 'rgba(255,180,50,0.25)',  solid: '#E5A020' },
  { id: 'pink',     label: 'Pink',     value: 'rgba(255,100,150,0.20)', solid: '#E55080' },
  { id: 'lavender', label: 'Lavender', value: 'rgba(160,130,255,0.22)', solid: '#7B68D0' },
  // Note: lavender swatch uses a DISPLAY-only UI color; it is never passed to AI citation path.
];

/**
 * ColorSwatchRow — shared color picker used by both highlight and note modes.
 */
function ColorSwatchRow({ selectedColor, onChange }) {
  return (
    <div
      role="radiogroup"
      aria-label="Highlight color"
      style={{ display: 'flex', gap: 12, marginBottom: 20 }}
    >
      {HIGHLIGHT_COLORS.map((c) => (
        <button
          key={c.id}
          role="radio"
          aria-checked={selectedColor === c.id}
          aria-label={c.label}
          className={`selah-highlight-swatch ${selectedColor === c.id ? 'selected' : ''}`}
          style={{ backgroundColor: c.solid }}
          onClick={() => onChange(c.id)}
          type="button"
        />
      ))}
    </div>
  );
}

/**
 * TextInput — shared multi-line text area styled to match glass surface.
 */
function TextInput({ value, onChange, placeholder, ariaLabel }) {
  return (
    <textarea
      aria-label={ariaLabel}
      placeholder={placeholder}
      value={value}
      onChange={(e) => onChange(e.target.value)}
      rows={4}
      style={{
        width: '100%',
        resize: 'none',
        border: '1px solid rgba(0,0,0,0.10)',
        borderRadius: 14,
        padding: '12px 14px',
        fontSize: 15,
        color: '#0A0A0A',
        backgroundColor: 'rgba(255,255,255,0.60)',
        fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
        lineHeight: 1.5,
        outline: 'none',
        boxSizing: 'border-box',
        marginBottom: 16,
      }}
    />
  );
}

/**
 * SaveButton — primary action button.
 */
function SaveButton({ onPress, disabled, label }) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onPress}
      style={{
        width: '100%',
        height: 50,
        borderRadius: 14,
        border: 'none',
        backgroundColor: disabled ? 'rgba(0,0,0,0.10)' : '#0A0A0A',
        color: disabled ? '#8A8A8E' : '#FFFFFF',
        fontSize: 16,
        fontWeight: 600,
        cursor: disabled ? 'default' : 'pointer',
        transition: 'background-color 0.15s ease, color 0.15s ease',
        fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
      }}
      aria-disabled={disabled}
    >
      {label}
    </button>
  );
}

/**
 * DeleteButton — soft-delete only. Sets deletedAt, never hard-deletes.
 */
function DeleteButton({ onPress }) {
  const [confirming, setConfirming] = useState(false);

  const handleClick = useCallback(() => {
    if (!confirming) {
      setConfirming(true);
      return;
    }
    onPress();
  }, [confirming, onPress]);

  return (
    <button
      type="button"
      onClick={handleClick}
      style={{
        width: '100%',
        height: 44,
        borderRadius: 14,
        border: '1px solid rgba(220,60,60,0.35)',
        backgroundColor: 'transparent',
        color: confirming ? '#CC2020' : '#8A8A8E',
        fontSize: 15,
        fontWeight: 500,
        cursor: 'pointer',
        marginTop: 10,
        transition: 'color 0.15s ease, border-color 0.15s ease',
        fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
      }}
      aria-label={confirming ? 'Confirm delete note' : 'Delete note'}
    >
      {confirming ? 'Confirm Delete' : 'Delete Note'}
    </button>
  );
}

// ─── Main Component ────────────────────────────────────────────────────────────

export default function SelahAnnotationPanel({
  verseRef,
  mode,
  existingNote,
  onCreateNote,
  onDeleteNote,
  onDismiss,
}) {
  const [selectedColor, setSelectedColor] = useState(
    existingNote?.color ?? 'cyan'
  );
  const [bodyText, setBodyText] = useState(existingNote?.body ?? '');

  // Keep state in sync if existingNote prop changes
  useEffect(() => {
    setSelectedColor(existingNote?.color ?? 'cyan');
    setBodyText(existingNote?.body ?? '');
  }, [existingNote]);

  // Resolve the solid color value for the current selection
  const resolvedColorValue = useCallback(
    (colorId) => HIGHLIGHT_COLORS.find((c) => c.id === colorId)?.value ?? null,
    []
  );

  // ── Highlight handler ──────────────────────────────────────────────────────
  const handleHighlightSelect = useCallback(
    (colorId) => {
      setSelectedColor(colorId);
      // Immediately commit on color pick (no Save button for highlight mode)
      onCreateNote({
        verseRef,
        kind: 'highlight',
        color: resolvedColorValue(colorId),
        body: null,
      });
      onDismiss();
    },
    [verseRef, onCreateNote, onDismiss, resolvedColorValue]
  );

  // ── Note / question / prayer save handler ──────────────────────────────────
  const handleSave = useCallback(() => {
    if (!bodyText.trim() && mode !== 'highlight') return;
    onCreateNote({
      verseRef,
      kind: mode,
      color: mode === 'note' ? resolvedColorValue(selectedColor) : null,
      body: bodyText.trim() || null,
    });
    onDismiss();
  }, [bodyText, mode, verseRef, selectedColor, onCreateNote, onDismiss, resolvedColorValue]);

  // ── Soft delete handler ────────────────────────────────────────────────────
  const handleDelete = useCallback(() => {
    if (existingNote?.id) {
      // Soft delete: caller sets deletedAt — no hard delete path exists
      onDeleteNote(existingNote.id);
      onDismiss();
    }
  }, [existingNote, onDeleteNote, onDismiss]);

  // ── Mode labels ────────────────────────────────────────────────────────────
  const modeConfig = {
    highlight: {
      title: 'Highlight Verse',
      placeholder: null,
      ariaLabel: null,
      showText: false,
      showColor: true,
    },
    note: {
      title: 'Add Study Note',
      placeholder: 'Write your reflection…',
      ariaLabel: 'Study note text',
      showText: true,
      showColor: true,
    },
    question: {
      title: 'Record a Question',
      placeholder: 'What are you wondering about?',
      ariaLabel: 'Question text',
      showText: true,
      showColor: false,
    },
    prayer: {
      title: 'Write a Prayer',
      placeholder: 'What would you like to pray about this verse?',
      ariaLabel: 'Prayer text',
      showText: true,
      showColor: false,
    },
  };

  const config = modeConfig[mode] ?? modeConfig.note;
  const canSave = mode === 'highlight' || bodyText.trim().length > 0;

  return (
    <div
      className="selah-bottom-sheet-overlay"
      role="dialog"
      aria-modal="true"
      aria-label={config.title}
      onClick={(e) => {
        // Dismiss when user taps the backdrop
        if (e.target === e.currentTarget) onDismiss();
      }}
    >
      <div className="selah-bottom-sheet">
        {/* Handle */}
        <div className="selah-bottom-sheet-handle" aria-hidden="true" />

        {/* Header row */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            marginBottom: 6,
          }}
        >
          <span
            style={{
              fontSize: 12,
              fontWeight: 500,
              color: '#8A8A8E',
              textTransform: 'uppercase',
              letterSpacing: 0.6,
            }}
          >
            {verseRef}
          </span>
          <button
            type="button"
            onClick={onDismiss}
            aria-label="Close annotation panel"
            style={{
              width: 28,
              height: 28,
              borderRadius: '50%',
              border: 'none',
              backgroundColor: 'rgba(0,0,0,0.08)',
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontSize: 14,
              color: '#8A8A8E',
            }}
          >
            ✕
          </button>
        </div>

        <h2
          style={{
            fontSize: 18,
            fontWeight: 600,
            color: '#0A0A0A',
            margin: '0 0 20px',
          }}
        >
          {config.title}
        </h2>

        {/* Highlight mode: immediate color picker, no Save button */}
        {mode === 'highlight' && (
          <>
            <p
              style={{
                fontSize: 14,
                color: '#8A8A8E',
                marginBottom: 16,
                marginTop: 0,
              }}
            >
              Choose a highlight color for this verse.
            </p>
            <ColorSwatchRow
              selectedColor={selectedColor}
              onChange={handleHighlightSelect}
            />
          </>
        )}

        {/* Note mode: color + text + Save */}
        {mode === 'note' && (
          <>
            <ColorSwatchRow
              selectedColor={selectedColor}
              onChange={setSelectedColor}
            />
            <TextInput
              value={bodyText}
              onChange={setBodyText}
              placeholder={config.placeholder}
              ariaLabel={config.ariaLabel}
            />
            <SaveButton
              onPress={handleSave}
              disabled={!canSave}
              label="Save Note"
            />
          </>
        )}

        {/* Question mode: text + Save */}
        {mode === 'question' && (
          <>
            <TextInput
              value={bodyText}
              onChange={setBodyText}
              placeholder={config.placeholder}
              ariaLabel={config.ariaLabel}
            />
            <SaveButton
              onPress={handleSave}
              disabled={!canSave}
              label="Save Question"
            />
          </>
        )}

        {/* Prayer mode: text + Save */}
        {mode === 'prayer' && (
          <>
            <TextInput
              value={bodyText}
              onChange={setBodyText}
              placeholder={config.placeholder}
              ariaLabel={config.ariaLabel}
            />
            <SaveButton
              onPress={handleSave}
              disabled={!canSave}
              label="Save Prayer"
            />
          </>
        )}

        {/* Soft delete — only shown when editing an existing note */}
        {existingNote?.id && mode !== 'highlight' && (
          <DeleteButton onPress={handleDelete} />
        )}
      </div>
    </div>
  );
}
