/**
 * useMentionComposer.ts — Orchestration hook for the Berean composer mention layer.
 *
 * Agent D (@Tool Mentions) — Connected Intelligence Phase 2.
 *
 * Wraps the existing useBerean().sendMessage(input, domain) call. Responsibilities:
 *   - Resolve which connector-backed mentions are available (grantsReader) and expose
 *     a picker availability map with explicit loading/error states.
 *   - Open/close the mention picker as the user types `@token`.
 *   - On submit: parse mentions → resolve domain+taskKey → gather scoped ContextItems →
 *     call sendMessage(enrichedInput, routedDomain). For @calendar WRITE intent, return
 *     a pending draft instead of sending, so the UI shows a ConfirmationGate first.
 *
 * Minor sessions ⇒ zero connector mentions (enforced in grantsReader).
 *
 * This hook is UI-framework-light: it manages state and returns handlers. The
 * MentionComposer component renders against it.
 *
 * OWNER: Agent D. Create-only under src/features/berean/composer/**.
 */

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import {
  ToolMention,
  ConnectorId,
  type Domain,
} from '../../connectedIntelligence.contracts';

import {
  MENTION_ORDER,
  MENTION_DESCRIPTORS,
  type MentionDescriptor,
} from './mentionConfig';

import {
  detectTrigger,
  applyMentionSelection,
  parseMessage,
  classifyCalendarIntent,
  type ActiveTrigger,
  type ParsedMessage,
} from './mentionParser';

import {
  grantsReader as defaultGrantsReader,
  type GrantsReader,
  type ConnectorAvailability,
} from './grantsReader';

import {
  contextGatherer as defaultContextGatherer,
  buildEnrichedInput,
  type ContextGatherer,
  type GatherResult,
} from './contextGatherer';

import {
  calendarDraftService as defaultCalendarService,
  type CalendarDraftService,
  type CalendarDraft,
  type CommitResult,
} from './calendarDraftService';

// ─────────────────────────────────────────────────────────────────────────────
// Public state shapes
// ─────────────────────────────────────────────────────────────────────────────

/** Loading lifecycle for the connector-availability resolution behind the picker. */
export type PickerLoadState = 'loading' | 'ready' | 'error';

export interface PickerItem {
  descriptor: MentionDescriptor;
  /** True ⇒ selectable. Connector mentions are disabled when no berean grant. */
  available: boolean;
  /** Why a connector mention is unavailable (for the "Connect" hint), else null. */
  disabledReason: string | null;
}

export interface DraftPending {
  kind: 'calendar';
  draft: CalendarDraft;
  /** The routed domain the turn will use once the user confirms or cancels. */
  domain: Domain;
}

/** A degraded-connector signal to render as a distinct chip (NOT an error toast). */
export interface DegradedSignal {
  connector: ConnectorId | null;
  reason: string;
}

// ─────────────────────────────────────────────────────────────────────────────
// Hook params
// ─────────────────────────────────────────────────────────────────────────────

export interface UseMentionComposerParams {
  userId: string;
  minorScoped: boolean;
  /** From useBerean(): sendMessage(input, domain). */
  sendMessage: (input: string, domain: Domain) => Promise<unknown>;
  /** Injectable seams (defaults wire the real services). */
  grantsReader?: GrantsReader;
  contextGatherer?: ContextGatherer;
  calendarService?: CalendarDraftService;
}

export interface MentionComposerState {
  text: string;
  setText: (t: string) => void;
  /** Call from the input's onChange/onSelect to track caret + trigger. */
  onTextChange: (text: string, caret: number) => void;
  /** Active @trigger (drives picker visibility). */
  trigger: ActiveTrigger;
  pickerOpen: boolean;
  closePicker: () => void;
  /** Picker items, filtered to the current query, with availability. */
  pickerItems: PickerItem[];
  pickerLoadState: PickerLoadState;
  /** Select a mention from the picker. */
  selectMention: (descriptor: MentionDescriptor) => void;
  /** Submit the composer. Resolves to one of the outcomes below. */
  submit: () => Promise<SubmitOutcome>;
  sending: boolean;
  /** Set when a connector degraded on the last turn; render a distinct chip. */
  degraded: DegradedSignal | null;
  clearDegraded: () => void;
  /** A pending calendar draft awaiting ConfirmationGate. */
  draftPending: DraftPending | null;
  /** Confirm the pending draft → event_create. */
  confirmDraft: () => Promise<CommitResult>;
  /** Cancel the pending draft (no write). */
  cancelDraft: () => void;
  /** True after caret tracking has resolved at least once. */
  ready: boolean;
}

export type SubmitOutcome =
  | { type: 'sent'; domain: Domain }
  | { type: 'draft'; draft: CalendarDraft }
  | { type: 'empty' }
  | { type: 'degraded'; signal: DegradedSignal };

// ─────────────────────────────────────────────────────────────────────────────
// Hook
// ─────────────────────────────────────────────────────────────────────────────

export function useMentionComposer(
  params: UseMentionComposerParams,
): MentionComposerState {
  const {
    userId,
    minorScoped,
    sendMessage,
    grantsReader = defaultGrantsReader,
    contextGatherer = defaultContextGatherer,
    calendarService = defaultCalendarService,
  } = params;

  const [text, setText] = useState('');
  const [trigger, setTrigger] = useState<ActiveTrigger>({ active: false, query: '', atIndex: -1 });

  const [availability, setAvailability] = useState<ConnectorAvailability | null>(null);
  const [pickerLoadState, setPickerLoadState] = useState<PickerLoadState>('loading');

  const [sending, setSending] = useState(false);
  const [degraded, setDegraded] = useState<DegradedSignal | null>(null);
  const [draftPending, setDraftPending] = useState<DraftPending | null>(null);

  const mountedRef = useRef(true);
  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
    };
  }, []);

  // ── Resolve connector availability (grants) ──────────────────────────────
  const reloadAvailability = useCallback(async () => {
    setPickerLoadState('loading');
    try {
      const result = await grantsReader.resolve(userId, minorScoped);
      if (!mountedRef.current) return;
      setAvailability(result);
      setPickerLoadState('ready');
    } catch {
      if (!mountedRef.current) return;
      // Fail-closed for connector mentions: error state, ungated still usable.
      setAvailability({ available: new Set(), grantsByConnector: new Map() });
      setPickerLoadState('error');
    }
  }, [grantsReader, userId, minorScoped]);

  useEffect(() => {
    void reloadAvailability();
  }, [reloadAvailability]);

  // ── Text / caret tracking ────────────────────────────────────────────────
  const onTextChange = useCallback((nextText: string, nextCaret: number) => {
    setText(nextText);
    setTrigger(detectTrigger(nextText, nextCaret));
  }, []);

  const setTextExternal = useCallback((t: string) => {
    setText(t);
    setTrigger(detectTrigger(t, t.length));
  }, []);

  const closePicker = useCallback(() => {
    setTrigger({ active: false, query: '', atIndex: -1 });
  }, []);

  // ── Build picker items, filtered by query + availability ─────────────────
  const pickerItems = useMemo<PickerItem[]>(() => {
    const query = trigger.query;
    const items: PickerItem[] = [];
    for (const mention of MENTION_ORDER) {
      const descriptor = MENTION_DESCRIPTORS[mention];
      if (query && !descriptor.token.startsWith(query) && !descriptor.label.toLowerCase().startsWith(query)) {
        continue;
      }
      if (descriptor.gating === 'ungated') {
        items.push({ descriptor, available: true, disabledReason: null });
        continue;
      }
      // Connector-gated: minor ⇒ entirely absent; otherwise availability-driven.
      if (minorScoped) continue;
      const connectorId = descriptor.connectorId as ConnectorId;
      const available = availability?.available.has(connectorId) ?? false;
      if (available) {
        items.push({ descriptor, available: true, disabledReason: null });
      } else {
        // Absent-vs-disabled decision: we keep it ABSENT to honor the privacy story
        // (a grant not scoped to berean ⇒ the mention does not appear at all).
        // Loading state is the one case we surface it as a disabled, pending row.
        if (pickerLoadState === 'loading') {
          items.push({
            descriptor,
            available: false,
            disabledReason: 'Checking access…',
          });
        }
        // ready/error + not available ⇒ omit entirely (privacy: no leak of existence).
      }
    }
    return items;
  }, [trigger.query, minorScoped, availability, pickerLoadState]);

  // ── Select a mention ──────────────────────────────────────────────────────
  const selectMention = useCallback(
    (descriptor: MentionDescriptor) => {
      const { text: nextText } = applyMentionSelection(text, trigger, descriptor);
      setText(nextText);
      closePicker();
    },
    [text, trigger, closePicker],
  );

  // ── Submit ─────────────────────────────────────────────────────────────────
  const runSend = useCallback(
    async (parsed: ParsedMessage): Promise<SubmitOutcome> => {
      let enriched = parsed.cleanText;
      let degradedSignal: DegradedSignal | null = null;

      if (parsed.routing) {
        const gather: GatherResult = await contextGatherer.gather(
          parsed.routing.descriptor,
          parsed.cleanText,
        );
        if (gather.status === 'degraded') {
          degradedSignal = {
            connector: gather.degradedConnector,
            reason: gather.degradedReason ?? 'Connector unavailable.',
          };
        } else if (gather.status === 'ok') {
          enriched = buildEnrichedInput(parsed.cleanText, gather.items);
        }
      }

      // Even on connector-degrade we still send the user's question to Berean — the
      // degraded chip tells them connector context was skipped; we never fabricate it.
      await sendMessage(enriched, parsed.domain);

      if (mountedRef.current) {
        setText('');
        setTrigger({ active: false, query: '', atIndex: -1 });
        setDegraded(degradedSignal);
      }
      if (degradedSignal) return { type: 'degraded', signal: degradedSignal };
      return { type: 'sent', domain: parsed.domain };
    },
    [contextGatherer, sendMessage],
  );

  const submit = useCallback(async (): Promise<SubmitOutcome> => {
    const raw = text;
    const parsed = parseMessage(raw);
    if (!parsed.cleanText) return { type: 'empty' };
    if (sending) return { type: 'empty' };

    setSending(true);
    setDegraded(null);
    try {
      // ── @calendar WRITE intent ⇒ produce a DRAFT, never a silent write ────
      if (
        parsed.routing?.descriptor.mention === ToolMention.calendar &&
        classifyCalendarIntent(parsed) === 'write'
      ) {
        const result = await calendarService.createDraft(parsed.cleanText);
        if (result.status === 'degraded' || !result.draft) {
          const signal: DegradedSignal = {
            connector: ConnectorId.calendar,
            reason: result.reason ?? 'Calendar is unavailable right now.',
          };
          if (mountedRef.current) setDegraded(signal);
          return { type: 'degraded', signal };
        }
        if (mountedRef.current) {
          setDraftPending({ kind: 'calendar', draft: result.draft, domain: parsed.domain });
        }
        return { type: 'draft', draft: result.draft };
      }

      // ── Normal turn (incl. @calendar READ, @music, @church, ungated) ──────
      return await runSend(parsed);
    } finally {
      if (mountedRef.current) setSending(false);
    }
  }, [text, sending, calendarService, runSend]);

  // ── Draft confirm / cancel ────────────────────────────────────────────────
  const confirmDraft = useCallback(async (): Promise<CommitResult> => {
    if (!draftPending) {
      return { status: 'degraded', pointer: null, reason: 'No draft to confirm.' };
    }
    const result = await calendarService.commitDraft(draftPending.draft.draftId);
    if (mountedRef.current) {
      if (result.status === 'committed') {
        setDraftPending(null);
        setText('');
        setDegraded(null);
      } else {
        setDegraded({
          connector: ConnectorId.calendar,
          reason: result.reason ?? 'Could not create the event. Nothing was written.',
        });
      }
    }
    return result;
  }, [draftPending, calendarService]);

  const cancelDraft = useCallback(() => {
    setDraftPending(null);
  }, []);

  const clearDegraded = useCallback(() => setDegraded(null), []);

  return {
    text,
    setText: setTextExternal,
    onTextChange,
    trigger,
    pickerOpen: trigger.active,
    closePicker,
    pickerItems,
    pickerLoadState,
    selectMention,
    submit,
    sending,
    degraded,
    clearDegraded,
    draftPending,
    confirmDraft,
    cancelDraft,
    ready: true,
  };
}
