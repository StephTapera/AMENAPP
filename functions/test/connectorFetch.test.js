/**
 * connectorFetch.test.js — read-side Connector CF (Connected Intelligence v1)
 *
 * Verifies the four required behaviors of the @calendar/@music READ endpoint:
 *   (a) consent OFF / no grant   ⇒ NO upstream provider fetch + degraded result
 *   (b) minor account            ⇒ blocked (degraded), NO upstream fetch
 *   (c) provider error / timeout ⇒ degraded chip result, NO fabricated content
 *   (d) happy path               ⇒ ContextItem(s) with summaryOnly + pointer; NOTHING persisted
 *
 * Strategy: connectorFetch.js reads its server-side helpers from
 * connectorFunctions._internal (grantRef, tokenRef, assertNotMinor) and summarizes via
 * router/callModel. We mock those modules + global.fetch and drive the PURE handler
 * (handleConnectorFetch) directly — no Firebase wrapper needed. We assert both the
 * returned shape AND that no write/persist call ever happens (we expose only .get()).
 */

"use strict";

// ── Mocks must be declared before requiring the module under test ───────────────

// Shared mutable fixtures the per-test setup mutates.
const fixtures = {
  grantSnap: null, // { exists, data() }
  tokenSnap: null, // { exists, data() }
  minorThrows: false, // when true, assertNotMinor rejects (minor account)
  writeCalls: [], // any .set/.update/.delete the handler attempted (must stay empty)
};

// grantRef / tokenRef return a doc-like object. We only implement get(); set/update/
// delete push to writeCalls so the "nothing persisted" invariant is testable.
function makeDocRef(getSnap, tag) {
  return {
    get: async () => getSnap(),
    set: async (...a) => { fixtures.writeCalls.push({ tag, op: "set", a }); },
    update: async (...a) => { fixtures.writeCalls.push({ tag, op: "update", a }); },
    delete: async (...a) => { fixtures.writeCalls.push({ tag, op: "delete", a }); },
  };
}

jest.mock("../connectedIntelligence/connectorFunctions", () => ({
  _internal: {
    grantRef: () => makeDocRef(() => fixtures.grantSnap, "grant"),
    tokenRef: () => makeDocRef(() => fixtures.tokenSnap, "token"),
    assertNotMinor: async () => {
      if (fixtures.minorThrows) {
        const e = new Error("minor");
        throw e;
      }
    },
    ALL_CONNECTOR_IDS: ["calendar", "music", "bible", "church_mgmt"],
    NEW_CONNECTOR_IDS: ["calendar", "music"],
  },
}));

// Router: record calls; default returns a summarized line. Tests can override.
const callModelMock = jest.fn(async ({ input }) => ({ output: `SUMMARY(${input})` }));
jest.mock("../router/callModel", () => ({ callModel: (...a) => callModelMock(...a) }));

// Rate limiter is only used by the wrapped callable, not the pure handler — stub anyway.
jest.mock("../rateLimiter", () => ({ enforceRateLimit: jest.fn(async () => ({ count: 1 })) }));

// firebase-admin / functions params / logger are imported at module load — stub minimally.
jest.mock("firebase-admin", () => ({ firestore: () => ({}) }));
jest.mock("firebase-functions/params", () => ({ defineSecret: () => ({ value: () => "x" }) }));
jest.mock("firebase-functions/logger", () => ({ info: () => {}, warn: () => {}, error: () => {} }));
jest.mock("firebase-functions/v2/https", () => ({
  onCall: (_opts, handler) => handler,
  HttpsError: class extends Error {
    constructor(code, message) { super(message); this.code = code; }
  },
}));

const { _internal } = require("../connectedIntelligence/connectorFetch");
const { handleConnectorFetch } = _internal;

// ── Helpers ─────────────────────────────────────────────────────────────────────

const FUTURE = { toMillis: () => Date.now() + 60 * 60 * 1000 };

function activeBereanGrant() {
  return {
    exists: true,
    data: () => ({
      status: "active",
      surfaces: ["berean"],
      scopes: ["read_content"],
      expiresAt: null,
    }),
  };
}

function liveToken() {
  return {
    exists: true,
    data: () => ({ accessToken: "server-token", refreshToken: "r", expiresAt: FUTURE }),
  };
}

beforeEach(() => {
  fixtures.grantSnap = { exists: false, data: () => ({}) };
  fixtures.tokenSnap = { exists: false, data: () => ({}) };
  fixtures.minorThrows = false;
  fixtures.writeCalls = [];
  callModelMock.mockClear();
  global.fetch = jest.fn(); // default: no provider call expected
});

afterEach(() => {
  delete global.fetch;
});

// ─────────────────────────────────────────────────────────────────────────────

describe("connectorFetch — consent gate (a)", () => {
  test("no grant ⇒ degraded result AND no upstream provider fetch occurs", async () => {
    fixtures.grantSnap = { exists: false, data: () => ({}) }; // consent OFF

    const res = await handleConnectorFetch("uid-1", {
      connectorId: "calendar",
      surface: "berean",
      query: "what's on today",
    });

    expect(res.ok).toBe(false);
    expect(res.degraded).toBe(true);
    expect(res.reason).toBe("no_grant");
    expect(res.items).toEqual([]);
    // The whole point: provider was never contacted.
    expect(global.fetch).not.toHaveBeenCalled();
    // Nothing fabricated, nothing persisted.
    expect(fixtures.writeCalls).toEqual([]);
  });

  test("grant exists but berean surface NOT granted ⇒ degraded, no fetch", async () => {
    fixtures.grantSnap = {
      exists: true,
      data: () => ({ status: "active", surfaces: ["scheduled_actions"], scopes: ["read_content"], expiresAt: null }),
    };

    const res = await handleConnectorFetch("uid-1", {
      connectorId: "calendar",
      surface: "berean",
      query: "x",
    });

    expect(res.ok).toBe(false);
    expect(res.reason).toBe("surface_not_granted");
    expect(global.fetch).not.toHaveBeenCalled();
  });
});

describe("connectorFetch — minor block (b)", () => {
  test("minor account ⇒ blocked degraded result, no grant read, no provider fetch", async () => {
    fixtures.minorThrows = true; // assertNotMinor rejects
    // Even if a grant + token existed, a minor must never reach the provider.
    fixtures.grantSnap = activeBereanGrant();
    fixtures.tokenSnap = liveToken();

    const res = await handleConnectorFetch("uid-minor", {
      connectorId: "music",
      surface: "berean",
      query: "worship",
    });

    expect(res.ok).toBe(false);
    expect(res.degraded).toBe(true);
    expect(res.reason).toBe("minor_blocked");
    expect(global.fetch).not.toHaveBeenCalled();
    expect(fixtures.writeCalls).toEqual([]);
  });
});

describe("connectorFetch — provider failure is fail-closed (c)", () => {
  test("provider error ⇒ degraded chip result, NO fabricated content", async () => {
    fixtures.grantSnap = activeBereanGrant();
    fixtures.tokenSnap = liveToken();
    global.fetch = jest.fn(async () => ({ ok: false, status: 401 })); // provider rejects

    const res = await handleConnectorFetch("uid-1", {
      connectorId: "calendar",
      surface: "berean",
      query: "x",
    });

    expect(res.ok).toBe(false);
    expect(res.degraded).toBe(true);
    expect(res.reason).toBe("provider_unavailable");
    expect(res.items).toEqual([]); // nothing fabricated
    expect(global.fetch).toHaveBeenCalledTimes(1); // we DID attempt, then failed closed
    expect(fixtures.writeCalls).toEqual([]); // nothing persisted
  });

  test("provider timeout (fetch throws) ⇒ degraded, no items", async () => {
    fixtures.grantSnap = activeBereanGrant();
    fixtures.tokenSnap = liveToken();
    global.fetch = jest.fn(async () => { throw new Error("AbortError: timeout"); });

    const res = await handleConnectorFetch("uid-1", {
      connectorId: "music",
      surface: "berean",
      query: "x",
    });

    expect(res.ok).toBe(false);
    expect(res.degraded).toBe(true);
    expect(res.reason).toBe("provider_unavailable");
    expect(res.items).toEqual([]);
  });
});

describe("connectorFetch — happy path (d)", () => {
  test("active grant + token + provider ⇒ ContextItems summaryOnly+pointer; nothing persisted", async () => {
    fixtures.grantSnap = activeBereanGrant();
    fixtures.tokenSnap = liveToken();

    // Provider returns two calendar events with deep-link pointers.
    global.fetch = jest.fn(async () => ({
      ok: true,
      json: async () => ({
        items: [
          { summary: "Bible study", start: { dateTime: "2026-06-10T19:00:00Z" }, htmlLink: "https://cal/evt1" },
          { summary: "Prayer night", start: { date: "2026-06-12" }, htmlLink: "https://cal/evt2" },
        ],
      }),
    }));

    const res = await handleConnectorFetch("uid-1", {
      connectorId: "calendar",
      surface: "berean",
      query: "this week",
    });

    expect(res.ok).toBe(true);
    expect(res.items).toHaveLength(2);

    for (const it of res.items) {
      expect(typeof it.payload).toBe("string");
      expect(it.payload.length).toBeGreaterThan(0);
      expect(it.truthLevel).toBe("grounded");
    }
    // Pointers flow back to source of truth.
    expect(res.items[0].pointer).toBe("https://cal/evt1");
    expect(res.items[1].pointer).toBe("https://cal/evt2");

    // Summarization routed through callModel with the real daily_brief task key.
    expect(callModelMock).toHaveBeenCalled();
    expect(callModelMock.mock.calls[0][0].task).toBe("daily_brief");

    // COMPUTED-AND-DISCARDED: the handler persisted nothing (only .get() was used).
    expect(fixtures.writeCalls).toEqual([]);
  });

  test("summarizer degrade ⇒ falls back to raw provider line, never fabricates, no throw", async () => {
    fixtures.grantSnap = activeBereanGrant();
    fixtures.tokenSnap = liveToken();
    callModelMock.mockImplementationOnce(async () => ({ degraded: true, output: null }));

    global.fetch = jest.fn(async () => ({
      ok: true,
      json: async () => ({
        items: [{ summary: "Sunday service", start: { date: "2026-06-14" }, htmlLink: "https://cal/svc" }],
      }),
    }));

    const res = await handleConnectorFetch("uid-1", {
      connectorId: "calendar",
      surface: "berean",
      query: "sunday",
    });

    expect(res.ok).toBe(true);
    expect(res.items).toHaveLength(1);
    // Raw provider-derived line is used (contains the event name) — not a fabricated summary.
    expect(res.items[0].payload).toContain("Sunday service");
    expect(res.items[0].pointer).toBe("https://cal/svc");
    expect(fixtures.writeCalls).toEqual([]);
  });
});
