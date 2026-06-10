/**
 * src/features/actionSheet/index.ts
 *
 * Public surface of the Response Action Sheet feature.
 *
 *   <ResponseActionSheet response={...} />  — mount under any Berean assistant bubble.
 *
 * OWNER: Agent F (Response Action Sheet). Connected Intelligence v1.
 */

export { ResponseActionSheet, default } from './ResponseActionSheet';
export { runAction, resumeCheckpoint } from './actionService';
export { groupedActions, VISIBLE_ACTIONS, PILL_ACTIONS } from './taxonomy';
export type {
  ActionSheetResponse,
  ConversationState,
  ActionResult,
  ActionUiState,
  ActionDescriptor,
  ActionGroup,
  ProvenanceStamp,
} from './types';
