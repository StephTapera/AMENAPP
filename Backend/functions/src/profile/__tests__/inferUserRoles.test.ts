/**
 * inferUserRoles.test.ts
 *
 * Unit tests for the inferUserRoles Cloud Function.
 * Verifies that roleFlags are computed correctly and written to Firestore.
 */

import { inferUserRoles } from "../inferUserRoles";

// eslint-disable-next-line @typescript-eslint/no-require-imports
const adminMock = require("firebase-admin");
const mockDoc = adminMock.__mockDoc as { get: jest.Mock; update: jest.Mock; __data: unknown };

type Handler = (req: Record<string, unknown>) => Promise<unknown>;
const invoke = inferUserRoles as unknown as Handler;

function makeRequest(opts: { uid?: string; userId?: string }) {
  return {
    auth: opts.uid ? { uid: opts.uid } : null,
    data: { userId: opts.userId },
  };
}

function makeUserDoc(overrides: Record<string, unknown> = {}) {
  return {
    exists: true,
    data: () => ({
      uid: "target",
      ...overrides,
    }),
  };
}

beforeEach(() => {
  jest.clearAllMocks();
  mockDoc.__data = undefined;
  mockDoc.get.mockResolvedValue({ exists: false, data: () => undefined });
  mockDoc.update.mockResolvedValue(undefined);
});

// ---------------------------------------------------------------------------
// Auth guard
// ---------------------------------------------------------------------------

describe("inferUserRoles — auth", () => {
  it("throws unauthenticated when caller is not signed in", async () => {
    await expect(invoke(makeRequest({ userId: "target" }))).rejects.toMatchObject({
      code: "unauthenticated",
    });
  });
});

// ---------------------------------------------------------------------------
// Input validation
// ---------------------------------------------------------------------------

describe("inferUserRoles — input validation", () => {
  it("throws invalid-argument when userId is missing", async () => {
    await expect(invoke(makeRequest({ uid: "caller" }))).rejects.toMatchObject({
      code: "invalid-argument",
    });
  });
});

// ---------------------------------------------------------------------------
// Permission: caller must be the target or an admin
// ---------------------------------------------------------------------------

describe("inferUserRoles — permissions", () => {
  it("throws permission-denied when a non-admin caller tries to infer roles for another user", async () => {
    mockDoc.get.mockResolvedValue(makeUserDoc({ role: "user" }));

    await expect(
      invoke(makeRequest({ uid: "other-user", userId: "target" }))
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  it("allows the target user to infer their own roles", async () => {
    mockDoc.get.mockResolvedValue(makeUserDoc());

    await expect(
      invoke(makeRequest({ uid: "target", userId: "target" }))
    ).resolves.toMatchObject({ success: true });
  });
});

// ---------------------------------------------------------------------------
// Happy path — role inference
// ---------------------------------------------------------------------------

describe("inferUserRoles — role computation", () => {
  it("writes roleFlags to Firestore on success", async () => {
    mockDoc.get.mockResolvedValue(makeUserDoc());

    await invoke(makeRequest({ uid: "target", userId: "target" }));

    expect(mockDoc.update).toHaveBeenCalledWith(
      expect.objectContaining({
        "profile.roleFlags": expect.objectContaining({
          isMentor: expect.any(Boolean),
          isCreator: expect.any(Boolean),
          isMinistryLeader: expect.any(Boolean),
          isChurchAccount: expect.any(Boolean),
        }),
      })
    );
  });

  it("returns the computed roleFlags in the response", async () => {
    mockDoc.get.mockResolvedValue(makeUserDoc());

    const result = await invoke(makeRequest({ uid: "target", userId: "target" })) as Record<string, unknown>;

    expect(result).toHaveProperty("roleFlags");
    const flags = result.roleFlags as Record<string, unknown>;
    expect(flags).toHaveProperty("isMentor");
    expect(flags).toHaveProperty("isCreator");
  });
});
