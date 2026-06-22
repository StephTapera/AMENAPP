/**
 * index.ts — Amen Notebooks barrel (Connected Intelligence v1, Agent C)
 *
 * Public mount point for the Notebooks surface. Import `NotebooksScreen` and
 * render with a `userId` prop. All grounding, Pinecone, and AI routing happen
 * server-side in functions/connectedIntelligence/notebookFunctions.js.
 */

export { default as NotebooksScreen } from './NotebooksScreen';

export {
  listNotebooks,
  createNotebook,
  ingestSource,
  queryNotebook,
  softDeleteNotebook,
  SUGGESTED_PROMPTS,
} from './notebooksService';

export type {
  NotebookCitation,
  NotebookGroundedAnswer,
  NotebookRefusal,
  NotebookQueryResult,
} from './notebooksService';
