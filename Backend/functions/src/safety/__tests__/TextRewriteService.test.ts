/**
 * TextRewriteService.test.ts
 *
 * Tests for rate limiting, Claude fallback, privacy guarantees,
 * and suggestion trimming.
 *
 * Mocks: firebase-admin (db), firebase-functions/v2/https, axios (via jest.mock)
 */

// Intercept axios before importing the service
jest.mock("axios");
import axios from "axios";
const mockedAxios = axios as jest.Mocked<typeof axios>;

import admin from "firebase-admin";

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
  get: jest.Mock;
};

// ─── Helpers ─────────────────────────────────────────────────────────────────

/** Build a callable request context. */
function makeRequest(data: Record<string, unknown>, uid = "uid-user-1") {
  return { auth: { uid, token: {} }, data } as any;
}

/** Build an Axios-style Claude success response with a JSON body. */
function claudeSuccessResponse(body: object) {
  return {
    data: {
      content: [{ type: "text", text: JSON.stringify(body) }],
    },
  };
}

/**
 * Set the rate-limit window mock so that n calls have already been consumed.
 * The transaction handler reads `snap` and checks count vs maxCalls.
 */
function setupRateLimit(existingCount: number, windowEndInFuture = true) {
  const now = Date.now();
  const windowEnd = windowEndInFuture ? now + 3_600_000 : now - 1;
  mockDoc.get.mockResolvedValue({
    exists: existingCount > 0,
    data: () =>
      existingCount > 0
        ? { count: existingCount, windowEnd, uid: "uid-user-1" }
        : undefined,
  });
  (admin.firestore() as any).runTransaction.mockImplementation(
    (handler: (tx: any) => Promise<void>) =>
      handler({ get: mockDoc.get, set: mockDoc.set, update: mockDoc.update, delete: mockDoc.delete })
  );
}

function resetMocks() {
  jest.clearAllMocks();
  mockDoc.__data = undefined;
  // Default: rate limit window is empty (0 calls)
  setupRateLimit(0);
  // Default: Claude returns 2 suggestions
  mockedAxios.post.mockResolvedValue(
    claudeSuccessResponse({
      suggestions: ["Option 1", "Option 2"],
      rationale: "Your message could be kinder.",
    })
  );
  // Default: audit log add succeeds
  mockCollection.add.mockResolvedValue({ id: "log-id" });
}

// ─── Import service under test ────────────────────────────────────────────────

import {
  requestTextRewrite as _requestTextRewrite,
  getToneCheckSuggestion as _getToneCheckSuggestion,
  suggestRewrite,
} from "../TextRewriteService";

// onCall exports are handler functions at runtime; unwrap type for tests.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const requestTextRewrite = _requestTextRewrite as unknown as (req: any) => Promise<any>;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const getToneCheckSuggestion = _getToneCheckSuggestion as unknown as (req: any) => Promise<any>;

// ─── Tests ────────────────────────────────────────────────────────────────────

describe("requestTextRewrite callable", () => {
  beforeEach(() => resetMocks());

  const validData = {
    text: "You are completely wrong about everything.",
    harmCategoryId: "harassment",
    contentType: "post",
  };

  test("throws unauthenticated when no auth", async () => {
    await expect(
      requestTextRewrite({ auth: null, data: validData } as any)
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("throws invalid-argument when text is empty", async () => {
    await expect(
      requestTextRewrite(makeRequest({ ...validData, text: "" }))
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("throws invalid-argument when harmCategoryId exceeds 50 chars", async () => {
    await expect(
      requestTextRewrite(
        makeRequest({ ...validData, harmCategoryId: "x".repeat(51) })
      )
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("returns fallback when Claude API unavailable (axios throws)", async () => {
    process.env.ANTHROPIC_API_KEY = "test-key";
    mockedAxios.post.mockRejectedValue(new Error("Network error"));

    const result = await requestTextRewrite(makeRequest(validData));

    expect(result.suggestions).toEqual([]);
    expect(result.rationale).toContain("unable to generate");
    expect(result.harmCategoryId).toBe("harassment");
    delete process.env.ANTHROPIC_API_KEY;
  });

  test("returns fallback when ANTHROPIC_API_KEY is not set", async () => {
    delete process.env.ANTHROPIC_API_KEY;

    const result = await requestTextRewrite(makeRequest(validData));

    expect(result.suggestions).toEqual([]);
    expect(result.rationale).toBeDefined();
  });

  test("original text is NOT written to Firestore (audit log omits text)", async () => {
    process.env.ANTHROPIC_API_KEY = "test-key";

    await requestTextRewrite(makeRequest(validData));

    // Every call to collection().add() must NOT contain the original text
    const addCalls: unknown[][] = mockCollection.add.mock.calls;
    for (const [payload] of addCalls) {
      const p = payload as Record<string, unknown>;
      expect(JSON.stringify(p)).not.toContain(validData.text);
    }
    delete process.env.ANTHROPIC_API_KEY;
  });

  test("suggestions trimmed to max 2 even if Claude returns more", async () => {
    process.env.ANTHROPIC_API_KEY = "test-key";
    mockedAxios.post.mockResolvedValue(
      claudeSuccessResponse({
        suggestions: ["A", "B", "C", "D"],
        rationale: "reason",
      })
    );

    const result = await requestTextRewrite(makeRequest(validData));

    expect(result.suggestions.length).toBeLessThanOrEqual(2);
    delete process.env.ANTHROPIC_API_KEY;
  });

  test("rate limit: 11th request in same hour returns resource-exhausted", async () => {
    // Simulate 10 calls already consumed in the current window
    setupRateLimit(10);

    await expect(requestTextRewrite(makeRequest(validData))).rejects.toMatchObject({
      code: "resource-exhausted",
    });
  });

  test("rate limit resets after window expires", async () => {
    process.env.ANTHROPIC_API_KEY = "test-key";
    // Window has expired (windowEnd in the past)
    setupRateLimit(10, false);

    // Should NOT throw — window expired, count resets to 0
    const result = await requestTextRewrite(makeRequest(validData));
    expect(result).toBeDefined();
    delete process.env.ANTHROPIC_API_KEY;
  });

  test("harmCategoryId is echoed back in the response", async () => {
    process.env.ANTHROPIC_API_KEY = "test-key";
    const result = await requestTextRewrite(makeRequest(validData));
    expect(result.harmCategoryId).toBe("harassment");
    delete process.env.ANTHROPIC_API_KEY;
  });
});

describe("getToneCheckSuggestion callable", () => {
  beforeEach(() => resetMocks());

  test("throws unauthenticated when no auth", async () => {
    await expect(
      getToneCheckSuggestion({ auth: null, data: { text: "hello", contentType: "post" } } as any)
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("returns null suggestion when Claude is unavailable", async () => {
    delete process.env.ANTHROPIC_API_KEY;

    const result = await getToneCheckSuggestion(
      makeRequest({ text: "Some text here", contentType: "post" })
    );

    expect(result.suggestion).toBeNull();
    expect(result.reason).toBeNull();
  });

  test("returns null when Claude returns null fields", async () => {
    process.env.ANTHROPIC_API_KEY = "test-key";
    mockedAxios.post.mockResolvedValue(
      claudeSuccessResponse({ suggestion: null, reason: null })
    );

    const result = await getToneCheckSuggestion(
      makeRequest({ text: "This is fine, thank you!", contentType: "post" })
    );

    expect(result.suggestion).toBeNull();
    expect(result.reason).toBeNull();
    delete process.env.ANTHROPIC_API_KEY;
  });

  test("returns suggestion when Claude provides one", async () => {
    process.env.ANTHROPIC_API_KEY = "test-key";
    mockedAxios.post.mockResolvedValue(
      claudeSuccessResponse({
        suggestion: "Perhaps say: 'I respectfully disagree'",
        reason: "The original could come across as dismissive.",
      })
    );

    const result = await getToneCheckSuggestion(
      makeRequest({ text: "You are completely wrong.", contentType: "comment" })
    );

    expect(result.suggestion).toBe("Perhaps say: 'I respectfully disagree'");
    expect(result.reason).toBeDefined();
    delete process.env.ANTHROPIC_API_KEY;
  });

  test("normalises to both-null when suggestion provided but reason is null", async () => {
    process.env.ANTHROPIC_API_KEY = "test-key";
    mockedAxios.post.mockResolvedValue(
      claudeSuccessResponse({ suggestion: "Better phrasing", reason: null })
    );

    const result = await getToneCheckSuggestion(
      makeRequest({ text: "Some text", contentType: "post" })
    );

    expect(result.suggestion).toBeNull();
    expect(result.reason).toBeNull();
    delete process.env.ANTHROPIC_API_KEY;
  });

  test("returns graceful fallback when Claude JSON is unparseable", async () => {
    process.env.ANTHROPIC_API_KEY = "test-key";
    mockedAxios.post.mockResolvedValue({
      data: { content: [{ type: "text", text: "not-valid-json{{" }] },
    });

    const result = await getToneCheckSuggestion(
      makeRequest({ text: "Some text", contentType: "post" })
    );

    expect(result.suggestion).toBeNull();
    delete process.env.ANTHROPIC_API_KEY;
  });
});

describe("suggestRewrite (internal helper)", () => {
  beforeEach(() => resetMocks());

  test("returns empty array when text is empty", async () => {
    const result = await suggestRewrite("", "harassment");
    expect(result).toEqual([]);
  });

  test("returns empty array when Claude is unavailable", async () => {
    delete process.env.ANTHROPIC_API_KEY;
    const result = await suggestRewrite("Some text", "harassment");
    expect(result).toEqual([]);
  });

  test("returns suggestions from Claude on success", async () => {
    process.env.ANTHROPIC_API_KEY = "test-key";
    mockedAxios.post.mockResolvedValue(
      claudeSuccessResponse({ suggestions: ["Opt A", "Opt B"], rationale: "reason" })
    );

    const result = await suggestRewrite("Problematic text", "harassment");

    expect(result).toEqual(["Opt A", "Opt B"]);
    delete process.env.ANTHROPIC_API_KEY;
  });

  test("filters out empty string suggestions", async () => {
    process.env.ANTHROPIC_API_KEY = "test-key";
    mockedAxios.post.mockResolvedValue(
      claudeSuccessResponse({ suggestions: ["  ", "Valid option", ""], rationale: "r" })
    );

    const result = await suggestRewrite("Some text", "harassment");

    expect(result).toEqual(["Valid option"]);
    delete process.env.ANTHROPIC_API_KEY;
  });
});
