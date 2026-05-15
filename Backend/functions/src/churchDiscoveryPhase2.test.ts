import {
    refreshChurchLiveState,
    generateChurchExperienceSummary,
    calculateChurchFitScore,
    resolveChurchSmartAction,
    generateBereanChurchSuggestions,
} from "./churchDiscoveryPhase2";

// eslint-disable-next-line @typescript-eslint/no-var-requires
const admin = require("firebase-admin");
const { __mockDoc, __mockCollection } = admin;

// Helper: simulate the Firebase Functions v2 callable mock invoking the handler
// The onCall mock from __mocks__ returns the raw handler function.
type Handler = (request: Record<string, unknown>) => Promise<unknown>;

function authedRequest(churchId?: string, extra: Record<string, unknown> = {}) {
    return {
        auth: { uid: "user-123" },
        app: { appId: "app-abc" },
        data: { churchId, ...extra },
    };
}

function anonRequest(extra: Record<string, unknown> = {}) {
    return {
        auth: undefined,
        app: { appId: "app-abc" },
        data: extra,
    };
}

// Before each test: set up mockDoc to have church data and a ref so subcollections work.
beforeEach(() => {
    jest.clearAllMocks();
    __mockDoc.__data = {
        denomination: "Baptist",
        livestreamUrl: "https://example.com/live",
        serviceTimes: [{ dayOfWeek: 1, time: "10:00 AM" }],
        accessibility: ["wheelchair"],
    };
    // Snapshot returned by .get() needs a `ref` so subcollection writes work.
    __mockDoc.get.mockResolvedValue({
        data: () => __mockDoc.__data,
        exists: true,
        ref: __mockDoc,
    });
});

// ── Exports ──────────────────────────────────────────────────────────────────

describe("churchDiscoveryPhase2 exports", () => {
    test("all 5 callables are exported", () => {
        expect(typeof refreshChurchLiveState).toBe("function");
        expect(typeof generateChurchExperienceSummary).toBe("function");
        expect(typeof calculateChurchFitScore).toBe("function");
        expect(typeof resolveChurchSmartAction).toBe("function");
        expect(typeof generateBereanChurchSuggestions).toBe("function");
    });
});

// ── refreshChurchLiveState ────────────────────────────────────────────────────

describe("refreshChurchLiveState", () => {
    const handler = refreshChurchLiveState as unknown as Handler;

    test("throws invalid-argument when churchId is missing", async () => {
        const req = { auth: { uid: "u" }, app: { appId: "a" }, data: {} };
        await expect(handler(req)).rejects.toMatchObject({ code: "invalid-argument" });
    });

    test("throws not-found when church document does not exist", async () => {
        __mockDoc.get.mockResolvedValueOnce({ data: () => undefined, exists: false });
        await expect(handler(authedRequest("church-x"))).rejects.toMatchObject({ code: "not-found" });
    });

    test("returns valid live state shape with service schedule data", async () => {
        const result = await handler(authedRequest("church-123")) as Record<string, unknown>;
        expect(result.churchId).toBe("church-123");
        expect(["live", "upcoming", "closed", "quiet", "unknown"]).toContain(result.state);
        expect(typeof result.title).toBe("string");
        expect(typeof result.confidence).toBe("number");
        expect(result.atmosphereTags).toBeInstanceOf(Array);
        // updatedAt must NOT be a FieldValue sentinel in the return value
        expect(result.updatedAt).toBeNull();
    });

    test("returns state=unknown and low confidence when no service times or livestream", async () => {
        __mockDoc.__data = {};
        __mockDoc.get.mockResolvedValue({ data: () => __mockDoc.__data, exists: true, ref: __mockDoc });
        const result = await handler(authedRequest("church-empty")) as Record<string, unknown>;
        expect(result.state).toBe("unknown");
        expect(result.livestreamUrl).toBeNull();
        expect(result.confidence).toBeLessThan(0.3);
    });
});

// ── generateChurchExperienceSummary ──────────────────────────────────────────

describe("generateChurchExperienceSummary", () => {
    const handler = generateChurchExperienceSummary as unknown as Handler;

    test("returns all expected summary fields", async () => {
        const result = await handler(authedRequest("church-123")) as Record<string, unknown>;
        expect(result.churchId).toBe("church-123");
        expect(result).toHaveProperty("parking");
        expect(result).toHaveProperty("bestArrivalTime");
        expect(result).toHaveProperty("entrance");
        expect(result).toHaveProperty("serviceLength");
        expect(result).toHaveProperty("worshipStyle");
        expect(result).toHaveProperty("kidsMinistry");
        expect(result).toHaveProperty("accessibility");
        expect(result).toHaveProperty("translation");
        expect(result).toHaveProperty("quietSpace");
        expect(result).toHaveProperty("firstTimeFlow");
        expect(typeof result.confidence).toBe("number");
        expect(result.updatedAt).toBeNull();
    });

    test("returns low confidence and Not confirmed yet for empty church data", async () => {
        __mockDoc.__data = {};
        __mockDoc.get.mockResolvedValue({ data: () => {}, exists: true, ref: __mockDoc });
        const result = await handler(authedRequest("church-empty")) as Record<string, unknown>;
        expect(result.parking).toBe("Not confirmed yet");
        expect(result.worshipStyle).toBe("Not confirmed yet");
        expect(result.confidence as number).toBeLessThan(0.25);
    });

    test("uses denomination as worshipStyle when available", async () => {
        const result = await handler(authedRequest("church-123")) as Record<string, unknown>;
        expect(result.worshipStyle).toBe("Baptist");
    });
});

// ── calculateChurchFitScore ───────────────────────────────────────────────────

describe("calculateChurchFitScore", () => {
    const handler = calculateChurchFitScore as unknown as Handler;

    test("throws unauthenticated when no auth", async () => {
        await expect(handler(anonRequest({ churchId: "c" }))).rejects.toMatchObject({ code: "unauthenticated" });
    });

    test("returns score=0 and low confidence when user has no savedChurches", async () => {
        const result = await handler(authedRequest("church-123")) as Record<string, unknown>;
        expect(result.score).toBe(0);
        expect(result.confidence as number).toBeLessThan(0.2);
        expect(result.disclaimers).toContain("Preference alignment only.");
        expect(result.disclaimers).toContain("Not a rating of spiritual quality.");
        expect(result.updatedAt).toBeNull();
    });

    test("never sets score > 100", async () => {
        const result = await handler(authedRequest("church-123")) as Record<string, unknown>;
        expect(result.score as number).toBeLessThanOrEqual(100);
    });
});

// ── resolveChurchSmartAction ──────────────────────────────────────────────────

describe("resolveChurchSmartAction", () => {
    const handler = resolveChurchSmartAction as unknown as Handler;

    const SMART_ACTIONS = ["joinLive", "checkIn", "planVisit", "askBerean", "saveChurch"];

    test("throws unauthenticated when no auth", async () => {
        await expect(handler(anonRequest({ churchId: "c" }))).rejects.toMatchObject({ code: "unauthenticated" });
    });

    test("returns a valid primaryAction", async () => {
        // Subcollection live_state/current and church_fit reads return empty docs.
        __mockDoc.get.mockResolvedValue({ data: () => __mockDoc.__data, exists: true, ref: __mockDoc });
        const result = await handler(authedRequest("church-123")) as Record<string, unknown>;
        expect(SMART_ACTIONS).toContain(result.primaryAction);
        expect(result.secondaryActions).toBeInstanceOf(Array);
        expect(typeof result.reason).toBe("string");
        expect(result.updatedAt).toBeNull();
    });

    test("ignores negative distanceMiles and does not trigger checkIn", async () => {
        const result = await handler(authedRequest("church-123", { distanceMiles: -5 })) as Record<string, unknown>;
        // With distanceMiles clamped to null (out of range), checkIn should not fire
        // unless the mock live state also triggers joinLive or upcoming.
        expect(SMART_ACTIONS).toContain(result.primaryAction);
        expect(result.primaryAction).not.toBe("checkIn");
    });

    test("ignores distanceMiles > 500", async () => {
        const result = await handler(authedRequest("church-123", { distanceMiles: 9999 })) as Record<string, unknown>;
        expect(result.primaryAction).not.toBe("checkIn");
    });

    test("accepts valid distanceMiles in range", async () => {
        // distanceMiles = 5 should be accepted and may trigger checkIn if no live signal.
        const result = await handler(authedRequest("church-123", { distanceMiles: 5 })) as Record<string, unknown>;
        expect(SMART_ACTIONS).toContain(result.primaryAction);
    });

    test("defaults to askBerean or saveChurch when no data", async () => {
        __mockDoc.__data = {};
        __mockDoc.get.mockResolvedValue({ data: () => {}, exists: true, ref: __mockDoc });
        const result = await handler(authedRequest("church-empty")) as Record<string, unknown>;
        expect(["askBerean", "saveChurch"]).toContain(result.primaryAction);
    });
});

// ── generateBereanChurchSuggestions ──────────────────────────────────────────

describe("generateBereanChurchSuggestions", () => {
    const handler = generateBereanChurchSuggestions as unknown as Handler;

    const VALID_INTENTS = [
        "nearby", "liveNow", "deeperTeaching", "youngAdults", "kidsMinistry",
        "prayer", "accessibility", "translation", "quietSpace", "saved",
        "upcomingService", "askBerean",
    ];

    test("returns suggestions array with fallback message", async () => {
        __mockDoc.get.mockResolvedValue({ data: () => null, exists: false, ref: __mockDoc });
        const result = await handler(anonRequest()) as Record<string, unknown>;
        expect(result.suggestions).toBeInstanceOf(Array);
        expect((result.suggestions as unknown[]).length).toBeGreaterThan(0);
        expect(typeof result.fallback).toBe("string");
    });

    test("each suggestion has required fields", async () => {
        const result = await handler(authedRequest()) as { suggestions: Record<string, unknown>[] };
        for (const s of result.suggestions) {
            expect(typeof s.id).toBe("string");
            expect(typeof s.title).toBe("string");
            expect(typeof s.iconName).toBe("string");
            expect(VALID_INTENTS).toContain(s.intent);
            expect(typeof s.confidence).toBe("number");
            expect(s.confidence as number).toBeGreaterThan(0);
            expect(s.confidence as number).toBeLessThanOrEqual(1);
        }
    });

    test("works for anonymous (unauthenticated) callers", async () => {
        const result = await handler(anonRequest()) as Record<string, unknown>;
        expect(result.suggestions).toBeDefined();
    });

    test("fallback message is not a fabricated church claim", async () => {
        const result = await handler(anonRequest()) as Record<string, unknown>;
        const fallback = result.fallback as string;
        // Should not contain church names or specific service claim language
        expect(fallback).not.toMatch(/\d{1,2}:\d{2}/);  // no times like "10:30"
    });
});
