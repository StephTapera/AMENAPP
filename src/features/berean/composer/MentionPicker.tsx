/**
 * MentionPicker.tsx — The `@` mention picker surfaced above the composer input.
 *
 * Agent D (@Tool Mentions) — Connected Intelligence Phase 2.
 *
 * Liquid Glass white/light. No cosmic-dark, no gold, no purple, no Cormorant Garamond.
 * Uses Berean design tokens (src/berean/contracts.ts).
 *
 * States rendered (per QUALITY bar):
 *   - loading  : resolving connector grants
 *   - empty    : query matches nothing
 *   - partial  : ungated mentions shown, connectors still resolving
 *   - full     : all available mentions shown
 *   - error    : grant read failed (ungated mentions still listed; banner explains)
 *   - offline  : same surface as error, copy tuned for connectivity
 *
 * Connector mentions appear ONLY when an active berean-scoped grant exists; otherwise
 * they are absent (privacy story). Minor sessions never see connector rows at all.
 *
 * OWNER: Agent D. Create-only under src/features/berean/composer/**.
 */

import React from 'react';

import { tokens } from '../../../berean/contracts';
import type { PickerItem, PickerLoadState } from './useMentionComposer';
import type { MentionDescriptor } from './mentionConfig';

const FONT = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';

interface MentionPickerProps {
  items: PickerItem[];
  loadState: PickerLoadState;
  /** Whether any connector-gated mention is currently available — drives partial copy. */
  hasConnectorMentions?: boolean;
  onSelect: (descriptor: MentionDescriptor) => void;
  onDismiss: () => void;
}

export function MentionPicker({
  items,
  loadState,
  onSelect,
  onDismiss,
}: MentionPickerProps): React.ReactElement {
  const shellStyle: React.CSSProperties = {
    position: 'absolute',
    bottom: '100%',
    left: 16,
    right: 16,
    marginBottom: 8,
    backgroundColor: tokens.card,
    borderRadius: tokens.radius,
    boxShadow: tokens.shadow,
    border: `1px solid ${tokens.divider}`,
    overflow: 'hidden',
    fontFamily: FONT,
    maxHeight: 280,
    display: 'flex',
    flexDirection: 'column',
    zIndex: 20,
  };

  const headerStyle: React.CSSProperties = {
    padding: '10px 14px',
    fontSize: 11,
    fontWeight: 600,
    letterSpacing: 0.4,
    textTransform: 'uppercase',
    color: tokens.textSub,
    borderBottom: `1px solid ${tokens.divider}`,
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
  };

  const listStyle: React.CSSProperties = { overflowY: 'auto', flex: 1 };

  const renderBody = () => {
    if (loadState === 'loading' && items.length === 0) {
      return <PickerMessage glyph="◌" title="Loading mentions…" sub="Checking your connected sources." />;
    }
    if (items.length === 0) {
      return <PickerMessage glyph="∅" title="No matches" sub="Try @bible, @prayer, @notes, @sermon or @church." />;
    }
    return (
      <div style={listStyle}>
        {items.map((item) => (
          <PickerRow key={item.descriptor.mention} item={item} onSelect={onSelect} />
        ))}
      </div>
    );
  };

  return (
    <div style={shellStyle} role="listbox" aria-label="Mention sources">
      <div style={headerStyle}>
        <span>Mention a source</span>
        <button
          onClick={onDismiss}
          aria-label="Close mention picker"
          style={{
            border: 'none', background: 'none', cursor: 'pointer',
            color: tokens.textSub, fontSize: 13, fontFamily: FONT,
          }}
        >
          esc
        </button>
      </div>

      {(loadState === 'error') && (
        <div
          role="status"
          style={{
            padding: '8px 14px',
            fontSize: 12,
            color: tokens.textSub,
            backgroundColor: tokens.bg,
            borderBottom: `1px solid ${tokens.divider}`,
          }}
        >
          Couldn’t check connected sources. Faith mentions still work.
        </div>
      )}

      {renderBody()}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Row
// ─────────────────────────────────────────────────────────────────────────────

function PickerRow({
  item,
  onSelect,
}: {
  item: PickerItem;
  onSelect: (descriptor: MentionDescriptor) => void;
}): React.ReactElement {
  const { descriptor, available, disabledReason } = item;
  const rowStyle: React.CSSProperties = {
    display: 'flex',
    alignItems: 'center',
    gap: 12,
    padding: '10px 14px',
    border: 'none',
    background: 'none',
    width: '100%',
    textAlign: 'left',
    cursor: available ? 'pointer' : 'default',
    opacity: available ? 1 : 0.55,
    fontFamily: FONT,
  };

  return (
    <button
      style={rowStyle}
      disabled={!available}
      role="option"
      aria-selected={false}
      aria-disabled={!available}
      onClick={() => available && onSelect(descriptor)}
    >
      <span
        aria-hidden
        style={{
          width: 28, height: 28, borderRadius: 8,
          backgroundColor: tokens.bg, display: 'flex',
          alignItems: 'center', justifyContent: 'center',
          fontSize: 15, color: tokens.text, flexShrink: 0,
        }}
      >
        {descriptor.glyph}
      </span>
      <span style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
        <span style={{ fontSize: 14, fontWeight: 600, color: tokens.text }}>
          @{descriptor.token}
          <span style={{ fontWeight: 400, color: tokens.textSub, marginLeft: 6 }}>
            {descriptor.label}
          </span>
        </span>
        <span style={{ fontSize: 12, color: tokens.textSub, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
          {disabledReason ?? descriptor.description}
        </span>
      </span>
      {descriptor.gating === 'connector' && (
        <span
          style={{
            marginLeft: 'auto', fontSize: 10, fontWeight: 600,
            color: tokens.accent, flexShrink: 0,
          }}
        >
          connected
        </span>
      )}
    </button>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty / loading message
// ─────────────────────────────────────────────────────────────────────────────

function PickerMessage({
  glyph,
  title,
  sub,
}: {
  glyph: string;
  title: string;
  sub: string;
}): React.ReactElement {
  return (
    <div style={{ padding: '20px 16px', textAlign: 'center', fontFamily: FONT }}>
      <div aria-hidden style={{ fontSize: 22, color: tokens.textSub, marginBottom: 6 }}>{glyph}</div>
      <div style={{ fontSize: 14, fontWeight: 600, color: tokens.text }}>{title}</div>
      <div style={{ fontSize: 12, color: tokens.textSub, marginTop: 2 }}>{sub}</div>
    </div>
  );
}
