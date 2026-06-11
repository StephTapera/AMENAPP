import * as admin from "firebase-admin";
import {
  bereanPulseFirestoreContract,
  generateBereanPulseDaily,
  generatePulseForUser,
  refreshBereanPulseForCurrentUser,
  refreshBereanPulseForCurrentUserHandler,
  savePulseCard,
  writePulseFeedbackEvent,
} from "./bereanPulse";
import type { BereanPulseEventRecord } from "./bereanPulseEngine";

// Access the shared Firestore mock handles exposed by the firebase-admin mock.
// These objects are shared across all Firestore calls in the module under test.
// eslint-disable-next-line @typescript-eslint/no-require-imports
const adminMock = require("firebase-admin");
const mockBatch = adminMock.__mockBatch as { commit: jest.Mock; set: jest.Mock; delete: jest.Mock };
const mockDoc = adminMock.__mockDoc as { get: jest.Mock; set: jest.Mock; collection: jest.Mock; __data: unknown };
const mockCollection = adminMock.__mockCollection as { get: jest.Mock };
const mockQuery = adminMock.__mockQuery as { get: jest.Mock };

function restoreMockDefaults() {
  mockDoc.__data = undefined;
  // Re-establish default implementations after clearAllMocks wipes call counts.
  // clearAllMocks does not reset implementations, but mockResolvedValue/mockImplementation
  // calls from a previous test persist unless explicitly overwritten here.
  mockBatch.commit.mockImplementation(() => Promise.resolve());
  mockDoc.get.mockImplementation(() =>
    Promise.resolve({ data: () => mockDoc.__data, exists: !!mockDoc.__data })
  );
  mockDoc.set.mockImplementation(() => Promise.resolve());
  mockCollection.get.mockImplementation(() =>
    Promise.resolve({ docs: [], empty: true })
  );
  mockQuery.get.mockImplementation(() =>
    Promise.resolve({ docs: [], empty: true })
  );
}

// ---------------------------------------------------------------------------
// Existing contract tests (unchanged)
// ---------------------------------------------------------------------------

describe("Berean Pulse backend contract", () => {
  test("exports callable and scheduled entrypoints", () => {
    expect(refreshBereanPulseForCurrentUser).toBeDefined();
    expect(generateBereanPulseDaily).toBeDefined();
  });

  test("uses the normalized Firestore contract", () => {
    expect(bereanPulseFirestoreContract.rootCollection).toBe("bereanPulse");
    expect(bereanPulseFirestoreContract.rootDocument).toBe("main");
    expect(bereanPulseFirestoreContract.daysCollection).toBe("days");
    expect(bereanPulseFirestoreContract.cardsCollection).toBe("cards");
    expect(bereanPulseFirestoreContract.preferencesCollection).toBe("preferences");
    expect(bereanPulseFirestoreContract.permissionsCollection).toBe("permissions");
    expect(bereanPulseFirestoreContract.singletonDocument).toBe("main");
    expect(bereanPulseFirestoreContract.eventsCollection).toBe("events");
    expect(bereanPulseFirestoreContract.savedCardsCollection).toBe("savedCards");
  });
});

// ---------------------------------------------------------------------------
// P0-1 / P0-2 / P0-3 — Callable execution gates
// ---------------------------------------------------------------------------

describe("Berean Pulse callable — execution gates", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    restoreMockDefaults();
  });

  /**
   * P0-1: Unauthenticated rejection.
   *
   * The callable must throw HttpsError("unauthenticated") when request.auth is
   * absent, and must not touch Firestore at all before that point.
   *
   * app: {} passes requireAppCheck (context.app != undefined) so we isolate the
   * uid check specifically.
   */
  test("P0-1: rejects unauthenticated requests and writes nothing to Firestore", async () => {
    const request = { data: {}, app: {} }; // no auth
    await expect(
      refreshBereanPulseForCurrentUserHandler(request)
    ).rejects.toMatchObject({ code: "unauthenticated" });

    expect(mockBatch.commit).not.toHaveBeenCalled();
    expect(mockDoc.set).not.toHaveBeenCalled();
  });

  /**
   * P0-2: App Check rejection.
   *
   * requireAppCheck() (from trustIntelligence.ts) throws HttpsError("failed-precondition")
   * when context.app == undefined. Providing valid auth but omitting app exercises
   * this guard. No Firestore write should occur before the rejection.
   */
  test("P0-2: rejects requests missing App Check token and writes nothing to Firestore", async () => {
    const request = { data: {}, auth: { uid: "user_1", token: {} } }; // no app
    await expect(
      refreshBereanPulseForCurrentUserHandler(request)
    ).rejects.toMatchObject({ code: "failed-precondition" });

    expect(mockBatch.commit).not.toHaveBeenCalled();
    expect(mockDoc.set).not.toHaveBeenCalled();
  });

  /**
   * P0-3: Firestore write failure propagation.
   *
   * generatePulseForUser catches batch.commit() failures, logs them, and re-throws.
   * The error must not be silently swallowed. Verified by asserting the promise
   * rejects with the original error message and that commit was actually called.
   */
  test("P0-3: propagates Firestore batch commit failure — error is not swallowed", async () => {
    const writeError = new Error("Firestore batch commit rejected");
    mockBatch.commit.mockRejectedValueOnce(writeError);

    await expect(
      generatePulseForUser("user_1", "2026-01-01")
    ).rejects.toThrow("Firestore batch commit rejected");

    // Confirm commit was called exactly once (not retried or skipped)
    expect(mockBatch.commit).toHaveBeenCalledTimes(1);
  });
});

// ---------------------------------------------------------------------------
// Rate limit enforcement
// ---------------------------------------------------------------------------

describe("Berean Pulse callable — rate limit enforcement", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    restoreMockDefaults();
  });

  /**
   * A refresh that happened less than 300 seconds ago must block the next call
   * with HttpsError("resource-exhausted"). No card generation (batch.commit)
   * should occur.
   */
  test("blocks manual refresh within the 5-minute cooldown window", async () => {
    const recentTs = admin.firestore.Timestamp.now(); // effectively 0 seconds ago
    // Only the pulse-root rate-limit doc.get() needs the timestamp; subsequent
    // doc.get() calls fall back to the default (returns undefined data).
    mockDoc.get.mockResolvedValueOnce({
      data: () => ({ lastManualRefreshAt: recentTs }),
      exists: true,
    });

    const request = { data: {}, app: {}, auth: { uid: "user_1", token: {} } };
    await expect(
      refreshBereanPulseForCurrentUserHandler(request)
    ).rejects.toMatchObject({ code: "resource-exhausted" });

    expect(mockBatch.commit).not.toHaveBeenCalled();
  });

  /**
   * A refresh that happened more than 300 seconds ago must be allowed through.
   * The callable should return { ok: true } after successfully running generation.
   */
  test("allows manual refresh after the 5-minute cooldown window has passed", async () => {
    const oldTs = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 6 * 60 * 1000) // 6 minutes ago — beyond the 300s window
    );
    // First doc.get() call is the pulse-root cooldown check; subsequent calls
    // (loadPermissions, loadPreferences) fall back to default (undefined data).
    mockDoc.get.mockResolvedValueOnce({
      data: () => ({ lastManualRefreshAt: oldTs }),
      exists: true,
    });

    const request = {
      data: { dateKey: "2026-01-01" },
      app: {},
      auth: { uid: "user_1", token: {} },
    };
    const result = await refreshBereanPulseForCurrentUserHandler(request);
    expect(result).toMatchObject({ ok: true, dateKey: "2026-01-01", cardCount: 0 });
  });
});

// ---------------------------------------------------------------------------
// Helper write path correctness
// ---------------------------------------------------------------------------

describe("Berean Pulse helper write paths", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    restoreMockDefaults();
  });

  /**
   * savePulseCard must forward the payload to the savedCards subcollection
   * document with merge:true semantics.
   */
  test("savePulseCard writes payload with merge:true to the savedCards path", async () => {
    const ts = admin.firestore.Timestamp.now();
    const payload = { cardId: "card_42", savedAt: ts };

    await savePulseCard("user_1", "card_42", payload);

    expect(mockDoc.set).toHaveBeenCalledTimes(1);
    expect(mockDoc.set).toHaveBeenCalledWith(payload, { merge: true });
  });

  /**
   * writePulseFeedbackEvent must write the full event record to the events
   * subcollection document with merge:true semantics, keyed by event.id.
   */
  test("writePulseFeedbackEvent writes event record with merge:true to the events path", async () => {
    const ts = admin.firestore.Timestamp.now();
    const event: BereanPulseEventRecord = {
      id: "evt_feedback_1",
      cardId: "card_1",
      eventType: "liked",
      mode: "learning",
      metadata: { topicKey: "savedPost:post_1" },
      timestamp: ts,
    };

    await writePulseFeedbackEvent("user_1", event);

    expect(mockDoc.set).toHaveBeenCalledTimes(1);
    expect(mockDoc.set).toHaveBeenCalledWith(event, { merge: true });
  });
});

// ---------------------------------------------------------------------------
// dateKey handling
// ---------------------------------------------------------------------------

describe("Berean Pulse callable — dateKey handling", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    restoreMockDefaults();
  });

  /**
   * When request.data.dateKey is not a string (e.g. a number), the callable
   * must silently fall back to today's date rather than passing the invalid
   * value to Firestore or throwing.
   *
   * NOTE: The current implementation does not reject malformed dateKeys — it
   * normalises them. This test documents that behaviour so a future hardening
   * of input validation does not silently regress the fallback.
   */
  test("falls back to today YYYY-MM-DD when dateKey is not a string", async () => {
    const request = {
      data: { dateKey: 99999 }, // number — not a string
      app: {},
      auth: { uid: "user_1", token: {} },
    };
    const result = await refreshBereanPulseForCurrentUserHandler(request);

    expect(result).toMatchObject({ ok: true });
    expect(result.dateKey).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(result.dateKey).not.toBe("99999");
  });
});
