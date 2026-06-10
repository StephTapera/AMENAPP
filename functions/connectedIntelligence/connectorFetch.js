/**
 * connectorFetch.js — AMEN Connected Intelligence v1 — Connector READ endpoint
 *
 * OWNER: Connected Intelligence Phase 2 (read-side gap closure, 2026-06-09).
 *
 * THE GAP THIS CLOSES
 *   src/features/berean/composer/contextGatherer.ts calls the `connectorFetch`
 *   httpsCallable for tool-orchestration mentions (@calendar / @music). No backing CF
 *   existed, so the gatherer always hit its catch path and rendered a degraded chip.
 *   This module is that backing CF. It returns the single shape connector data may
 *   enter a prompt in: scoped ContextItem(s), summaryOnly with a pointer back to source.
 *
 * CONTRACT (src/features/connectedIntelligence.contracts.ts — FROZEN; mirrored, never edited)
 *   Request : { connectorId: ConnectorId, surface: GrantSurface, query: string }
 *             (matches contextGatherer.ts ConnectorFetchRequest)
 *   Response: { ok: boolean, items: Array<{ payload, pointer, truthLevel? }>, error?, degraded?, reason? }
 *             (matches contextGatherer.ts ConnectorFetchResponse; ok:false ⇒ visible
 *              degraded chip; the gatherer NEVER fabricates from a non-ok response.)
 *
 * SECURITY / PRIVACY INVARIANTS (all enforced below; see inline citations)
 *   1. REGISTRATION  — onCallV2 + requireBereanAuth + enforceRateLimit, region us-central1,
 *      App Check enforced at the v2triggers codebase level (same as bereanChat). Registered
 *      in functions/v2entry.js.
 *   2. CONSENT-GATED — a read happens ONLY when an active, non-expired ConnectorGrant for
 *      this connector includes the requested GrantSurface AND grants a read scope. No grant /
 *      wrong surface / expired / no read scope ⇒ a typed degraded result, NEVER fabricated data.
 *   3. MINOR-BLOCK   — gating lives upstream (a minor cannot hold a grant). Defense-in-depth:
 *      assertNotMinor here too; minor ⇒ degraded result, no upstream fetch.
 *   4. COMPUTED-AND-DISCARDED — fetched connector context is returned in the turn and
 *      persisted NOWHERE. No Firestore writes of connector payloads, no payloads in logs
 *      (logs carry only connectorId, surface, item count, latency). Tokens are read
 *      server-side via connectorFunctions.tokenRef and NEVER returned to the client.
 *   5. FAIL-CLOSED   — provider error / timeout / invalid token ⇒ { ok:false, degraded:true,
 *      reason } so the client renders the existing visible degraded chip. We never throw a
 *      raw error to the client for an upstream failure.
 *   6. SUMMARIZATION — any model summarization of fetched content routes through
 *      functions/router/callModel.js with the real `daily_brief` task key (no new router,
 *      no new route). Summaries are best-effort: if the router degrades, the raw provider
 *      snippet is used; ContextItems remain summaryOnly with a pointer.
 *
 * Pattern mirrors connectorFunctions.js (onCallV2 + requireBereanAuth + enforceRateLimit +
 * defineSecretV2) and reuses its server-side token retrieval + minor gate via _internal.
 */

"use strict";

const { onCall: onCallV2, HttpsError: HttpsErrorV2 } = require("firebase-functions/v2/https");
const { defineSecret: defineSecretV2 } = require("firebase-functions/params");
const admin = require("firebase-admin");
const logger = require("firebase-functions/logger");
const { enforceRateLimit } = require("../rateLimiter");
const { callModel } = require("../router/callModel");
const connectors = require("./connectorFunctions");

// Reused server-side helpers (token retrieval, grant ref, minor gate). NEVER expose tokens.
const { grantRef, tokenRef, assertNotMinor, ALL_CONNECTOR_IDS, NEW_CONNECTOR_IDS } =
  connectors._internal;

// Secrets used by the daily_brief summarization route chain (gemini → openai) + its
// output guard (nvidia). Declared so the route can resolve them at runtime.
const FETCH_GEMINI_KEY = defineSecretV2("GEMINI_API_KEY");
const FETCH_OPENAI_KEY = defineSecretV2("OPENAI_API_KEY");
const FETCH_NVIDIA_KEY = defineSecretV2("NVIDIA_API_KEY");

// ── Contract-mirrored constants (kept in sync with the FROZEN contract) ─────────
const VALID_SURFACES = ["berean", "daily_brief", "notebooks", "scheduled_actions", "action_sheet"];
// A read requires at least one of these scopes on the grant.
const READ_SCOPES = ["read_metadata", "read_content"];

// Per-uid read budget. Connector reads are turn-scoped and can be frequent; a sane
// window prevents a single session from hammering a provider. Mirrors connectorStatus.
const FETCH_REQUESTS_PER_HOUR = 120;
const ONE_HOUR_SECONDS = 3600;

const PROVIDER_TIMEOUT_MS = 8000; // hard cap on the upstream provider call (fail-closed on timeout)
const MAX_ITEMS = 5;              // cap how much connector context can enter a single turn

// ── Helpers ─────────────────────────────────────────────────────────────────────

function requireBereanAuth(request) {
  if (!request.auth?.uid) {
    throw new HttpsErrorV2("unauthenticated", "Authentication required.");
  }
  return request.auth.uid;
}

/** A typed degraded result the gatherer already knows how to render (ok:false ⇒ chip). */
function degraded(reason) {
  return { ok: false, items: [], degraded: true, reason };
}

/**
 * Resolve the active grant for (uid, connectorId) and assert it permits this read.
 * Returns { grant } on success, or { deny: <reason> } so the caller can degrade.
 * Pure read — writes nothing.
 */
async function resolveGrantForRead(uid, connectorId, surface) {
  let snap;
  try {
    snap = await grantRef(uid, connectorId).get();
  } catch (err) {
    // Firestore unavailable ⇒ fail closed (degrade), never assume consent.
    logger.warn("[connectorFetch] grant lookup failed", { connectorId, surface });
    return { deny: "consent_unavailable" };
  }

  if (!snap.exists) return { deny: "no_grant" };

  const g = snap.data() || {};

  if (g.status !== "active") return { deny: "grant_inactive" };

  // Expiry honoured server-side (matches connectorStatus): expired ⇒ no read.
  if (g.expiresAt && typeof g.expiresAt.toMillis === "function") {
    if (g.expiresAt.toMillis() <= Date.now()) return { deny: "grant_expired" };
  }

  const surfaces = Array.isArray(g.surfaces) ? g.surfaces : [];
  if (!surfaces.includes(surface)) return { deny: "surface_not_granted" };

  const scopes = Array.isArray(g.scopes) ? g.scopes : [];
  if (!scopes.some((s) => READ_SCOPES.includes(s))) return { deny: "no_read_scope" };

  return { grant: { scopes, surfaces } };
}

/**
 * Retrieve the server-side OAuth access token for a NEW provider. Tokens live in the
 * private connectorTokens collection and NEVER leave the server. Returns the access
 * token string, or null when missing/expired-without-refresh (caller degrades).
 */
async function getServerSideAccessToken(uid, connectorId) {
  let snap;
  try {
    snap = await tokenRef(uid, connectorId).get();
  } catch {
    return null;
  }
  if (!snap.exists) return null;
  const tok = snap.data() || {};
  if (!tok.accessToken) return null;
  const expired =
    tok.expiresAt && typeof tok.expiresAt.toMillis === "function"
      ? tok.expiresAt.toMillis() <= Date.now()
      : false;
  if (expired && !tok.refreshToken) return null; // no usable credential
  return tok.accessToken;
}

/**
 * Fetch raw, NON-PERSISTED context snippets from the provider for the query.
 * Returns Array<{ payload, pointer }>. Throws on provider error / timeout so the
 * caller degrades (fail-closed). Provider payloads are returned, never stored.
 *
 * NOTE: this is deliberately a thin read of upcoming/relevant items. We request a
 * small page and summarize downstream. No write scopes are ever exercised here.
 */
async function fetchProviderContext(connectorId, accessToken, query) {
  if (connectorId === "calendar") {
    // Google Calendar: upcoming events from the primary calendar, time-ordered.
    const nowIso = new Date().toISOString();
    const url =
      "https://www.googleapis.com/calendar/v3/calendars/primary/events" +
      `?timeMin=${encodeURIComponent(nowIso)}` +
      "&singleEvents=true&orderBy=startTime&maxResults=" + MAX_ITEMS;
    const res = await fetch(url, {
      headers: { Authorization: `Bearer ${accessToken}` },
      signal: AbortSignal.timeout(PROVIDER_TIMEOUT_MS),
    });
    if (!res.ok) throw new Error(`calendar_${res.status}`);
    const json = await res.json();
    const events = Array.isArray(json.items) ? json.items : [];
    return events.slice(0, MAX_ITEMS).map((ev) => {
      const start = ev.start?.dateTime || ev.start?.date || "";
      const summary = typeof ev.summary === "string" ? ev.summary : "(untitled event)";
      return {
        payload: start ? `${summary} — ${start}` : summary,
        pointer: typeof ev.htmlLink === "string" ? ev.htmlLink : null,
      };
    });
  }

  if (connectorId === "music") {
    // Spotify: search the user's query against tracks (read-only catalog read).
    const url =
      "https://api.spotify.com/v1/search" +
      `?type=track&limit=${MAX_ITEMS}&q=${encodeURIComponent(query || "worship")}`;
    const res = await fetch(url, {
      headers: { Authorization: `Bearer ${accessToken}` },
      signal: AbortSignal.timeout(PROVIDER_TIMEOUT_MS),
    });
    if (!res.ok) throw new Error(`music_${res.status}`);
    const json = await res.json();
    const tracks = json.tracks?.items;
    const list = Array.isArray(tracks) ? tracks : [];
    return list.slice(0, MAX_ITEMS).map((t) => {
      const name = typeof t.name === "string" ? t.name : "(untitled track)";
      const artist = Array.isArray(t.artists) && t.artists[0]?.name ? t.artists[0].name : "";
      return {
        payload: artist ? `${name} — ${artist}` : name,
        pointer: t.external_urls?.spotify ?? null,
      };
    });
  }

  // No upstream OAuth provider for alias connectors here.
  throw new Error("unsupported_connector");
}

/**
 * Best-effort summarization of fetched snippets through callModel (daily_brief route).
 * The router owns provider choice + output guard. If it blocks/degrades/throws, we
 * fall back to the raw provider snippet — the ContextItem stays summaryOnly with its
 * pointer, and nothing is fabricated. Summaries are NOT persisted.
 *
 * Returns the (possibly summarized) payload string for one snippet.
 */
async function summarizeSnippet(uid, connectorId, surface, snippet) {
  const raw = snippet.payload;
  try {
    const result = await callModel({
      task: "daily_brief", // real key in amenRouting.config.js (failover, outputGuard)
      input: raw,
      context: `Summarize this ${connectorId} item in one short, plain line for a faith app context card. No guilt framing.`,
      userId: uid,
    });
    if (result?.blocked || result?.degraded) return raw; // never fabricate; use the source line
    const out = typeof result?.output === "string" ? result.output.trim() : "";
    return out || raw;
  } catch (err) {
    // Router error ⇒ degrade to the raw provider line (still grounded by its pointer).
    logger.warn("[connectorFetch] summarize degraded to raw snippet", { connectorId, surface });
    return raw;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CORE — pure handler, exported for unit tests (no Firebase wrapper).
//
// Returns the ConnectorFetchResponse shape contextGatherer.ts expects:
//   ok:true  ⇒ { ok:true, items:[{ payload, pointer, truthLevel:'grounded' }] }
//   ok:false ⇒ { ok:false, items:[], degraded:true, reason }   (visible chip)
// ─────────────────────────────────────────────────────────────────────────────
async function handleConnectorFetch(uid, data) {
  const startMs = Date.now();
  const { connectorId, surface, query } = data || {};

  // ── Input validation (typed degrade, not a raw throw, so the chip renders) ──
  if (!connectorId || !ALL_CONNECTOR_IDS.includes(connectorId)) {
    return degraded("unknown_connector");
  }
  if (!surface || !VALID_SURFACES.includes(surface)) {
    return degraded("invalid_surface");
  }
  if (typeof query !== "string") {
    return degraded("invalid_query");
  }

  // ── INVARIANT 3: minor-block defense-in-depth. Minor ⇒ degrade, no upstream read. ──
  try {
    await assertNotMinor(uid);
  } catch (err) {
    logger.info("[connectorFetch] blocked: minor or ineligible account", { connectorId, surface });
    return degraded("minor_blocked");
  }

  // ── Alias connectors (bible / church_mgmt) have no OAuth read path here. ──
  // They resolve through their own always-on adapters elsewhere; degrade gracefully
  // rather than fabricate, so the client falls back to its existing handling.
  if (!NEW_CONNECTOR_IDS.includes(connectorId)) {
    return degraded("connector_has_no_read_endpoint");
  }

  // ── INVARIANT 2: consent gate. No grant / wrong surface / expired / no read scope ⇒ degrade. ──
  const resolved = await resolveGrantForRead(uid, connectorId, surface);
  if (resolved.deny) {
    logger.info("[connectorFetch] consent gate refused read", {
      connectorId,
      surface,
      reason: resolved.deny,
    });
    return degraded(resolved.deny);
  }

  // ── INVARIANT 4 (token): retrieve token SERVER-SIDE; never returned to client. ──
  const accessToken = await getServerSideAccessToken(uid, connectorId);
  if (!accessToken) {
    logger.info("[connectorFetch] no usable token — degrading", { connectorId, surface });
    return degraded("token_unavailable");
  }

  // ── INVARIANT 5: fail-closed. Provider error / timeout ⇒ degrade, never fabricate. ──
  let rawItems;
  try {
    rawItems = await fetchProviderContext(connectorId, accessToken, query);
  } catch (err) {
    // Reason is non-sensitive (e.g. "calendar_401"); NO payload, NO token logged.
    const reason = typeof err?.message === "string" ? err.message : "provider_error";
    logger.warn("[connectorFetch] provider read failed — degrading", { connectorId, surface, reason });
    return degraded("provider_unavailable");
  }

  if (!Array.isArray(rawItems) || rawItems.length === 0) {
    return degraded("no_results");
  }

  // ── INVARIANT 6: optional summarization via callModel (best-effort, never fabricates). ──
  const items = [];
  for (const snip of rawItems.slice(0, MAX_ITEMS)) {
    const payload = await summarizeSnippet(uid, connectorId, surface, snip);
    items.push({
      payload,
      pointer: snip.pointer ?? null,
      truthLevel: "grounded", // grounded by the source pointer
    });
  }

  // ── INVARIANT 4 (discard): metadata-only log. NO payloads, NO tokens persisted/logged. ──
  logger.info("[connectorFetch] ok", {
    connectorId,
    surface,
    itemCount: items.length,
    latencyMs: Date.now() - startMs,
  });

  // Nothing written to Firestore. The turn consumes these and discards them; the
  // client maps each into a ContextItem with summaryOnly:true + pointer.
  return { ok: true, items };
}

// ─────────────────────────────────────────────────────────────────────────────
// connectorFetch — the registered callable (thin wrapper around the pure handler).
// ─────────────────────────────────────────────────────────────────────────────
exports.connectorFetch = onCallV2(
  {
    region: "us-central1",
    timeoutSeconds: 30,
    secrets: [FETCH_GEMINI_KEY, FETCH_OPENAI_KEY, FETCH_NVIDIA_KEY],
  },
  async (request) => {
    const uid = requireBereanAuth(request);
    // Per-uid window. Limiter fails closed on its own DB outage (resource-exhausted /
    // unavailable HttpsError) — that propagates and the client's catch path degrades.
    await enforceRateLimit(uid, "connectorFetch", FETCH_REQUESTS_PER_HOUR, ONE_HOUR_SECONDS);
    return handleConnectorFetch(uid, request.data || {});
  },
);

// Export the pure handler + helpers for unit testing (not registered as callables).
exports._internal = {
  handleConnectorFetch,
  resolveGrantForRead,
  getServerSideAccessToken,
  fetchProviderContext,
  summarizeSnippet,
  degraded,
  READ_SCOPES,
  VALID_SURFACES,
  MAX_ITEMS,
};
