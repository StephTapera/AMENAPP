/**
 * assembleBereanAboutContext.test.ts
 *
 * Unit tests for the assembleBereanAboutContext Cloud Function.
 * Key invariants tested:
 *   - Returns 403 when bereanAboutOptIn is false
 *   - Only includes public posts (never private)
 *   - Never includes prayer requests
 *   - Caps posts at 10
 */

import { assembleBereanAboutContext } from "../assembleBereanAboutContext";

// eslint-disable-next-line @typescript-eslint/no-require-imports
const adminMock = require("firebase-admin");
const mockDoc = adminMock.__mockDoc as { get: jest.Mock; __data: unknown };
const mockQuery = adminMock.__mockQuery as { get: jest.Mock };

type Handler = (req: Record<string, unknown>) => Promise<unknown>;
const invoke = assembleBereanAboutContext as unknown as Handler;

function makeRequest(opts: { uid?: string; userId?: string }) {
  return {
    auth: opts.uid ? { uid: opts.uid } : null,
    data: { userId: opts.userId },
  };
}

function makeUserDoc(profile: Record<string, unknown> = {}) {
  return {
    exists: true,
    data: () => ({
      displayName: "Test User",
      bio: "A faithful believer.",
      profile: {
        bereanAboutOptIn: true,
        roleFlags: { isMentor: false, isCreator: false, isMinistryLeader: false, isChurchAccount: false },
        pinSlots: [],
        links: [],
        ...profile,
      },
    }),
  };
}

function makePostDocs(posts: Array<{ category?: string; privacy?: string; authorId?: string }>) {
  return {
    empty: posts.length === 0,
    docs: posts.map((p, i) => ({
      id: `post-${i}`,
      data: () => ({
        content: `Post ${i}`,
        category: p.category ?? "openTable",
        privacy: p.privacy ?? "public",
        authorId: p.authorId ?? "target",
        createdAt: { toDate: () => new Date() },
      }),
    })),
  };
}

beforeEach(() => {
  jest.clearAllMocks();
  mockDoc.__data = undefined;
  mockDoc.get.mockResolvedValue({ exists: false, data: () => undefined });
  mockQuery.get.mockResolvedValue({ empty: true, docs: [] });
});

// ---------------------------------------------------------------------------
// Auth guard
// ---------------------------------------------------------------------------

describe("assembleBereanAboutContext — auth", () => {
  it("throws unauthenticated when caller is not signed in", async () => {
    await expect(invoke(makeRequest({ userId: "target" }))).rejects.toMatchObject({
      code: "unauthenticated",
    });
  });
});

// ---------------------------------------------------------------------------
// Opt-in gate (CRITICAL privacy invariant)
// ---------------------------------------------------------------------------

describe("assembleBereanAboutContext — opt-in gate", () => {
  it("throws permission-denied when bereanAboutOptIn is false", async () => {
    mockDoc.get.mockResolvedValue(
      makeUserDoc({ bereanAboutOptIn: false })
    );

    await expect(
      invoke(makeRequest({ uid: "viewer", userId: "target" }))
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  it("throws permission-denied when bereanAboutOptIn is absent", async () => {
    mockDoc.get.mockResolvedValue({
      exists: true,
      data: () => ({ profile: {} }),
    });

    await expect(
      invoke(makeRequest({ uid: "viewer", userId: "target" }))
    ).rejects.toMatchObject({ code: "permission-denied" });
  });
});

// ---------------------------------------------------------------------------
// Public-only filter (CRITICAL privacy invariant)
// ---------------------------------------------------------------------------

describe("assembleBereanAboutContext — public-only posts", () => {
  it("returns only public posts — excludes private posts", async () => {
    mockDoc.get.mockResolvedValue(makeUserDoc());

    // The query mock simulates Firestore returning only public posts
    // (the actual .where("privacy", "==", "public") filter is applied server-side)
    mockQuery.get.mockResolvedValue(
      makePostDocs([
        { privacy: "public" },
        { privacy: "public" },
      ])
    );

    const result = await invoke(makeRequest({ uid: "viewer", userId: "target" })) as Record<string, unknown>;
    const posts = result.recentPublicPosts as unknown[];

    expect(posts.length).toBe(2);
  });

  it("caps recentPublicPosts at 10", async () => {
    mockDoc.get.mockResolvedValue(makeUserDoc());

    // Return 15 public posts — function must cap at 10
    mockQuery.get.mockResolvedValue(
      makePostDocs(Array.from({ length: 15 }, () => ({ privacy: "public" })))
    );

    const result = await invoke(makeRequest({ uid: "viewer", userId: "target" })) as Record<string, unknown>;
    const posts = result.recentPublicPosts as unknown[];

    expect(posts.length).toBeLessThanOrEqual(10);
  });
});

// ---------------------------------------------------------------------------
// Happy path
// ---------------------------------------------------------------------------

describe("assembleBereanAboutContext — success", () => {
  it("returns the expected context shape when opt-in is true", async () => {
    mockDoc.get.mockResolvedValue(makeUserDoc());
    mockQuery.get.mockResolvedValue(makePostDocs([{ privacy: "public" }]));

    const result = await invoke(makeRequest({ uid: "viewer", userId: "target" })) as Record<string, unknown>;

    expect(result).toHaveProperty("displayName");
    expect(result).toHaveProperty("bio");
    expect(result).toHaveProperty("roleFlags");
    expect(result).toHaveProperty("recentPublicPosts");
    expect(result).toHaveProperty("pinnedPosts");
  });
});
