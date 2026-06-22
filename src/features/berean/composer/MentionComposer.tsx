/**
 * MentionComposer.tsx — Drop-in composer input with @mention support for Berean.
 *
 * Agent D (@Tool Mentions) — Connected Intelligence Phase 2.
 *
 * Replaces the raw <input> + Send button in BereanApp.tsx → ChatScreen. It owns:
 *   - the text input + Send button (Liquid Glass white/light)
 *   - the MentionPicker (opens on `@`)
 *   - the DegradedChip (distinct from error)
 *   - the CalendarDraftCard + ConfirmationGate for @calendar writes
 *
 * It calls useBerean().sendMessage under the hood via useMentionComposer. The parent
 * passes `sendMessage`, `userId`, and `minorScoped` (from the Berean context) plus an
 * optional onSent callback so the chat transcript can append the user's message.
 *
 * ATTACH POINT: see HANDOFF.md. The parent renders <MentionComposer .../> where the
 * old input row was; everything else (transcript, loading bubble) stays as-is.
 *
 * OWNER: Agent D. Create-only under src/features/berean/composer/**.
 */

import React, { useRef } from 'react';

import { tokens } from '../../../berean/contracts';
import type { Domain } from '../../connectedIntelligence.contracts';

import { useMentionComposer, type SubmitOutcome } from './useMentionComposer';
import { MentionPicker } from './MentionPicker';
import { DegradedChip } from './DegradedChip';
import { CalendarDraftCard } from './CalendarDraftCard';

const FONT = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';

export interface MentionComposerProps {
  userId: string;
  minorScoped: boolean;
  /** From useBerean(): sendMessage(input, domain). */
  sendMessage: (input: string, domain: Domain) => Promise<unknown>;
  /** Called with the raw user text the moment a turn is submitted (for the transcript). */
  onUserSubmit?: (rawText: string) => void;
  /** Called after a turn fully resolves (sent or degraded or committed draft). */
  onResolved?: (outcome: SubmitOutcome) => void;
  placeholder?: string;
  disabled?: boolean;
}

export function MentionComposer({
  userId,
  minorScoped,
  sendMessage,
  onUserSubmit,
  onResolved,
  placeholder = 'Ask Berean…  try @bible, @prayer, @notes',
  disabled = false,
}: MentionComposerProps): React.ReactElement {
  const inputRef = useRef<HTMLInputElement>(null);

  const composer = useMentionComposer({ userId, minorScoped, sendMessage });

  const handleSubmit = async () => {
    if (disabled || composer.sending) return;
    const raw = composer.text.trim();
    if (!raw) return;
    // Optimistically surface the user's message before async work resolves.
    onUserSubmit?.(raw);
    const outcome = await composer.submit();
    onResolved?.(outcome);
    // Keep focus in the input for fast follow-ups.
    inputRef.current?.focus();
  };

  const handleConfirmDraft = async () => {
    const result = await composer.confirmDraft();
    return result;
  };

  const canSend = composer.text.trim().length > 0 && !composer.sending && !disabled;

  return (
    <div style={{ position: 'relative' }}>
      {/* Degraded connector chip (distinct from error) */}
      {composer.degraded && (
        <DegradedChip signal={composer.degraded} onDismiss={composer.clearDegraded} />
      )}

      {/* Calendar draft + ConfirmationGate */}
      {composer.draftPending && (
        <CalendarDraftCard
          draft={composer.draftPending.draft}
          onConfirm={handleConfirmDraft}
          onCancel={composer.cancelDraft}
        />
      )}

      {/* Mention picker (floats above the input row) */}
      {composer.pickerOpen && (
        <MentionPicker
          items={composer.pickerItems}
          loadState={composer.pickerLoadState}
          onSelect={composer.selectMention}
          onDismiss={composer.closePicker}
        />
      )}

      {/* Input row */}
      <div
        style={{
          padding: 16,
          borderTop: `1px solid ${tokens.divider}`,
          display: 'flex',
          gap: 8,
          backgroundColor: tokens.card,
        }}
      >
        <input
          ref={inputRef}
          value={composer.text}
          onChange={(e) => composer.onTextChange(e.target.value, e.target.selectionStart ?? e.target.value.length)}
          onKeyUp={(e) => {
            const el = e.currentTarget;
            composer.onTextChange(el.value, el.selectionStart ?? el.value.length);
          }}
          onKeyDown={(e) => {
            if (e.key === 'Escape' && composer.pickerOpen) {
              e.preventDefault();
              composer.closePicker();
              return;
            }
            if (e.key === 'Enter' && !e.shiftKey && !composer.pickerOpen) {
              e.preventDefault();
              void handleSubmit();
            }
          }}
          placeholder={placeholder}
          disabled={disabled || composer.sending}
          aria-label="Message Berean"
          style={{
            flex: 1, padding: '10px 14px', borderRadius: 12,
            border: `1px solid ${tokens.divider}`, fontSize: 15, fontFamily: FONT,
            outline: 'none', backgroundColor: tokens.card, color: tokens.text,
          }}
        />
        <button
          onClick={() => void handleSubmit()}
          disabled={!canSend}
          aria-label="Send message"
          style={{
            padding: '10px 18px', borderRadius: 12, border: 'none',
            backgroundColor: canSend ? tokens.accent : tokens.divider,
            color: '#fff', fontSize: 15, fontWeight: 600,
            cursor: canSend ? 'pointer' : 'default', fontFamily: FONT,
          }}
        >
          {composer.sending ? '…' : 'Send'}
        </button>
      </div>
    </div>
  );
}
