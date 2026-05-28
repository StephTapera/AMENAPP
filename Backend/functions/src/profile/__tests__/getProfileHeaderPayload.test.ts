/**
 * getProfileHeaderPayload.test.ts
 *
 * Unit tests for the getProfileHeaderPayload Cloud Function.
 */

import { getProfileHeaderPayload } from "../getProfileHeaderPayload";

// eslint-disable-next-line @typescript-eslint/no-require-imports
const adminMock = require("firebase-admin");
const mockDoc = adminMock.__mockDoc as { get: jest.Mock; __data: unknown };

type Handler = (req: Record<string, unknown>) => Promise<unknown>;
const invoke = getProfileHeaderPayload as unknown as Handler;

const DEFAULT_PROFILE = {
  links: [],
  pinSlots: [],
  roleFlags: {
    isMentor: false,
    isCreator: false,
    isMinistryLeader: false,
    isChurchAccount: false,
    churchId: null,
  },
  profileMetrics: {
    peopleDiscipled: 0,
    versesShared: 0,
    yearsWalkingWithChrist: null,
    testimoniesGiven: 0,
    prayersOffered: 0,
  },
  bereanAboutOptIn: false,
};

function makeUserDoc(profile = DEFAULT_PROFILE) {
  return {
    exists: true,
    data: () => ({ profile }),
  };
}

function makeRequest(opts: { uid?: string; userId?: string; viewerId?: string }) {
  return {
    auth: opts.uid ? { uid: opts.uid } : null,
    data: { userId: opts.userId, viewerId: opts.viewerId ?? opts.uid ?? "" },
  };
}

beforeEach(() => {
  jest.clearAllMocks();
  mockDoc.__data = undefined;
  mockDoc.get.mockResolvedValue({ exists: false, data: () => undefined });
});

// ---------------------------------------------------------------------------
// Auth guard
// ---------------------------------------------------------------------------

describe("getProfileHeaderPayload — auth", () => {
  it("throws unauthenticated when caller is not signed in", async () => {
    await expect(invoke(makeRequest({ userId: "target" }))).rejects.toMatchObject({
      code: "unauthenticated",
    });
  });
});

// ---------------------------------------------------------------------------
// Input validation
// ---------------------------------------------------------------------------

describe("getProfileHeaderPayload — input validation", () => {
  it("throws invalid-argument when userId is missing", async () => {
    await expect(invoke(makeRequest({ uid: "viewer" }))).rejects.toMatchObject({
      code: "invalid-argument",
    });
  });

  it("throws invalid-argument when userId is empty string", async () => {
    await expect(invoke(makeRequest({ uid: "viewer", userId: "" }))).rejects.toMatchObject({
      code: "invalid-argument",
    });
  });
});

// ---------------------------------------------------------------------------
// not-found
// ---------------------------------------------------------------------------

describe("getProfileHeaderPayload — not-found", () => {
  it("throws not-found when the target user document does not exist", async () => {
    mockDoc.get.mockResolvedValue({ exists: false, data: () => undefined });

    await expect(
      invoke(makeRequest({ uid: "viewer", userId: "missing-user" }))
    ).rejects.toMatchObject({ code: "not-found" });
  });
});

// ---------------------------------------------------------------------------
// Happy path
// ---------------------------------------------------------------------------

describe("getProfileHeaderPayload — success", () => {
  it("returns the full payload with defaults when profile fields are absent", async () => {
    mockDoc.get.mockResolvedValue(makeUserDoc(DEFAULT_PROFILE));

    const result = await invoke(makeRequest({ uid: "viewer", userId: "target" })) as Record<string, unknown>;

    expect(result.userId).toBe("target");
    expect(result.links).toEqual([]);
    expect(result.pinSlotIds).toEqual([]);
    expect(result.bereanAboutOptIn).toBe(false);
    expect(result.roleFlags).toMatchObject({ isMentor: false, isCreator: false });
    expect(result.profileMetrics).toMatchObject({ peopleDiscipled: 0, versesShared: 0 });
  });

  it("returns bereanAboutOptIn true when the user has opted in", async () => {
    mockDoc.get.mockResolvedValue(
      makeUserDoc({ ...DEFAULT_PROFILE, bereanAboutOptIn: true })
    );

    const result = await invoke(makeRequest({ uid: "viewer", userId: "target" })) as Record<string, unknown>;

    expect(result.bereanAboutOptIn).toBe(true);
  });

  it("returns roleFlags from the user document", async () => {
    const customFlags = {
      isMentor: true,
      isCreator: false,
      isMinistryLeader: false,
      isChurchAccount: false,
      churchId: null,
    };
    mockDoc.get.mockResolvedValue(
      makeUserDoc({ ...DEFAULT_PROFILE, roleFlags: customFlags })
    );

    const result = await invoke(makeRequest({ uid: "viewer", userId: "target" })) as Record<string, unknown>;

    expect(result.roleFlags).toMatchObject({ isMentor: true });
  });

  it("surfaces visitChurchURL when churchId is set", async () => {
    const flags = { ...DEFAULT_PROFILE.roleFlags, isChurchAccount: true, churchId: "church-abc" };
    mockDoc.get.mockResolvedValue(makeUserDoc({ ...DEFAULT_PROFILE, roleFlags: flags }));

    const result = await invoke(makeRequest({ uid: "viewer", userId: "target" })) as Record<string, unknown>;

    expect(result.visitChurchURL).toBeTruthy();
  });
});
