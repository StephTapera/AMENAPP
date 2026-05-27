/**
 * MentorshipVerificationService.test.ts
 *
 * Tests for mentorship connection lifecycle, church verification code flow,
 * and trust event integration.
 *
 * Mocks: firebase-admin, firebase-functions/v2/https, ProgressiveTrustService,
 *        AmenSafetyPolicy
 */

jest.mock("../AmenSafetyPolicy", () => ({
  AMEN_SAFETY_POLICY_VERSION: "2026-05-25",
}));

jest.mock("../ProgressiveTrustService", () => ({
  recordTrustEvent: jest.fn().mockResolvedValue(undefined),
}));

import admin from "firebase-admin";
import { recordTrustEvent } from "../ProgressiveTrustService";

const mockRecordTrustEvent = recordTrustEvent as jest.Mock;

const mockDoc = (admin as any).__mockDoc as {
  get: jest.Mock;
  set: jest.Mock;
  update: jest.Mock;
  collection: jest.Mock;
  id: string;
  __data: Record<string, unknown> | undefined;
};
const mockCollection = (admin as any).__mockCollection as {
  doc: jest.Mock;
  add: jest.Mock;
  where: jest.Mock;
  limit: jest.Mock;
  get: jest.Mock;
};
const mockQuery = (admin as any).__mockQuery as {
  where: jest.Mock;
  limit: jest.Mock;
  get: jest.Mock;
};
const mockBatch = (admin as any).__mockBatch as {
  set: jest.Mock;
  update: jest.Mock;
  commit: jest.Mock;
};

// ─── Helpers ─────────────────────────────────────────────────────────────────

function makeRequest(data: Record<string, unknown>, uid = "uid-mentee") {
  return { auth: { uid, token: {} }, data } as any;
}

function makeUserSnap(data: Record<string, unknown> | undefined, exists = true) {
  return { data: () => data, exists };
}

/** Future timestamp (not expired). */
function futureTimestamp() {
  const ms = Date.now() + 48 * 60 * 60 * 1000;
  return { toMillis: () => ms, toDate: () => new Date(ms) };
}

/** Past timestamp (already expired). */
function pastTimestamp() {
  const ms = Date.now() - 1000;
  return { toMillis: () => ms, toDate: () => new Date(ms) };
}

function resetMocks() {
  jest.clearAllMocks();
  mockDoc.__data = undefined;
  mockDoc.get.mockResolvedValue(makeUserSnap(undefined, false));
  mockDoc.set.mockResolvedValue(undefined);
  mockDoc.update.mockResolvedValue(undefined);
  mockCollection.add.mockResolvedValue({ id: "mock-id" });
  mockCollection.doc.mockReturnValue(mockDoc);
  mockQuery.get.mockResolvedValue({ docs: [], empty: true, size: 0 });
  mockBatch.set.mockClear();
  mockBatch.update.mockClear();
  mockBatch.commit.mockResolvedValue(undefined);
}

// ─── Import service under test ────────────────────────────────────────────────

import {
  requestMentorship as _requestMentorship,
  approveMentorship as _approveMentorship,
  endMentorship as _endMentorship,
  requestChurchVerification as _requestChurchVerification,
  issueChurchVerificationCode as _issueChurchVerificationCode,
  getChurchVerificationStatus as _getChurchVerificationStatus,
} from "../MentorshipVerificationService";

// onCall exports are handler functions at runtime; unwrap type for tests.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const requestMentorship = _requestMentorship as unknown as (req: any) => Promise<any>;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const approveMentorship = _approveMentorship as unknown as (req: any) => Promise<any>;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const endMentorship = _endMentorship as unknown as (req: any) => Promise<any>;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const requestChurchVerification = _requestChurchVerification as unknown as (req: any) => Promise<any>;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const issueChurchVerificationCode = _issueChurchVerificationCode as unknown as (req: any) => Promise<any>;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const getChurchVerificationStatus = _getChurchVerificationStatus as unknown as (req: any) => Promise<any>;

// ─── requestMentorship ────────────────────────────────────────────────────────

describe("requestMentorship callable", () => {
  beforeEach(() => resetMocks());

  test("throws unauthenticated when no auth", async () => {
    await expect(
      requestMentorship({ auth: null, data: { mentorUid: "uid-mentor" } } as any)
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("throws invalid-argument when mentorUid is empty", async () => {
    await expect(
      requestMentorship(makeRequest({ mentorUid: "" }))
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("throws invalid-argument when mentorUid equals menteeUid", async () => {
    await expect(
      requestMentorship(makeRequest({ mentorUid: "uid-mentee" }, "uid-mentee"))
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("throws failed-precondition when mentor trust level is below 2", async () => {
    // mentor snap: trustLevel = 1, active
    let callCount = 0;
    mockDoc.get.mockImplementation(() => {
      callCount++;
      if (callCount === 1) return Promise.resolve(makeUserSnap({ trustLevel: 1, accountStatus: "active" }));
      return Promise.resolve(makeUserSnap({ accountStatus: "active" }));
    });

    await expect(
      requestMentorship(makeRequest({ mentorUid: "uid-mentor" }))
    ).rejects.toMatchObject({ code: "failed-precondition" });
  });

  test("creates pending connection document when all checks pass", async () => {
    // Parallel fetch: mentor + mentee account checks
    let callCount = 0;
    mockDoc.get.mockImplementation(() => {
      callCount++;
      if (callCount === 1) return Promise.resolve(makeUserSnap({ trustLevel: 2, accountStatus: "active", ageTier: "adult" })); // mentor
      if (callCount === 2) return Promise.resolve(makeUserSnap({ trustLevel: 1, accountStatus: "active", ageTier: "adult" })); // mentee
      return Promise.resolve(makeUserSnap(undefined, false));
    });

    // Active connection counts: 0 each
    mockQuery.get.mockResolvedValue({ docs: [], empty: true, size: 0 });

    const result = await requestMentorship(
      makeRequest({ mentorUid: "uid-mentor", context: "Bible study" }, "uid-mentee")
    );

    expect(result.status).toBe("pending");
    expect(result.connectionId).toBeDefined();
    expect(mockBatch.set).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ status: "pending", mentorUid: "uid-mentor", menteeUid: "uid-mentee" })
    );
  });
});

// ─── approveMentorship ────────────────────────────────────────────────────────

describe("approveMentorship callable", () => {
  beforeEach(() => resetMocks());

  test("throws unauthenticated when no auth", async () => {
    await expect(
      approveMentorship({ auth: null, data: { connectionId: "conn-1" } } as any)
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("throws not-found when connection document does not exist", async () => {
    mockDoc.get.mockResolvedValue(makeUserSnap(undefined, false));

    await expect(
      approveMentorship(makeRequest({ connectionId: "conn-1" }, "uid-mentor"))
    ).rejects.toMatchObject({ code: "not-found" });
  });

  test("throws permission-denied when caller is not the mentor", async () => {
    mockDoc.get.mockResolvedValue(
      makeUserSnap({
        mentorUid: "uid-mentor",
        menteeUid: "uid-mentee",
        status: "pending",
      })
    );

    await expect(
      // Caller is the mentee, not the mentor
      approveMentorship(makeRequest({ connectionId: "conn-1" }, "uid-mentee"))
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  test("throws failed-precondition when connection is already active", async () => {
    mockDoc.get.mockResolvedValue(
      makeUserSnap({
        mentorUid: "uid-mentor",
        menteeUid: "uid-mentee",
        status: "active",
      })
    );

    await expect(
      approveMentorship(makeRequest({ connectionId: "conn-1" }, "uid-mentor"))
    ).rejects.toMatchObject({ code: "failed-precondition" });
  });

  test("updates status to 'active' and calls recordTrustEvent for both parties", async () => {
    mockDoc.get.mockResolvedValue(
      makeUserSnap({
        mentorUid: "uid-mentor",
        menteeUid: "uid-mentee",
        status: "pending",
      })
    );

    const result = await approveMentorship(
      makeRequest({ connectionId: "conn-1" }, "uid-mentor")
    );

    expect(result.success).toBe(true);
    expect(mockDoc.update).toHaveBeenCalledWith(
      expect.objectContaining({ status: "active" })
    );
    expect(mockRecordTrustEvent).toHaveBeenCalledWith(
      "uid-mentee",
      "mentorship_connection_approved"
    );
    expect(mockRecordTrustEvent).toHaveBeenCalledWith(
      "uid-mentor",
      "mentorship_connection_approved"
    );
  });
});

// ─── endMentorship ────────────────────────────────────────────────────────────

describe("endMentorship callable", () => {
  beforeEach(() => resetMocks());

  test("throws unauthenticated when no auth", async () => {
    await expect(
      endMentorship({ auth: null, data: { connectionId: "conn-1" } } as any)
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("throws not-found when connection does not exist", async () => {
    mockDoc.get.mockResolvedValue(makeUserSnap(undefined, false));

    await expect(
      endMentorship(makeRequest({ connectionId: "conn-1" }, "uid-mentor"))
    ).rejects.toMatchObject({ code: "not-found" });
  });

  test("throws permission-denied when caller is neither mentor nor mentee", async () => {
    mockDoc.get.mockResolvedValue(
      makeUserSnap({ mentorUid: "uid-mentor", menteeUid: "uid-mentee", status: "active" })
    );

    await expect(
      endMentorship(makeRequest({ connectionId: "conn-1" }, "uid-stranger"))
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  test("throws failed-precondition when connection is already ended", async () => {
    mockDoc.get.mockResolvedValue(
      makeUserSnap({ mentorUid: "uid-mentor", menteeUid: "uid-mentee", status: "ended" })
    );

    await expect(
      endMentorship(makeRequest({ connectionId: "conn-1" }, "uid-mentor"))
    ).rejects.toMatchObject({ code: "failed-precondition" });
  });

  test("updates connection status to 'ended'", async () => {
    mockDoc.get.mockResolvedValue(
      makeUserSnap({ mentorUid: "uid-mentor", menteeUid: "uid-mentee", status: "active" })
    );

    const result = await endMentorship(makeRequest({ connectionId: "conn-1" }, "uid-mentee"));

    expect(result.success).toBe(true);
    expect(mockDoc.update).toHaveBeenCalledWith(
      expect.objectContaining({ status: "ended" })
    );
  });
});

// ─── requestChurchVerification ────────────────────────────────────────────────

describe("requestChurchVerification callable", () => {
  beforeEach(() => resetMocks());

  test("throws unauthenticated when no auth", async () => {
    await expect(
      requestChurchVerification({
        auth: null,
        data: { churchId: "church-1", verificationCode: "123456" },
      } as any)
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("throws not-found when church does not exist", async () => {
    mockDoc.get.mockResolvedValue(makeUserSnap(undefined, false)); // church doc missing

    await expect(
      requestChurchVerification(
        makeRequest({ churchId: "church-1", verificationCode: "123456" })
      )
    ).rejects.toMatchObject({ code: "not-found" });
  });

  test("throws invalid-argument for expired verification code", async () => {
    let callCount = 0;
    mockDoc.get.mockImplementation(() => {
      callCount++;
      if (callCount === 1) {
        // Church doc: exists, verification enabled
        return Promise.resolve(makeUserSnap({ name: "Grace Church", adminUids: [], verificationEnabled: true }));
      }
      if (callCount === 2) {
        // Code doc: exists but expired
        return Promise.resolve(
          makeUserSnap({ used: false, issuedBy: "admin-1", expiresAt: pastTimestamp(), createdAt: pastTimestamp() })
        );
      }
      // Existing verification query: empty
      return Promise.resolve(makeUserSnap(undefined, false));
    });
    mockQuery.get.mockResolvedValue({ docs: [], empty: true, size: 0 });

    await expect(
      requestChurchVerification(
        makeRequest({ churchId: "church-1", verificationCode: "123456" })
      )
    ).rejects.toMatchObject({ code: "deadline-exceeded" });
  });

  test("commits batch and calls recordTrustEvent on successful verification", async () => {
    let callCount = 0;
    mockDoc.get.mockImplementation(() => {
      callCount++;
      if (callCount === 1) {
        return Promise.resolve(makeUserSnap({ name: "Grace Church", adminUids: [], verificationEnabled: true }));
      }
      if (callCount === 2) {
        return Promise.resolve(
          makeUserSnap({ used: false, issuedBy: "admin-1", expiresAt: futureTimestamp(), createdAt: futureTimestamp() })
        );
      }
      return Promise.resolve(makeUserSnap(undefined, false));
    });
    // Existing verification check: empty
    mockQuery.get.mockResolvedValue({ docs: [], empty: true, size: 0 });

    const result = await requestChurchVerification(
      makeRequest({ churchId: "church-1", verificationCode: "123456" })
    );

    expect(result.success).toBe(true);
    expect(result.churchName).toBe("Grace Church");
    expect(mockBatch.commit).toHaveBeenCalled();
    expect(mockRecordTrustEvent).toHaveBeenCalledWith("uid-mentee", "church_connection_verified");
  });

  test("throws already-exists when code has already been used", async () => {
    let callCount = 0;
    mockDoc.get.mockImplementation(() => {
      callCount++;
      if (callCount === 1) {
        return Promise.resolve(makeUserSnap({ name: "Grace Church", adminUids: [], verificationEnabled: true }));
      }
      if (callCount === 2) {
        return Promise.resolve(
          makeUserSnap({ used: true, issuedBy: "admin-1", expiresAt: futureTimestamp(), createdAt: futureTimestamp() })
        );
      }
      return Promise.resolve(makeUserSnap(undefined, false));
    });

    await expect(
      requestChurchVerification(
        makeRequest({ churchId: "church-1", verificationCode: "123456" })
      )
    ).rejects.toMatchObject({ code: "already-exists" });
  });
});

// ─── issueChurchVerificationCode ──────────────────────────────────────────────

describe("issueChurchVerificationCode callable", () => {
  beforeEach(() => resetMocks());

  test("throws unauthenticated when no auth", async () => {
    await expect(
      issueChurchVerificationCode({ auth: null, data: { churchId: "church-1" } } as any)
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("throws permission-denied when caller is not a church admin", async () => {
    mockDoc.get.mockResolvedValue(
      makeUserSnap({ name: "Grace Church", adminUids: ["other-admin"], verificationEnabled: true })
    );

    await expect(
      issueChurchVerificationCode(makeRequest({ churchId: "church-1" }, "uid-stranger"))
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  test("writes code document with expiry and returns 6-digit code", async () => {
    let callCount = 0;
    mockDoc.get.mockImplementation(() => {
      callCount++;
      if (callCount === 1) {
        // Church doc
        return Promise.resolve(makeUserSnap({ name: "Grace Church", adminUids: ["uid-admin"], verificationEnabled: true }));
      }
      // Code doc: does not exist (so this candidate is valid)
      return Promise.resolve(makeUserSnap(undefined, false));
    });

    const result = await issueChurchVerificationCode(
      makeRequest({ churchId: "church-1" }, "uid-admin")
    );

    expect(result.code).toMatch(/^\d{6}$/);
    expect(result.expiresAt).toBeDefined();
    expect(mockDoc.set).toHaveBeenCalledWith(
      expect.objectContaining({ used: false, issuedBy: "uid-admin" })
    );
  });

  test("respects custom expiresInHours parameter", async () => {
    let callCount = 0;
    mockDoc.get.mockImplementation(() => {
      callCount++;
      if (callCount === 1) {
        return Promise.resolve(makeUserSnap({ name: "Grace Church", adminUids: ["uid-admin"], verificationEnabled: true }));
      }
      return Promise.resolve(makeUserSnap(undefined, false));
    });

    const before = Date.now();
    const result = await issueChurchVerificationCode(
      makeRequest({ churchId: "church-1", expiresInHours: 24 }, "uid-admin")
    );
    const expectedExpiry = before + 24 * 60 * 60 * 1000;

    // expiresAt should be approximately 24 hours from now
    expect(result.expiresAt.toMillis()).toBeGreaterThanOrEqual(expectedExpiry - 5000);
    expect(result.expiresAt.toMillis()).toBeLessThanOrEqual(expectedExpiry + 5000);
  });
});

// ─── getChurchVerificationStatus ─────────────────────────────────────────────

describe("getChurchVerificationStatus callable", () => {
  beforeEach(() => resetMocks());

  test("throws unauthenticated when no auth", async () => {
    await expect(
      getChurchVerificationStatus({ auth: null, data: {} } as any)
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("returns empty list when user has no verified churches", async () => {
    mockQuery.get.mockResolvedValue({ docs: [], empty: true, size: 0 });

    const result = await getChurchVerificationStatus(makeRequest({}, "uid-user"));

    expect(result.verifiedChurches).toEqual([]);
  });

  test("returns verified churches for user", async () => {
    const fakeDocs = [
      {
        id: "verif-1",
        data: () => ({
          churchId: "church-grace",
          churchName: "Grace Church",
          verifiedAt: futureTimestamp(),
        }),
      },
    ];
    mockQuery.get.mockResolvedValue({ docs: fakeDocs, empty: false, size: 1 });

    const result = await getChurchVerificationStatus(makeRequest({}, "uid-user"));

    expect(result.verifiedChurches).toHaveLength(1);
    expect(result.verifiedChurches[0].churchId).toBe("church-grace");
    expect(result.verifiedChurches[0].churchName).toBe("Grace Church");
  });
});
