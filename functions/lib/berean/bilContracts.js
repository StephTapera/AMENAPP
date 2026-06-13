"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.BILContractError = void 0;
exports.assertServerContentAllowed = assertServerContentAllowed;
exports.sanitizeServerEnvelope = sanitizeServerEnvelope;
exports.validateCompactionEpisodeDraft = validateCompactionEpisodeDraft;
exports.validateLedgerEntryDraft = validateLedgerEntryDraft;
exports.validateSourceCardDraft = validateSourceCardDraft;
exports.validateContextPackageDraft = validateContextPackageDraft;
class BILContractError extends Error {
    constructor(message) {
        super(message);
        this.name = 'BILContractError';
    }
}
exports.BILContractError = BILContractError;
function assertServerContentAllowed(envelope) {
    assertNonEmpty(envelope.sourceKind, 'sourceKind');
    assertNonEmpty(envelope.sourceId, 'sourceId');
    if (envelope.tier === 'tier_p' && hasText(envelope.plaintext)) {
        throw new BILContractError('Tier P plaintext is local-only and must not enter server BIL processing.');
    }
}
function sanitizeServerEnvelope(envelope) {
    assertServerContentAllowed(envelope);
    const { plaintext: _plaintext, ...sanitized } = envelope;
    return sanitized;
}
function validateCompactionEpisodeDraft(draft) {
    assertServerContentAllowed(draft);
    assertNonEmpty(draft.threadId, 'threadId');
    assertNonEmpty(draft.turnRange.startTurnId, 'turnRange.startTurnId');
    assertNonEmpty(draft.turnRange.endTurnId, 'turnRange.endTurnId');
    if (draft.turnRange.endIndex < draft.turnRange.startIndex) {
        throw new BILContractError('turnRange.endIndex must be greater than or equal to startIndex.');
    }
    const summary = draft.summaryStruct;
    ['decisions', 'facts', 'openQuestions', 'actionItems', 'preferences', 'links', 'risks'].forEach((key) => {
        if (!Array.isArray(summary[key])) {
            throw new BILContractError(`summaryStruct.${key} must be an array.`);
        }
    });
}
function validateLedgerEntryDraft(draft) {
    assertServerContentAllowed(draft);
    if (draft.tier === 'tier_p' && hasText(draft.belief)) {
        throw new BILContractError('Tier P ledger beliefs must remain device-local.');
    }
    if (draft.tier !== 'tier_p') {
        assertNonEmpty(draft.belief, 'belief');
    }
    assertNonEmpty(draft.provenance.kind, 'provenance.kind');
}
function validateSourceCardDraft(draft) {
    assertServerContentAllowed(draft);
    if (draft.tier === 'tier_p') {
        const hasPrivateSummary = hasText(draft.title) || hasText(draft.layers.oneLine) || hasText(draft.layers.paragraph);
        if (hasPrivateSummary) {
            throw new BILContractError('Tier P Source Card summaries must remain device-local.');
        }
    }
    else {
        assertNonEmpty(draft.title, 'title');
        assertNonEmpty(draft.layers.oneLine, 'layers.oneLine');
    }
}
function validateContextPackageDraft(draft) {
    assertNonEmpty(draft.name, 'name');
    assertNonEmpty(draft.instructions, 'instructions');
    if (!Array.isArray(draft.pinnedLedgerIds)) {
        throw new BILContractError('pinnedLedgerIds must be an array.');
    }
    if (!Array.isArray(draft.sourceCardIds)) {
        throw new BILContractError('sourceCardIds must be an array.');
    }
    if (!Array.isArray(draft.toolGrants)) {
        throw new BILContractError('toolGrants must be an array.');
    }
}
function assertNonEmpty(value, field) {
    if (typeof value !== 'string' || value.trim().length === 0) {
        throw new BILContractError(`${field} must be a non-empty string.`);
    }
}
function hasText(value) {
    return typeof value === 'string' && value.trim().length > 0;
}
