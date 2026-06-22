/**
 * semanticIntelligence.test.ts — System 29: Liquid Glass Intelligence Layer
 *
 * Unit tests for all 5 Cloud Function callable handlers.
 * Uses the firebase-admin and firebase-functions/v2/https mocks so the
 * handlers can be invoked directly with a synthetic request object — no
 * Firebase emulator or real network calls needed.
 *
 * Run: cd Backend/functions && npm test
 */

// ── Module mocks (must be declared before any imports) ──────────────────────
jest.mock("../rateLimit", () => ({
    enforceRateLimit: jest.fn().mockResolvedValue(undefined),
}));

jest.mock("../berean/services/SafetyValidator", () => ({
    validateRawTextOutput: jest.fn().mockReturnValue({ isValid: true, violations: [] }),
}));

// ── Imports ───────────────────────────────────────────────────────────────────
import {
    defineSemanticTerm,
    detectSmartActions,
    createKnowledgeThread,
    saveSemanticInsight,
    logPresenceSignal,
} from "../semanticIntelligence";
import { enforceRateLimit } from "../rateLimit";
import { validateRawTextOutput } from "../berean/services/SafetyValidator";

// ── Firebase admin mock internals ─────────────────────────────────────────────
// eslint-disable-next-line @typescript-eslint/no-require-imports
const adminMock = require("firebase-admin");
const mockDoc = adminMock.__mockDoc as {
    get: jest.Mock;
    set: jest.Mock;
    update: jest.Mock;
    delete: jest.Mock;
    collection: jest.Mock;
    __data: Record<string, unknown> | undefined;
    id: string;
};
const mockCollection = adminMock.__mockCollection as {
    doc: jest.Mock;
    add: jest.Mock;
    where: jest.Mock;
    get: jest.Mock;
    orderBy: jest.Mock;
    limit: jest.Mock;
};
const mockQuery = adminMock.__mockQuery as {
    get: jest.Mock;
    where: jest.Mock;
    limit: jest.Mock;
    orderBy: jest.Mock;
};

// ── Global fetch mock ─────────────────────────────────────────────────────────
type FetchLike = (url: string, init?: unknown) => Promise<unknown>;
let mockFetch: jest.MockedFunction<FetchLike>;

// ── Callable handler types ────────────────────────────────────────────────────
type CallableRequest = {
    data?: Record<string, unknown>;
    auth?: { uid: string } | null;
    app?: unknown;
};
type CallableHandler<T = unknown> = (req: CallableRequest) => Promise<T>;

const defineTermFn  = defineSemanticTerm  as unknown as CallableHandler;
const detectFn      = detectSmartActions  as unknown as CallableHandler;
const createThreadFn = createKnowledgeThread as unknown as CallableHandler;
const saveInsightFn  = saveSemanticInsight  as unknown as CallableHandler;
const logSignalFn    = logPresenceSignal    as unknown as CallableHandler;

// ── Auth/App helpers ──────────────────────────────────────────────────────────
const AUTH = { uid: "test-uid-001" };
const APP  = {};

function authed(data: Record<string, unknown> = {}): CallableRequest {
    return { data, auth: AUTH, app: APP };
}

// ── Firestore data factories ──────────────────────────────────────────────────

function approvedDefinitionData(term = "grace"): Record<string, unknown> {
    return {
        term,
        normalizedTerm: term.toLowerCase(),
        compactDefinition: `${term} is a theological concept of unmerited favour.`,
        expandedDefinition: null,
        biblicalContext: null,
        relatedScriptureRefs: ["Ephesians 2:8"],
        confidence: 0.95,
        safetyStatus: "approved",
        modelUsed: "grok-3-mini",
        generationSource: "ai",
        cacheKey: "testkey123",
        id: "testkey123",
    };
}

function grokJsonResponse(term: string, refs: string[] = ["Ephesians 2:8"]): object {
    return {
        compact: `${term} is the unmerited favour of God toward sinners.`,
        expanded: null,
        biblical: null,
        refs,
        confidence: 0.92,
    };
}

function makeFetchSuccess(body: object): object {
    return {
        ok: true,
        status: 200,
        json: jest.fn().mockResolvedValue({
            choices: [{ message: { content: JSON.stringify(body) } }],
        }),
        text: jest.fn().mockResolvedValue(""),
    };
}

function makeFetchError(status = 500, body = "Internal Server Error"): object {
    return {
        ok: false,
        status,
        json: jest.fn().mockResolvedValue({}),
        text: jest.fn().mockResolvedValue(body),
    };
}

// ── Reset helpers ─────────────────────────────────────────────────────────────

function resetMockDefaults(): void {
    mockDoc.get.mockReset();
    mockDoc.set.mockReset();
    mockDoc.update.mockReset();
    mockDoc.delete.mockReset();
    mockDoc.collection.mockReset();
    mockCollection.doc.mockReset();
    mockCollection.add.mockReset();
    mockCollection.where.mockReset();
    mockCollection.get.mockReset();
    mockCollection.limit.mockReset();
    mockQuery.where.mockReset();
    mockQuery.limit.mockReset();
    mockQuery.orderBy.mockReset();
    mockQuery.get.mockReset();

    mockDoc.__data = undefined;
    mockDoc.get.mockImplementation(() =>
        Promise.resolve({ data: () => mockDoc.__data, exists: !!mockDoc.__data })
    );
    mockDoc.set.mockResolvedValue(undefined);
    mockDoc.update.mockResolvedValue(undefined);
    mockDoc.delete.mockResolvedValue(undefined);
    mockDoc.collection.mockReturnValue(mockCollection);
    mockCollection.doc.mockReturnValue(mockDoc);
    mockCollection.add.mockResolvedValue({ id: "generated-id" });
    mockCollection.where.mockReturnValue(mockQuery);
    mockCollection.get.mockResolvedValue({ docs: [], empty: true, size: 0 });
    mockCollection.limit.mockReturnValue(mockCollection);
    mockQuery.where.mockReturnValue(mockQuery);
    mockQuery.limit.mockReturnValue(mockQuery);
    mockQuery.orderBy.mockReturnValue(mockQuery);
    mockQuery.get.mockResolvedValue({ docs: [], empty: true, size: 0 });

    (enforceRateLimit as jest.Mock).mockResolvedValue(undefined);
    (validateRawTextOutput as jest.Mock).mockReturnValue({ isValid: true, violations: [] });
}

// ── Fetch mock setup ──────────────────────────────────────────────────────────

beforeAll(() => {
    mockFetch = jest.fn();
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (global as any).fetch = mockFetch;
});

beforeEach(() => {
    jest.clearAllMocks();
    resetMockDefaults();
});

// ═══════════════════════════════════════════════════════════════════════════════
// 1. defineSemanticTerm
// ═══════════════════════════════════════════════════════════════════════════════

describe("defineSemanticTerm — authentication gates", () => {

    test("rejects unauthenticated request", async () => {
        await expect(defineTermFn({ data: { term: "grace" } }))
            .rejects.toMatchObject({ code: "unauthenticated" });
        expect(mockDoc.set).not.toHaveBeenCalled();
    });

    test("rejects missing App Check token", async () => {
        // auth present but app absent
        await expect(defineTermFn({ data: { term: "grace" }, auth: AUTH }))
            .rejects.toMatchObject({ code: "failed-precondition" });
        expect(mockDoc.set).not.toHaveBeenCalled();
    });

});

describe("defineSemanticTerm — input validation", () => {

    test("rejects term shorter than 2 characters", async () => {
        await expect(defineTermFn(authed({ term: "a" })))
            .rejects.toMatchObject({ code: "invalid-argument" });
    });

    test("rejects empty term", async () => {
        await expect(defineTermFn(authed({ term: "" })))
            .rejects.toMatchObject({ code: "invalid-argument" });
    });

    test("rejects missing term field", async () => {
        await expect(defineTermFn(authed({})))
            .rejects.toMatchObject({ code: "invalid-argument" });
    });

});

describe("defineSemanticTerm — rate limiting", () => {

    test("enforces rate limit and propagates HttpsError", async () => {
        const { HttpsError } = require("firebase-functions/v2/https");
        (enforceRateLimit as jest.Mock).mockRejectedValueOnce(
            new HttpsError("resource-exhausted", "Rate limit exceeded.")
        );
        await expect(defineTermFn(authed({ term: "grace" })))
            .rejects.toMatchObject({ code: "resource-exhausted" });
    });

});

describe("defineSemanticTerm — cache hit path", () => {

    test("returns cached definition without calling AI", async () => {
        const cachedData = approvedDefinitionData("grace");
        mockDoc.get.mockResolvedValueOnce({ exists: true, data: () => cachedData });

        const result = await defineTermFn(authed({ term: "grace" })) as Record<string, unknown>;

        expect(result.cacheStatus).toBe("hit");
        expect(result.term).toBe("grace");
        // fetch must not be called when cache hits
        expect(mockFetch).not.toHaveBeenCalled();
    });

    test("logs semantic_definition_cache_hit analytics on cache hit", async () => {
        const cachedData = approvedDefinitionData("grace");
        mockDoc.get.mockResolvedValueOnce({ exists: true, data: () => cachedData });

        await defineTermFn(authed({ term: "grace" }));

        const addCalls = mockCollection.add.mock.calls as unknown[][];
        const analyticsEvents = addCalls
            .map((args) => (args[0] as Record<string, unknown>)?.event as string)
            .filter(Boolean);
        expect(analyticsEvents).toContain("semantic_definition_cache_hit");
    });

});

describe("defineSemanticTerm — cache miss + AI generation", () => {

    test("generates definition via Grok on cache miss and persists it", async () => {
        // cache miss (first get → empty doc), in-flight miss (second get → empty)
        mockDoc.get
            .mockResolvedValueOnce({ exists: false, data: () => undefined }) // cache
            .mockResolvedValueOnce({ exists: false, data: () => undefined }); // inflight

        mockFetch.mockResolvedValue(makeFetchSuccess(grokJsonResponse("grace")));

        const result = await defineTermFn(authed({ term: "grace", sourceType: "post" })) as Record<string, unknown>;

        expect(result.cacheStatus).toBe("miss");
        expect(result.generationSource).toBe("ai");
        expect(typeof result.compactDefinition).toBe("string");
        // set called at least twice: once for inflight, once for persisting
        expect(mockDoc.set).toHaveBeenCalled();
    });

    test("logs semantic_definition_cache_miss analytics on cache miss", async () => {
        mockDoc.get
            .mockResolvedValueOnce({ exists: false, data: () => undefined })
            .mockResolvedValueOnce({ exists: false, data: () => undefined });
        mockFetch.mockResolvedValue(makeFetchSuccess(grokJsonResponse("grace")));

        await defineTermFn(authed({ term: "grace" }));

        const addCalls = mockCollection.add.mock.calls as unknown[][];
        const events = addCalls
            .map((args) => (args[0] as Record<string, unknown>)?.event as string)
            .filter(Boolean);
        expect(events).toContain("semantic_definition_cache_miss");
    });

    test("logs semantic_definition_persisted when definition is approved and saved", async () => {
        mockDoc.get
            .mockResolvedValueOnce({ exists: false, data: () => undefined })
            .mockResolvedValueOnce({ exists: false, data: () => undefined });
        mockFetch.mockResolvedValue(makeFetchSuccess(grokJsonResponse("grace")));

        await defineTermFn(authed({ term: "grace" }));

        const addCalls = mockCollection.add.mock.calls as unknown[][];
        const events = addCalls
            .map((args) => (args[0] as Record<string, unknown>)?.event as string)
            .filter(Boolean);
        expect(events).toContain("semantic_definition_persisted");
    });

    test("falls back to Claude when Grok fails", async () => {
        mockDoc.get
            .mockResolvedValueOnce({ exists: false, data: () => undefined })
            .mockResolvedValueOnce({ exists: false, data: () => undefined });

        // Grok fails, Claude succeeds
        mockFetch
            .mockResolvedValueOnce(makeFetchError(500, "Grok unavailable")) // Grok
            .mockResolvedValue({                                             // Claude (3 retries ok)
                ok: true,
                status: 200,
                json: jest.fn().mockResolvedValue({
                    content: [{
                        type: "text",
                        text: JSON.stringify(grokJsonResponse("grace")),
                    }],
                }),
                text: jest.fn().mockResolvedValue(""),
            });

        const result = await defineTermFn(authed({ term: "grace" })) as Record<string, unknown>;
        expect(result.generationSource).toBe("ai");
        expect(result.modelUsed).toMatch(/claude/);
    });

    test("falls back to theological dictionary when both AI providers fail", async () => {
        mockDoc.get
            .mockResolvedValueOnce({ exists: false, data: () => undefined })
            .mockResolvedValueOnce({ exists: false, data: () => undefined });

        mockFetch.mockResolvedValue(makeFetchError(500, "Both providers down"));

        const result = await defineTermFn(authed({ term: "grace" })) as Record<string, unknown>;
        expect(result.generationSource).toBe("fallback");
        expect(result.modelUsed).toContain("builtin-theological-dictionary");
    });

    test("returns safe non-fabricating fallback when AI fails on unknown term", async () => {
        mockDoc.get
            .mockResolvedValueOnce({ exists: false, data: () => undefined })
            .mockResolvedValueOnce({ exists: false, data: () => undefined });

        mockFetch.mockResolvedValue(makeFetchError(500, "Error"));

        const result = await defineTermFn(authed({ term: "neopresuppositionalism" })) as Record<string, unknown>;
        expect(result.modelUsed).toBe("fallback-none");
        expect(result.confidence).toBe(0);
        // safe message must not fabricate a definition
        expect((result.compactDefinition as string)).toContain("Ask Berean");
    });

});

describe("defineSemanticTerm — moderation", () => {

    test("rejects and does not persist unsafe AI output", async () => {
        mockDoc.get
            .mockResolvedValueOnce({ exists: false, data: () => undefined })
            .mockResolvedValueOnce({ exists: false, data: () => undefined });

        mockFetch.mockResolvedValue(makeFetchSuccess({
            compact: "Hate-filled unsafe content",
            expanded: null,
            biblical: null,
            refs: [],
            confidence: 0.5,
        }));

        (validateRawTextOutput as jest.Mock).mockReturnValue({
            isValid: false,
            violations: ["hate_speech"],
        });

        await expect(defineTermFn(authed({ term: "grace" })))
            .rejects.toMatchObject({ code: "internal" });

        // Ensure the invalid definition was never saved to semanticDefinitions
        const setCalls = mockDoc.set.mock.calls as unknown[][];
        const persistedDocs = setCalls.filter(args => {
            const data = args[0] as Record<string, unknown>;
            return data?.safetyStatus === "approved";
        });
        expect(persistedDocs).toHaveLength(0);
    });

    test("logs semantic_definition_moderation_rejected analytics on unsafe output", async () => {
        mockDoc.get
            .mockResolvedValueOnce({ exists: false, data: () => undefined })
            .mockResolvedValueOnce({ exists: false, data: () => undefined });

        mockFetch.mockResolvedValue(makeFetchSuccess({
            compact: "Dangerous content",
            expanded: null, biblical: null, refs: [], confidence: 0.5,
        }));
        (validateRawTextOutput as jest.Mock).mockReturnValue({
            isValid: false, violations: ["self_harm"],
        });

        await expect(defineTermFn(authed({ term: "grace" }))).rejects.toThrow();

        const addCalls = mockCollection.add.mock.calls as unknown[][];
        const events = addCalls
            .map((args) => (args[0] as Record<string, unknown>)?.event as string)
            .filter(Boolean);
        expect(events).toContain("semantic_definition_moderation_rejected");
    });

});

describe("defineSemanticTerm — scripture reference validation", () => {

    test("filters out fabricated scripture references", async () => {
        mockDoc.get
            .mockResolvedValueOnce({ exists: false, data: () => undefined })
            .mockResolvedValueOnce({ exists: false, data: () => undefined });

        // Includes one valid ref and one fabricated ref
        mockFetch.mockResolvedValue(makeFetchSuccess(
            grokJsonResponse("grace", ["Ephesians 2:8", "FakeBook 99:1", "Romans 5:8"])
        ));

        const result = await defineTermFn(authed({ term: "grace" })) as Record<string, unknown>;

        const refs = result.relatedScriptureRefs as string[];
        expect(refs).toContain("Ephesians 2:8");
        expect(refs).toContain("Romans 5:8");
        expect(refs).not.toContain("FakeBook 99:1");
    });

    test("logs semantic_definition_scripture_refs_rejected when refs are filtered", async () => {
        mockDoc.get
            .mockResolvedValueOnce({ exists: false, data: () => undefined })
            .mockResolvedValueOnce({ exists: false, data: () => undefined });

        mockFetch.mockResolvedValue(makeFetchSuccess(
            grokJsonResponse("grace", ["FakeBook 99:1"])
        ));

        await defineTermFn(authed({ term: "grace" }));

        const addCalls = mockCollection.add.mock.calls as unknown[][];
        const events = addCalls
            .map((args) => (args[0] as Record<string, unknown>)?.event as string)
            .filter(Boolean);
        expect(events).toContain("semantic_definition_scripture_refs_rejected");
    });

});

// ═══════════════════════════════════════════════════════════════════════════════
// 2. detectSmartActions
// ═══════════════════════════════════════════════════════════════════════════════

describe("detectSmartActions — authentication gates", () => {

    test("rejects unauthenticated request", async () => {
        await expect(detectFn({ data: { screen: "feed" } }))
            .rejects.toMatchObject({ code: "unauthenticated" });
    });

    test("rejects missing App Check token", async () => {
        await expect(detectFn({ data: { screen: "feed" }, auth: AUTH }))
            .rejects.toMatchObject({ code: "failed-precondition" });
    });

});

describe("detectSmartActions — action limit", () => {

    test("returns at most 3 ranked actions regardless of context signals", async () => {
        // Trigger all possible actions: selected text + scripture + church notes + berean + selah
        const result = await detectFn(authed({
            screen: "churchNotes",
            sourceType: "churchNote",
            sourceId: "note-1",
            selectedText: "atonement through Christ",
            visibleText: "Romans 3:24 speaks to justification freely given by grace",
            featureFlags: {
                semantic_underline_enabled: true,
                church_notes_semantic_actions_enabled: true,
                berean_rag_enabled: true,
                selah_media_os_enabled: true,
                selah_semantic_save_enabled: true,
                explain_video_enabled: true,
            },
        })) as { rankedActions: unknown[] };

        expect(result.rankedActions.length).toBeLessThanOrEqual(3);
    });

});

describe("detectSmartActions — suppression", () => {

    test("suppresses explain_video when transcript is not ready", async () => {
        const result = await detectFn(authed({
            screen: "mediaDetail",
            sourceType: "media",
            sourceId: "vid-1",
            featureFlags: { explain_video_enabled: true, has_transcript: false },
        })) as { suppressedActions: string[]; suppressedDetails: Array<{ id: string; suppressionReason: string }> };

        expect(result.suppressedActions).toContain("explain_video");
        const detail = result.suppressedDetails.find(s => s.id === "explain_video");
        expect(detail?.suppressionReason).toBe("transcript_not_ready");
    });

    test("suppresses save_to_selah when surface is not reflection-eligible", async () => {
        const result = await detectFn(authed({
            screen: "settings",
            sourceType: "settings",
            featureFlags: { selah_media_os_enabled: true, selah_semantic_save_enabled: true },
        })) as { suppressedActions: string[] };

        expect(result.suppressedActions).toContain("save_to_selah");
    });

    test("does not include ask_berean when berean_rag_enabled is false", async () => {
        const result = await detectFn(authed({
            screen: "feed",
            sourceType: "post",
            visibleText: "God's grace is sufficient.",
            featureFlags: { berean_rag_enabled: false },
        })) as { rankedActions: Array<{ id: string }> };

        expect(result.rankedActions.map(a => a.id)).not.toContain("ask_berean");
    });

    test("does not show explain_video when has_transcript is false even if flag is on", async () => {
        const result = await detectFn(authed({
            screen: "media",
            sourceType: "media",
            featureFlags: { explain_video_enabled: true, has_transcript: false },
        })) as { rankedActions: Array<{ id: string }> };

        expect(result.rankedActions.map(a => a.id)).not.toContain("explain_video");
    });

    test("returns empty actions and crisis reason code when crisis keywords detected", async () => {
        const result = await detectFn(authed({
            screen: "feed",
            visibleText: "I want to suicid myself tonight",
            featureFlags: { berean_rag_enabled: true },
        })) as { rankedActions: unknown[]; reasonCodes: string[]; suppressedActions: string[] };

        expect(result.rankedActions).toHaveLength(0);
        expect(result.suppressedActions).toContain("all");
        expect(result.reasonCodes).toContain("crisis_dominates");
    });

});

describe("detectSmartActions — response structure", () => {

    test("each ranked action includes a confidence score", async () => {
        const result = await detectFn(authed({
            screen: "feed",
            sourceType: "post",
            selectedText: "sanctification",
            featureFlags: { semantic_underline_enabled: true },
        })) as { rankedActions: Array<{ id: string; confidence: number }> };

        expect(result.rankedActions.length).toBeGreaterThan(0);
        for (const action of result.rankedActions) {
            expect(typeof action.confidence).toBe("number");
            expect(action.confidence).toBeGreaterThanOrEqual(0.70);
            expect(action.confidence).toBeLessThanOrEqual(1.0);
        }
    });

    test("suppressedDetails contains structured id and suppressionReason", async () => {
        const result = await detectFn(authed({
            screen: "media",
            sourceType: "media",
            featureFlags: { explain_video_enabled: true, has_transcript: false },
        })) as {
            suppressedDetails: Array<{ id: string; suppressionReason: string }>;
        };

        for (const detail of result.suppressedDetails) {
            expect(typeof detail.id).toBe("string");
            expect(typeof detail.suppressionReason).toBe("string");
            expect(detail.id.length).toBeGreaterThan(0);
            expect(detail.suppressionReason.length).toBeGreaterThan(0);
        }
    });

    test("logs smart_action_rendered analytics", async () => {
        await detectFn(authed({
            screen: "feed",
            sourceType: "post",
            featureFlags: { berean_rag_enabled: true },
        }));

        const addCalls = mockCollection.add.mock.calls as unknown[][];
        const events = addCalls
            .map((args) => (args[0] as Record<string, unknown>)?.event as string)
            .filter(Boolean);
        expect(events).toContain("smart_action_rendered");
    });

    test("logs smart_action_suppressed analytics for each suppressed action", async () => {
        await detectFn(authed({
            screen: "mediaDetail",
            sourceType: "media",
            featureFlags: { explain_video_enabled: true, has_transcript: false },
        }));

        const addCalls = mockCollection.add.mock.calls as unknown[][];
        const events = addCalls
            .map((args) => (args[0] as Record<string, unknown>)?.event as string)
            .filter(Boolean);
        expect(events.some(e => e === "smart_action_suppressed")).toBe(true);
    });

});

// ═══════════════════════════════════════════════════════════════════════════════
// 3. createKnowledgeThread
// ═══════════════════════════════════════════════════════════════════════════════

describe("createKnowledgeThread — authentication gates", () => {

    test("rejects unauthenticated request", async () => {
        await expect(createThreadFn({ data: { term: "grace", definitionId: "abc" } }))
            .rejects.toMatchObject({ code: "unauthenticated" });
    });

    test("rejects missing App Check token", async () => {
        await expect(createThreadFn({ data: { term: "grace", definitionId: "abc" }, auth: AUTH }))
            .rejects.toMatchObject({ code: "failed-precondition" });
    });

});

describe("createKnowledgeThread — payload validation", () => {

    test("rejects when term is missing", async () => {
        // Stub definition lookup to avoid not-found error masking the validation
        mockDoc.get.mockResolvedValueOnce({ exists: true, data: () => ({ safetyStatus: "approved" }) });
        await expect(createThreadFn(authed({ definitionId: "def-1" })))
            .rejects.toMatchObject({ code: "invalid-argument" });
    });

    test("rejects when definitionId is missing", async () => {
        await expect(createThreadFn(authed({ term: "grace" })))
            .rejects.toMatchObject({ code: "invalid-argument" });
    });

    test("rejects when definition does not exist", async () => {
        mockDoc.get.mockResolvedValueOnce({ exists: false, data: () => undefined });
        await expect(createThreadFn(authed({ term: "grace", definitionId: "missing" })))
            .rejects.toMatchObject({ code: "not-found" });
    });

    test("rejects when definition safetyStatus is not approved", async () => {
        mockDoc.get.mockResolvedValueOnce({
            exists: true, data: () => ({ safetyStatus: "review_required" }),
        });
        await expect(createThreadFn(authed({ term: "grace", definitionId: "def-1" })))
            .rejects.toMatchObject({ code: "not-found" });
    });

});

describe("createKnowledgeThread — creation", () => {

    test("creates thread at user-scoped path and returns threadId", async () => {
        mockDoc.get.mockResolvedValueOnce({
            exists: true, data: () => ({ safetyStatus: "approved" }),
        });

        const result = await createThreadFn(authed({
            term: "grace",
            definitionId: "def-abc",
            sourceType: "post",
            sourceId: "post-1",
            relatedRefs: ["Romans 3:24", "Ephesians 2:8"],
        })) as { threadId: string };

        expect(typeof result.threadId).toBe("string");
        expect(mockDoc.set).toHaveBeenCalled();
        const setData = mockDoc.set.mock.calls[0][0] as Record<string, unknown>;
        expect(setData.primaryTerm).toBe("grace");
        expect(setData.savedInsightIds).toContain("def-abc");
    });

    test("filters fabricated scripture refs in the thread", async () => {
        mockDoc.get.mockResolvedValueOnce({
            exists: true, data: () => ({ safetyStatus: "approved" }),
        });

        await createThreadFn(authed({
            term: "grace",
            definitionId: "def-abc",
            relatedRefs: ["Romans 3:24", "FakeBook 99:1"],
        }));

        const setData = mockDoc.set.mock.calls[0][0] as Record<string, unknown>;
        const refs = setData.relatedScriptureRefs as string[];
        expect(refs).toContain("Romans 3:24");
        expect(refs).not.toContain("FakeBook 99:1");
    });

});

// ═══════════════════════════════════════════════════════════════════════════════
// 4. saveSemanticInsight
// ═══════════════════════════════════════════════════════════════════════════════

describe("saveSemanticInsight — authentication gates", () => {

    test("rejects unauthenticated request", async () => {
        await expect(saveInsightFn({ data: { definitionId: "d1", term: "grace" } }))
            .rejects.toMatchObject({ code: "unauthenticated" });
    });

    test("rejects missing App Check token", async () => {
        await expect(saveInsightFn({ data: { definitionId: "d1", term: "grace" }, auth: AUTH }))
            .rejects.toMatchObject({ code: "failed-precondition" });
    });

});

describe("saveSemanticInsight — payload validation", () => {

    test("rejects when definitionId is missing", async () => {
        await expect(saveInsightFn(authed({ term: "grace" })))
            .rejects.toMatchObject({ code: "invalid-argument" });
    });

    test("rejects when term is missing", async () => {
        await expect(saveInsightFn(authed({ definitionId: "def-1" })))
            .rejects.toMatchObject({ code: "invalid-argument" });
    });

    test("rejects when definition does not exist", async () => {
        mockDoc.get.mockResolvedValueOnce({ exists: false, data: () => undefined });
        await expect(saveInsightFn(authed({ definitionId: "missing", term: "grace" })))
            .rejects.toMatchObject({ code: "not-found" });
    });

    test("rejects when definition safetyStatus is not approved", async () => {
        mockDoc.get.mockResolvedValueOnce({
            exists: true, data: () => ({ safetyStatus: "review_required", compactDefinition: "..." }),
        });
        await expect(saveInsightFn(authed({ definitionId: "def-1", term: "grace" })))
            .rejects.toMatchObject({ code: "not-found" });
    });

});

describe("saveSemanticInsight — save and deduplication", () => {

    test("saves insight to user-owned path and returns savedInsightId", async () => {
        mockDoc.get.mockResolvedValueOnce({
            exists: true,
            data: () => ({
                safetyStatus: "approved",
                compactDefinition: "Grace is unmerited favour.",
                relatedScriptureRefs: ["Ephesians 2:8"],
            }),
        });
        // No existing duplicate
        mockQuery.get.mockResolvedValueOnce({ docs: [], empty: true });

        const result = await saveInsightFn(authed({
            definitionId: "def-abc",
            term: "grace",
            sourceType: "post",
            sourceId: "post-1",
        })) as { savedInsightId: string; deduplicated: boolean };

        expect(result.deduplicated).toBe(false);
        expect(typeof result.savedInsightId).toBe("string");

        // Insight was written via insightRef.set or collection.add
        expect(mockDoc.set).toHaveBeenCalled();
    });

    test("deduplicates when same definition already saved", async () => {
        mockDoc.get.mockResolvedValueOnce({
            exists: true,
            data: () => ({
                safetyStatus: "approved",
                compactDefinition: "Grace is unmerited favour.",
                relatedScriptureRefs: [],
            }),
        });
        // Existing duplicate found
        const existingDoc = { id: "existing-insight-id" };
        mockQuery.get.mockResolvedValueOnce({
            docs: [existingDoc], empty: false,
        });

        const result = await saveInsightFn(authed({
            definitionId: "def-abc",
            term: "grace",
        })) as { savedInsightId: string; deduplicated: boolean };

        expect(result.deduplicated).toBe(true);
        expect(result.savedInsightId).toBe("existing-insight-id");
    });

    test("writes only to user-owned path (uid-scoped subcollection)", async () => {
        mockDoc.get.mockResolvedValueOnce({
            exists: true,
            data: () => ({
                safetyStatus: "approved",
                compactDefinition: "Grace is unmerited favour.",
                relatedScriptureRefs: [],
            }),
        });
        mockQuery.get.mockResolvedValueOnce({ docs: [], empty: true });

        await saveInsightFn(authed({ definitionId: "def-abc", term: "grace" }));

        // Verify the write happened (mockDoc.set should be called for the insight)
        expect(mockDoc.set).toHaveBeenCalled();
        const writtenData = mockDoc.set.mock.calls.find(args => {
            const d = args[0] as Record<string, unknown>;
            return d?.visibility === "private";
        })?.[0] as Record<string, unknown> | undefined;
        expect(writtenData?.uid).toBe(AUTH.uid);
        expect(writtenData?.visibility).toBe("private");
    });

});

// ═══════════════════════════════════════════════════════════════════════════════
// 5. logPresenceSignal
// ═══════════════════════════════════════════════════════════════════════════════

describe("logPresenceSignal — authentication gates", () => {

    test("rejects unauthenticated request", async () => {
        await expect(logSignalFn({ data: { screen: "feed", signalType: "scroll" } }))
            .rejects.toMatchObject({ code: "unauthenticated" });
    });

    test("rejects missing App Check token", async () => {
        await expect(logSignalFn({ data: { screen: "feed", signalType: "scroll" }, auth: AUTH }))
            .rejects.toMatchObject({ code: "failed-precondition" });
    });

});

describe("logPresenceSignal — signal acceptance", () => {

    test("accepts a valid privacy-safe signal", async () => {
        const result = await logSignalFn(authed({
            screen: "feed",
            signalType: "semantic_term_viewed",
            sourceId: "post-123",
            metadata: { suggestionType: "define", scrollDepth: "80" },
        })) as { accepted: boolean };

        expect(result.accepted).toBe(true);
        // Should have written to user's presenceSignals subcollection
        expect(mockCollection.add).toHaveBeenCalled();
    });

    test("strips non-allowlist metadata keys to protect privacy", async () => {
        await logSignalFn(authed({
            screen: "feed",
            signalType: "scroll",
            metadata: {
                suggestionType: "define",       // allowed
                rawUserText: "private prayer",  // NOT in allowlist — must be stripped
                sessionDuration: "120",         // allowed
            },
        }));

        const addCalls = mockCollection.add.mock.calls as unknown[][];
        const signalDoc = addCalls.find(args => {
            const d = args[0] as Record<string, unknown>;
            return d?.signalType === "scroll";
        })?.[0] as Record<string, unknown> | undefined;

        if (signalDoc?.metadata) {
            const meta = signalDoc.metadata as Record<string, unknown>;
            expect(meta.rawUserText).toBeUndefined();
            expect(meta.suggestionType).toBeDefined();
            expect(meta.sessionDuration).toBeDefined();
        }
    });

    test("caps metadata values at 80 characters", async () => {
        const longValue = "x".repeat(200);
        await logSignalFn(authed({
            screen: "feed",
            signalType: "scroll",
            metadata: { suggestionType: longValue },
        }));

        const addCalls = mockCollection.add.mock.calls as unknown[][];
        const signalDoc = addCalls.find(args => {
            const d = args[0] as Record<string, unknown>;
            return d?.signalType === "scroll";
        })?.[0] as Record<string, unknown> | undefined;

        if (signalDoc?.metadata) {
            const meta = signalDoc.metadata as Record<string, unknown>;
            expect((meta.suggestionType as string).length).toBeLessThanOrEqual(80);
        }
    });

    test("logs presence_signal_logged analytics", async () => {
        await logSignalFn(authed({
            screen: "feed",
            signalType: "semantic_term_viewed",
        }));

        const addCalls = mockCollection.add.mock.calls as unknown[][];
        const events = addCalls
            .map(args => (args[0] as Record<string, unknown>)?.event as string)
            .filter(Boolean);
        expect(events).toContain("presence_signal_logged");
    });

    test("always writes privacyLevel as 'aggregate'", async () => {
        await logSignalFn(authed({ screen: "feed", signalType: "scroll" }));

        const addCalls = mockCollection.add.mock.calls as unknown[][];
        const signalDoc = addCalls.find(args => {
            const d = args[0] as Record<string, unknown>;
            return d?.privacyLevel !== undefined && d?.event === undefined;
        })?.[0] as Record<string, unknown> | undefined;

        expect(signalDoc?.privacyLevel).toBe("aggregate");
    });

});
