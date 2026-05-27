/**
 * ProgressiveTrustService.test.ts
 *
 * Tests for trust ratchet logic, capability gates, and admin grant path.
 * Mocks: firebase-admin (db), firebase-functions/v2/https, firebase-functions/v2/firestore
 */

import admin from "firebase-admin";

// Pulled off the manual-export surface so tests can configure return values
const mockDoc = (admin as any).__mockDoc as {
  get: jest.Mock;
  set: jest.Mock;
  update: jest.Mock;
  delete: jest.Mock;
  collection: jest.Mock;
  __data: Record<string, unknown> | undefined;
};
const mockCollection = (admin as any).__mockCollection as {
  doc: jest.Mock;
  add: jest.Mock;
  where: jest.Mock;
  orderBy: jest.Mock;
  limit: jest.Mock;
  get: jest.Mock;
};
const mockQuery = (admin as any).__mockQuery as {
  orderBy: jest.Mock;
  limit: jest.Mock;
  where: jest.Mock;
  get: jest.Mock;
};

// ─── Helpers ─────────────────────────────────────────────────────────────────

type EventDoc = { points: number };

function makeEventDocs(eventList: EventDoc[]) {
  return {
    docs: eventList.map((e) => ({ data: () => e, id: `ev-${Math.random()}` })),
    forEach(cb: (doc: { data: () => EventDoc; id: string }) => void) {
      this.docs.forEach(cb);
    },
    empty: eventList.length === 0,
    size: eventList.length,
  };
}

function resetMocks() {
  jest.clearAllMocks();
  mockDoc.__data = undefined;

  // Default: doc.get() returns empty (no existing user)
  mockDoc.get.mockResolvedValue({ data: () => mockDoc.__data, exists: !!mockDoc.__data });
  // Default: query.get() returns empty events
  mockQuery.get.mockResolvedValue(makeEventDocs([]));
  // Default: collection().add() succeeds
  mockCollection.add.mockResolvedValue({ id: "mock-event-id" });
  // Default: runTransaction calls handler with mocks
  (admin.firestore() as any).runTransaction.mockImplementation(
    (handler: (tx: any) => Promise<void>) =>
      handler({
        get: mockDoc.get,
        set: mockDoc.set,
        update: mockDoc.update,
        delete: mockDoc.delete,
      })
  );
}

// ─── Import service under test (after mock setup) ────────────────────────────

import {
  TRUST_LEVELS,
  TRUST_EVENTS,
  recordTrustEvent,
  checkAccountCapability,
  getTrustProfile as _getTrustProfile,
  adminGrantTrustEvent as _adminGrantTrustEvent,
} from "../ProgressiveTrustService";

// onCall exports are handler functions at runtime (mock returns maybeHandler),
// but TypeScript types them as HttpsFunction which requires (req, res) signature.
// We unwrap to any here so tests can call with a single request object.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const getTrustProfile = _getTrustProfile as unknown as (req: any) => Promise<any>;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const adminGrantTrustEvent = _adminGrantTrustEvent as unknown as (req: any) => Promise<any>;

// ─── Tests ────────────────────────────────────────────────────────────────────

describe("TRUST_LEVELS constants", () => {
  test("Level 0 has all capabilities false/restricted", () => {
    const caps = TRUST_LEVELS[0].capabilities;
    expect(caps.canDM).toBe(false);
    expect(caps.dmScope).toBe(false);
    expect(caps.canUploadMedia).toBe(false);
    expect(caps.mediaScope).toBe(false);
    expect(caps.canCreateGroup).toBe(false);
    expect(caps.canPostPublicly).toBe(false);
    expect(caps.canMentor).toBe(false);
  });

  test("Level 2 enables canDM with verified_only scope", () => {
    const caps = TRUST_LEVELS[2].capabilities;
    expect(caps.canDM).toBe(true);
    expect(caps.dmScope).toBe("verified_only");
  });

  test("Level 5 enables canMentor", () => {
    expect(TRUST_LEVELS[5].capabilities.canMentor).toBe(true);
  });

  test("Level 4 can create groups but cannot mentor", () => {
    const caps = TRUST_LEVELS[4].capabilities;
    expect(caps.canCreateGroup).toBe(true);
    expect(caps.canMentor).toBe(false);
  });
});

describe("recordTrustEvent", () => {
  beforeEach(() => resetMocks());

  test("throws for unknown eventType", async () => {
    await expect(recordTrustEvent("uid-1", "not_a_real_event")).rejects.toThrow(
      /Unknown eventType/
    );
  });

  test("writes event document to trustEvents/{uid}/events", async () => {
    // Simulate 0 existing points so level stays at 0
    mockQuery.get.mockResolvedValue(makeEventDocs([]));
    mockDoc.__data = { trustLevel: 0, trustPoints: 0 };
    mockDoc.get.mockResolvedValue({ data: () => mockDoc.__data, exists: true });

    await recordTrustEvent("uid-abc", "email_verified");

    // collection().doc().collection().add() — we verify add was called
    expect(mockCollection.add).toHaveBeenCalledWith(
      expect.objectContaining({
        eventType: "email_verified",
        points: TRUST_EVENTS["email_verified"],
      })
    );
  });

  test("accumulates points from events and recalculates level", async () => {
    // Simulate 5 pts already on account (email_verified=5)
    mockQuery.get.mockResolvedValue(makeEventDocs([{ points: 5 }]));
    mockDoc.__data = { trustLevel: 0, trustPoints: 0 };
    mockDoc.get.mockResolvedValue({ data: () => mockDoc.__data, exists: true });

    await recordTrustEvent("uid-abc", "account_age_7d"); // +5 pts

    // After adding a 5-pt event to an existing 5-pt account: total = 10 → level 1
    // mockQuery.get returns [5] (existing), then add writes 5 more
    // But in test, the query snapshot is fixed at [{ points: 5 }] —
    // the new event is written first via add(), then the query re-runs
    // The query here returns 5 pts (only the existing doc in the snapshot),
    // so newLevel = max(0, level_from_5pts) = max(0, 1) = 1
    expect(mockDoc.set).toHaveBeenCalledWith(
      expect.objectContaining({
        trustLevel: 1,
        trustPoints: 5,
      }),
      expect.objectContaining({ merge: true })
    );
  });

  test("level never decreases: max(currentLevel, newLevel) is used", async () => {
    // User is already at level 3 but their rolling-year points only yield level 1
    mockQuery.get.mockResolvedValue(makeEventDocs([{ points: 5 }])); // 5 pts = L1
    mockDoc.__data = { trustLevel: 3, trustPoints: 50 };
    mockDoc.get.mockResolvedValue({ data: () => mockDoc.__data, exists: true });

    await recordTrustEvent("uid-abc", "email_verified");

    // Level should stay at 3 (max of 3, 1)
    expect(mockDoc.set).toHaveBeenCalledWith(
      expect.objectContaining({ trustLevel: 3 }),
      expect.objectContaining({ merge: true })
    );
  });

  test("sends level-up notification when level increases", async () => {
    // 4 points already, adding 1 more crosses 5-pt threshold → L1
    mockQuery.get.mockResolvedValue(makeEventDocs([{ points: 5 }])); // 5 pts → L1
    mockDoc.__data = { trustLevel: 0, trustPoints: 0 };
    mockDoc.get.mockResolvedValue({ data: () => mockDoc.__data, exists: true });

    await recordTrustEvent("uid-abc", "account_age_7d");

    // Level went from 0 to 1 — notification add should be called
    expect(mockCollection.add).toHaveBeenCalledWith(
      expect.objectContaining({ type: "trust_level_up", trustLevel: 1 })
    );
  });
});

describe("checkAccountCapability", () => {
  beforeEach(() => resetMocks());

  test("returns false when user document does not exist", async () => {
    mockDoc.get.mockResolvedValue({ data: () => undefined, exists: false });
    const result = await checkAccountCapability("uid-missing", "canDM");
    expect(result).toBe(false);
  });

  test("returns false when trustCapabilities is absent", async () => {
    mockDoc.__data = { trustLevel: 0 }; // no trustCapabilities field
    mockDoc.get.mockResolvedValue({ data: () => mockDoc.__data, exists: true });
    const result = await checkAccountCapability("uid-1", "canDM");
    expect(result).toBe(false);
  });

  test("returns true for boolean true capability", async () => {
    mockDoc.__data = {
      trustCapabilities: TRUST_LEVELS[2].capabilities, // canDM: true
    };
    mockDoc.get.mockResolvedValue({ data: () => mockDoc.__data, exists: true });
    const result = await checkAccountCapability("uid-1", "canDM");
    expect(result).toBe(true);
  });

  test("returns false for boolean false capability", async () => {
    mockDoc.__data = {
      trustCapabilities: TRUST_LEVELS[0].capabilities, // canDM: false
    };
    mockDoc.get.mockResolvedValue({ data: () => mockDoc.__data, exists: true });
    const result = await checkAccountCapability("uid-1", "canDM");
    expect(result).toBe(false);
  });

  test("returns true for scoped string capability (dmScope = verified_only)", async () => {
    mockDoc.__data = {
      trustCapabilities: TRUST_LEVELS[2].capabilities,
    };
    mockDoc.get.mockResolvedValue({ data: () => mockDoc.__data, exists: true });
    const result = await checkAccountCapability("uid-1", "dmScope");
    expect(result).toBe(true);
  });

  test("fails closed (returns false) on Firestore error", async () => {
    mockDoc.get.mockRejectedValue(new Error("Firestore unavailable"));
    const result = await checkAccountCapability("uid-1", "canMentor");
    expect(result).toBe(false);
  });
});

describe("getTrustProfile callable", () => {
  beforeEach(() => resetMocks());

  test("throws unauthenticated when no auth", async () => {
    await expect(getTrustProfile({ auth: null, data: {} } as any)).rejects.toMatchObject({
      code: "unauthenticated",
    });
  });

  test("throws not-found when user document missing", async () => {
    mockDoc.get.mockResolvedValue({ data: () => undefined, exists: false });
    await expect(
      getTrustProfile({ auth: { uid: "uid-1", token: {} }, data: {} } as any)
    ).rejects.toMatchObject({ code: "not-found" });
  });

  test("returns correct shape for existing user", async () => {
    const caps = TRUST_LEVELS[2].capabilities;
    mockDoc.__data = { trustLevel: 2, trustPoints: 25, trustCapabilities: caps };
    mockDoc.get.mockResolvedValue({ data: () => mockDoc.__data, exists: true });
    mockQuery.get.mockResolvedValue({ docs: [], empty: true, size: 0 });

    const result = await getTrustProfile({
      auth: { uid: "uid-1", token: {} },
      data: {},
    } as any);

    expect(result.trustLevel).toBe(2);
    expect(result.trustPoints).toBe(25);
    expect(result.trustCapabilities).toEqual(caps);
    expect(result.nextLevelRequirement).toBe(45 - 25); // L3 threshold - current pts
    expect(Array.isArray(result.recentEvents)).toBe(true);
  });

  test("returns null nextLevelRequirement at max level (5)", async () => {
    const caps = TRUST_LEVELS[5].capabilities;
    mockDoc.__data = { trustLevel: 5, trustPoints: 150, trustCapabilities: caps };
    mockDoc.get.mockResolvedValue({ data: () => mockDoc.__data, exists: true });
    mockQuery.get.mockResolvedValue({ docs: [], empty: true, size: 0 });

    const result = await getTrustProfile({
      auth: { uid: "uid-1", token: {} },
      data: {},
    } as any);

    expect(result.nextLevelRequirement).toBeNull();
  });

  test("throws permission-denied when non-admin fetches another user's profile", async () => {
    await expect(
      getTrustProfile({
        auth: { uid: "uid-caller", token: {} },
        data: { uid: "uid-other" },
      } as any)
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  test("admin token can fetch another user's profile", async () => {
    const caps = TRUST_LEVELS[1].capabilities;
    mockDoc.__data = { trustLevel: 1, trustPoints: 5, trustCapabilities: caps };
    mockDoc.get.mockResolvedValue({ data: () => mockDoc.__data, exists: true });
    mockQuery.get.mockResolvedValue({ docs: [], empty: true, size: 0 });

    const result = await getTrustProfile({
      auth: { uid: "admin-uid", token: { admin: true } },
      data: { uid: "uid-other" },
    } as any);

    expect(result.trustLevel).toBe(1);
  });
});

describe("adminGrantTrustEvent callable", () => {
  beforeEach(() => resetMocks());

  test("throws unauthenticated when no auth", async () => {
    await expect(
      adminGrantTrustEvent({ auth: null, data: {} } as any)
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("throws permission-denied for non-admin caller", async () => {
    await expect(
      adminGrantTrustEvent({
        auth: { uid: "uid-1", token: {} },
        data: { uid: "uid-target", eventType: "email_verified", reason: "manual" },
      } as any)
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  test("throws invalid-argument for unknown eventType", async () => {
    await expect(
      adminGrantTrustEvent({
        auth: { uid: "admin-1", token: { admin: true } },
        data: { uid: "uid-target", eventType: "not_real", reason: "test" },
      } as any)
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("throws invalid-argument when required fields are missing", async () => {
    await expect(
      adminGrantTrustEvent({
        auth: { uid: "admin-1", token: { admin: true } },
        data: { uid: "uid-target", eventType: "", reason: "" },
      } as any)
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("admin grant writes audit log and returns auditLogId", async () => {
    // Setup: recordTrustEvent will need a user snap
    mockDoc.__data = { trustLevel: 0, trustPoints: 0 };
    mockDoc.get.mockResolvedValue({ data: () => mockDoc.__data, exists: true });
    mockQuery.get.mockResolvedValue(makeEventDocs([]));
    mockCollection.add.mockResolvedValue({ id: "audit-log-123" });

    const result = await adminGrantTrustEvent({
      auth: { uid: "admin-1", token: { admin: true } },
      data: { uid: "uid-target", eventType: "email_verified", reason: "onboarding manual grant" },
    } as any);

    expect(result.success).toBe(true);
    expect(result.auditLogId).toBe("audit-log-123");
    // The audit log add call should include uid and eventType
    expect(mockCollection.add).toHaveBeenCalledWith(
      expect.objectContaining({
        uid: "uid-target",
        eventType: "email_verified",
        reason: "onboarding manual grant",
      })
    );
  });
});
