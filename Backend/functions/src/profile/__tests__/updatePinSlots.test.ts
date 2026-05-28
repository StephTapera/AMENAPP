/**
 * updatePinSlots.test.ts
 *
 * Unit tests for the updatePinSlots Cloud Function.
 * Uses the firebase-admin mock and firebase-functions/v2/https mock.
 *
 * Key detail: the function verifies post ownership via `db.getAll(...postRefs)`
 * rather than individual `doc.get()` calls, so tests must configure __mockGetAll.
 */

import { updatePinSlots } from "../updatePinSlots";

// eslint-disable-next-line @typescript-eslint/no-require-imports
const adminMock = require("firebase-admin");
const mockDoc = adminMock.__mockDoc as { set: jest.Mock; __data: unknown };
const mockGetAll = adminMock.__mockGetAll as jest.Mock;

type Handler = (req: Record<string, unknown>) => Promise<unknown>;
const invoke = updatePinSlots as unknown as Handler;

function makeRequest(opts: { uid?: string; postIds?: unknown }) {
  return {
    auth: opts.uid ? { uid: opts.uid } : null,
    data: { postIds: opts.postIds },
  };
}

function makeGetAllResult(docs: Array<{ exists: boolean; authorId?: string; id?: string }>) {
  return docs.map((d) => ({
    exists: d.exists,
    id: d.id ?? "mock-post",
    data: () => (d.exists ? { authorId: d.authorId ?? "user1" } : undefined),
  }));
}

beforeEach(() => {
  jest.clearAllMocks();
  mockDoc.__data = undefined;
  mockDoc.set.mockResolvedValue(undefined);
  mockGetAll.mockResolvedValue([]);
});

// ---------------------------------------------------------------------------
// Auth guard
// ---------------------------------------------------------------------------

describe("updatePinSlots — auth", () => {
  it("throws unauthenticated when caller is not signed in", async () => {
    await expect(invoke(makeRequest({ postIds: [] }))).rejects.toMatchObject({
      code: "unauthenticated",
    });
  });
});

// ---------------------------------------------------------------------------
// Input validation
// ---------------------------------------------------------------------------

describe("updatePinSlots — input validation", () => {
  it("throws invalid-argument when postIds is not an array", async () => {
    await expect(
      invoke(makeRequest({ uid: "user1", postIds: "not-an-array" }))
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  it("throws invalid-argument when postIds has more than 3 items", async () => {
    await expect(
      invoke(makeRequest({ uid: "user1", postIds: ["a", "b", "c", "d"] }))
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  it("throws invalid-argument when a postId is an empty string", async () => {
    await expect(
      invoke(makeRequest({ uid: "user1", postIds: ["valid", ""] }))
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  it("throws invalid-argument when a postId is not a string", async () => {
    await expect(
      invoke(makeRequest({ uid: "user1", postIds: [42] }))
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });
});

// ---------------------------------------------------------------------------
// Post ownership (via db.getAll)
// ---------------------------------------------------------------------------

describe("updatePinSlots — post ownership", () => {
  it("throws not-found when a post does not exist", async () => {
    mockGetAll.mockResolvedValue(makeGetAllResult([{ exists: false }]));

    await expect(
      invoke(makeRequest({ uid: "user1", postIds: ["post-missing"] }))
    ).rejects.toMatchObject({ code: "not-found" });
  });

  it("throws permission-denied when a post belongs to a different user", async () => {
    mockGetAll.mockResolvedValue(
      makeGetAllResult([{ exists: true, authorId: "other-user" }])
    );

    await expect(
      invoke(makeRequest({ uid: "user1", postIds: ["post-owned-by-other"] }))
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  it("succeeds when the caller owns all posts", async () => {
    mockGetAll.mockResolvedValue(
      makeGetAllResult([
        { exists: true, authorId: "user1" },
        { exists: true, authorId: "user1" },
      ])
    );

    const result = await invoke(makeRequest({ uid: "user1", postIds: ["post1", "post2"] }));

    expect(result).toMatchObject({ success: true });
    expect((result as { pinSlotIds: string[] }).pinSlotIds).toEqual(["post1", "post2"]);
  });
});

// ---------------------------------------------------------------------------
// Empty slots
// ---------------------------------------------------------------------------

describe("updatePinSlots — empty slots", () => {
  it("succeeds with an empty array (clears all pins) without calling getAll", async () => {
    const result = await invoke(makeRequest({ uid: "user1", postIds: [] }));

    expect(result).toMatchObject({ success: true });
    expect((result as { pinSlotIds: string[] }).pinSlotIds).toEqual([]);
    // No post verification needed for empty slot clear
    expect(mockGetAll).not.toHaveBeenCalled();
  });
});
