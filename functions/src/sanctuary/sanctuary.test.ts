type StoredDoc = Record<string, any>;

const firestoreStore = new Map<string, StoredDoc>();
const mockSecretValues: Record<string, string> = {};

function clone<T>(value: T): T {
  return JSON.parse(JSON.stringify(value));
}

function directChildDocs(collectionPath: string): Array<{ id: string; path: string; data: StoredDoc }> {
  const prefix = `${collectionPath}/`;
  return Array.from(firestoreStore.entries())
    .filter(([path]) => path.startsWith(prefix) && !path.slice(prefix.length).includes("/"))
    .map(([path, data]) => ({ id: path.slice(prefix.length), path, data: clone(data) }));
}

class MockDocumentSnapshot {
  constructor(public id: string, private readonly value: StoredDoc | undefined, public ref: MockDocumentReference) {}
  get exists(): boolean {
    return this.value !== undefined;
  }
  data(): StoredDoc | undefined {
    return this.value ? clone(this.value) : undefined;
  }
}

class MockQuerySnapshot {
  constructor(public docs: MockDocumentSnapshot[]) {}
}

class MockDocumentReference {
  constructor(public path: string) {}
  get id(): string {
    return this.path.split("/").pop() ?? this.path;
  }
  collection(name: string): MockCollectionReference {
    return new MockCollectionReference(`${this.path}/${name}`);
  }
  async get(): Promise<MockDocumentSnapshot> {
    return new MockDocumentSnapshot(this.id, firestoreStore.get(this.path), this);
  }
  async set(data: StoredDoc, options?: { merge?: boolean }): Promise<void> {
    const current = options?.merge ? firestoreStore.get(this.path) ?? {} : {};
    firestoreStore.set(this.path, { ...current, ...clone(data) });
  }
}

class MockCollectionReference {
  private limitCount?: number;
  private orderField?: string;
  private whereClause?: { field: string; op: string; value: any };

  constructor(public path: string) {}

  doc(id = `auto_${firestoreStore.size}_${Date.now()}`): MockDocumentReference {
    return new MockDocumentReference(`${this.path}/${id}`);
  }

  limit(count: number): MockCollectionReference {
    const next = new MockCollectionReference(this.path);
    next.limitCount = count;
    next.orderField = this.orderField;
    next.whereClause = this.whereClause;
    return next;
  }

  orderBy(field: string): MockCollectionReference {
    const next = new MockCollectionReference(this.path);
    next.limitCount = this.limitCount;
    next.orderField = field;
    next.whereClause = this.whereClause;
    return next;
  }

  where(field: string, op: string, value: any): MockCollectionReference {
    const next = new MockCollectionReference(this.path);
    next.limitCount = this.limitCount;
    next.orderField = this.orderField;
    next.whereClause = { field, op, value };
    return next;
  }

  async get(): Promise<MockQuerySnapshot> {
    let docs = directChildDocs(this.path);
    if (this.whereClause) {
      docs = docs.filter((doc) => {
        const actual = doc.data[this.whereClause!.field];
        if (this.whereClause!.op === ">=") {
          return actual === undefined || JSON.stringify(actual) >= JSON.stringify(this.whereClause!.value);
        }
        return actual === this.whereClause!.value;
      });
    }
    if (this.orderField) {
      docs.sort((a, b) => Number(a.data[this.orderField!] ?? 0) - Number(b.data[this.orderField!] ?? 0));
    }
    if (this.limitCount !== undefined) {
      docs = docs.slice(0, this.limitCount);
    }
    return new MockQuerySnapshot(docs.map((doc) => new MockDocumentSnapshot(doc.id, doc.data, new MockDocumentReference(doc.path))));
  }

  count(): { get: () => Promise<{ data: () => { count: number } }> } {
    return {
      get: async () => ({ data: () => ({ count: directChildDocs(this.path).length }) }),
    };
  }
}

const mockDb = {
  collection: jest.fn((path: string) => new MockCollectionReference(path)),
  batch: jest.fn(() => {
    const writes: Array<() => Promise<void>> = [];
    return {
      set: (ref: MockDocumentReference, data: StoredDoc, options?: { merge?: boolean }) => {
        writes.push(() => ref.set(data, options));
      },
      commit: async () => {
        for (const write of writes) {
          await write();
        }
      },
    };
  }),
  runTransaction: jest.fn(async (handler: (tx: any) => Promise<void>) => {
    await handler({
      get: (ref: MockDocumentReference) => ref.get(),
      set: (ref: MockDocumentReference, data: StoredDoc, options?: { merge?: boolean }) => ref.set(data, options),
    });
  }),
};

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
  defineSecret: jest.fn((name: string) => ({ value: jest.fn(() => mockSecretValues[name] ?? "") })),
}));

jest.mock("firebase-functions/logger", () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
}));

jest.mock("firebase-admin/firestore", () => ({
  getFirestore: jest.fn(() => mockDb),
  FieldValue: {
    serverTimestamp: jest.fn(() => "__serverTimestamp__"),
    arrayUnion: jest.fn((...items) => ({ __arrayUnion: items })),
  },
  Timestamp: {
    fromMillis: jest.fn((ms) => ({ ms })),
  },
}));

const mockVerifyIdToken = jest.fn(async () => ({ uid: "asker" }));
jest.mock("firebase-admin/auth", () => ({
  getAuth: jest.fn(() => ({ verifyIdToken: mockVerifyIdToken })),
}));

jest.mock("firebase-admin/app-check", () => ({
  getAppCheck: jest.fn(() => ({ verifyToken: jest.fn() })),
}));

jest.mock("@google-cloud/speech", () => ({
  SpeechClient: jest.fn(),
}));

import {
  applyRoomOperation,
  computeReactionDensity,
  detectScriptureReferences,
  sanctuaryAnchorScripture,
  sanctuaryAskMoment,
  sanctuaryReact,
  sanctuaryReactionField,
  sanctuaryRoomSync,
  sanctuarySearch,
  sanctuaryTranscribe,
  sanctuaryWeeklyDigest,
} from "./index";

beforeEach(() => {
  firestoreStore.clear();
  Object.keys(mockSecretValues).forEach((key) => delete mockSecretValues[key]);
  jest.clearAllMocks();
  (global as any).fetch = jest.fn(async () => ({
    ok: true,
    json: async () => ({ content: [{ type: "text", text: "Answer from this moment. Cite John 3:16." }] }),
  }));
});

function authed(data: StoredDoc): any {
  return { auth: { uid: "u1" }, data };
}

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

describe("Sanctuary room sync helper", () => {
  it("joins a member once and applies prayer state", () => {
    const joined = applyRoomOperation({ id: "room", memberOrbs: [], playheadMs: 0, state: "paused" }, { type: "join", member: { uid: "u1" } }, "u1", 1000);
    const prayed = applyRoomOperation(joined, { type: "prayer", playheadMs: 2500 }, "u1", 1100);
    expect(prayed.memberOrbs).toHaveLength(1);
    expect(prayed.state).toBe("prayer");
    expect(prayed.playheadMs).toBe(2500);
  });
});

describe("Sanctuary Wave 2 callable emulator coverage", () => {
  it("B1 sanctuaryTranscribe rejects non-gs media and records failed status", async () => {
    firestoreStore.set("livingVideos/v-transcribe", { mediaURL: "https://example.com/video.mp4" });

    await expect(sanctuaryTranscribe(authed({ videoId: "v-transcribe" }))).rejects.toMatchObject({ code: "failed-precondition" });
    expect(firestoreStore.get("livingVideos/v-transcribe")?.transcriptStatus).toBe("failed");
  });

  it("B2 sanctuaryAnchorScripture writes explicit OSIS anchors from transcript chunks", async () => {
    firestoreStore.set("livingVideos/v-anchor", { mediaURL: "gs://bucket/video.mp4" });
    firestoreStore.set("livingVideos/v-anchor/transcriptChunks/chunk_0000", {
      text: "The teacher reads John 3:16 before Romans 8:28.",
      startMs: 1500,
      endMs: 9000,
      words: [],
    });

    const result = await sanctuaryAnchorScripture(authed({ videoId: "v-anchor" }));

    expect(result.anchors.map((anchor: any) => anchor.verseRef)).toEqual(["JHN.3.16", "ROM.8.28"]);
    expect(directChildDocs("livingVideos/v-anchor/anchors")).toHaveLength(2);
  });

  it("B1 sanctuarySearch returns timestamped keyword results and writes journey interaction", async () => {
    firestoreStore.set("livingVideos/v-search", { ownerUid: "u1", title: "Mercy Study", contentType: "study", scriptureAnchors: [{ verseRef: "JHN.3.16" }] });
    firestoreStore.set("livingVideos/v-search/transcriptChunks/chunk_0000", { text: "Mercy and faithfulness meet in this study.", startMs: 42000, endMs: 45000 });

    const result = await sanctuarySearch(authed({ query: "mercy faithfulness", scope: { visibility: "mine" } }));

    expect(result.results[0]).toMatchObject({ videoId: "v-search", timestampMs: 42000, score: 1 });
    expect(directChildDocs("journeyNodes/u1/nodes")).toHaveLength(1);
  });

  it("B3 sanctuaryReact accepts text-free reactions and sanctuaryReactionField returns density only", async () => {
    firestoreStore.set("livingVideos/v-react", { ownerUid: "u1", durationMs: 10000 });

    const reaction = await sanctuaryReact(authed({ videoId: "v-react", reaction: { type: "amen", timestampMs: 2500 } }));
    const field = await sanctuaryReactionField(authed({ videoId: "v-react" }));

    expect(reaction).toEqual({ accepted: true, bucketIndex: 25 });
    expect(field.videoId).toBe("v-react");
    expect(field.buckets).toHaveLength(100);
    expect(field).not.toHaveProperty("count");
    expect(directChildDocs("livingVideos/v-react/reactions")).toHaveLength(1);
  });

  it("B3 sanctuaryRoomSync persists room presence and prayer state", async () => {
    const joined = await sanctuaryRoomSync(authed({ roomId: "room-1", op: { type: "join", member: { uid: "u1" } } }));
    const prayed = await sanctuaryRoomSync(authed({ roomId: "room-1", op: { type: "prayer", playheadMs: 3200 } }));

    expect(joined.room.memberOrbs).toHaveLength(1);
    expect(prayed.room.state).toBe("prayer");
    expect(prayed.room.playheadMs).toBe(3200);
  });

  it("B4 sanctuaryAskMoment streams citation and answer events over SSE", async () => {
    mockSecretValues.ANTHROPIC_API_KEY = "test-key";
    firestoreStore.set("livingVideos/v-ask/transcriptChunks/chunk_0000", { text: "God so loved the world.", startMs: 1000, endMs: 5000 });
    firestoreStore.set("livingVideos/v-ask/anchors/JHN_3_16_1000_ai", { verseRef: "JHN.3.16", timestampMs: 1000, confidence: 0.96, source: "ai" });
    const writes: string[] = [];
    const response: any = {
      writeHead: jest.fn(),
      write: jest.fn((chunk: string) => writes.push(chunk)),
      end: jest.fn(),
      status: jest.fn(() => response),
      json: jest.fn(),
    };

    await sanctuaryAskMoment(
      {
        method: "POST",
        body: { videoId: "v-ask", timestampMs: 1000, question: "What does this mean?" },
        header: (name: string) => (name.toLowerCase() === "authorization" ? "Bearer token" : undefined),
      } as any,
      response
    );

    expect(mockVerifyIdToken).toHaveBeenCalledWith("token");
    expect(response.writeHead).toHaveBeenCalledWith(200, expect.objectContaining({ "Content-Type": "text/event-stream" }));
    expect(writes.join("\n")).toContain("event: citations");
    expect(writes.join("\n")).toContain("event: done");
  });

  it("B3 sanctuaryWeeklyDigest writes server-only creator digest documents", async () => {
    firestoreStore.set("livingVideos/v-digest", { ownerUid: "creator-1", updatedAt: { ms: Date.now() } });
    firestoreStore.set("livingVideos/v-digest/reactions/u1_amen_100", { type: "amen", timestampMs: 100 });

    await sanctuaryWeeklyDigest();

    const digests = directChildDocs("creatorWeeklyDigests");
    expect(digests).toHaveLength(1);
    expect(digests[0].data.creatorId).toBe("creator-1");
    expect(digests[0].data.sanctuary.reactionCount).toBe(1);
  });
});
