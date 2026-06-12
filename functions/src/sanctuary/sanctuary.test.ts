jest.mock("firebase-functions/v2/https", () => {
  class HttpsError extends Error {
    public code: string;
    constructor(code: string, message: string) {
      super(message);
      this.code = code;
    }
  }
  return {
    onCall: jest.fn((_, handler) => handler),
    onRequest: jest.fn((_, handler) => handler),
    HttpsError,
  };
});

jest.mock("firebase-functions/v2/scheduler", () => ({
  onSchedule: jest.fn((_, handler) => handler),
}));

jest.mock("firebase-functions/params", () => ({
  defineSecret: jest.fn(() => ({ value: jest.fn(() => "") })),
}));

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn() },
}));

jest.mock("firebase-admin/firestore", () => ({
  getFirestore: jest.fn(() => ({})),
  FieldValue: {
    serverTimestamp: jest.fn(() => "__serverTimestamp__"),
    arrayUnion: jest.fn((...items) => ({ __arrayUnion: items })),
  },
  Timestamp: {
    fromMillis: jest.fn((ms) => ({ ms })),
  },
}));

jest.mock("firebase-admin/auth", () => ({
  getAuth: jest.fn(() => ({ verifyIdToken: jest.fn() })),
}));

jest.mock("firebase-admin/app-check", () => ({
  getAppCheck: jest.fn(() => ({ verifyToken: jest.fn() })),
}));

jest.mock("@google-cloud/speech", () => ({
  SpeechClient: jest.fn(),
}));

import { applyRoomOperation, computeReactionDensity, detectScriptureReferences } from "./index";

describe("Sanctuary scripture detection", () => {
  it("converts explicit references to OSIS", () => {
    const anchors = detectScriptureReferences("John 3:16 and Romans 8:28", 42000);
    expect(anchors).toEqual([
      { verseRef: "JHN.3.16", timestampMs: 42000, confidence: 0.96, source: "ai" },
      { verseRef: "ROM.8.28", timestampMs: 42000, confidence: 0.96, source: "ai" },
    ]);
  });

  it("supports ranges and numbered books", () => {
    const anchors = detectScriptureReferences("1 John 4:7-8");
    expect(anchors[0].verseRef).toBe("1JN.4.7-1JN.4.8");
  });
});

describe("Sanctuary reaction density", () => {
  it("normalizes warmth buckets without exposing counts", () => {
    const buckets = computeReactionDensity([{ timestampMs: 0 }, { timestampMs: 500 }, { timestampMs: 9500 }], 10000, 10);
    expect(buckets[0]).toBe(1);
    expect(buckets[9]).toBe(0.5);
    expect(buckets.reduce((sum, value) => sum + value, 0)).toBeGreaterThan(0);
  });

  it("returns zeros when duration is unavailable", () => {
    expect(computeReactionDensity([{ timestampMs: 10 }], 0, 3)).toEqual([0, 0, 0]);
  });
});

describe("Sanctuary room sync", () => {
  it("joins a member once and applies prayer state", () => {
    const joined = applyRoomOperation({ id: "room", memberOrbs: [], playheadMs: 0, state: "paused" }, { type: "join", member: { uid: "u1" } }, "u1", 1000);
    const prayed = applyRoomOperation(joined, { type: "prayer", playheadMs: 2500 }, "u1", 1100);
    expect(prayed.memberOrbs).toHaveLength(1);
    expect(prayed.state).toBe("prayer");
    expect(prayed.playheadMs).toBe(2500);
  });
});
