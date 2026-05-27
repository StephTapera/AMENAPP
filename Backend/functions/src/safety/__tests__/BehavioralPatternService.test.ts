/**
 * BehavioralPatternService.test.ts
 *
 * Tests for DM metric recording, behavioral signal detection,
 * and coordinated harassment / grooming velocity scans.
 *
 * Mocks: firebase-admin, firebase-functions/v2/scheduler,
 *        firebase-functions/v2/firestore, plus service-layer deps.
 */

// Mock sibling service dependencies before importing BehavioralPatternService
jest.mock("../AmenSafetyPolicy", () => ({
  AMEN_SAFETY_POLICY_VERSION: "2026-05-25",
}));

jest.mock("../ModerationAuditLogService", () => ({
  writeAuditLog: jest.fn().mockResolvedValue(undefined),
}));

jest.mock("../GuardianConnectionService", () => ({
  deliverSafetyAlertToGuardians: jest.fn().mockResolvedValue(undefined),
}));

import admin from "firebase-admin";

const mockDoc = (admin as any).__mockDoc as {
  get: jest.Mock;
  set: jest.Mock;
  update: jest.Mock;
  delete: jest.Mock;
  collection: jest.Mock;
  id: string;
  __data: Record<string, unknown> | undefined;
};
const _mockCollection = (admin as any).__mockCollection as {
  doc: jest.Mock;
  add: jest.Mock;
  where: jest.Mock;
  orderBy: jest.Mock;
  limit: jest.Mock;
  get: jest.Mock;
};
const _mockQuery = (admin as any).__mockQuery as {
  orderBy: jest.Mock;
  limit: jest.Mock;
  where: jest.Mock;
  get: jest.Mock;
};
const mockBatch = (admin as any).__mockBatch as {
  set: jest.Mock;
  delete: jest.Mock;
  update: jest.Mock;
  commit: jest.Mock;
};

// ─── Helpers ─────────────────────────────────────────────────────────────────

function resetMocks() {
  jest.clearAllMocks();
  mockDoc.__data = undefined;
  mockDoc.get.mockResolvedValue({ data: () => mockDoc.__data, exists: !!mockDoc.__data });
  mockDoc.set.mockResolvedValue(undefined);
  mockBatch.set.mockClear();
  mockBatch.commit.mockResolvedValue(undefined);
  // runTransaction default implementation
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

function makeUserSnap(data: Record<string, unknown> | undefined, exists = true) {
  return { data: () => data, exists };
}

/** Build a mock Promise.all response for [senderSnap, recipientSnap, metricsSnap, senderStatsSnap] */
function mockFourWayGet(
  senderData: Record<string, unknown>,
  recipientData: Record<string, unknown>,
  metricsData: Record<string, unknown>,
  statsData: Record<string, unknown>
) {
  let callCount = 0;
  mockDoc.get.mockImplementation(() => {
    callCount++;
    switch (callCount) {
      case 1: return Promise.resolve(makeUserSnap(senderData));
      case 2: return Promise.resolve(makeUserSnap(recipientData));
      case 3: return Promise.resolve(makeUserSnap(metricsData));
      case 4: return Promise.resolve(makeUserSnap(statsData));
      default: return Promise.resolve(makeUserSnap(undefined, false));
    }
  });
}

// ─── Import service under test ────────────────────────────────────────────────

import { recordDMSent, checkBehavioralSignals } from "../BehavioralPatternService";
import { deliverSafetyAlertToGuardians } from "../GuardianConnectionService";
import { writeAuditLog } from "../ModerationAuditLogService";

const mockDeliverAlerts = deliverSafetyAlertToGuardians as jest.Mock;
const _mockWriteAudit = writeAuditLog as jest.Mock;

// ─── recordDMSent ─────────────────────────────────────────────────────────────

describe("recordDMSent", () => {
  beforeEach(() => resetMocks());

  test("increments dmMetrics document for sender→recipient pair on new doc", async () => {
    // Recipient lookup (utcOffset)
    mockDoc.get.mockResolvedValueOnce(makeUserSnap({ utcOffsetMinutes: 0 }));
    // dmMetrics: does not exist
    mockDoc.get.mockResolvedValueOnce(makeUserSnap(undefined, false));
    // senderStats: does not exist
    mockDoc.get.mockResolvedValueOnce(makeUserSnap(undefined, false));

    await recordDMSent("sender-uid", "recipient-uid");

    // tx.set(ref, data) — two args; first is the doc ref, second is the data
    expect(mockDoc.set).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ messageCount24h: 1, messageCount7d: 1 })
    );
  });

  test("increments userDMStats for sender", async () => {
    // Recipient lookup
    mockDoc.get.mockResolvedValueOnce(makeUserSnap({ utcOffsetMinutes: 0 }));
    // dmMetrics: does not exist
    mockDoc.get.mockResolvedValueOnce(makeUserSnap(undefined, false));
    // senderStats: does not exist
    mockDoc.get.mockResolvedValueOnce(makeUserSnap(undefined, false));

    await recordDMSent("sender-uid", "recipient-uid");

    // userDMStats should be initialised with distinctRecipients24h: 1, totalDMs1h: 1
    // tx.set(ref, data) — second arg is the data payload
    expect(mockDoc.set).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ distinctRecipients24h: 1, totalDMs1h: 1 })
    );
  });

  test("increments existing dmMetrics within the same 24h window", async () => {
    const now = Date.now();
    const recentUpdate = now - 60_000; // 1 minute ago

    // Recipient lookup
    mockDoc.get.mockResolvedValueOnce(makeUserSnap({ utcOffsetMinutes: 0 }));
    // dmMetrics: exists, last updated 1 min ago
    mockDoc.get.mockResolvedValueOnce(
      makeUserSnap({
        messageCount24h: 4,
        messageCount7d: 10,
        offHoursCount: 0,
        weeklyVelocity: [4, 2, 0, 0],
        updatedAt: { toMillis: () => recentUpdate },
        lastMessageAt: null,
      })
    );
    // senderStats: does not exist
    mockDoc.get.mockResolvedValueOnce(makeUserSnap(undefined, false));

    await recordDMSent("sender-uid", "recipient-uid");

    // messageCount24h should be 5 (4 + 1)
    // tx.set(ref, data, options) — third arg is merge options
    expect(mockDoc.set).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ messageCount24h: 5 }),
      expect.anything()
    );
  });
});

// ─── checkBehavioralSignals ───────────────────────────────────────────────────

describe("checkBehavioralSignals", () => {
  beforeEach(() => resetMocks());

  test("triggers adult→minor contact velocity alert when messageCount24h > 5", async () => {
    mockFourWayGet(
      { ageTier: "adult" },     // sender
      { ageTier: "minor", utcOffsetMinutes: 0 }, // recipient
      { messageCount24h: 6, messageCount7d: 6, offHoursCount: 0, weeklyVelocity: [6, 0, 0, 0] }, // metrics
      { distinctRecipients24h: 1, totalDMs1h: 1 }  // senderStats
    );

    await checkBehavioralSignals("adult-uid", "minor-uid");

    // Should have committed the behavioralAlerts + moderationQueue batch
    expect(mockBatch.commit).toHaveBeenCalled();
    expect(mockDeliverAlerts).toHaveBeenCalledWith(
      "minor-uid",
      "adult_minor_contact_velocity",
      "adult-uid"
    );
  });

  test("does NOT trigger velocity alert when sender is not adult", async () => {
    mockFourWayGet(
      { ageTier: "teen" },        // sender is teen (minor), not adult
      { ageTier: "minor", utcOffsetMinutes: 0 },
      { messageCount24h: 10, messageCount7d: 10, offHoursCount: 0, weeklyVelocity: [10, 0, 0, 0] },
      { distinctRecipients24h: 1, totalDMs1h: 2 }
    );

    await checkBehavioralSignals("teen-uid", "minor-uid");

    expect(mockDeliverAlerts).not.toHaveBeenCalled();
  });

  test("triggers off-hours alert when adult→minor messaging in off-hours with offHoursCount > 3", async () => {
    // Use utcOffsetMinutes = 0 and mock Date.now to force off-hours (11 pm UTC)
    const originalNow = Date.now;
    // 23:00 UTC = hour 23 >= 22 → off hours
    const offHoursMs = new Date("2026-05-25T23:00:00Z").getTime();
    Date.now = jest.fn(() => offHoursMs);

    mockFourWayGet(
      { ageTier: "adult" },
      { ageTier: "minor", utcOffsetMinutes: 0 },
      { messageCount24h: 3, messageCount7d: 3, offHoursCount: 4, weeklyVelocity: [3, 0, 0, 0] },
      { distinctRecipients24h: 1, totalDMs1h: 3 }
    );

    await checkBehavioralSignals("adult-uid", "minor-uid");

    expect(mockDeliverAlerts).toHaveBeenCalledWith(
      "minor-uid",
      "off_hours_adult_minor",
      "adult-uid"
    );

    Date.now = originalNow;
  });

  test("triggers spam_ring alert when totalDMs1h > 50", async () => {
    mockFourWayGet(
      { ageTier: "adult" },
      { ageTier: "adult", utcOffsetMinutes: 0 },
      { messageCount24h: 2, messageCount7d: 2, offHoursCount: 0, weeklyVelocity: [2, 0, 0, 0] },
      { distinctRecipients24h: 5, totalDMs1h: 51 }  // exceeds SPAM_DM_PER_HOUR_THRESHOLD
    );

    await checkBehavioralSignals("spammer-uid", "recipient-uid");

    expect(mockBatch.set).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ signalType: "spam_ring" })
    );
  });

  test("severity for adult_minor_contact_velocity is 'critical'", async () => {
    mockFourWayGet(
      { ageTier: "adult" },
      { ageTier: "minor", utcOffsetMinutes: 0 },
      { messageCount24h: 6, messageCount7d: 6, offHoursCount: 0, weeklyVelocity: [6, 0, 0, 0] },
      { distinctRecipients24h: 1, totalDMs1h: 1 }
    );

    await checkBehavioralSignals("adult-uid", "minor-uid");

    // Batch set should have been called with severity = "critical"
    expect(mockBatch.set).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ severity: "critical" })
    );
  });

  test("does not throw when Firestore get fails gracefully", async () => {
    mockDoc.get.mockRejectedValue(new Error("Firestore unavailable"));

    await expect(checkBehavioralSignals("uid-a", "uid-b")).resolves.toBeUndefined();
  });
});
