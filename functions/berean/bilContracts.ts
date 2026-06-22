export type BILTier = 'tier_s' | 'tier_c' | 'tier_p'

export type BILApprovalState =
  | 'auto_approved'
  | 'pending_user_approval'
  | 'approved'
  | 'rejected'
  | 'undone'

export type BILLedgerEntryState = 'active' | 'pinned' | 'locked' | 'corrected' | 'deleted'

export type BILModeId =
  | 'prayer'
  | 'study'
  | 'church_notes'
  | 'project_planning'
  | 'coding'
  | 'leadership'
  | 'moderation'
  | 'content_creation'

export interface BILContentEnvelope {
  tier: BILTier
  sourceKind: string
  sourceId: string
  plaintext?: string
}

export interface BILSummaryAtom {
  id: string
  text: string
  confidence?: number
  provenanceTurnIds?: string[]
}

export interface BILCompactionEpisodeDraft extends BILContentEnvelope {
  threadId: string
  turnRange: {
    startTurnId: string
    endTurnId: string
    startIndex: number
    endIndex: number
  }
  summaryStruct: {
    decisions: BILSummaryAtom[]
    facts: BILSummaryAtom[]
    openQuestions: BILSummaryAtom[]
    actionItems: BILSummaryAtom[]
    preferences: BILSummaryAtom[]
    links: Array<{ id: string; url: string; label?: string; sourceTurnId: string }>
    risks: Array<BILSummaryAtom & { severity?: 'low' | 'medium' | 'high' }>
  }
  approvalState: BILApprovalState
  approvedBy?: string | null
}

export interface BILLedgerEntryDraft extends BILContentEnvelope {
  belief?: string
  provenance: {
    kind: 'turn' | 'source_card' | 'ledger_entry' | 'compaction_episode' | 'system' | 'callable'
    turnId?: string
    threadId?: string
    sourceCardId?: string
    episodeId?: string
  }
  state: BILLedgerEntryState
  pinScope?: 'thread' | 'package' | 'global' | null
  lockReason?: 'user_locked' | 'system_safety' | null
}

export interface BILSourceCardDraft extends BILContentEnvelope {
  title?: string
  sourceType: 'document' | 'sermon' | 'note' | 'pdf' | 'link' | 'imported_chat' | 'thread_timeline'
  layers: {
    oneLine?: string
    paragraph?: string
    outline?: Array<{ heading: string; items: string[] }>
  }
  citations: Array<{ id: string; label: string; locator: string; value: string; quoteHash?: string }>
  scriptureRefs: Array<{ reference: string; normalizedReference: string; translation?: string; citationId?: string }>
}

export interface BILContextPackageDraft {
  name: string
  instructions: string
  pinnedLedgerIds: string[]
  sourceCardIds: string[]
  modeId: BILModeId
  toolGrants: string[]
  spaceShareScope: {
    spaceId?: string | null
    visibility: 'private' | 'space_members' | 'space_leaders'
  }
}

export class BILContractError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'BILContractError'
  }
}

export function assertServerContentAllowed(envelope: BILContentEnvelope): void {
  assertNonEmpty(envelope.sourceKind, 'sourceKind')
  assertNonEmpty(envelope.sourceId, 'sourceId')

  if (envelope.tier === 'tier_p' && hasText(envelope.plaintext)) {
    throw new BILContractError('Tier P plaintext is local-only and must not enter server BIL processing.')
  }
}

export function sanitizeServerEnvelope<T extends BILContentEnvelope>(envelope: T): Omit<T, 'plaintext'> {
  assertServerContentAllowed(envelope)
  const { plaintext: _plaintext, ...sanitized } = envelope
  return sanitized
}

export function validateCompactionEpisodeDraft(draft: BILCompactionEpisodeDraft): void {
  assertServerContentAllowed(draft)
  assertNonEmpty(draft.threadId, 'threadId')
  assertNonEmpty(draft.turnRange.startTurnId, 'turnRange.startTurnId')
  assertNonEmpty(draft.turnRange.endTurnId, 'turnRange.endTurnId')

  if (draft.turnRange.endIndex < draft.turnRange.startIndex) {
    throw new BILContractError('turnRange.endIndex must be greater than or equal to startIndex.')
  }

  const summary = draft.summaryStruct
  ;['decisions', 'facts', 'openQuestions', 'actionItems', 'preferences', 'links', 'risks'].forEach((key) => {
    if (!Array.isArray(summary[key as keyof typeof summary])) {
      throw new BILContractError(`summaryStruct.${key} must be an array.`)
    }
  })
}

export function validateLedgerEntryDraft(draft: BILLedgerEntryDraft): void {
  assertServerContentAllowed(draft)
  if (draft.tier === 'tier_p' && hasText(draft.belief)) {
    throw new BILContractError('Tier P ledger beliefs must remain device-local.')
  }
  if (draft.tier !== 'tier_p') {
    assertNonEmpty(draft.belief, 'belief')
  }
  assertNonEmpty(draft.provenance.kind, 'provenance.kind')
}

export function validateSourceCardDraft(draft: BILSourceCardDraft): void {
  assertServerContentAllowed(draft)
  if (draft.tier === 'tier_p') {
    const hasPrivateSummary = hasText(draft.title) || hasText(draft.layers.oneLine) || hasText(draft.layers.paragraph)
    if (hasPrivateSummary) {
      throw new BILContractError('Tier P Source Card summaries must remain device-local.')
    }
  } else {
    assertNonEmpty(draft.title, 'title')
    assertNonEmpty(draft.layers.oneLine, 'layers.oneLine')
  }
}

export function validateContextPackageDraft(draft: BILContextPackageDraft): void {
  assertNonEmpty(draft.name, 'name')
  assertNonEmpty(draft.instructions, 'instructions')
  if (!Array.isArray(draft.pinnedLedgerIds)) {
    throw new BILContractError('pinnedLedgerIds must be an array.')
  }
  if (!Array.isArray(draft.sourceCardIds)) {
    throw new BILContractError('sourceCardIds must be an array.')
  }
  if (!Array.isArray(draft.toolGrants)) {
    throw new BILContractError('toolGrants must be an array.')
  }
}

function assertNonEmpty(value: unknown, field: string): void {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new BILContractError(`${field} must be a non-empty string.`)
  }
}

function hasText(value: unknown): boolean {
  return typeof value === 'string' && value.trim().length > 0
}

