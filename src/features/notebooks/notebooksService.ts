/**
 * notebooksService.ts — Amen Notebooks client service (Connected Intelligence v1)
 *
 * Thin client wrapper around the five Notebooks Cloud Functions. NO AI routing,
 * NO Pinecone, NO secrets here — everything grounded happens server-side.
 *
 * The Pinecone namespace is ALWAYS server-derived (`notebook-{uid}-{notebookId}`)
 * and is never sent from the client. We import the frozen contract types so this
 * service stays in lockstep with Agent 1's single source of truth.
 *
 * STRICT OWNERSHIP: this file lives under src/features/notebooks/** only.
 */

import { httpsCallable } from 'firebase/functions';
import {
  collection,
  query as fsQuery,
  where,
  orderBy,
  getDocs,
} from 'firebase/firestore';
import { functions, db } from '../../berean/firebase';
import type {
  Notebook,
  NotebookKind,
} from '../connectedIntelligence.contracts';

// ─────────────────────────────────────────────────────────────────────────────
// CF payload shapes
// ─────────────────────────────────────────────────────────────────────────────

interface CreateReq {
  kind: NotebookKind;
  title: string;
  sharedWithSpaceId?: string | null;
  sourceRefs?: Notebook['sourceRefs'];
}
interface CreateRes {
  success: boolean;
  notebookId: string;
  pineconeNamespace: string;
}

interface IngestReq {
  notebookId: string;
  sourceType: 'note' | 'sermon' | 'verse_range' | 'doc' | 'chat_checkpoint';
  pointer: string;
  title?: string;
  content: string;
}
interface IngestRes {
  success: boolean;
  chunksIndexed?: number;
  sourceId?: string;
  error?: string;
}

interface QueryReq {
  notebookId: string;
  query: string;
}

/** A single cited source chunk the answer drew from. */
export interface NotebookCitation {
  sourceId: string | null;
  sourceType: string | null;
  pointer: string | null;
  sourceTitle: string;
  chunkIndex: number | null;
  score: number | null;
  snippet: string;
  marker: string;
}

/** Grounded answer with citations. */
export interface NotebookGroundedAnswer {
  grounded: true;
  answer: string;
  citations: NotebookCitation[];
  scripture: boolean;
}

/** Explicit ungrounded REFUSE — distinct from an error. */
export interface NotebookRefusal {
  grounded: false;
  refused: true;
  reason: 'ungrounded';
  message: string;
}

export type NotebookQueryResult = NotebookGroundedAnswer | NotebookRefusal;

interface SoftDeleteRes {
  success: boolean;
  alreadyDeleted?: boolean;
}

// ─────────────────────────────────────────────────────────────────────────────
// Callable singletons
// ─────────────────────────────────────────────────────────────────────────────

const cfCreate = httpsCallable<CreateReq, CreateRes>(functions, 'notebookCreate');
const cfIngest = httpsCallable<IngestReq, IngestRes>(functions, 'notebookIngest');
const cfQuery = httpsCallable<QueryReq, NotebookQueryResult>(functions, 'notebookQuery');
const cfSoftDelete = httpsCallable<{ notebookId: string }, SoftDeleteRes>(
  functions,
  'notebookSoftDelete',
);

// ─────────────────────────────────────────────────────────────────────────────
// PUBLIC API
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Lists the caller's active (non-deleted) notebooks straight from Firestore.
 * Firestore Security Rules scope reads to the owner; the namespace is read-only.
 */
export async function listNotebooks(uid: string): Promise<Notebook[]> {
  const col = collection(db, 'users', uid, 'notebooks');
  const q = fsQuery(col, where('deletedAt', '==', null), orderBy('createdAt', 'desc'));
  const snap = await getDocs(q);
  return snap.docs.map((d) => d.data() as Notebook);
}

/** Create a notebook. Namespace is server-derived; never supply it here. */
export async function createNotebook(input: CreateReq): Promise<CreateRes> {
  const res = await cfCreate(input);
  return res.data;
}

/** Attach + index a source. */
export async function ingestSource(input: IngestReq): Promise<IngestRes> {
  const res = await cfIngest(input);
  return res.data;
}

/**
 * Ask a grounded question of a notebook. Returns either a grounded answer with
 * citations, or an explicit ungrounded REFUSE. NEVER returns an ungrounded answer.
 */
export async function queryNotebook(input: QueryReq): Promise<NotebookQueryResult> {
  const res = await cfQuery(input);
  return res.data;
}

/** Soft-delete a notebook. The namespace is hard-purged later by the scheduled job. */
export async function softDeleteNotebook(notebookId: string): Promise<SoftDeleteRes> {
  const res = await cfSoftDelete({ notebookId });
  return res.data;
}

/**
 * Suggested grounded prompts surfaced as one-tap affordances in the query UX.
 * Each is a real grounded operation handled by notebookQuery.
 */
export const SUGGESTED_PROMPTS: ReadonlyArray<{ label: string; prompt: string }> = [
  { label: 'Summarize my notes', prompt: 'Summarize my notes from this sermon.' },
  { label: 'Compare with Romans 8', prompt: 'Compare these notes with Romans 8.' },
  { label: 'Small-group questions', prompt: 'Turn this into small-group discussion questions.' },
  { label: 'Key takeaways', prompt: 'What are the key takeaways from these sources?' },
];
