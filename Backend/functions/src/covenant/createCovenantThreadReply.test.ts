import { createCovenantThreadReply } from "./createCovenantThreadReply";
import admin from "firebase-admin";

// Reach into the shared mock objects exported by __mocks__/firebase-admin.js
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const mockAdmin = admin as any;
const mockQuery: jest.Mocked<{
    get: jest.Mock;
    where: jest.Mock;
    limit: jest.Mock;
    orderBy: jest.Mock;
}> = mockAdmin.__mockQuery;
const mockDoc: jest.Mocked<{
    get: jest.Mock;
    set: jest.Mock;
    update: jest.Mock;
    collection: jest.Mock;
    id: string;
    __data: unknown;
}> = mockAdmin.__mockDoc;
const mockBatch: jest.Mocked<{
    set: jest.Mock;
    update: jest.Mock;
    commit: jest.Mock;
}> = mockAdmin.__mockBatch;

// ── Helpers ──────────────────────────────────────────────────────────────────

function makeRequest(dataOverrides: Record<string, unknown> = {}) {
    return {
        auth: { uid: "uid-alice" },
        data: {
            covenantId: "cov-1",
            roomId: "room-1",
            parentMessageId: "msg-1",
            body: "Great point — that connects to Romans 5.",
            ...dataOverrides,
        },
    };
}

// Sets up mock call sequence for the three async reads that precede the batch:
//   1. covenantMemberships query  → non-empty (active member)
//   2. parentRef.get()            → exists, not deleted, not locked
//   3. users/{uid}.get()          → display name + avatar
function setupHappyPath(
    parentOverrides: Record<string, unknown> = {},
    userOverrides: Record<string, unknown> = {},
) {
    mockQuery.get.mockResolvedValueOnce({ docs: [{ data: () => ({}) }], empty: false });
    mockDoc.get
        .mockResolvedValueOnce({
            data: () => ({ isDeleted: false, threadLocked: false, ...parentOverrides }),
            exists: true,
        })
        .mockResolvedValueOnce({
            data: () => ({ displayName: "Alice", avatarURL: null, ...userOverrides }),
            exists: true,
        });
}

// ── Setup ─────────────────────────────────────────────────────────────────────

beforeAll(() => {
    // The base mock does not include FieldValue.increment; add it so batch.update
    // calls using increment(1) don't throw during tests.
    (admin.firestore.FieldValue as unknown as Record<string, unknown>).increment =
        jest.fn((n: number) => ({ _type: "increment", n }));
});

beforeEach(() => {
    jest.clearAllMocks();
    mockDoc.__data = undefined;
    // Re-mock default mockDoc.get to return "doc does not exist" baseline
    mockDoc.get.mockResolvedValue({ data: () => null, exists: false });
    mockQuery.get.mockResolvedValue({ docs: [], empty: true });
    mockBatch.commit.mockResolvedValue(undefined);
    mockBatch.set.mockClear();
    mockBatch.update.mockClear();
});

// ── Tests ─────────────────────────────────────────────────────────────────────

describe("createCovenantThreadReply", () => {

    // ── Auth ──────────────────────────────────────────────────────────────────

    test("rejects unauthenticated requests", async () => {
        await expect(
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            (createCovenantThreadReply as any)({ auth: null, data: {} })
        ).rejects.toMatchObject({ code: "unauthenticated" });
    });

    // ── Input validation ──────────────────────────────────────────────────────

    test("rejects when covenantId is missing", async () => {
        await expect(
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            (createCovenantThreadReply as any)(
                makeRequest({ covenantId: "" })
            )
        ).rejects.toMatchObject({ code: "invalid-argument" });
    });

    test("rejects when parentMessageId is missing", async () => {
        await expect(
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            (createCovenantThreadReply as any)(
                makeRequest({ parentMessageId: undefined })
            )
        ).rejects.toMatchObject({ code: "invalid-argument" });
    });

    test("rejects whitespace-only body", async () => {
        await expect(
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            (createCovenantThreadReply as any)(
                makeRequest({ body: "   " })
            )
        ).rejects.toMatchObject({ code: "invalid-argument" });
    });

    test("rejects body exceeding 4000 characters", async () => {
        await expect(
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            (createCovenantThreadReply as any)(
                makeRequest({ body: "x".repeat(4001) })
            )
        ).rejects.toMatchObject({ code: "invalid-argument" });
    });

    test("rejects body of exactly 4001 characters", async () => {
        await expect(
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            (createCovenantThreadReply as any)(
                makeRequest({ body: "a".repeat(4001) })
            )
        ).rejects.toMatchObject({ code: "invalid-argument" });
    });

    test("rejects mentions array with more than 5 entries", async () => {
        await expect(
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            (createCovenantThreadReply as any)(
                makeRequest({ mentions: ["u1", "u2", "u3", "u4", "u5", "u6"] })
            )
        ).rejects.toMatchObject({ code: "invalid-argument" });
    });

    // ── Membership ────────────────────────────────────────────────────────────

    test("rejects when caller is not an active member", async () => {
        mockQuery.get.mockResolvedValueOnce({ docs: [], empty: true });
        await expect(
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            (createCovenantThreadReply as any)(makeRequest())
        ).rejects.toMatchObject({ code: "permission-denied" });
    });

    // ── Parent message ────────────────────────────────────────────────────────

    test("rejects when parent message does not exist", async () => {
        mockQuery.get.mockResolvedValueOnce({ docs: [{}], empty: false });
        mockDoc.get.mockResolvedValueOnce({ data: () => null, exists: false });
        await expect(
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            (createCovenantThreadReply as any)(makeRequest())
        ).rejects.toMatchObject({ code: "not-found" });
    });

    test("rejects when parent message isDeleted is true", async () => {
        mockQuery.get.mockResolvedValueOnce({ docs: [{}], empty: false });
        mockDoc.get.mockResolvedValueOnce({ data: () => ({ isDeleted: true }), exists: true });
        await expect(
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            (createCovenantThreadReply as any)(makeRequest())
        ).rejects.toMatchObject({ code: "failed-precondition" });
    });

    test("rejects when parent message deleted field is true", async () => {
        mockQuery.get.mockResolvedValueOnce({ docs: [{}], empty: false });
        mockDoc.get.mockResolvedValueOnce({ data: () => ({ deleted: true }), exists: true });
        await expect(
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            (createCovenantThreadReply as any)(makeRequest())
        ).rejects.toMatchObject({ code: "failed-precondition" });
    });

    test("rejects when thread is locked", async () => {
        mockQuery.get.mockResolvedValueOnce({ docs: [{}], empty: false });
        mockDoc.get.mockResolvedValueOnce({
            data: () => ({ isDeleted: false, threadLocked: true }),
            exists: true,
        });
        await expect(
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            (createCovenantThreadReply as any)(makeRequest())
        ).rejects.toMatchObject({ code: "failed-precondition" });
    });

    // ── Success path ──────────────────────────────────────────────────────────

    test("returns { ok: true, replyId } on success", async () => {
        setupHappyPath();
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const result = await (createCovenantThreadReply as any)(makeRequest()) as {
            ok: boolean;
            replyId: string;
        };
        expect(result.ok).toBe(true);
        expect(typeof result.replyId).toBe("string");
        expect(result.replyId.length).toBeGreaterThan(0);
    });

    test("commits exactly one batch with one set and one update", async () => {
        setupHappyPath();
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        await (createCovenantThreadReply as any)(makeRequest());
        expect(mockBatch.set).toHaveBeenCalledTimes(1);
        expect(mockBatch.update).toHaveBeenCalledTimes(1);
        expect(mockBatch.commit).toHaveBeenCalledTimes(1);
    });

    test("reply document contains all required fields", async () => {
        setupHappyPath();
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        await (createCovenantThreadReply as any)(makeRequest());

        // batch.set(replyRef, data) — second argument is the document data
        const replyData = mockBatch.set.mock.calls[0][1] as Record<string, unknown>;
        expect(replyData).toMatchObject({
            covenantId: "cov-1",
            roomId: "room-1",
            parentMessageId: "msg-1",
            authorId: "uid-alice",
            authorDisplayName: "Alice",
            body: "Great point — that connects to Romans 5.",
            mentions: [],
            isMarkedAnswer: false,
            moderationStatus: "clean",
            deleted: false,
            hidden: false,
            replyDepth: 1,
        });
        expect(replyData.createdAt).toBeDefined();
        expect(replyData.updatedAt).toBeDefined();
    });

    test("parent aggregate update includes replyCount increment, lastReplyAt, updatedAt", async () => {
        setupHappyPath();
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        await (createCovenantThreadReply as any)(makeRequest());

        // batch.update(parentRef, data) — second argument is the update payload
        const updateData = mockBatch.update.mock.calls[0][1] as Record<string, unknown>;
        expect(updateData.replyCount).toMatchObject({ _type: "increment", n: 1 });
        expect(updateData.lastReplyAt).toBeDefined();
        expect(updateData.updatedAt).toBeDefined();
    });

    test("accepts body of exactly 4000 characters", async () => {
        setupHappyPath();
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const result = await (createCovenantThreadReply as any)(
            makeRequest({ body: "a".repeat(4000) })
        );
        expect(result.ok).toBe(true);
    });

    test("accepts exactly 5 mentions", async () => {
        setupHappyPath();
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const result = await (createCovenantThreadReply as any)(
            makeRequest({ mentions: ["u1", "u2", "u3", "u4", "u5"] })
        );
        expect(result.ok).toBe(true);
    });

    test("trims leading/trailing whitespace from body before persisting", async () => {
        setupHappyPath();
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        await (createCovenantThreadReply as any)(makeRequest({ body: "  trimmed body  " }));
        const replyData = mockBatch.set.mock.calls[0][1] as Record<string, unknown>;
        expect(replyData.body).toBe("trimmed body");
    });
});
