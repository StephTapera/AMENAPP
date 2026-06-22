import {
    scorePriorityItem,
    summarizeSilentReactions,
    updatePresenceState,
    addSilentReaction,
    getSilentReactionSummary,
    checkComposeIntent,
    getSpiritualPriorityInbox,
    evaluateThreadLifecycle,
    getContextualMemoryLayer,
    summonThreads,
} from "./spiritualSystems";

// eslint-disable-next-line @typescript-eslint/no-require-imports
const admin = require("firebase-admin");

// Helpers to build Firestore snapshot shapes the callables expect.
function docSnapshot(data: Record<string, unknown> | null) {
    return Promise.resolve({
        exists: !!data,
        data: () => (data ?? undefined),
        get: (field: string) => (data as Record<string, unknown> | null)?.[field],
    });
}

function querySnapshot(docs: Array<Record<string, unknown>>) {
    return Promise.resolve({
        empty: docs.length === 0,
        docs: docs.map((d) => ({
            id: `doc-${Math.random()}`,
            exists: true,
            data: () => d,
            get: (field: string) => d[field],
        })),
    });
}

// Minimal callable context helpers.
type CallContext = { auth: { uid: string } | null; app: object | undefined };
const authed = (uid = "uid-alice"): CallContext => ({ auth: { uid }, app: {} });
const unauthed = (): CallContext => ({ auth: null, app: {} });
const noAppCheck = (uid = "uid-alice"): CallContext => ({ auth: { uid }, app: undefined });

// Type-erased callable invoker (mock makes onCall a passthrough).
function call<T>(callable: unknown, data: unknown, ctx: CallContext): Promise<T> {
    return (callable as (request: { data: unknown; auth: CallContext["auth"]; app: CallContext["app"] }) => Promise<T>)({
        data,
        auth: ctx.auth,
        app: ctx.app,
    });
}

describe("spiritualSystems", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        // Default: no doc found, no query results.
        admin.__mockDoc.get = jest.fn(() => docSnapshot(null));
        admin.__mockDoc.set = jest.fn(() => Promise.resolve());
        admin.__mockQuery.get = jest.fn(() => querySnapshot([]));
    });

    // ── Pure functions ──────────────────────────────────────────────────────────

    describe("scorePriorityItem", () => {
        test("weighted score favors urgency over recency", () => {
            const highUrgency = scorePriorityItem({
                urgencyScore: 1, relationshipScore: 0, depthScore: 0,
                followUpNeedScore: 0, scriptureRelevanceScore: 0, recencyScore: 0,
            });
            const highRecency = scorePriorityItem({
                urgencyScore: 0, relationshipScore: 0, depthScore: 0,
                followUpNeedScore: 0, scriptureRelevanceScore: 0, recencyScore: 1,
            });
            expect(highUrgency).toBeGreaterThan(highRecency);
        });

        test("full score is a valid bounded float", () => {
            const score = scorePriorityItem({
                urgencyScore: 1, relationshipScore: 0.8, depthScore: 0.9,
                followUpNeedScore: 0.7, scriptureRelevanceScore: 0.6, recencyScore: 0.5,
            });
            expect(score).toBeGreaterThan(0.75);
            expect(score).toBeLessThanOrEqual(1);
        });

        test("all-zero scores produce zero", () => {
            const score = scorePriorityItem({
                urgencyScore: 0, relationshipScore: 0, depthScore: 0,
                followUpNeedScore: 0, scriptureRelevanceScore: 0, recencyScore: 0,
            });
            expect(score).toBe(0);
        });
    });

    describe("summarizeSilentReactions", () => {
        test("never exposes identities or raw counts", () => {
            const summary = summarizeSilentReactions(["prayed", "encouraged", "prayed"]);
            expect(summary.summaryText).toContain("Someone prayed with this");
            expect(summary.summaryText).toContain("Someone found this encouraging");
            expect(summary.summaryText).not.toMatch(/\d+/);
            expect(summary.summaryText).not.toContain("@");
        });

        test("deduplicates reaction types in returned array", () => {
            const summary = summarizeSilentReactions(["prayed", "prayed", "prayed"]);
            expect(summary.reactionTypes).toEqual(["prayed"]);
        });

        test("returns empty for empty input", () => {
            const summary = summarizeSilentReactions([]);
            expect(summary.summaryText).toBe("");
            expect(summary.reactionTypes).toEqual([]);
        });

        test("unknown reaction type produces no summary phrase", () => {
            const summary = summarizeSilentReactions(["unknown_type"]);
            expect(summary.summaryText).toBe("");
        });

        test("all five canonical types produce summary phrases", () => {
            const all = ["prayed", "encouraged", "reflected", "grateful", "stoodWithYou"];
            const summary = summarizeSilentReactions(all);
            expect(summary.summaryText).toContain("Someone prayed with this");
            expect(summary.summaryText).toContain("Someone found this encouraging");
            expect(summary.summaryText).toContain("This helped someone reflect");
            expect(summary.summaryText).toContain("Someone felt grateful for this");
            expect(summary.summaryText).toContain("Someone quietly stood with you");
        });
    });

    // ── Auth guards ─────────────────────────────────────────────────────────────

    describe("auth guards — all callables reject unauthenticated callers", () => {
        const cases: Array<[string, unknown, unknown]> = [
            ["updatePresenceState", updatePresenceState, { selectedState: "praying", visibility: "everyone" }],
            ["addSilentReaction", addSilentReaction, { sourceId: "p1", sourceType: "post", reactionType: "prayed" }],
            ["getSilentReactionSummary", getSilentReactionSummary, { sourceId: "p1", sourceType: "post" }],
            ["checkComposeIntent", checkComposeIntent, { text: "hello", sourceSurface: "feed" }],
            ["getSpiritualPriorityInbox", getSpiritualPriorityInbox, {}],
            ["evaluateThreadLifecycle", evaluateThreadLifecycle, { threadId: "t1" }],
            ["getContextualMemoryLayer", getContextualMemoryLayer, { sourceId: "p1" }],
            ["summonThreads", summonThreads, { query: "prayer" }],
        ];

        for (const [name, callable, data] of cases) {
            test(`${name} throws unauthenticated`, async () => {
                await expect(call(callable, data, unauthed()))
                    .rejects.toMatchObject({ code: "unauthenticated" });
            });
        }
    });

    describe("App Check guards — all callables reject missing app token", () => {
        const cases: Array<[string, unknown, unknown]> = [
            ["updatePresenceState", updatePresenceState, { selectedState: "praying", visibility: "everyone" }],
            ["addSilentReaction", addSilentReaction, { sourceId: "p1", sourceType: "post", reactionType: "prayed" }],
            ["getSilentReactionSummary", getSilentReactionSummary, { sourceId: "p1", sourceType: "post" }],
            ["checkComposeIntent", checkComposeIntent, { text: "hello", sourceSurface: "feed" }],
            ["getSpiritualPriorityInbox", getSpiritualPriorityInbox, {}],
            ["evaluateThreadLifecycle", evaluateThreadLifecycle, { threadId: "t1" }],
            ["getContextualMemoryLayer", getContextualMemoryLayer, { sourceId: "p1" }],
            ["summonThreads", summonThreads, { query: "prayer" }],
        ];

        for (const [name, callable, data] of cases) {
            test(`${name} throws failed-precondition`, async () => {
                await expect(call(callable, data, noAppCheck()))
                    .rejects.toMatchObject({ code: "failed-precondition" });
            });
        }
    });

    // ── updatePresenceState ─────────────────────────────────────────────────────

    describe("updatePresenceState — visibility enforcement", () => {
        test("rejects mutuals visibility (no server-side enforcement)", async () => {
            await expect(
                call(updatePresenceState, { selectedState: "praying", visibility: "mutuals" }, authed())
            ).rejects.toMatchObject({ code: "invalid-argument" });
        });

        test("rejects unknown visibility value", async () => {
            await expect(
                call(updatePresenceState, { selectedState: "praying", visibility: "friends" }, authed())
            ).rejects.toMatchObject({ code: "invalid-argument" });
        });

        test("rejects invalid presence state", async () => {
            await expect(
                call(updatePresenceState, { selectedState: "scrolling", visibility: "everyone" }, authed())
            ).rejects.toMatchObject({ code: "invalid-argument" });
        });

        test("accepts all six valid states with private_only", async () => {
            const states = ["reflecting", "praying", "reading", "resting", "seeking", "available"];
            for (const selectedState of states) {
                const result = await call<{ ok: boolean }>(
                    updatePresenceState, { selectedState, visibility: "private_only" }, authed()
                );
                expect(result.ok).toBe(true);
            }
        });

        test("accepts valid state with everyone", async () => {
            const result = await call<{ ok: boolean }>(
                updatePresenceState, { selectedState: "reflecting", visibility: "everyone" }, authed()
            );
            expect(result.ok).toBe(true);
        });
    });

    // ── addSilentReaction ───────────────────────────────────────────────────────

    describe("addSilentReaction — access control + validation", () => {
        test("rejects invalid reaction type", async () => {
            await expect(
                call(addSilentReaction, { sourceId: "p1", sourceType: "post", reactionType: "like" }, authed())
            ).rejects.toMatchObject({ code: "invalid-argument" });
        });

        test("rejects unsupported source type", async () => {
            await expect(
                call(addSilentReaction, { sourceId: "p1", sourceType: "thread", reactionType: "prayed" }, authed())
            ).rejects.toMatchObject({ code: "invalid-argument" });
        });

        test("rejects empty sourceId", async () => {
            await expect(
                call(addSilentReaction, { sourceId: "", sourceType: "post", reactionType: "prayed" }, authed())
            ).rejects.toMatchObject({ code: "invalid-argument" });
        });

        test("throws not-found when post does not exist", async () => {
            admin.__mockDoc.get = jest.fn(() => docSnapshot(null));
            await expect(
                call(addSilentReaction, { sourceId: "ghost", sourceType: "post", reactionType: "prayed" }, authed())
            ).rejects.toMatchObject({ code: "not-found" });
        });

        test("rejects self-reaction on own post", async () => {
            admin.__mockDoc.get = jest.fn(() => docSnapshot({ authorId: "uid-alice", visibility: "everyone" }));
            await expect(
                call(addSilentReaction, { sourceId: "p1", sourceType: "post", reactionType: "prayed" }, authed("uid-alice"))
            ).rejects.toMatchObject({ code: "permission-denied" });
        });

        test("allows reaction on another user's post", async () => {
            admin.__mockDoc.get = jest.fn(() => docSnapshot({ authorId: "uid-bob", visibility: "everyone" }));
            const result = await call<{ ok: boolean; reactionId: string }>(
                addSilentReaction, { sourceId: "p1", sourceType: "post", reactionType: "prayed" }, authed("uid-alice")
            );
            expect(result.ok).toBe(true);
            expect(result.reactionId).toBeTruthy();
        });

        test("all five canonical reaction types are accepted", async () => {
            admin.__mockDoc.get = jest.fn(() => docSnapshot({ authorId: "uid-bob", visibility: "everyone" }));
            const reactions = ["prayed", "encouraged", "reflected", "grateful", "stoodWithYou"];
            for (const reactionType of reactions) {
                const result = await call<{ ok: boolean }>(
                    addSilentReaction, { sourceId: "p1", sourceType: "post", reactionType }, authed("uid-alice")
                );
                expect(result.ok).toBe(true);
            }
        });

        test("reactionId encodes uid + sourceType + sourceId + reactionType", async () => {
            admin.__mockDoc.get = jest.fn(() => docSnapshot({ authorId: "uid-bob", visibility: "everyone" }));
            const result = await call<{ reactionId: string }>(
                addSilentReaction, { sourceId: "post-99", sourceType: "post", reactionType: "prayed" }, authed("uid-alice")
            );
            expect(result.reactionId).toBe("uid-alice_post_post-99_prayed");
        });
    });

    // ── getSilentReactionSummary ────────────────────────────────────────────────

    describe("getSilentReactionSummary — author-only access", () => {
        test("returns empty for comment sourceType — never exposes reaction data for non-post types", async () => {
            const result = await call<{ summaryText: string; reactionTypes: string[] }>(
                getSilentReactionSummary, { sourceId: "c1", sourceType: "comment" }, authed()
            );
            expect(result.summaryText).toBe("");
            expect(result.reactionTypes).toEqual([]);
        });

        test("throws permission-denied for non-author on a post", async () => {
            admin.__mockDoc.get = jest.fn(() => docSnapshot({ authorId: "uid-bob", visibility: "everyone" }));
            await expect(
                call(getSilentReactionSummary, { sourceId: "p1", sourceType: "post" }, authed("uid-alice"))
            ).rejects.toMatchObject({ code: "permission-denied" });
        });

        test("throws not-found when post does not exist", async () => {
            admin.__mockDoc.get = jest.fn(() => docSnapshot(null));
            await expect(
                call(getSilentReactionSummary, { sourceId: "ghost", sourceType: "post" }, authed())
            ).rejects.toMatchObject({ code: "not-found" });
        });

        test("throws invalid-argument when sourceId is empty", async () => {
            await expect(
                call(getSilentReactionSummary, { sourceId: "", sourceType: "post" }, authed())
            ).rejects.toMatchObject({ code: "invalid-argument" });
        });

        test("returns qualitative summary for post author with reactions", async () => {
            admin.__mockDoc.get = jest.fn(() => docSnapshot({ authorId: "uid-alice", visibility: "everyone" }));
            admin.__mockQuery.get = jest.fn(() => querySnapshot([
                { reactionType: "prayed" },
                { reactionType: "encouraged" },
            ]));
            const result = await call<{ summaryText: string }>(
                getSilentReactionSummary, { sourceId: "p1", sourceType: "post" }, authed("uid-alice")
            );
            expect(result.summaryText).toContain("Someone prayed with this");
            expect(result.summaryText).not.toMatch(/\d+/);
        });

        test("returns empty text for author post with no reactions", async () => {
            admin.__mockDoc.get = jest.fn(() => docSnapshot({ authorId: "uid-alice", visibility: "everyone" }));
            admin.__mockQuery.get = jest.fn(() => querySnapshot([]));
            const result = await call<{ summaryText: string }>(
                getSilentReactionSummary, { sourceId: "p1", sourceType: "post" }, authed("uid-alice")
            );
            expect(result.summaryText).toBe("");
        });
    });

    // ── checkComposeIntent ──────────────────────────────────────────────────────

    describe("checkComposeIntent — tone and intent analysis", () => {
        test("requires both text and sourceSurface", async () => {
            await expect(
                call(checkComposeIntent, { text: "", sourceSurface: "feed" }, authed())
            ).rejects.toMatchObject({ code: "invalid-argument" });
            await expect(
                call(checkComposeIntent, { text: "hello", sourceSurface: "" }, authed())
            ).rejects.toMatchObject({ code: "invalid-argument" });
        });

        test("detects prayer intent", async () => {
            const result = await call<{ intentType: string; toneRisk: string }>(
                checkComposeIntent, { text: "Please pray for me this week.", sourceSurface: "feed" }, authed()
            );
            expect(result.intentType).toBe("prayer");
            expect(result.toneRisk).toBe("green");
        });

        test("detects testimony intent", async () => {
            const result = await call<{ intentType: string }>(
                checkComposeIntent, { text: "I have a testimony — God brought me through.", sourceSurface: "feed" }, authed()
            );
            expect(result.intentType).toBe("testimony");
        });

        test("flags shame language as amber tone risk with rewrite available", async () => {
            const result = await call<{ toneRisk: string; rewriteAvailable: boolean }>(
                checkComposeIntent, { text: "You should be ashamed of yourself.", sourceSurface: "feed" }, authed()
            );
            expect(result.toneRisk).toBe("amber");
            expect(result.rewriteAvailable).toBe(true);
        });

        test("flags coercive spiritual language as amber", async () => {
            const result = await call<{ toneRisk: string }>(
                checkComposeIntent, { text: "If you loved God you would agree with me.", sourceSurface: "feed" }, authed()
            );
            expect(result.toneRisk).toBe("amber");
        });

        test("benign prayer text is green", async () => {
            const result = await call<{ toneRisk: string; rewriteAvailable: boolean }>(
                checkComposeIntent, { text: "God is so good, all the time!", sourceSurface: "feed" }, authed()
            );
            expect(result.toneRisk).toBe("green");
            expect(result.rewriteAvailable).toBe(false);
        });
    });

    // ── getSpiritualPriorityInbox ───────────────────────────────────────────────

    describe("getSpiritualPriorityInbox — computes from real posts", () => {
        test("returns empty items when user has no posts", async () => {
            admin.__mockQuery.get = jest.fn(() => querySnapshot([]));
            const result = await call<{ items: unknown[] }>(getSpiritualPriorityInbox, {}, authed());
            expect(result.items).toEqual([]);
        });

        test("includes unanswered prayer posts", async () => {
            admin.__mockQuery.get = jest.fn()
                .mockResolvedValueOnce(querySnapshot([
                    { authorId: "uid-alice", category: "prayer", content: "Pray for my family", prayerStatus: null },
                ]))
                .mockResolvedValueOnce(querySnapshot([]));
            const result = await call<{ items: Array<{ reasonChips: string[] }> }>(
                getSpiritualPriorityInbox, {}, authed("uid-alice")
            );
            expect(result.items.length).toBeGreaterThan(0);
            expect(result.items[0].reasonChips).toContain("Prayer follow-up");
        });

        test("excludes answered prayer posts", async () => {
            admin.__mockQuery.get = jest.fn()
                .mockResolvedValueOnce(querySnapshot([
                    { authorId: "uid-alice", category: "prayer", content: "Answered", prayerStatus: "answered" },
                ]))
                .mockResolvedValueOnce(querySnapshot([]));
            const result = await call<{ items: unknown[] }>(getSpiritualPriorityInbox, {}, authed("uid-alice"));
            expect(result.items).toEqual([]);
        });
    });

    // ── evaluateThreadLifecycle ─────────────────────────────────────────────────

    describe("evaluateThreadLifecycle — access control + lifecycle states", () => {
        test("throws invalid-argument when threadId is missing", async () => {
            await expect(
                call(evaluateThreadLifecycle, { threadId: "" }, authed())
            ).rejects.toMatchObject({ code: "invalid-argument" });
        });

        test("throws not-found for nonexistent thread", async () => {
            admin.__mockQuery.get = jest.fn(() => querySnapshot([]));
            await expect(
                call(evaluateThreadLifecycle, { threadId: "ghost-thread" }, authed())
            ).rejects.toMatchObject({ code: "not-found" });
        });

        test("throws permission-denied when thread belongs to another user", async () => {
            admin.__mockQuery.get = jest.fn(() => querySnapshot([
                { authorId: "uid-bob", category: "post", content: "Another user's post" },
            ]));
            await expect(
                call(evaluateThreadLifecycle, { threadId: "t1" }, authed("uid-alice"))
            ).rejects.toMatchObject({ code: "permission-denied" });
        });

        test("returns answered lifecycle for answered prayer", async () => {
            admin.__mockQuery.get = jest.fn(() => querySnapshot([
                { authorId: "uid-alice", category: "prayer", prayerStatus: "answered", content: "God answered!" },
            ]));
            const result = await call<{ lifecycleState: string }>(
                evaluateThreadLifecycle, { threadId: "t1" }, authed("uid-alice")
            );
            expect(result.lifecycleState).toBe("answered");
        });

        test("returns followUpNeeded for unanswered prayer", async () => {
            admin.__mockQuery.get = jest.fn(() => querySnapshot([
                { authorId: "uid-alice", category: "prayer", content: "Please pray for my family" },
            ]));
            const result = await call<{ lifecycleState: string }>(
                evaluateThreadLifecycle, { threadId: "t1" }, authed("uid-alice")
            );
            expect(result.lifecycleState).toBe("followUpNeeded");
        });

        test("returns threadId and postCount in response", async () => {
            admin.__mockQuery.get = jest.fn(() => querySnapshot([
                { authorId: "uid-alice", category: "prayer", prayerStatus: "answered" },
                { authorId: "uid-alice", category: "prayer" },
            ]));
            const result = await call<{ threadId: string; postCount: number }>(
                evaluateThreadLifecycle, { threadId: "thread-xyz" }, authed("uid-alice")
            );
            expect(result.threadId).toBe("thread-xyz");
            expect(result.postCount).toBe(2);
        });
    });

    // ── getContextualMemoryLayer ────────────────────────────────────────────────

    describe("getContextualMemoryLayer — access control + post-based computation", () => {
        test("throws invalid-argument when sourceId is missing", async () => {
            await expect(
                call(getContextualMemoryLayer, { sourceId: "" }, authed())
            ).rejects.toMatchObject({ code: "invalid-argument" });
        });

        test("throws not-found for nonexistent post", async () => {
            admin.__mockDoc.get = jest.fn(() => docSnapshot(null));
            await expect(
                call(getContextualMemoryLayer, { sourceId: "ghost" }, authed())
            ).rejects.toMatchObject({ code: "not-found" });
        });

        test("throws permission-denied for private post belonging to another user", async () => {
            admin.__mockDoc.get = jest.fn(() => docSnapshot({
                authorId: "uid-bob", visibility: "private_only", content: "Private",
            }));
            await expect(
                call(getContextualMemoryLayer, { sourceId: "p1" }, authed("uid-alice"))
            ).rejects.toMatchObject({ code: "permission-denied" });
        });

        test("returns scripture refs extracted from post verseReference", async () => {
            admin.__mockDoc.get = jest.fn(() => docSnapshot({
                authorId: "uid-bob", visibility: "everyone", verseReference: "Romans 8:28", content: "Verse post",
            }));
            admin.__mockQuery.get = jest.fn(() => querySnapshot([]));
            const result = await call<{ scriptureRefs: string[] }>(
                getContextualMemoryLayer, { sourceId: "p1" }, authed("uid-alice")
            );
            expect(result.scriptureRefs).toEqual(["Romans 8:28"]);
        });

        test("author can access their own private post", async () => {
            admin.__mockDoc.get = jest.fn(() => docSnapshot({
                authorId: "uid-alice", visibility: "private_only", content: "Private post",
            }));
            admin.__mockQuery.get = jest.fn(() => querySnapshot([]));
            const result = await call<{ scriptureRefs: string[] }>(
                getContextualMemoryLayer, { sourceId: "p1" }, authed("uid-alice")
            );
            expect(result).toBeDefined();
        });

        test("response always includes all required fields", async () => {
            admin.__mockDoc.get = jest.fn(() => docSnapshot({
                authorId: "uid-alice", visibility: "everyone", content: "Post",
            }));
            admin.__mockQuery.get = jest.fn(() => querySnapshot([]));
            const result = await call<{
                scriptureRefs: unknown; relatedPostIds: unknown; relatedPrayerIds: unknown;
                savedNoteIds: unknown; bereanInsightIds: unknown;
            }>(getContextualMemoryLayer, { sourceId: "p1" }, authed("uid-alice"));
            expect(Array.isArray(result.scriptureRefs)).toBe(true);
            expect(Array.isArray(result.relatedPostIds)).toBe(true);
            expect(Array.isArray(result.relatedPrayerIds)).toBe(true);
            expect(Array.isArray(result.savedNoteIds)).toBe(true);
            expect(Array.isArray(result.bereanInsightIds)).toBe(true);
        });
    });

    // ── summonThreads ───────────────────────────────────────────────────────────

    describe("summonThreads — caller-scoped search", () => {
        test("throws invalid-argument when query is empty", async () => {
            await expect(
                call(summonThreads, { query: "" }, authed())
            ).rejects.toMatchObject({ code: "invalid-argument" });
        });

        test("returns empty results when no posts match", async () => {
            admin.__mockQuery.get = jest.fn(() => querySnapshot([]));
            const result = await call<{ results: unknown[] }>(
                summonThreads, { query: "prayer" }, authed()
            );
            expect(result.results).toEqual([]);
        });

        test("matches posts by content tokens", async () => {
            admin.__mockQuery.get = jest.fn(() => querySnapshot([
                { authorId: "uid-alice", category: "prayer", content: "Please pray for my family this week" },
            ]));
            const result = await call<{ results: Array<{ reason: string; sourceType: string }> }>(
                summonThreads, { query: "prayer family" }, authed("uid-alice")
            );
            expect(result.results.length).toBeGreaterThan(0);
            expect(result.results[0].reason).toBeTruthy();
            expect(result.results[0].sourceType).toBe("post");
        });

        test("short tokens (2 chars or fewer) are not used for matching", async () => {
            admin.__mockQuery.get = jest.fn(() => querySnapshot([
                { authorId: "uid-alice", category: "post", content: "Just a regular post" },
            ]));
            // All query tokens are <=2 chars — should produce zero matches.
            const result = await call<{ results: unknown[] }>(
                summonThreads, { query: "do it ok" }, authed("uid-alice")
            );
            expect(result.results).toEqual([]);
        });

        test("results capped at 20", async () => {
            const docs = Array.from({ length: 25 }, (_, i) => ({
                authorId: "uid-alice", category: "prayer", content: `Pray for item ${i}`,
            }));
            admin.__mockQuery.get = jest.fn(() => querySnapshot(docs));
            const result = await call<{ results: unknown[] }>(
                summonThreads, { query: "pray item" }, authed("uid-alice")
            );
            expect(result.results.length).toBeLessThanOrEqual(20);
        });
    });
});
