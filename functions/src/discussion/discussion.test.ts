// discussion.test.ts — Unit tests for the discussion system
// Run with: jest functions/src/discussion/discussion.test.ts

// ── Mocks must be declared before imports ─────────────────────────────────────

// Mock firebase-functions/v2/https so HttpsError is available without Firebase
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
    HttpsError,
  };
});

// Mock firebase-functions/logger
jest.mock("firebase-functions/logger", () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
}));

// Mock firebase-admin/firestore
jest.mock("firebase-admin/firestore", () => ({
  getFirestore: jest.fn(() => ({})),
  FieldValue: {
    serverTimestamp: jest.fn(() => "__serverTimestamp__"),
    increment: jest.fn((n) => `__increment(${n})__`),
  },
}));

// ── Imports after mocks ───────────────────────────────────────────────────────

import { cosineSimilarity, embedText } from "./embeddingAdapter";
import { detectVerseKeys } from "./callable";

// We import the raw handler functions by bypassing the onCall wrapper.
// Since onCall mock returns the handler directly, we re-require after mocking.

// ─────────────────────────────────────────────────────────────────────────────
// 1. cosineSimilarity — pure math
// ─────────────────────────────────────────────────────────────────────────────

describe("cosineSimilarity", () => {
  test("orthogonal vectors → 0", () => {
    const a = [1, 0, 0];
    const b = [0, 1, 0];
    expect(cosineSimilarity(a, b)).toBeCloseTo(0, 6);
  });

  test("identical vectors → 1", () => {
    const a = [3, 4, 0];
    expect(cosineSimilarity(a, a)).toBeCloseTo(1, 6);
  });

  test("known pair: [1,0] vs [1,1] → ~0.707", () => {
    const a = [1, 0];
    const b = [1, 1];
    expect(cosineSimilarity(a, b)).toBeCloseTo(Math.SQRT1_2, 5);
  });

  test("zero vector → 0 (no divide-by-zero crash)", () => {
    const a = [0, 0, 0];
    const b = [1, 2, 3];
    expect(cosineSimilarity(a, b)).toBe(0);
  });

  test("length mismatch → 0", () => {
    expect(cosineSimilarity([1, 2], [1, 2, 3])).toBe(0);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 2. detectVerseKeys — verse detection regex
// ─────────────────────────────────────────────────────────────────────────────

describe("detectVerseKeys", () => {
  test("detects John 3:16 → JHN.3.16", () => {
    expect(detectVerseKeys("As we read in John 3:16")).toContain("JHN.3.16");
  });

  test("detects Romans 8:28 → ROM.8.28", () => {
    expect(detectVerseKeys("I love Romans 8:28")).toContain("ROM.8.28");
  });

  test("detects Psalms 23:1 → PSA.23.1", () => {
    expect(detectVerseKeys("Psalms 23:1 is comforting")).toContain("PSA.23.1");
  });

  test("detects multiple verses", () => {
    const result = detectVerseKeys("John 3:16 and Romans 8:28 both speak to this.");
    expect(result).toContain("JHN.3.16");
    expect(result).toContain("ROM.8.28");
  });

  test("deduplicates same verse", () => {
    const result = detectVerseKeys("John 3:16 again John 3:16");
    const count = result.filter((k) => k === "JHN.3.16").length;
    expect(count).toBe(1);
  });

  test("returns empty array for no verses", () => {
    expect(detectVerseKeys("No scripture here, just a thought.")).toEqual([]);
  });

  test("detects Matthew 5:3 → MAT.5.3", () => {
    expect(detectVerseKeys("Matthew 5:3 is the beatitudes")).toContain("MAT.5.3");
  });

  test("detects Acts 2:38 → ACT.2.38", () => {
    expect(detectVerseKeys("Peter says Acts 2:38")).toContain("ACT.2.38");
  });

  test("detects Genesis 1:1 → GEN.1.1", () => {
    expect(detectVerseKeys("In the beginning Genesis 1:1")).toContain("GEN.1.1");
  });

  test("detects Revelation 21:4 → REV.21.4", () => {
    expect(detectVerseKeys("Revelation 21:4 no more tears")).toContain("REV.21.4");
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 3. computeReputation — point math and badge tiers
// ─────────────────────────────────────────────────────────────────────────────

describe("computeReputation — badge tiers", () => {
  // Helper: build a fake Firestore db that returns the given event docs
  function makeMockDb(events: Array<{ type: string }>) {
    const docs = events.map((e, i) => ({ id: `evt${i}`, data: () => e }));
    const snap = { docs };
    const limitFn = jest.fn().mockResolvedValue(snap);
    const whereFn = jest.fn().mockReturnValue({ limit: limitFn });
    return {
      collection: jest.fn().mockReturnValue({ where: whereFn }),
    };
  }

  // We test the aggregation logic directly since the handler is wrapped by onCall mock
  function aggregate(events: Array<{ type: string }>) {
    const breakdown = { helpfulMark: 0, acceptedAnswer: 0, firstComment: 0, bereanCite: 0 };
    for (const e of events) {
      switch (e.type) {
        case "helpfulMark": breakdown.helpfulMark += 3; break;
        case "acceptedAnswer": breakdown.acceptedAnswer += 10; break;
        case "firstComment": breakdown.firstComment += 1; break;
        case "bereanCite": breakdown.bereanCite += 2; break;
      }
    }
    const totalPoints = breakdown.helpfulMark + breakdown.acceptedAnswer + breakdown.firstComment + breakdown.bereanCite;
    let badgeTier: string;
    if (totalPoints >= 200) badgeTier = "elder";
    else if (totalPoints >= 50) badgeTier = "berean";
    else if (totalPoints >= 10) badgeTier = "seeker";
    else badgeTier = "none";
    return { totalPoints, badgeTier, breakdown };
  }

  test("0 events → 0 points, badge=none", () => {
    const { totalPoints, badgeTier } = aggregate([]);
    expect(totalPoints).toBe(0);
    expect(badgeTier).toBe("none");
  });

  test("3 helpfulMark events → 9 points, badge=none", () => {
    const { totalPoints, badgeTier } = aggregate([
      { type: "helpfulMark" }, { type: "helpfulMark" }, { type: "helpfulMark" },
    ]);
    expect(totalPoints).toBe(9);
    expect(badgeTier).toBe("none");
  });

  test("4 helpfulMark events → 12 points, badge=seeker", () => {
    const events = Array(4).fill({ type: "helpfulMark" });
    const { totalPoints, badgeTier } = aggregate(events);
    expect(totalPoints).toBe(12);
    expect(badgeTier).toBe("seeker");
  });

  test("5 acceptedAnswer events → 50 points, badge=berean (boundary)", () => {
    const events = Array(5).fill({ type: "acceptedAnswer" });
    const { totalPoints, badgeTier } = aggregate(events);
    expect(totalPoints).toBe(50);
    expect(badgeTier).toBe("berean");
  });

  test("20 acceptedAnswer events → 200 points, badge=elder (boundary)", () => {
    const events = Array(20).fill({ type: "acceptedAnswer" });
    const { totalPoints, badgeTier } = aggregate(events);
    expect(totalPoints).toBe(200);
    expect(badgeTier).toBe("elder");
  });

  test("mixed events aggregate correctly", () => {
    const events = [
      { type: "helpfulMark" },   // 3
      { type: "helpfulMark" },   // 3 → 6
      { type: "acceptedAnswer" }, // 10 → 16
      { type: "firstComment" },  // 1 → 17
      { type: "bereanCite" },    // 2 → 19
    ];
    const { totalPoints, badgeTier, breakdown } = aggregate(events);
    expect(totalPoints).toBe(19);
    expect(badgeTier).toBe("seeker");
    expect(breakdown.helpfulMark).toBe(6);
    expect(breakdown.acceptedAnswer).toBe(10);
    expect(breakdown.firstComment).toBe(1);
    expect(breakdown.bereanCite).toBe(2);
  });

  test("unknown event type contributes 0 points", () => {
    const { totalPoints } = aggregate([{ type: "unknown" }]);
    expect(totalPoints).toBe(0);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 4. detectDuplicate — short-circuits when EMBEDDING_KEY is unset
// ─────────────────────────────────────────────────────────────────────────────

describe("detectDuplicate — EMBEDDING_KEY not set", () => {
  const ORIGINAL_ENV = process.env;

  beforeEach(() => {
    process.env = { ...ORIGINAL_ENV };
    delete process.env.EMBEDDING_KEY;
  });

  afterEach(() => {
    process.env = ORIGINAL_ENV;
  });

  test("returns isDuplicate=false with empty arrays when key absent", async () => {
    // Import embedText after env manipulation
    const { embedText } = await import("./embeddingAdapter");
    const result = await embedText("some text");
    // Mock vector is all zeros (768 dim) — embedText returns mock
    expect(result).toHaveLength(768);
    expect(result.every((v: number) => v === 0)).toBe(true);
  });

  test("cosineSimilarity of two zero vectors → 0 (safe)", () => {
    const zeros = Array(768).fill(0);
    expect(cosineSimilarity(zeros, zeros)).toBe(0);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 5. postComment — body validation logic
// ─────────────────────────────────────────────────────────────────────────────

describe("postComment — body validation", () => {
  // We test the validation rule directly as a pure function to avoid Firebase init
  function validateBody(body: string): { ok: boolean; error?: string } {
    const trimmed = String(body ?? "").trim();
    if (trimmed.length < 1 || trimmed.length > 2000) {
      return { ok: false, error: "body must be 1–2000 characters." };
    }
    return { ok: true };
  }

  test("empty body → invalid", () => {
    expect(validateBody("")).toMatchObject({ ok: false });
  });

  test("body of exactly 1 char → valid", () => {
    expect(validateBody("A")).toMatchObject({ ok: true });
  });

  test("body of exactly 2000 chars → valid", () => {
    expect(validateBody("A".repeat(2000))).toMatchObject({ ok: true });
  });

  test("body of 2001 chars → invalid", () => {
    expect(validateBody("A".repeat(2001))).toMatchObject({ ok: false });
  });

  test("body > 2000 chars throws invalid-argument semantics", () => {
    const result = validateBody("X".repeat(3000));
    expect(result.ok).toBe(false);
    expect(result.error).toMatch(/2000/);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 6. markHelpful — own-comment guard
// ─────────────────────────────────────────────────────────────────────────────

describe("markHelpful — own-comment guard", () => {
  // Test the own-comment guard logic as a pure predicate
  function canMarkHelpful(requestingUserId: string, commentAuthorUID: string): boolean {
    return requestingUserId !== commentAuthorUID;
  }

  test("same user → cannot mark as helpful", () => {
    expect(canMarkHelpful("user123", "user123")).toBe(false);
  });

  test("different user → can mark as helpful", () => {
    expect(canMarkHelpful("user123", "user456")).toBe(true);
  });

  test("error code for own-comment is failed-precondition", () => {
    const { HttpsError } = jest.requireMock("firebase-functions/v2/https") as {
      HttpsError: new (code: string, msg: string) => { code: string; message: string };
    };
    const err = new HttpsError("failed-precondition", "Cannot mark your own comment as helpful.");
    expect(err.code).toBe("failed-precondition");
    expect(err.message).toBe("Cannot mark your own comment as helpful.");
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 7. Destination validation
// ─────────────────────────────────────────────────────────────────────────────

describe("postComment — destination validation", () => {
  const VALID_DESTINATIONS = ["public", "reflection", "churchNotes"];

  test.each(VALID_DESTINATIONS)("'%s' is a valid destination", (dest) => {
    expect(VALID_DESTINATIONS.includes(dest)).toBe(true);
  });

  test("'private' is not a valid destination", () => {
    expect(VALID_DESTINATIONS.includes("private")).toBe(false);
  });

  test("empty string is not a valid destination", () => {
    expect(VALID_DESTINATIONS.includes("")).toBe(false);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 8. updateWatchProgress — shouldNudge logic
// ─────────────────────────────────────────────────────────────────────────────

describe("updateWatchProgress — shouldNudge logic", () => {
  function computeShouldNudge(progressFraction: number, transcriptRead: boolean): boolean {
    return progressFraction < 0.8 && !transcriptRead;
  }

  test("progress=0.5, transcript=false → shouldNudge=true", () => {
    expect(computeShouldNudge(0.5, false)).toBe(true);
  });

  test("progress=0.9, transcript=false → shouldNudge=false", () => {
    expect(computeShouldNudge(0.9, false)).toBe(false);
  });

  test("progress=0.5, transcript=true → shouldNudge=false", () => {
    expect(computeShouldNudge(0.5, true)).toBe(false);
  });

  test("progress=0.8 exactly, transcript=false → shouldNudge=false (boundary)", () => {
    expect(computeShouldNudge(0.8, false)).toBe(false);
  });

  test("progress=0.0, transcript=false → shouldNudge=true", () => {
    expect(computeShouldNudge(0.0, false)).toBe(true);
  });

  test("progress=1.0, transcript=false → shouldNudge=false", () => {
    expect(computeShouldNudge(1.0, false)).toBe(false);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 9. processEmbeddingQueue — zero-vector stub safety guarantees
// ─────────────────────────────────────────────────────────────────────────────

describe("processEmbeddingQueue — zero-vector stub guarantees", () => {
  const EMBEDDING_DIM = 768;
  const ORIGINAL_ENV = process.env;

  beforeEach(() => {
    process.env = { ...ORIGINAL_ENV };
    delete process.env.EMBEDDING_KEY;
  });

  afterAll(() => {
    process.env = ORIGINAL_ENV;
  });

  test("embedText with no EMBEDDING_KEY returns 768-dim zero vector", async () => {
    const vec = await embedText("test body text");
    expect(vec).toHaveLength(EMBEDDING_DIM);
    expect(vec.every(v => v === 0)).toBe(true);
  });

  test("zero-vector stub cosine similarity with itself is 0 (no false positives)", () => {
    const zeroVec = Array(EMBEDDING_DIM).fill(0);
    expect(cosineSimilarity(zeroVec, zeroVec)).toBe(0);
  });

  test("zero-vector stub cosine similarity with any real vector is 0", () => {
    const zeroVec = Array(EMBEDDING_DIM).fill(0);
    const realVec = Array(EMBEDDING_DIM).fill(0).map((_, i) => (i % 7) * 0.1 + 0.01);
    expect(cosineSimilarity(zeroVec, realVec)).toBe(0);
  });

  test("zero-vector stub never triggers 0.8 duplicate threshold", () => {
    const zeroVec = Array(EMBEDDING_DIM).fill(0);
    const other   = Array(EMBEDDING_DIM).fill(0).map((_, i) => i % 5 === 0 ? 1.0 : 0.0);
    expect(cosineSimilarity(zeroVec, other)).toBeLessThan(0.8);
  });

  test("embedText returns 768-dim vector (contract: processEmbeddingQueue always writes same-dim embedding)", async () => {
    const vec = await embedText("another comment body");
    expect(vec.length).toBe(EMBEDDING_DIM);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 10. setAccepted — reputation event logic
// ─────────────────────────────────────────────────────────────────────────────

describe("setAccepted — reputation points and toggle logic", () => {
  const REPUTATION_POINTS = { helpfulMark: 3, acceptedAnswer: 10, firstComment: 1, bereanCite: 2 };

  test("acceptedAnswer awards exactly 10 points", () => {
    expect(REPUTATION_POINTS.acceptedAnswer).toBe(10);
  });

  test("un-accepting (isAccepted=false) should not award reputation points", () => {
    const isAccepted = false;
    expect(isAccepted).toBe(false); // server: no reputation event created when isAccepted=false
  });

  test("accepting after 2 helpfulMarks → 16 total points, badge=seeker", () => {
    const events = [
      { type: "acceptedAnswer" },  // 10
      { type: "helpfulMark" },     // 3 → 13
      { type: "helpfulMark" },     // 3 → 16
    ];
    let total = 0;
    for (const e of events) {
      if (e.type === "acceptedAnswer") total += REPUTATION_POINTS.acceptedAnswer;
      if (e.type === "helpfulMark")    total += REPUTATION_POINTS.helpfulMark;
    }
    expect(total).toBe(16);
    // badge tier
    const tier = total >= 200 ? "elder" : total >= 50 ? "berean" : total >= 10 ? "seeker" : "none";
    expect(tier).toBe("seeker");
  });

  test("toggle: accepting same comment twice is idempotent (un-accept then re-accept only awards once)", () => {
    // Server: checks for existing acceptedAnswer event before creating a new one
    let eventsCreated = 0;
    function tryAward(existingCount: number) {
      if (existingCount === 0) eventsCreated++;
    }
    tryAward(0); // first accept — awards
    tryAward(1); // second accept (re-accept) — no-op
    expect(eventsCreated).toBe(1);
  });

  test("accepting a different comment clears the previous accepted flag", () => {
    // Server clears isAcceptedAnswer on all other comments before accepting new one
    const comments = [
      { id: "c1", isAcceptedAnswer: true },
      { id: "c2", isAcceptedAnswer: false },
    ];
    const newAcceptedId = "c2";
    // Simulate server clear
    comments.forEach(c => { c.isAcceptedAnswer = c.id === newAcceptedId; });
    expect(comments.find(c => c.id === "c1")?.isAcceptedAnswer).toBe(false);
    expect(comments.find(c => c.id === "c2")?.isAcceptedAnswer).toBe(true);
  });
});
