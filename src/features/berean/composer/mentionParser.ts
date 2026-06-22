/**
 * mentionParser.ts — Parse @mentions out of composer text and resolve routing.
 *
 * Agent D (@Tool Mentions) — Connected Intelligence Phase 2.
 *
 * Two jobs:
 *   1. ACTIVE TRIGGER: given the text + caret position, decide whether the user is
 *      mid-`@token` (so the picker should open) and what the partial query is.
 *   2. PARSE: extract the leading mention(s) from a submitted message, resolve the
 *      routed Domain + taskKey via the FROZEN MENTION_ROUTING (through MentionDescriptor),
 *      strip the token from the prompt body, and (for @calendar) classify write intent.
 *
 * Routing rule: the FIRST recognized mention in the message decides the turn's domain.
 * Mentions are the ONLY way connector context enters a Berean turn — there is no
 * ambient connector context anywhere in this layer.
 *
 * Calendar WRITE intent: phrases like "schedule prayer night Friday" must NOT silently
 * write. classifyCalendarIntent() flags write so the composer produces a DRAFT card →
 * ConfirmationGate → event_create. Ceiling is drafts_for_approval.
 *
 * OWNER: Agent D. Create-only under src/features/berean/composer/**.
 */

import {
  ToolMention,
  type Domain,
} from '../../connectedIntelligence.contracts';

import {
  MENTION_DESCRIPTORS,
  descriptorForToken,
  type MentionDescriptor,
} from './mentionConfig';

// ─────────────────────────────────────────────────────────────────────────────
// Active trigger detection (picker open/close)
// ─────────────────────────────────────────────────────────────────────────────

export interface ActiveTrigger {
  active: boolean;
  /** Partial token after `@` (lowercased), e.g. "cal" while typing "@cal". */
  query: string;
  /** Index of the `@` that opened this trigger, for replacement on selection. */
  atIndex: number;
}

const INACTIVE: ActiveTrigger = { active: false, query: '', atIndex: -1 };

/**
 * Returns whether the caret sits inside an `@token` run. A trigger opens at `@`
 * that is at string start or preceded by whitespace, and stays open while the
 * following characters are word-chars (letters). A space closes it.
 */
export function detectTrigger(text: string, caret: number): ActiveTrigger {
  const pos = Math.max(0, Math.min(caret, text.length));
  // Walk backwards from caret to find a candidate '@'.
  let i = pos - 1;
  while (i >= 0) {
    const ch = text[i];
    if (ch === '@') {
      const before = i === 0 ? '' : text[i - 1];
      if (before === '' || /\s/.test(before)) {
        const query = text.slice(i + 1, pos);
        // Token chars only — a space/newline already closed any earlier '@'.
        if (/^[a-zA-Z]*$/.test(query)) {
          return { active: true, query: query.toLowerCase(), atIndex: i };
        }
      }
      return INACTIVE;
    }
    if (/\s/.test(ch)) return INACTIVE; // whitespace before any '@' ⇒ not in a trigger
    i -= 1;
  }
  return INACTIVE;
}

/**
 * Replace the active `@query` run with a fully-typed `@token ` (trailing space).
 * Returns the new text and the caret position after the inserted token.
 */
export function applyMentionSelection(
  text: string,
  trigger: ActiveTrigger,
  descriptor: MentionDescriptor,
): { text: string; caret: number } {
  if (!trigger.active) return { text, caret: text.length };
  const head = text.slice(0, trigger.atIndex);
  const tail = text.slice(trigger.atIndex + 1 + trigger.query.length);
  const inserted = `@${descriptor.token} `;
  const next = `${head}${inserted}${tail}`;
  return { text: next, caret: head.length + inserted.length };
}

// ─────────────────────────────────────────────────────────────────────────────
// Submitted-message parse
// ─────────────────────────────────────────────────────────────────────────────

export interface ParsedMention {
  descriptor: MentionDescriptor;
  /** Char index of the `@` in the original text. */
  index: number;
}

export interface ParsedMessage {
  /** All recognized mentions, in order of appearance. */
  mentions: ParsedMention[];
  /** The mention that routes the turn (the first recognized one), or null. */
  routing: ParsedMention | null;
  /** Message body with recognized @token literals stripped, trimmed. */
  cleanText: string;
  /** Resolved domain for the turn (routing mention's domain, or 'general'). */
  domain: Domain;
  /** Resolved router taskKey (routing mention's taskKey, or null for default flow). */
  taskKey: string | null;
}

const MENTION_TOKEN_RE = /(^|\s)@([a-zA-Z]+)/g;

/**
 * Parse a submitted message. Recognizes every `@token` that maps to a known
 * ToolMention; unknown `@words` are left untouched in the body.
 */
export function parseMessage(text: string): ParsedMessage {
  const mentions: ParsedMention[] = [];
  let match: RegExpExecArray | null;
  MENTION_TOKEN_RE.lastIndex = 0;

  while ((match = MENTION_TOKEN_RE.exec(text)) !== null) {
    const token = match[2];
    const descriptor = descriptorForToken(token);
    if (descriptor) {
      const atIndex = match.index + match[1].length;
      mentions.push({ descriptor, index: atIndex });
    }
  }

  const routing = mentions.length > 0 ? mentions[0] : null;

  // Strip ONLY recognized mention tokens from the body.
  let clean = text;
  if (mentions.length > 0) {
    clean = text.replace(MENTION_TOKEN_RE, (whole, lead: string, token: string) => {
      return descriptorForToken(token) ? lead : whole;
    });
  }
  clean = clean.replace(/\s{2,}/g, ' ').trim();

  return {
    mentions,
    routing,
    cleanText: clean,
    domain: routing ? routing.descriptor.domain : 'general',
    taskKey: routing ? routing.descriptor.taskKey : null,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Calendar write-intent classification
// ─────────────────────────────────────────────────────────────────────────────

export type CalendarIntent = 'read' | 'write';

const WRITE_VERB_RE =
  /\b(schedule|add|create|book|set up|set-up|put|plan|block out|reserve|remind me to|make an? event)\b/i;

/**
 * Classify a @calendar turn as read vs write. Write intents (e.g. "schedule prayer
 * night Friday") must route through a DRAFT card + ConfirmationGate before any
 * event_create. Read intents (e.g. "what's on my calendar Friday") just fetch context.
 *
 * Only meaningful when the routing mention is @calendar; returns 'read' otherwise.
 */
export function classifyCalendarIntent(parsed: ParsedMessage): CalendarIntent {
  if (!parsed.routing || parsed.routing.descriptor.mention !== ToolMention.calendar) {
    return 'read';
  }
  return WRITE_VERB_RE.test(parsed.cleanText) ? 'write' : 'read';
}

/** Convenience: is this a connector-backed (degrade-gracefully) mention turn? */
export function isToolOrchestrationTurn(parsed: ParsedMessage): boolean {
  return parsed.routing?.descriptor.provider === 'tool-orchestration';
}

/** Convenience re-export for descriptors keyed by mention. */
export { MENTION_DESCRIPTORS };
