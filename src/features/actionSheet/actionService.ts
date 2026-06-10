/**
 * src/features/actionSheet/actionService.ts
 *
 * Real logic behind every Response Action. No stubs, no dead handlers.
 *
 * Invariants enforced here:
 *   - PROVENANCE: every object-producing action writes a ProvenanceStamp pointing
 *     back to the originating response + its citations.
 *   - MEMORY via the EXISTING memoryService (berean/{uid}/memory). remember_this /
 *     forget_this / why_remembered / show_related — NO passive inference, NO parallel store.
 *     origin + sourcePointer are written as EXTRA fields on the schemaless memory doc.
 *   - MODERATION: turn_into_post / turn_into_carousel call checkContentSafety and
 *     FAIL CLOSED — anything but 'allow', or any callable error ⇒ BLOCKED, never publishes.
 *   - CONTINUITY: continue_later writes users/{uid}/checkpoints/{id}; resume restores it.
 *   - verify_scripture / show_sources / simplify / deep_dive / challenge_this /
 *     generate_questions ⇒ bereanTransform CF (typed blocked/refusal — never throws).
 *
 * OWNER: Agent F (Response Action Sheet). Connected Intelligence v1.
 */

import {
  collection,
  doc,
  setDoc,
  getDoc,
  getDocs,
  query,
  where,
  serverTimestamp,
} from 'firebase/firestore';
import { httpsCallable } from 'firebase/functions';

import { db, functions } from '../../berean/firebase';
import { memoryService } from '../../berean/core/memory';
import type { BereanMemoryDoc, Domain } from '../../berean/contracts';
import { ResponseAction } from '../connectedIntelligence.contracts';
import type {
  ActionSheetResponse,
  ActionResult,
  ProvenanceStamp,
  ConversationState,
} from './types';

// ─────────────────────────────────────────────────────────────────────────────
// Provenance helper — the single source of the stamp every object inherits.
// ─────────────────────────────────────────────────────────────────────────────

function buildStamp(response: ActionSheetResponse): ProvenanceStamp {
  return {
    originResponseId: response.responseId,
    originDomain: response.domain,
    provenance: response.provenance,
    excerpt: response.text.slice(0, 2000),
    createdAt: serverTimestamp(),
  };
}

/** Write a created object under users/{uid}/{collection}/{id} carrying provenance. */
async function writeObjectWithProvenance(
  uid: string,
  collectionName: string,
  payload: Record<string, unknown>,
  response: ActionSheetResponse,
): Promise<ProvenanceStamp> {
  const stamp = buildStamp(response);
  const id = `${collectionName}_${Date.now()}`;
  const ref = doc(collection(db, 'users', uid, collectionName), id);
  await setDoc(ref, {
    ...payload,
    provenance: stamp.provenance,           // canonical Provenance
    originResponseId: stamp.originResponseId, // pointer back to the response
    originDomain: stamp.originDomain,
    sourceExcerpt: stamp.excerpt,
    createdAt: serverTimestamp(),
  });
  return stamp;
}

// ─────────────────────────────────────────────────────────────────────────────
// KNOWLEDGE — note / notebook / prayer journal (all carry provenance)
// ─────────────────────────────────────────────────────────────────────────────

async function saveToNote(uid: string, r: ActionSheetResponse): Promise<ActionResult> {
  const stamp = await writeObjectWithProvenance(uid, 'notes', { kind: 'note', body: r.text }, r);
  return { state: 'success', message: 'Saved to your notes.', stamp };
}

async function addToNotebook(uid: string, r: ActionSheetResponse): Promise<ActionResult> {
  const stamp = await writeObjectWithProvenance(
    uid, 'notebookEntries', { kind: 'notebook_entry', body: r.text }, r,
  );
  return { state: 'success', message: 'Added to your notebook.', stamp };
}

async function addToPrayerJournal(uid: string, r: ActionSheetResponse): Promise<ActionResult> {
  const stamp = await writeObjectWithProvenance(
    uid, 'prayerJournal', { kind: 'prayer_entry', body: r.text }, r,
  );
  return { state: 'success', message: 'Added to your prayer journal.', stamp };
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMUNITY — drafts that carry provenance (no autonomous external sends in v1)
// ─────────────────────────────────────────────────────────────────────────────

async function communityDraft(
  uid: string,
  r: ActionSheetResponse,
  kind: string,
  label: string,
): Promise<ActionResult> {
  const stamp = await writeObjectWithProvenance(
    uid, 'shareDrafts', { kind, body: r.text }, r,
  );
  return { state: 'success', message: `${label} — draft ready to send.`, stamp };
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTION — task / calendar / plan / poll (all carry provenance)
// ─────────────────────────────────────────────────────────────────────────────

async function createTask(uid: string, r: ActionSheetResponse): Promise<ActionResult> {
  const stamp = await writeObjectWithProvenance(
    uid, 'tasks', { kind: 'task', title: r.text.slice(0, 120), done: false }, r,
  );
  return { state: 'success', message: 'Task created.', stamp };
}

async function addToCalendar(uid: string, r: ActionSheetResponse): Promise<ActionResult> {
  // v1 ceiling is a draft event (drafts_for_approval) — no autonomous external write.
  const stamp = await writeObjectWithProvenance(
    uid, 'calendarDrafts', { kind: 'calendar_event', title: r.text.slice(0, 120) }, r,
  );
  return { state: 'success', message: 'Calendar event drafted for your approval.', stamp };
}

async function buildPlan(uid: string, r: ActionSheetResponse): Promise<ActionResult> {
  const stamp = await writeObjectWithProvenance(
    uid, 'plans', { kind: 'plan', title: r.text.slice(0, 120), source: r.text }, r,
  );
  return { state: 'success', message: 'Plan created.', stamp };
}

async function createPoll(uid: string, r: ActionSheetResponse): Promise<ActionResult> {
  const stamp = await writeObjectWithProvenance(
    uid, 'polls', { kind: 'poll', prompt: r.text.slice(0, 240) }, r,
  );
  return { state: 'success', message: 'Poll draft created.', stamp };
}

// ─────────────────────────────────────────────────────────────────────────────
// PUBLISH (turn_into_post / turn_into_carousel) — MODERATION FAIL-CLOSED
// ─────────────────────────────────────────────────────────────────────────────

interface SafetyResponse { decision?: 'allow' | 'warn' | 'block' | 'review'; reason?: string }

/**
 * Calls checkContentSafety and FAILS CLOSED: anything but 'allow', or any callable
 * error, returns blocked. Never lets unmoderated content reach the publish write.
 */
async function moderateOrBlock(text: string): Promise<{ allowed: boolean; reason?: string }> {
  try {
    const callable = httpsCallable<
      { content: string; contentType: 'post' },
      SafetyResponse
    >(functions, 'checkContentSafety');
    const res = await callable({ content: text.slice(0, 10000), contentType: 'post' });
    const decision = res.data?.decision;
    if (decision === 'allow') return { allowed: true };
    return { allowed: false, reason: res.data?.reason ?? 'Held for safety review.' };
  } catch {
    // Callable error ⇒ fail closed. NEVER publish unmoderated.
    return { allowed: false, reason: 'Safety check unavailable — not published.' };
  }
}

async function publishWithModeration(
  uid: string,
  r: ActionSheetResponse,
  template: 'post' | 'carousel',
): Promise<ActionResult> {
  const gate = await moderateOrBlock(r.text);
  if (!gate.allowed) {
    return {
      state: 'blocked',
      message: 'This couldn’t be published.',
      detail: gate.reason,
    };
  }
  // Only reached when decision === 'allow'. Write the published draft + provenance.
  const stamp = await writeObjectWithProvenance(
    uid, 'posts', { kind: template, body: r.text, moderation: 'allow', status: 'ready' }, r,
  );
  return {
    state: 'success',
    message: template === 'carousel' ? 'Carousel ready to post.' : 'Post ready to publish.',
    stamp,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// MEMORY — via the EXISTING memoryService. origin + sourcePointer as extra fields.
// ─────────────────────────────────────────────────────────────────────────────

/** Deterministic memory id for a given response so remember/forget/why agree. */
function memoryIdFor(r: ActionSheetResponse): string {
  return `actionsheet_${r.responseId}`;
}

async function rememberThis(uid: string, r: ActionSheetResponse): Promise<ActionResult> {
  const memoryId = memoryIdFor(r);
  const sourcePointer = `berean/response/${r.responseId}`;
  // BereanMemoryDoc is schemaless at rest — we attach origin + sourcePointer as
  // EXTRA fields (MemoryItem semantics) via the existing upsertMemory.
  const docData = {
    memoryId,
    domain: r.domain,
    summary: r.text.slice(0, 1000),
    refs: r.provenance.sources,
    pinned: false,
    visibility: 'private',
    createdAt: serverTimestamp(),
    softDeleted: false,
    // MemoryItem extras (explicit_remember — NO passive inference):
    origin: 'explicit_remember',
    sourcePointer,
  } as unknown as BereanMemoryDoc & { memoryId: string };

  await memoryService.upsertMemory(uid, docData);

  return {
    state: 'success',
    message: 'Berean will remember this.',
    detail: 'Saved as an explicit memory you control.',
    undo: async () => { await memoryService.softDeleteMemory(uid, memoryId); },
  };
}

async function forgetThis(uid: string, r: ActionSheetResponse): Promise<ActionResult> {
  const memoryId = memoryIdFor(r);
  await memoryService.softDeleteMemory(uid, memoryId);
  return {
    state: 'success',
    message: 'Forgotten.',
    detail: 'This memory was removed.',
    undo: async () => {
      // Re-remember restores it (soft-delete is reversible by re-upsert).
      await rememberThis(uid, r);
    },
  };
}

/** Reads the memory doc verbatim and renders origin + sourcePointer. NO inference. */
async function whyRemembered(uid: string, r: ActionSheetResponse): Promise<ActionResult> {
  const memoryId = memoryIdFor(r);
  const ref = doc(collection(db, 'berean', uid, 'memory'), memoryId);
  const snap = await getDoc(ref);
  if (!snap.exists()) {
    return { state: 'empty', message: 'Not in memory.', detail: 'You haven’t asked Berean to remember this.' };
  }
  const data = snap.data() as Record<string, unknown>;
  const origin = (data.origin as string) ?? 'explicit_remember';
  const sourcePointer = (data.sourcePointer as string) ?? '(no source pointer)';
  return {
    state: 'success',
    message: 'Why this is remembered',
    detail: `origin: ${origin}\nsource: ${sourcePointer}`,   // verbatim
    rows: [
      { text: origin, label: 'origin' },
      { text: sourcePointer, label: 'source' },
    ],
  };
}

/** Queries memory for the same domain and labels each result. */
async function showRelated(uid: string, r: ActionSheetResponse): Promise<ActionResult> {
  const memoryCol = collection(db, 'berean', uid, 'memory');
  const q = query(memoryCol, where('softDeleted', '==', false));
  const snap = await getDocs(q);
  const rows: Array<{ text: string; label: string }> = [];
  snap.forEach((d) => {
    const data = d.data() as Record<string, unknown>;
    if ((data.domain as Domain) !== r.domain) return;
    if (d.id === memoryIdFor(r)) return; // exclude self
    const origin = (data.origin as string) ?? 'imported';
    rows.push({ text: String(data.summary ?? ''), label: origin });
  });
  if (rows.length === 0) {
    return { state: 'empty', message: 'Nothing related yet.', detail: `No saved ${r.domain} memories.` };
  }
  return { state: 'success', message: `${rows.length} related memor${rows.length === 1 ? 'y' : 'ies'}`, rows };
}

// ─────────────────────────────────────────────────────────────────────────────
// CONTINUITY — continue_later writes users/{uid}/checkpoints/{id}; resume restores.
// ─────────────────────────────────────────────────────────────────────────────

async function continueLater(uid: string, r: ActionSheetResponse): Promise<ActionResult> {
  const checkpointId = `chk_${Date.now()}`;
  const state: ConversationState =
    r.conversationState ?? {
      threadId: r.threadId ?? r.responseId,
      domain: r.domain,
      messages: [{ role: 'berean', text: r.text }],
    };
  const ref = doc(collection(db, 'users', uid, 'checkpoints'), checkpointId);
  await setDoc(ref, {
    ...state,
    originResponseId: r.responseId,
    provenance: r.provenance,
    createdAt: serverTimestamp(),
  });
  return {
    state: 'success',
    message: 'Saved. You can pick this up later.',
    detail: 'Find it under Continue where you left off.',
    stamp: buildStamp(r),
  };
}

/** Restore a checkpoint. Returns the full conversational state for the host to rehydrate. */
export async function resumeCheckpoint(
  uid: string,
  checkpointId: string,
): Promise<ConversationState | null> {
  const ref = doc(collection(db, 'users', uid, 'checkpoints'), checkpointId);
  const snap = await getDoc(ref);
  if (!snap.exists()) return null;
  const data = snap.data() as Record<string, unknown>;
  return {
    threadId: String(data.threadId ?? checkpointId),
    domain: (data.domain as Domain) ?? 'general',
    messages: (data.messages as ConversationState['messages']) ?? [],
    ui: (data.ui as Record<string, unknown>) ?? undefined,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// AI TRANSFORMS — bereanTransform CF (typed blocked/refusal; never throws).
// ─────────────────────────────────────────────────────────────────────────────

interface TransformResult {
  text: string | null;
  blocked: boolean;
  refusal: string | null;
  claudeExclusive: boolean;
}

const TRANSFORM_MAP: Partial<Record<ResponseAction, string>> = {
  [ResponseAction.simplify]: 'simplify',
  [ResponseAction.deep_dive]: 'deep_dive',
  [ResponseAction.challenge_this]: 'challenge_this',
  [ResponseAction.generate_questions]: 'generate_questions',
  [ResponseAction.verify_scripture]: 'verify_scripture',
  [ResponseAction.show_sources]: 'show_sources',
};

async function runTransform(
  action: ResponseAction,
  r: ActionSheetResponse,
): Promise<ActionResult> {
  const transform = TRANSFORM_MAP[action];
  if (!transform) {
    return { state: 'error', message: 'Unknown transform.' };
  }
  try {
    const callable = httpsCallable<
      { transform: string; sourceText: string; sourceDomain: Domain },
      TransformResult
    >(functions, 'bereanTransform');
    const res = await callable({ transform, sourceText: r.text, sourceDomain: r.domain });
    const data = res.data;
    if (data.blocked) {
      // Distinct moderation/refusal state (e.g. cite-or-refuse for verify_scripture).
      const reason = data.refusal === 'citations_required'
        ? 'Couldn’t verify against a grounded source — nothing was changed.'
        : data.refusal === 'crisis_handoff'
          ? 'This content routes to human support, not a transform.'
          : 'Held for safety review — nothing was changed.';
      return { state: 'blocked', message: 'Transform blocked.', detail: reason };
    }
    if (!data.text) {
      return { state: 'empty', message: 'No result.', detail: 'The transform returned nothing.' };
    }
    return { state: 'success', message: labelForTransform(action), detail: data.text };
  } catch {
    return { state: 'error', message: 'Couldn’t reach Berean.', detail: 'Please try again.' };
  }
}

function labelForTransform(action: ResponseAction): string {
  switch (action) {
    case ResponseAction.simplify: return 'Simplified';
    case ResponseAction.deep_dive: return 'Deeper context';
    case ResponseAction.challenge_this: return 'Perspectives (Acts 17:11)';
    case ResponseAction.generate_questions: return 'Discussion questions';
    case ResponseAction.verify_scripture: return 'Scripture verified';
    case ResponseAction.show_sources: return 'Sources';
    default: return 'Done';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DISPATCH — the single entry point the UI calls.
// ─────────────────────────────────────────────────────────────────────────────

export async function runAction(
  action: ResponseAction,
  uid: string,
  r: ActionSheetResponse,
): Promise<ActionResult> {
  if (!uid) return { state: 'error', message: 'Sign in to use actions.' };

  switch (action) {
    // Knowledge
    case ResponseAction.save_to_note:          return saveToNote(uid, r);
    case ResponseAction.add_to_notebook:       return addToNotebook(uid, r);
    case ResponseAction.add_to_prayer_journal: return addToPrayerJournal(uid, r);

    // Community (drafts — no autonomous send in v1)
    case ResponseAction.add_to_space:    return communityDraft(uid, r, 'space_post', 'Add to Space');
    case ResponseAction.discuss_in_space: return communityDraft(uid, r, 'space_discussion', 'Discuss in Space');
    case ResponseAction.send_to_friend:  return communityDraft(uid, r, 'dm', 'Send to a friend');
    case ResponseAction.ask_my_church:   return communityDraft(uid, r, 'church_question', 'Ask my church');
    case ResponseAction.ask_my_group:    return communityDraft(uid, r, 'group_question', 'Ask my group');
    case ResponseAction.ask_my_notes:    return communityDraft(uid, r, 'notes_query', 'Ask my notes');

    // AI transforms (CF)
    case ResponseAction.simplify:
    case ResponseAction.deep_dive:
    case ResponseAction.challenge_this:
    case ResponseAction.generate_questions:
    case ResponseAction.verify_scripture:
    case ResponseAction.show_sources:
      return runTransform(action, r);

    // Action
    case ResponseAction.create_task:     return createTask(uid, r);
    case ResponseAction.add_to_calendar: return addToCalendar(uid, r);
    case ResponseAction.build_plan:      return buildPlan(uid, r);
    case ResponseAction.create_poll:     return createPoll(uid, r);

    // Publish — moderation fail-closed
    case ResponseAction.turn_into_post:     return publishWithModeration(uid, r, 'post');
    case ResponseAction.turn_into_carousel: return publishWithModeration(uid, r, 'carousel');

    // Memory (existing memoryService)
    case ResponseAction.remember_this:  return rememberThis(uid, r);
    case ResponseAction.forget_this:    return forgetThis(uid, r);
    case ResponseAction.why_remembered: return whyRemembered(uid, r);
    case ResponseAction.show_related:   return showRelated(uid, r);

    // Continuity
    case ResponseAction.continue_later: return continueLater(uid, r);

    default:
      return { state: 'error', message: 'This action isn’t available.' };
  }
}
