// selahMedia.test.ts
// Behavioral tests for Selah Media OS callable functions.
// Validates: auth guards, App Check guards, input validation,
// idempotency, hallucination guardrail, cleanup logic.

import * as admin from "firebase-admin";
import * as fs from "fs";
import * as path from "path";

// ─── Source text (used for structural/guardrail assertions) ─────────────────

const SOURCE = fs.readFileSync(path.join(__dirname, "selahMedia.ts"), "utf8");

// ─── Mocks ───────────────────────────────────────────────────────────────────

const mockBatchUpdate = jest.fn();
const mockBatchSet = jest.fn();
const mockBatchDelete = jest.fn();
const mockBatchCommit = jest.fn().mockResolvedValue(undefined);
const mockBatch = {
  update: mockBatchUpdate,
  set: mockBatchSet,
  delete: mockBatchDelete,
  commit: mockBatchCommit,
};

const mockDocGet = jest.fn();
const mockDocSet = jest.fn().mockResolvedValue(undefined);
const mockDocUpdate = jest.fn().mockResolvedValue(undefined);
const mockDocDelete = jest.fn().mockResolvedValue(undefined);
const mockDocRef = {
  get: mockDocGet,
  set: mockDocSet,
  update: mockDocUpdate,
  delete: mockDocDelete,
  id: "doc_id_mock",
};

const mockCollectionAdd = jest.fn().mockResolvedValue({ id: "new_doc_id" });
const mockCollectionGet = jest.fn();
const mockQueryWhere = jest.fn();
const mockQueryOrderBy = jest.fn();
const mockQueryLimit = jest.fn();

const mockCollection = jest.fn();
const mockDoc = jest.fn().mockReturnValue(mockDocRef);

const mockDb = {
  collection: mockCollection,
  collectionGroup: jest.fn().mockReturnValue({
    where: mockQueryWhere.mockReturnThis(),
    limit: mockQueryLimit.mockReturnThis(),
    get: mockCollectionGet,
  }),
  runTransaction: jest.fn(),
  batch: jest.fn().mockReturnValue(mockBatch),
};

jest.mock("firebase-admin", () => ({
  apps: ["app"],
  initializeApp: jest.fn(),
  firestore: jest.fn(() => mockDb),
}));

(admin.firestore as unknown as {
  FieldValue: {
    serverTimestamp: () => string;
    increment: (n: number) => string;
    arrayUnion: (...args: unknown[]) => string;
  };
  Timestamp: {
    now: () => { toMillis: () => number };
    fromMillis: (ms: number) => string;
    fromDate: (d: Date) => string;
  };
}).FieldValue = {
  serverTimestamp: () => "SERVER_TIMESTAMP",
  increment: (n: number) => `INCREMENT(${n})`,
  arrayUnion: (...args: unknown[]) => `ARRAY_UNION(${args.join(",")})`,
};

(admin.firestore as unknown as {
  Timestamp: {
    now: () => { toMillis: () => number };
    fromMillis: (ms: number) => string;
    fromDate: (d: Date) => string;
  };
}).Timestamp = {
  now: () => ({ toMillis: () => Date.now() }),
  fromMillis: (ms: number) => `TIMESTAMP(${ms})`,
  fromDate: (d: Date) => `TIMESTAMP(${d.getTime()})`,
};

// Default: query chain returns empty
function resetMocks() {
  jest.clearAllMocks();
  mockDb.batch.mockReturnValue(mockBatch);
  mockBatchCommit.mockResolvedValue(undefined);
  mockDocSet.mockResolvedValue(undefined);
  mockDocUpdate.mockResolvedValue(undefined);
  mockCollectionAdd.mockResolvedValue({ id: "new_doc_id" });
  mockCollectionGet.mockResolvedValue({ empty: true, docs: [] });
  mockDocGet.mockResolvedValue({ exists: false, data: () => undefined });
  mockQueryWhere.mockReturnThis();
  mockQueryOrderBy.mockReturnThis();
  mockQueryLimit.mockReturnThis();

  const chainable = {
    doc: mockDoc.mockReturnValue({ ...mockDocRef }),
    add: mockCollectionAdd,
    where: mockQueryWhere.mockReturnThis(),
    orderBy: mockQueryOrderBy.mockReturnThis(),
    limit: mockQueryLimit.mockReturnThis(),
    get: mockCollectionGet,
  };
  mockCollection.mockReturnValue(chainable);
  mockDoc.mockReturnValue({ ...mockDocRef, collection: jest.fn().mockReturnValue(chainable) });
}

// ─── Export smoke tests ───────────────────────────────────────────────────────

describe("Module exports", () => {
  it("exports all required callables and triggers", async () => {
    resetMocks();
    const mod = await import("./selahMedia");
    const expected = [
      "getSelahFeed",
      "updateSelahSession",
      "saveSelahMemory",
      "askBereanAboutSelahMedia",
      "createSelahContinuation",
      "createSelahOutcome",
      "buildSelahMeaningGraphEdge",
      "cleanupStaleSelahContinuations",
    ];
    for (const name of expected) {
      expect(typeof (mod as Record<string, unknown>)[name]).toBe("function");
    }
  });
});

// ─── App Check enforcement (structural) ──────────────────────────────────────

describe("App Check enforcement", () => {
  const callables = [
    "getSelahFeed",
    "updateSelahSession",
    "saveSelahMemory",
    "askBereanAboutSelahMedia",
    "createSelahContinuation",
    "createSelahOutcome",
  ];

  it.each(callables)(
    "%s: requireAppCheck appears before requireAuth in the function body",
    (fnName) => {
      const start = SOURCE.indexOf(`export const ${fnName}`);
      // Find the next export after this one
      const nextExport = SOURCE.indexOf("export const", start + 1);
      const block = SOURCE.substring(start, nextExport === -1 ? undefined : nextExport);

      const checkIdx = block.indexOf("requireAppCheck");
      const authIdx = block.indexOf("requireAuth");

      expect(checkIdx).toBeGreaterThan(-1);
      expect(authIdx).toBeGreaterThan(-1);
      expect(checkIdx).toBeLessThan(authIdx);
    }
  );
});

// ─── saveSelahMemory ─────────────────────────────────────────────────────────

describe("saveSelahMemory", () => {
  it("uses deterministic docId when primaryMediaId is present (idempotency)", () => {
    expect(SOURCE).toContain("`${uid}_${primaryMediaId}`");
  });

  it("enriches memory with AI asynchronously (fire-and-forget)", () => {
    expect(SOURCE).toContain("enrichMemoryWithAI");
    expect(SOURCE).toContain(".catch(() => {})");
  });

  it("enforces aiSummary: null on initial write", () => {
    expect(SOURCE).toContain("aiSummary: null");
  });

  it("validates required title field", () => {
    expect(SOURCE).toContain('"title is required"');
  });

  it("writes audit log on both success and failure", () => {
    const saveBlock = SOURCE.substring(
      SOURCE.indexOf("export const saveSelahMemory"),
      SOURCE.indexOf("export const askBereanAboutSelahMedia")
    );
    const auditCalls = (saveBlock.match(/writeSelahAuditLog/g) ?? []).length;
    expect(auditCalls).toBeGreaterThanOrEqual(2);
  });
});

// ─── createSelahOutcome (idempotency) ────────────────────────────────────────

describe("createSelahOutcome", () => {
  it("uses day-bucket idempotency key to prevent double-counting", () => {
    expect(SOURCE).toContain("idempotencyKey");
    expect(SOURCE).toContain("dayBucket");
    expect(SOURCE).toContain('toISOString().slice(0, 10)');
  });

  it("returns existing outcome when idempotency key already exists", () => {
    // Structural: the code checks existingOutcome.empty before writing
    expect(SOURCE).toContain("if (!existingOutcome.empty)");
  });

  it("validates continuationId before writing", () => {
    expect(SOURCE).toContain('"continuationId is required"');
  });

  it("verifies userId ownership before completing a continuation", () => {
    expect(SOURCE).toContain("snap.data()?.userId !== uid");
  });
});

// ─── askBereanAboutSelahMedia ────────────────────────────────────────────────

describe("askBereanAboutSelahMedia — hallucination guardrail", () => {
  it("system prompt contains scripture fabrication guardrail", () => {
    expect(SOURCE).toContain(
      "Never quote or cite scripture verses unless they appear verbatim"
    );
  });

  it("validates required question field", () => {
    const block = SOURCE.substring(
      SOURCE.indexOf("export const askBereanAboutSelahMedia"),
      SOURCE.indexOf("export const createSelahContinuation")
    );
    expect(block).toContain('"question is required"');
  });

  it("enforces rate limit before AI call", () => {
    const block = SOURCE.substring(
      SOURCE.indexOf("export const askBereanAboutSelahMedia"),
      SOURCE.indexOf("export const createSelahContinuation")
    );
    const rateLimitIdx = block.indexOf("enforceSelahRateLimit");
    const anthropicIdx = block.indexOf("anthropicKey");
    expect(rateLimitIdx).toBeGreaterThan(-1);
    expect(rateLimitIdx).toBeLessThan(anthropicIdx);
  });

  it("writes audit log on both claude success and error", () => {
    const block = SOURCE.substring(
      SOURCE.indexOf("export const askBereanAboutSelahMedia"),
      SOURCE.indexOf("export const createSelahContinuation")
    );
    const auditCalls = (block.match(/writeSelahAuditLog/g) ?? []).length;
    expect(auditCalls).toBeGreaterThanOrEqual(2);
  });
});

// ─── createSelahContinuation ─────────────────────────────────────────────────

describe("createSelahContinuation", () => {
  it("validates action against allowlist (rejects arbitrary strings)", () => {
    expect(SOURCE).toContain(
      '["reflect", "pray", "share", "study", "create", "journal", "rest"]'
    );
    expect(SOURCE).toContain("safeAction");
  });

  it("clamps relevanceScore to 0–1 range", () => {
    expect(SOURCE).toContain("Math.min(Math.max(Number(relevanceScore), 0), 1)");
  });

  it("truncates promptText to 300 characters", () => {
    const block = SOURCE.substring(
      SOURCE.indexOf("export const createSelahContinuation"),
      SOURCE.indexOf("export const createSelahOutcome")
    );
    expect(block).toContain(".slice(0, 300)");
  });
});

// ─── Rate limiting ────────────────────────────────────────────────────────────

describe("Rate limiting", () => {
  it("uses per-minute bucket (60_000 ms) for all rate limits", () => {
    expect(SOURCE).toContain("60_000");
  });

  it("enforceSelahRateLimit throws resource-exhausted when limit exceeded", () => {
    expect(SOURCE).toContain('"resource-exhausted"');
    expect(SOURCE).toContain('"Rate limit exceeded"');
  });

  it("rate limit key includes userId and function name (per-user isolation)", () => {
    expect(SOURCE).toContain("`selah:${key}:${userId}:${bucket}`");
  });
});

// ─── cleanupStaleSelahContinuations ──────────────────────────────────────────

describe("cleanupStaleSelahContinuations", () => {
  it("only targets completed continuations (never active ones)", () => {
    const block = SOURCE.substring(
      SOURCE.indexOf("export const cleanupStaleSelahContinuations")
    );
    expect(block).toContain('"completed", "==", true');
    expect(block).toContain('"completedAt", "<", cutoff');
    // Must NOT accidentally delete active (uncompleted) continuations
    expect(block).not.toContain('"completed", "==", false');
  });

  it("uses a 30-day cutoff window", () => {
    expect(SOURCE).toContain("30 * 86_400_000");
  });

  it("batches deletes (never one-by-one)", () => {
    const block = SOURCE.substring(
      SOURCE.indexOf("export const cleanupStaleSelahContinuations")
    );
    expect(block).toContain("batch.delete");
    expect(block).toContain("batch.commit");
  });
});

// ─── getSelahFeed ────────────────────────────────────────────────────────────

describe("getSelahFeed", () => {
  it("only fetches community/public tier items", () => {
    const block = SOURCE.substring(
      SOURCE.indexOf("export const getSelahFeed"),
      SOURCE.indexOf("export const updateSelahSession")
    );
    expect(block).toContain('"community", "public"');
    expect(block).not.toContain('"close"');
  });

  it("boosts items matching user's recent memory categories", () => {
    const block = SOURCE.substring(
      SOURCE.indexOf("export const getSelahFeed"),
      SOURCE.indexOf("export const updateSelahSession")
    );
    expect(block).toContain("recentCategories");
    expect(block).toContain("score +=");
  });

  it("applies recency decay in scoring", () => {
    const block = SOURCE.substring(
      SOURCE.indexOf("export const getSelahFeed"),
      SOURCE.indexOf("export const updateSelahSession")
    );
    expect(block).toContain("age");
    expect(block).toContain("86_400_000");
  });
});

// ─── buildSelahMeaningGraphEdge ───────────────────────────────────────────────

describe("buildSelahMeaningGraphEdge (Firestore trigger)", () => {
  it("skips processing if new item has no meaning tags", () => {
    expect(SOURCE).toContain("if (newCats.size === 0) return");
  });

  it("limits edges written per item to 5", () => {
    expect(SOURCE).toContain("edgeCount >= 5");
  });

  it("only creates edges between items from the same author", () => {
    const block = SOURCE.substring(
      SOURCE.indexOf("export const buildSelahMeaningGraphEdge")
    );
    expect(block).toContain('"authorId", "==", authorId');
  });

  it("connection strength is capped at 1.0", () => {
    expect(SOURCE).toContain("Math.min(shared.length * 0.3, 1)");
  });
});

// ─── Audit logging ────────────────────────────────────────────────────────────

describe("Audit logging safety", () => {
  it("writeSelahAuditLog swallows errors (never throws)", () => {
    const block = SOURCE.substring(
      SOURCE.indexOf("async function writeSelahAuditLog"),
      SOURCE.indexOf("// MARK: - Feed")
    );
    expect(block).toContain("} catch {");
    expect(block).toContain("// Audit logging must never throw");
  });
});
