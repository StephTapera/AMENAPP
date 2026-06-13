"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const bilContracts_1 = require("./bilContracts");
function baseEpisode() {
    return {
        tier: 'tier_c',
        sourceKind: 'thread',
        sourceId: 'thread-1',
        threadId: 'thread-1',
        turnRange: {
            startTurnId: 'turn-1',
            endTurnId: 'turn-8',
            startIndex: 1,
            endIndex: 8,
        },
        summaryStruct: {
            decisions: [],
            facts: [],
            openQuestions: [],
            actionItems: [],
            preferences: [],
            links: [],
            risks: [],
        },
        approvalState: 'pending_user_approval',
    };
}
function baseSourceCard() {
    return {
        tier: 'tier_c',
        sourceKind: 'source_card',
        sourceId: 'source-1',
        sourceType: 'note',
        title: 'Romans study note',
        layers: {
            oneLine: 'A study note about Romans.',
            paragraph: 'A longer study note summary.',
            outline: [],
        },
        citations: [],
        scriptureRefs: [],
    };
}
describe('BIL contract guards', () => {
    test('rejects Tier P plaintext before server processing', () => {
        expect(() => (0, bilContracts_1.assertServerContentAllowed)({
            tier: 'tier_p',
            sourceKind: 'thread',
            sourceId: 'private-thread',
            plaintext: 'private prayer details',
        })).toThrow(bilContracts_1.BILContractError);
    });
    test('allows Tier P metadata envelopes without plaintext', () => {
        expect(() => (0, bilContracts_1.assertServerContentAllowed)({
            tier: 'tier_p',
            sourceKind: 'thread',
            sourceId: 'private-thread',
        })).not.toThrow();
    });
    test('sanitizes allowed server envelopes by stripping plaintext', () => {
        const sanitized = (0, bilContracts_1.sanitizeServerEnvelope)({
            tier: 'tier_c',
            sourceKind: 'thread',
            sourceId: 'thread-1',
            plaintext: 'confidential text',
        });
        expect('plaintext' in sanitized).toBe(false);
        expect(sanitized.sourceId).toBe('thread-1');
    });
    test('validates compaction episode turn ranges and summary arrays', () => {
        const episode = baseEpisode();
        expect(() => (0, bilContracts_1.validateCompactionEpisodeDraft)(episode)).not.toThrow();
        expect(() => (0, bilContracts_1.validateCompactionEpisodeDraft)({
            ...episode,
            turnRange: { ...episode.turnRange, startIndex: 9 },
        })).toThrow('turnRange.endIndex');
    });
    test('rejects Tier P ledger belief text on server', () => {
        expect(() => (0, bilContracts_1.validateLedgerEntryDraft)({
            tier: 'tier_p',
            sourceKind: 'ledger',
            sourceId: 'entry-1',
            belief: 'private belief',
            provenance: { kind: 'turn', turnId: 'turn-1' },
            state: 'active',
        })).toThrow('Tier P ledger beliefs');
    });
    test('requires non-private ledger belief text for server ledger entries', () => {
        expect(() => (0, bilContracts_1.validateLedgerEntryDraft)({
            tier: 'tier_c',
            sourceKind: 'ledger',
            sourceId: 'entry-1',
            belief: 'User wants scripture-first answers.',
            provenance: { kind: 'turn', turnId: 'turn-1' },
            state: 'pinned',
        })).not.toThrow();
    });
    test('rejects Tier P source summary layers on server', () => {
        const sourceCard = baseSourceCard();
        expect(() => (0, bilContracts_1.validateSourceCardDraft)({
            ...sourceCard,
            tier: 'tier_p',
        })).toThrow('Tier P Source Card summaries');
    });
    test('validates context package arrays and instructions', () => {
        expect(() => (0, bilContracts_1.validateContextPackageDraft)({
            name: 'AMEN Architecture',
            instructions: 'Use BIL contracts before implementation.',
            pinnedLedgerIds: ['ledger-1'],
            sourceCardIds: ['source-1'],
            modeId: 'project_planning',
            toolGrants: ['source_cards'],
            spaceShareScope: { visibility: 'private' },
        })).not.toThrow();
    });
});
