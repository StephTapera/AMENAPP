/**
 * connectorFunctions.js — AMEN Connected Intelligence v1 — Connectors backend
 *
 * OWNER: Phase 2 Agent A (Connectors Hub). This is the ONLY backend module Agent A
 * owns. It must NOT be required from index.js by anyone but a human (see
 * src/features/connectors/HANDOFF.md for the exact registration deltas).
 *
 * RESPONSIBILITIES
 *   - OAuth token-exchange for the two NEW providers (calendar, music). All third-party
 *     tokens are stored SERVER-SIDE only, keyed by uid, and NEVER returned to the client.
 *   - Grant docs written to users/{uid}/connectorGrants/{connectorId}.
 *   - Minor accounts are rejected at grant time (ageTier !== 'tierD' ⇒ rejected).
 *   - Token-health probes flip status:'error' so client surfaces render DEGRADED.
 *   - Per-surface grant matrix persisted on the grant doc (GrantSurface[]).
 *   - One-tap revoke + expiry honoured server-side.
 *
 * SECURITY MODEL
 *   - ZERO client API keys. Client only ever calls these callables.
 *   - Provider client-secrets live in defineSecret-managed secrets:
 *       GOOGLE_CALENDAR_CLIENT_SECRET, SPOTIFY_CLIENT_SECRET.
 *   - Tokens persisted to the PRIVATE collection connectorTokens/{uid}_{connectorId},
 *     which client Firestore rules MUST deny all client read/write to (see HANDOFF.md).
 *   - bible + church_mgmt connectors resolve through the existing adapters; this module
 *     does NOT touch their token storage (they have none — open-license / native).
 *
 * Firebase Functions v2. Pattern mirrors functions/v2functions.js (requireBereanAuth,
 * enforceRateLimit, onCallV2, defineSecretV2).
 */

"use strict";

const { onCall: onCallV2, HttpsError: HttpsErrorV2 } = require("firebase-functions/v2/https");
const { defineSecret: defineSecretV2 } = require("firebase-functions/params");
const admin = require("firebase-admin");
const logger = require("firebase-functions/logger");
const { enforceRateLimit } = require("../rateLimiter");

// ── Secrets (server-side only; never logged, never returned) ───────────────────
const GOOGLE_CALENDAR_CLIENT_SECRET = defineSecretV2("GOOGLE_CALENDAR_CLIENT_SECRET");
const GOOGLE_CALENDAR_CLIENT_ID     = defineSecretV2("GOOGLE_CALENDAR_CLIENT_ID");
const SPOTIFY_CLIENT_SECRET         = defineSecretV2("SPOTIFY_CLIENT_SECRET");
const SPOTIFY_CLIENT_ID             = defineSecretV2("SPOTIFY_CLIENT_ID");

// ── Contract-mirrored constants (kept in sync with connectedIntelligence.contracts.ts) ──
const NEW_CONNECTOR_IDS = ["calendar", "music"];
const ALIAS_CONNECTOR_IDS = ["bible", "church_mgmt"];
const ALL_CONNECTOR_IDS = [...NEW_CONNECTOR_IDS, ...ALIAS_CONNECTOR_IDS];

const VALID_SCOPES = ["read_metadata", "read_content", "write_draft", "write_commit"];
const VALID_SURFACES = ["berean", "daily_brief", "notebooks", "scheduled_actions", "action_sheet"];

// connectorRequestsPerDay from connectedIntelligence.config.ts → limits.connectorRequestsPerDay
const CONNECTOR_REQUESTS_PER_DAY = 100;
const ONE_DAY_SECONDS = 86400;

// ── Helpers ────────────────────────────────────────────────────────────────────

function requireBereanAuth(request) {
  if (!request.auth?.uid) {
    throw new HttpsErrorV2("unauthenticated", "Authentication required.");
  }
  return request.auth.uid;
}

function getDb() {
  return admin.firestore();
}

function grantRef(uid, connectorId) {
  return getDb().collection("users").doc(uid).collection("connectorGrants").doc(connectorId);
}

/** PRIVATE — client rules MUST deny all access to this collection. */
function tokenRef(uid, connectorId) {
  return getDb().collection("connectorTokens").doc(`${uid}_${connectorId}`);
}

function assertValidConnectorId(connectorId) {
  if (!ALL_CONNECTOR_IDS.includes(connectorId)) {
    throw new HttpsErrorV2("invalid-argument", `Unknown connectorId "${connectorId}".`);
  }
}

function assertIsNewProvider(connectorId) {
  if (!NEW_CONNECTOR_IDS.includes(connectorId)) {
    // bible + church_mgmt resolve through existing adapters — no OAuth path here.
    throw new HttpsErrorV2(
      "failed-precondition",
      `Connector "${connectorId}" uses an existing adapter and has no OAuth flow.`,
    );
  }
}

function assertValidScopes(scopes) {
  if (!Array.isArray(scopes) || scopes.length === 0) {
    throw new HttpsErrorV2("invalid-argument", "scopes must be a non-empty array.");
  }
  for (const s of scopes) {
    if (!VALID_SCOPES.includes(s)) {
      throw new HttpsErrorV2("invalid-argument", `Invalid scope "${s}".`);
    }
  }
}

function assertValidSurfaces(surfaces) {
  if (!Array.isArray(surfaces) || surfaces.length === 0) {
    throw new HttpsErrorV2("invalid-argument", "surfaces must be a non-empty array.");
  }
  for (const s of surfaces) {
    if (!VALID_SURFACES.includes(s)) {
      throw new HttpsErrorV2("invalid-argument", `Invalid surface "${s}".`);
    }
  }
}

/**
 * Minor gate. A grant is rejected unless the account is a confirmed adult (tierD).
 * ageTier is server-computed in authenticationHelpers.computeAgeTier and stored on
 * users/{uid}. Conservative default: if the field is missing OR not tierD, REJECT.
 *
 * @returns {Promise<void>} resolves only for confirmed adults; throws otherwise.
 */
async function assertNotMinor(uid) {
  let ageTier = "blocked";
  try {
    const snap = await getDb().collection("users").doc(uid).get();
    ageTier = snap.exists ? (snap.data()?.ageTier ?? "blocked") : "blocked";
  } catch (err) {
    logger.error("[connectors] ageTier lookup failed — failing closed", { uid });
    throw new HttpsErrorV2("permission-denied", "Could not verify account eligibility.");
  }
  if (ageTier !== "tierD") {
    // minorBlocked assertion — no grant path for minors.
    throw new HttpsErrorV2(
      "permission-denied",
      "Connectors are not available for this account.",
      { minorBlocked: true },
    );
  }
}

/**
 * Persist OAuth tokens server-side ONLY. Never returned to the client.
 * Stored in the private connectorTokens collection.
 */
async function storeTokens(uid, connectorId, tokens) {
  await tokenRef(uid, connectorId).set(
    {
      uid,
      connectorId,
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken ?? null,
      expiresAt: tokens.expiresAt ?? null,
      scope: tokens.scope ?? null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

/**
 * Exchange an OAuth authorization code for tokens with the provider's token endpoint.
 * Provider client-secret comes from the bound secret. Returns a normalized token shape.
 *
 * Fail-closed: any non-200 / network error throws "unavailable" so the grant is NOT
 * written and the client can retry.
 */
async function exchangeOAuthCode(connectorId, code, redirectUri, codeVerifier) {
  let tokenUrl;
  let body;

  if (connectorId === "calendar") {
    tokenUrl = "https://oauth2.googleapis.com/token";
    body = new URLSearchParams({
      code,
      client_id: GOOGLE_CALENDAR_CLIENT_ID.value(),
      client_secret: GOOGLE_CALENDAR_CLIENT_SECRET.value(),
      redirect_uri: redirectUri,
      grant_type: "authorization_code",
      ...(codeVerifier ? { code_verifier: codeVerifier } : {}),
    });
  } else if (connectorId === "music") {
    tokenUrl = "https://accounts.spotify.com/api/token";
    body = new URLSearchParams({
      code,
      client_id: SPOTIFY_CLIENT_ID.value(),
      client_secret: SPOTIFY_CLIENT_SECRET.value(),
      redirect_uri: redirectUri,
      grant_type: "authorization_code",
      ...(codeVerifier ? { code_verifier: codeVerifier } : {}),
    });
  } else {
    throw new HttpsErrorV2("invalid-argument", `No OAuth flow for "${connectorId}".`);
  }

  let res;
  try {
    res = await fetch(tokenUrl, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: body.toString(),
    });
  } catch (err) {
    logger.error("[connectors] token exchange network error", { connectorId });
    throw new HttpsErrorV2("unavailable", "Could not reach the provider. Please try again.");
  }

  if (!res.ok) {
    // Do NOT echo provider error body to client (may contain secrets/PII).
    logger.warn("[connectors] token exchange rejected", { connectorId, status: res.status });
    throw new HttpsErrorV2("unavailable", "The provider declined the connection. Please try again.");
  }

  const json = await res.json();
  const expiresAt = json.expires_in
    ? admin.firestore.Timestamp.fromMillis(Date.now() + json.expires_in * 1000)
    : null;

  return {
    accessToken: json.access_token,
    refreshToken: json.refresh_token ?? null,
    expiresAt,
    scope: json.scope ?? null,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// connectorOAuthExchange — server-side OAuth token exchange + grant write.
//
// Input:  { connectorId, code, redirectUri, codeVerifier?, scopes[], surfaces[], expiresAt? }
// Output: { status:'active', connectorId, scopes, surfaces, grantedAt, expiresAt }
//         (tokens are NEVER included)
// ─────────────────────────────────────────────────────────────────────────────
exports.connectorOAuthExchange = onCallV2(
  {
    region: "us-central1",
    timeoutSeconds: 30,
    secrets: [
      GOOGLE_CALENDAR_CLIENT_ID,
      GOOGLE_CALENDAR_CLIENT_SECRET,
      SPOTIFY_CLIENT_ID,
      SPOTIFY_CLIENT_SECRET,
    ],
  },
  async (request) => {
    const uid = requireBereanAuth(request);
    await enforceRateLimit(uid, "connectorOAuthExchange", 10, 3600);
    await assertNotMinor(uid);

    const { connectorId, code, redirectUri, codeVerifier, scopes, surfaces, expiresAt } =
      request.data || {};

    assertValidConnectorId(connectorId);
    assertIsNewProvider(connectorId);
    assertValidScopes(scopes);
    assertValidSurfaces(surfaces);

    if (!code || typeof code !== "string") {
      throw new HttpsErrorV2("invalid-argument", "Authorization code is required.");
    }
    if (!redirectUri || typeof redirectUri !== "string") {
      throw new HttpsErrorV2("invalid-argument", "redirectUri is required.");
    }

    // write_commit requires confirmation at grant time AND each use — the client
    // gates the UI; here we additionally require an explicit acknowledgement flag.
    if (scopes.includes("write_commit") && request.data?.writeCommitConfirmed !== true) {
      throw new HttpsErrorV2(
        "failed-precondition",
        "write_commit scope requires explicit confirmation at grant time.",
      );
    }

    // 1. Exchange code → tokens (fail-closed; grant not written on failure).
    const tokens = await exchangeOAuthCode(connectorId, code, redirectUri, codeVerifier);

    // 2. Persist tokens SERVER-SIDE ONLY.
    await storeTokens(uid, connectorId, tokens);

    // 3. Write the grant doc. minorBlocked literal-true per contract.
    const grantExpiresAt =
      typeof expiresAt === "number"
        ? admin.firestore.Timestamp.fromMillis(expiresAt)
        : null;

    const grantDoc = {
      uid,
      connectorId,
      scopes,
      surfaces,
      grantedAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: grantExpiresAt,
      status: "active",
      minorBlocked: true,
    };
    await grantRef(uid, connectorId).set(grantDoc, { merge: false });

    logger.info("[connectors] grant created", { uid, connectorId, scopes, surfaces });

    return {
      status: "active",
      connectorId,
      scopes,
      surfaces,
      grantedAt: Date.now(),
      expiresAt: typeof expiresAt === "number" ? expiresAt : null,
    };
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// connectorUpdateGrant — change the per-surface matrix / scopes / expiry of an
// EXISTING active grant without re-running OAuth. (e.g. "Calendar for reminders,
// not recommendations" = surfaces:['scheduled_actions'] minus ['berean']).
//
// Input:  { connectorId, scopes?, surfaces?, expiresAt? }
// Output: { status:'active', connectorId, scopes, surfaces, expiresAt }
// ─────────────────────────────────────────────────────────────────────────────
exports.connectorUpdateGrant = onCallV2(
  { region: "us-central1", timeoutSeconds: 15 },
  async (request) => {
    const uid = requireBereanAuth(request);
    await enforceRateLimit(uid, "connectorUpdateGrant", 30, 3600);
    await assertNotMinor(uid);

    const { connectorId, scopes, surfaces, expiresAt } = request.data || {};
    assertValidConnectorId(connectorId);

    const ref = grantRef(uid, connectorId);
    const snap = await ref.get();
    if (!snap.exists || snap.data()?.status === "revoked") {
      throw new HttpsErrorV2("failed-precondition", "No active grant to update.");
    }

    const patch = { updatedAt: admin.firestore.FieldValue.serverTimestamp() };
    if (scopes !== undefined) {
      assertValidScopes(scopes);
      if (scopes.includes("write_commit") && request.data?.writeCommitConfirmed !== true) {
        throw new HttpsErrorV2(
          "failed-precondition",
          "write_commit scope requires explicit confirmation.",
        );
      }
      patch.scopes = scopes;
    }
    if (surfaces !== undefined) {
      assertValidSurfaces(surfaces);
      patch.surfaces = surfaces;
    }
    if (expiresAt !== undefined) {
      patch.expiresAt =
        typeof expiresAt === "number"
          ? admin.firestore.Timestamp.fromMillis(expiresAt)
          : null;
    }

    await ref.set(patch, { merge: true });
    const updated = (await ref.get()).data();

    logger.info("[connectors] grant updated", { uid, connectorId });

    return {
      status: updated.status,
      connectorId,
      scopes: updated.scopes ?? [],
      surfaces: updated.surfaces ?? [],
      expiresAt: null,
    };
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// connectorRevoke — one-tap revoke. Soft-revokes the grant AND purges stored tokens.
//
// Input:  { connectorId }
// Output: { status:'revoked', connectorId }
// ─────────────────────────────────────────────────────────────────────────────
exports.connectorRevoke = onCallV2(
  { region: "us-central1", timeoutSeconds: 15 },
  async (request) => {
    const uid = requireBereanAuth(request);
    await enforceRateLimit(uid, "connectorRevoke", 30, 3600);

    const { connectorId } = request.data || {};
    assertValidConnectorId(connectorId);

    // Soft-revoke the grant (kept for audit), hard-delete the tokens (no lingering creds).
    await grantRef(uid, connectorId).set(
      {
        status: "revoked",
        revokedAt: admin.firestore.FieldValue.serverTimestamp(),
        minorBlocked: true,
      },
      { merge: true },
    );

    try {
      await tokenRef(uid, connectorId).delete();
    } catch (err) {
      logger.warn("[connectors] token purge on revoke failed", { uid, connectorId });
    }

    logger.info("[connectors] grant revoked", { uid, connectorId });
    return { status: "revoked", connectorId };
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// connectorStatus — fetch grant status for all connectors + a token-health probe.
// Drives the SIX UI states. A failed/expired token flips status:'error' so the
// client renders the DEGRADED chip. Honours grant expiry server-side.
//
// Input:  {}  (uid taken from auth)
// Output: { connectors: { [connectorId]: { status, scopes, surfaces, expiresAt, degraded, reason } },
//           usage: { connectorRequestsUsedToday, connectorRequestsPerDay } }
// ─────────────────────────────────────────────────────────────────────────────
exports.connectorStatus = onCallV2(
  { region: "us-central1", timeoutSeconds: 20 },
  async (request) => {
    const uid = requireBereanAuth(request);
    await enforceRateLimit(uid, "connectorStatus", CONNECTOR_REQUESTS_PER_DAY, ONE_DAY_SECONDS);

    const db = getDb();
    const out = {};

    const grantSnaps = await Promise.all(
      ALL_CONNECTOR_IDS.map((id) => grantRef(uid, id).get()),
    );

    const now = Date.now();

    for (let i = 0; i < ALL_CONNECTOR_IDS.length; i++) {
      const id = ALL_CONNECTOR_IDS[i];
      const snap = grantSnaps[i];

      if (!snap.exists) {
        out[id] = { status: "inactive", scopes: [], surfaces: [], expiresAt: null, degraded: false, reason: null };
        continue;
      }

      const g = snap.data();
      let status = g.status || "inactive";

      // Honour expiry server-side: an expired grant is treated as revoked.
      let expMs = null;
      if (g.expiresAt && typeof g.expiresAt.toMillis === "function") {
        expMs = g.expiresAt.toMillis();
        if (expMs <= now && status === "active") {
          status = "revoked";
        }
      }

      let degraded = false;
      let reason = null;

      // Token-health probe for NEW providers only (alias connectors have no tokens).
      if (status === "active" && NEW_CONNECTOR_IDS.includes(id)) {
        const tokSnap = await tokenRef(uid, id).get();
        const tok = tokSnap.exists ? tokSnap.data() : null;
        const tokenExpired =
          tok?.expiresAt && typeof tok.expiresAt.toMillis === "function"
            ? tok.expiresAt.toMillis() <= now
            : false;

        if (!tok || !tok.accessToken) {
          status = "error";
          degraded = true;
          reason = "token_missing";
        } else if (tokenExpired && !tok.refreshToken) {
          status = "error";
          degraded = true;
          reason = "token_expired";
        }

        // Mirror error status back onto the grant doc so other surfaces see it.
        if (degraded && g.status !== "error") {
          await grantRef(uid, id).set({ status: "error" }, { merge: true });
        }
      }

      out[id] = {
        status,
        scopes: g.scopes ?? [],
        surfaces: g.surfaces ?? [],
        expiresAt: expMs,
        degraded,
        reason,
      };
    }

    // Usage counter for the connector-requests cap (read-only snapshot).
    let connectorRequestsUsedToday = 0;
    try {
      const rl = await db.collection("rateLimits").doc(`${uid}_connectorStatus`).get();
      connectorRequestsUsedToday = rl.exists ? (rl.data()?.count ?? 0) : 0;
    } catch {
      connectorRequestsUsedToday = 0;
    }

    return {
      connectors: out,
      usage: {
        connectorRequestsUsedToday,
        connectorRequestsPerDay: CONNECTOR_REQUESTS_PER_DAY,
      },
    };
  },
);

// Export internal helpers for unit testing (not registered as callables).
exports._internal = {
  computeAssertNotMinor: assertNotMinor,
  ALL_CONNECTOR_IDS,
  NEW_CONNECTOR_IDS,
  VALID_SCOPES,
  VALID_SURFACES,
};
